create table if not exists public.hubspot_generic_records (
  hubspot_object_type text not null,
  internal_object_key text not null,
  hubspot_record_id text not null,
  properties jsonb not null default '{}'::jsonb,
  raw_hubspot_data jsonb not null default '{}'::jsonb,
  hubspot_created_at timestamptz,
  hubspot_updated_at timestamptz,
  last_synced_at timestamptz not null default now(),
  source_fingerprint text,
  is_archived boolean not null default false,
  primary key (hubspot_object_type, hubspot_record_id)
);
alter table public.hubspot_generic_records enable row level security;
revoke all on public.hubspot_generic_records from anon, authenticated;

create table if not exists public.hubspot_integration_resync_runs (
  id uuid primary key default gen_random_uuid(),
  status text not null check (status in ('running','completed','completed_with_warnings','failed')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  requested_by uuid,
  schema_summary jsonb not null default '{}'::jsonb,
  data_summary jsonb not null default '{}'::jsonb,
  change_summary jsonb not null default '{}'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  error_message text
);
alter table public.hubspot_integration_resync_runs enable row level security;
revoke all on public.hubspot_integration_resync_runs from anon, authenticated;

create or replace function public.sync_hubspot_object_catalog()
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $$
declare
  access jsonb;
  hubspot_key text;
  r extensions.http_response;
  body jsonb;
  s jsonb;
  discovered integer:=0;
  status_note text:='ok';
  object_type text;
  object_name text;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to refresh HubSpot object configuration'; end if;
  select decrypted_secret into hubspot_key from vault.decrypted_secrets where name='hubspot_service_key' limit 1;
  if hubspot_key is null then raise exception 'The HubSpot service key was not found in Vault.'; end if;

  r:=extensions.http((
    'GET','https://api.hubapi.com/crm/v3/schemas',
    array[extensions.http_header('Authorization','Bearer '||hubspot_key),extensions.http_header('Accept','application/json')],null,null
  )::extensions.http_request);

  if r.status=200 then
    body:=r.content::jsonb;
    for s in select value from jsonb_array_elements(coalesce(body->'results','[]'::jsonb)) loop
      object_type:=coalesce(nullif(s->>'objectTypeId',''),nullif(s->>'fullyQualifiedName',''),nullif(s->>'name',''));
      object_name:=coalesce(nullif(s->'labels'->>'plural',''),nullif(s->'labels'->>'singular',''),nullif(s->>'name',''),object_type);
      if object_type is not null then
        insert into public.hubspot_object_definitions(hubspot_object_type,internal_object_key,object_category,description,read_access,write_access,is_active,source_system,first_seen_at,last_seen_at,updated_at)
        values(object_type,lower(regexp_replace(coalesce(nullif(s->>'name',''),object_type),'[^a-zA-Z0-9_]+','_','g')),'CUSTOM_OBJECTS',s->>'description','AVAILABLE','READ_ONLY',true,'hubspot_schema_api',now(),now(),now())
        on conflict(hubspot_object_type) do update set
          description=coalesce(excluded.description,public.hubspot_object_definitions.description),
          is_active=true,last_seen_at=now(),updated_at=now();
        discovered:=discovered+1;
      end if;
    end loop;
  elsif r.status in (401,403) then
    status_note:='schema_scope_missing';
  else
    status_note:='schema_endpoint_http_'||r.status::text;
  end if;

  return jsonb_build_object('status',status_note,'objects_discovered',discovered,'http_status',r.status,
    'message',case when status_note='schema_scope_missing' then 'Current HubSpot credential cannot enumerate object schemas. Existing registered objects will still refresh.' else null end);
end;$$;
revoke all on function public.sync_hubspot_object_catalog() from public, anon;
grant execute on function public.sync_hubspot_object_catalog() to authenticated;

create or replace function public.sync_hubspot_generic_object_records(target_hubspot_object_type text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $$
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
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to sync HubSpot object records'; end if;
  select * into obj from public.hubspot_object_definitions where hubspot_object_type=target_hubspot_object_type and is_active;
  if obj.hubspot_object_type is null then raise exception 'Unknown HubSpot object type %',target_hubspot_object_type; end if;
  if obj.read_access<>'AVAILABLE' then return jsonb_build_object('hubspot_object_type',target_hubspot_object_type,'status','skipped','reason',obj.read_access); end if;
  select decrypted_secret into hubspot_key from vault.decrypted_secrets where name='hubspot_service_key' limit 1;
  if hubspot_key is null then raise exception 'The HubSpot service key was not found in Vault.'; end if;

  select string_agg(property_name,',') into props
  from (
    select distinct fm.property_name
    from public.comp_hubspot_field_mappings fm
    join public.comp_hubspot_mapping_versions mv on mv.id=fm.mapping_version_id
    where fm.object_type=obj.internal_object_key and fm.is_eligible
      and mv.id=(select id from public.comp_hubspot_mapping_versions order by case status when 'active' then 0 when 'draft' then 1 else 2 end,version_number desc limit 1)
    order by fm.property_name
    limit 100
  ) q;

  after_cursor:=null;
  loop
    url:='https://api.hubapi.com/crm/v3/objects/'||target_hubspot_object_type||'?archived=false&limit=100';
    if coalesce(props,'')<>'' then url:=url||'&properties='||props; end if;
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
    end loop;
    after_cursor:=body->'paging'->'next'->>'after';
    exit when after_cursor is null;
  end loop;
  return jsonb_build_object('hubspot_object_type',target_hubspot_object_type,'status','completed','records_received',count_records,'created',created_count,'updated',updated_count,'properties_requested',coalesce(array_length(string_to_array(props,','),1),0));
end;$$;
revoke all on function public.sync_hubspot_generic_object_records(text) from public, anon;
grant execute on function public.sync_hubspot_generic_object_records(text) to authenticated;

create or replace function public.resync_hubspot_integration()
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $$
declare
  access jsonb;
  run_id uuid;
  schema_catalog jsonb;
  pipeline_result jsonb;
  obj record;
  prop_result jsonb;
  record_result jsonb;
  schema_items jsonb:='[]'::jsonb;
  data_items jsonb:='[]'::jsonb;
  warnings jsonb:='[]'::jsonb;
  change_result jsonb;
  enabled_mv uuid;
  enabled_count integer:=0;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to re-sync HubSpot integration'; end if;
  insert into public.hubspot_integration_resync_runs(status,requested_by) values('running',auth.uid()) returning id into run_id;

  begin schema_catalog:=public.sync_hubspot_object_catalog(); exception when others then schema_catalog:=jsonb_build_object('status','warning','error',sqlerrm); end;
  if coalesce(schema_catalog->>'status','')<>'ok' then warnings:=warnings||jsonb_build_array(schema_catalog); end if;

  begin pipeline_result:=public.sync_hubspot_pipelines(); exception when others then pipeline_result:=jsonb_build_object('status','warning','error',sqlerrm); warnings:=warnings||jsonb_build_array(pipeline_result); end;

  for obj in select hubspot_object_type,internal_object_key,read_access from public.hubspot_object_definitions where is_active order by object_category,hubspot_object_type loop
    if obj.read_access='AVAILABLE' then
      begin
        prop_result:=public.sync_hubspot_object_properties(obj.hubspot_object_type);
        schema_items:=schema_items||jsonb_build_array(prop_result);
      exception when others then
        warnings:=warnings||jsonb_build_array(jsonb_build_object('object',obj.hubspot_object_type,'phase','properties','error',sqlerrm));
      end;
    end if;
  end loop;

  select id into enabled_mv from public.comp_hubspot_mapping_versions order by case status when 'active' then 0 when 'draft' then 1 else 2 end,version_number desc limit 1;
  if enabled_mv is not null then
    for obj in
      select od.hubspot_object_type,od.internal_object_key
      from public.comp_hubspot_object_mappings om
      join public.hubspot_object_definitions od on od.internal_object_key=om.object_type
      where om.mapping_version_id=enabled_mv and om.is_eligible and od.is_active and od.read_access='AVAILABLE'
      order by od.hubspot_object_type
    loop
      enabled_count:=enabled_count+1;
      begin
        record_result:=public.sync_hubspot_generic_object_records(obj.hubspot_object_type);
        data_items:=data_items||jsonb_build_array(record_result);
      exception when others then
        warnings:=warnings||jsonb_build_array(jsonb_build_object('object',obj.hubspot_object_type,'phase','records','error',sqlerrm));
      end;
    end loop;
  end if;

  begin perform public.sync_hubspot_deals(); exception when others then warnings:=warnings||jsonb_build_array(jsonb_build_object('object','DEAL','phase','normalized_records','error',sqlerrm)); end;
  begin perform public.sync_hubspot_deal_company_associations(); exception when others then warnings:=warnings||jsonb_build_array(jsonb_build_object('object','DEAL_COMPANY_ASSOCIATIONS','phase','associations','error',sqlerrm)); end;
  begin perform public.sync_hubspot_companies(); exception when others then warnings:=warnings||jsonb_build_array(jsonb_build_object('object','COMPANY','phase','normalized_records','error',sqlerrm)); end;

  change_result:=public.refresh_hubspot_comp_configuration_changes();

  update public.hubspot_integration_resync_runs set
    status=case when jsonb_array_length(warnings)>0 then 'completed_with_warnings' else 'completed' end,
    completed_at=now(),schema_summary=jsonb_build_object('object_catalog',schema_catalog,'pipelines',pipeline_result,'objects_refreshed',jsonb_array_length(schema_items),'details',schema_items),
    data_summary=jsonb_build_object('enabled_objects',enabled_count,'details',data_items),change_summary=change_result,warnings=warnings
  where id=run_id;

  return jsonb_build_object('run_id',run_id,'status',case when jsonb_array_length(warnings)>0 then 'completed_with_warnings' else 'completed' end,
    'schema',jsonb_build_object('object_catalog',schema_catalog,'pipelines',pipeline_result,'objects_refreshed',jsonb_array_length(schema_items)),
    'data',jsonb_build_object('enabled_objects',enabled_count,'details',data_items),'changes',change_result,'warnings',warnings);
exception when others then
  update public.hubspot_integration_resync_runs set status='failed',completed_at=now(),error_message=sqlerrm where id=run_id;
  raise;
end;$$;
revoke all on function public.resync_hubspot_integration() from public, anon;
grant execute on function public.resync_hubspot_integration() to authenticated;