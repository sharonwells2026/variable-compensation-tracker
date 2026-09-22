create table if not exists public.hubspot_generic_associations (
  source_hubspot_object_type text not null,
  source_internal_object_key text not null,
  source_hubspot_record_id text not null,
  target_object_type text not null,
  target_hubspot_record_id text not null,
  association_type text,
  last_synced_at timestamptz not null default now(),
  primary key (source_hubspot_object_type, source_hubspot_record_id, target_object_type, target_hubspot_record_id, association_type)
);

alter table public.hubspot_generic_associations enable row level security;
revoke all on table public.hubspot_generic_associations from anon, authenticated;

create index if not exists idx_hubspot_generic_assoc_source on public.hubspot_generic_associations(source_hubspot_object_type, source_hubspot_record_id);
create index if not exists idx_hubspot_generic_assoc_target on public.hubspot_generic_associations(target_object_type, target_hubspot_record_id);

create or replace function public.sync_hubspot_generic_object_records(target_hubspot_object_type text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $function$
declare
  access jsonb;
  obj public.hubspot_object_definitions%rowtype;
  hubspot_key text;
  r extensions.http_response;
  body jsonb;
  rec jsonb;
  props text;
  after_cursor text;
  url text;
  count_records integer:=0;
  existed boolean;
  created_count integer:=0;
  updated_count integer:=0;
  assoc_group record;
  assoc_rec jsonb;
  assoc_count integer:=0;
  target_type text;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to sync HubSpot object records'; end if;
  select * into obj from public.hubspot_object_definitions where hubspot_object_type=target_hubspot_object_type and is_active;
  if obj.hubspot_object_type is null then raise exception 'Unknown HubSpot object type %',target_hubspot_object_type; end if;
  if obj.read_access<>'AVAILABLE' then return jsonb_build_object('hubspot_object_type',target_hubspot_object_type,'status','skipped','reason',obj.read_access); end if;
  select decrypted_secret into hubspot_key from vault.decrypted_secrets where name='hubspot_service_key' limit 1;
  if hubspot_key is null then raise exception 'The HubSpot service key was not found in Vault.'; end if;

  select string_agg(property_name,',' order by mapped desc, property_name) into props
  from (
    select p.property_name,
           exists(
             select 1
             from public.comp_hubspot_field_mappings fm
             join public.comp_hubspot_mapping_versions mv on mv.id=fm.mapping_version_id
             where fm.object_type=obj.internal_object_key
               and fm.property_name=p.property_name
               and fm.is_eligible
               and mv.id=(select id from public.comp_hubspot_mapping_versions order by case status when 'active' then 0 when 'draft' then 1 else 2 end,version_number desc limit 1)
           ) as mapped
    from public.hubspot_property_definitions p
    where p.hubspot_object_type=target_hubspot_object_type
      and p.is_active and not p.is_archived and not p.is_hidden
    order by mapped desc,p.property_name
    limit 100
  ) q;

  after_cursor:=null;
  loop
    url:='https://api.hubapi.com/crm/v3/objects/'||target_hubspot_object_type||'?archived=false&limit=100';
    if coalesce(props,'')<>'' then url:=url||'&properties='||props; end if;
    if target_hubspot_object_type='MEETING_EVENT' then url:=url||'&associations=deals,companies'; end if;
    if after_cursor is not null then url:=url||'&after='||after_cursor; end if;
    r:=extensions.http(('GET',url,array[extensions.http_header('Authorization','Bearer '||hubspot_key),extensions.http_header('Accept','application/json')],null,null)::extensions.http_request);
    if r.status<>200 then
      return jsonb_build_object('hubspot_object_type',target_hubspot_object_type,'status','warning','http_status',r.status,'reason',left(r.content,300),'records_received',count_records);
    end if;
    body:=r.content::jsonb;
    for rec in select value from jsonb_array_elements(coalesce(body->'results','[]'::jsonb)) loop
      select exists(select 1 from public.hubspot_generic_records g where g.hubspot_object_type=target_hubspot_object_type and g.hubspot_record_id=rec->>'id') into existed;
      insert into public.hubspot_generic_records(hubspot_object_type,internal_object_key,hubspot_record_id,properties,raw_hubspot_data,hubspot_created_at,hubspot_updated_at,last_synced_at,source_fingerprint,is_archived)
      values(target_hubspot_object_type,obj.internal_object_key,rec->>'id',coalesce(rec->'properties','{}'::jsonb),rec,nullif(rec->>'createdAt','')::timestamptz,nullif(rec->>'updatedAt','')::timestamptz,now(),md5(rec::text),coalesce((rec->>'archived')::boolean,false))
      on conflict(hubspot_object_type,hubspot_record_id) do update set
        internal_object_key=excluded.internal_object_key,properties=excluded.properties,raw_hubspot_data=excluded.raw_hubspot_data,
        hubspot_created_at=excluded.hubspot_created_at,hubspot_updated_at=excluded.hubspot_updated_at,last_synced_at=excluded.last_synced_at,
        source_fingerprint=excluded.source_fingerprint,is_archived=excluded.is_archived;
      count_records:=count_records+1;
      if existed then updated_count:=updated_count+1; else created_count:=created_count+1; end if;

      if target_hubspot_object_type='MEETING_EVENT' then
        delete from public.hubspot_generic_associations
        where source_hubspot_object_type=target_hubspot_object_type
          and source_hubspot_record_id=rec->>'id';

        for assoc_group in select key,value from jsonb_each(coalesce(rec->'associations','{}'::jsonb)) loop
          target_type:=case assoc_group.key when 'companies' then 'company' when 'deals' then 'deal' else assoc_group.key end;
          for assoc_rec in select value from jsonb_array_elements(coalesce(assoc_group.value->'results','[]'::jsonb)) loop
            insert into public.hubspot_generic_associations(source_hubspot_object_type,source_internal_object_key,source_hubspot_record_id,target_object_type,target_hubspot_record_id,association_type,last_synced_at)
            values(target_hubspot_object_type,obj.internal_object_key,rec->>'id',target_type,assoc_rec->>'id',assoc_rec->>'type',now())
            on conflict do update set last_synced_at=excluded.last_synced_at;
            assoc_count:=assoc_count+1;
          end loop;
        end loop;
      end if;
    end loop;
    after_cursor:=body->'paging'->'next'->>'after';
    exit when after_cursor is null;
    perform pg_catalog.pg_sleep(0.10);
  end loop;
  return jsonb_build_object('hubspot_object_type',target_hubspot_object_type,'status','completed','records_received',count_records,'created',created_count,'updated',updated_count,'properties_requested',coalesce(array_length(string_to_array(props,','),1),0),'associations_synced',assoc_count);
end;$function$;

revoke execute on function public.sync_hubspot_generic_object_records(text) from public, anon, authenticated;
grant execute on function public.sync_hubspot_generic_object_records(text) to postgres, service_role;