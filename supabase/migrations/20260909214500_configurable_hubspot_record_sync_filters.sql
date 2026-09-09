-- Configurable record-level HubSpot sync filters.
-- Keeps object enablement separate from the record scope copied into the tracker.

alter table public.hubspot_object_sync_settings
  add column if not exists record_filter_mode text not null default 'all',
  add column if not exists record_filter jsonb not null default '{"filterGroups":[]}'::jsonb;

alter table public.hubspot_object_sync_settings
  drop constraint if exists hubspot_object_sync_settings_filter_mode_check;
alter table public.hubspot_object_sync_settings
  add constraint hubspot_object_sync_settings_filter_mode_check
  check (record_filter_mode in ('all','filtered'));

alter table public.hubspot_generic_records
  add column if not exists in_sync_scope boolean not null default true,
  add column if not exists scope_evaluated_at timestamptz;

create index if not exists idx_hubspot_generic_records_scope
  on public.hubspot_generic_records(hubspot_object_type,in_sync_scope,is_archived);

create or replace function public.get_hubspot_object_sync_settings()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare access jsonb; begin
  access:=public.get_current_user_access();
  if not private.can_view_hubspot_comp_mapping(access) then raise exception 'Not authorized'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'hubspot_object_type',o.hubspot_object_type,
    'internal_object_key',o.internal_object_key,
    'object_category',o.object_category,
    'description',o.description,
    'read_access',o.read_access,
    'record_sync_enabled',coalesce(s.record_sync_enabled,false),
    'sync_reason',s.sync_reason,
    'record_filter_mode',coalesce(s.record_filter_mode,'all'),
    'record_filter',coalesce(s.record_filter,'{"filterGroups":[]}'::jsonb),
    'updated_at',s.updated_at
  ) order by o.object_category,o.internal_object_key)
  from public.hubspot_object_definitions o
  left join public.hubspot_object_sync_settings s on s.hubspot_object_type=o.hubspot_object_type
  where o.is_active),'[]'::jsonb);
end;$$;
revoke all on function public.get_hubspot_object_sync_settings() from public, anon;
grant execute on function public.get_hubspot_object_sync_settings() to authenticated;

create or replace function public.set_hubspot_object_record_filter(
  target_hubspot_object_type text,
  filter_mode text,
  filter_definition jsonb default '{"filterGroups": []}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  access jsonb;
  obj public.hubspot_object_definitions%rowtype;
  group_item jsonb;
  filter_item jsonb;
  prop text;
  op text;
  vals jsonb;
  v text;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then
    raise exception 'Not authorized to configure HubSpot record filters';
  end if;
  if filter_mode not in ('all','filtered') then raise exception 'filter_mode must be all or filtered'; end if;

  select * into obj
  from public.hubspot_object_definitions
  where hubspot_object_type=target_hubspot_object_type and is_active;
  if obj.hubspot_object_type is null then raise exception 'Unknown HubSpot object type %',target_hubspot_object_type; end if;

  if filter_mode='filtered' then
    if jsonb_typeof(coalesce(filter_definition->'filterGroups','null'::jsonb))<>'array'
       or jsonb_array_length(filter_definition->'filterGroups')=0 then
      raise exception 'Filtered mode requires at least one filter group';
    end if;

    for group_item in select value from jsonb_array_elements(filter_definition->'filterGroups') loop
      if jsonb_typeof(coalesce(group_item->'filters','null'::jsonb))<>'array'
         or jsonb_array_length(group_item->'filters')=0 then
        raise exception 'Each filter group requires at least one filter';
      end if;

      for filter_item in select value from jsonb_array_elements(group_item->'filters') loop
        prop:=nullif(filter_item->>'propertyName','');
        op:=upper(coalesce(nullif(filter_item->>'operator',''),'EQ'));
        if prop is null then raise exception 'Each filter requires propertyName'; end if;
        if not exists(
          select 1 from public.hubspot_property_definitions p
          where p.hubspot_object_type=target_hubspot_object_type
            and p.property_name=prop and p.is_active and not p.is_archived
        ) then
          raise exception 'HubSpot field % is not available on %',prop,target_hubspot_object_type;
        end if;
        if op not in ('EQ','NEQ','IN','NOT_IN','GT','GTE','LT','LTE','BETWEEN','HAS_PROPERTY','NOT_HAS_PROPERTY') then
          raise exception 'Unsupported HubSpot sync filter operator %',op;
        end if;
        if op in ('EQ','NEQ','GT','GTE','LT','LTE') and nullif(filter_item->>'value','') is null then raise exception '% requires value',op; end if;
        if op in ('IN','NOT_IN') and (
          jsonb_typeof(coalesce(filter_item->'values','null'::jsonb))<>'array'
          or jsonb_array_length(filter_item->'values')=0
        ) then raise exception '% requires values',op; end if;
        if op='BETWEEN' and (nullif(filter_item->>'highValue','') is null or nullif(filter_item->>'value','') is null) then
          raise exception 'BETWEEN requires value and highValue';
        end if;

        if exists(
          select 1 from public.hubspot_property_definitions p
          where p.hubspot_object_type=target_hubspot_object_type
            and p.property_name=prop and p.property_type='enumeration'
        ) then
          vals:=case
            when op in ('IN','NOT_IN') then filter_item->'values'
            when op in ('EQ','NEQ') then jsonb_build_array(filter_item->>'value')
            else '[]'::jsonb
          end;
          for v in select value #>> '{}' from jsonb_array_elements(vals) loop
            if not exists(
              select 1 from public.comp_hubspot_discovered_values dv
              where dv.object_type=obj.internal_object_key
                and dv.property_name=prop and dv.hubspot_value=v and dv.is_active
            ) then
              raise exception 'HubSpot value % is not currently available for %.%',v,obj.internal_object_key,prop;
            end if;
          end loop;
        end if;
      end loop;
    end loop;
  end if;

  insert into public.hubspot_object_sync_settings(
    hubspot_object_type,record_sync_enabled,sync_reason,updated_by,updated_at,record_filter_mode,record_filter
  )
  values(
    target_hubspot_object_type,false,'Available for future opt-in',auth.uid(),now(),filter_mode,
    case when filter_mode='all' then '{"filterGroups":[]}'::jsonb else filter_definition end
  )
  on conflict(hubspot_object_type) do update set
    record_filter_mode=excluded.record_filter_mode,
    record_filter=excluded.record_filter,
    updated_by=auth.uid(),
    updated_at=now();

  return jsonb_build_object(
    'hubspot_object_type',target_hubspot_object_type,
    'filter_mode',filter_mode,
    'filter',case when filter_mode='all' then '{"filterGroups":[]}'::jsonb else filter_definition end
  );
end;$$;
revoke all on function public.set_hubspot_object_record_filter(text,text,jsonb) from public, anon;
grant execute on function public.set_hubspot_object_record_filter(text,text,jsonb) to authenticated;

create or replace function public.sync_hubspot_generic_object_records(target_hubspot_object_type text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $$
declare
  access jsonb;
  obj public.hubspot_object_definitions%rowtype;
  setting public.hubspot_object_sync_settings%rowtype;
  hubspot_key text;
  r extensions.http_response;
  body jsonb;
  rec jsonb;
  props text;
  props_json jsonb;
  after_cursor text;
  url text;
  request_body jsonb;
  count_records integer:=0;
  existed boolean;
  created_count integer:=0;
  updated_count integer:=0;
  assoc_count integer:=0;
  batch_ids jsonb;
  assoc_result jsonb;
  assoc_to jsonb;
  target_type text;
  batch_no integer;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to sync HubSpot object records'; end if;

  select * into obj from public.hubspot_object_definitions
  where hubspot_object_type=target_hubspot_object_type and is_active;
  if obj.hubspot_object_type is null then raise exception 'Unknown HubSpot object type %',target_hubspot_object_type; end if;
  if obj.read_access<>'AVAILABLE' then
    return jsonb_build_object('hubspot_object_type',target_hubspot_object_type,'status','skipped','reason',obj.read_access);
  end if;

  select * into setting from public.hubspot_object_sync_settings
  where hubspot_object_type=target_hubspot_object_type;
  if setting.hubspot_object_type is null then
    setting.record_filter_mode:='all';
    setting.record_filter:='{"filterGroups":[]}'::jsonb;
  end if;

  select decrypted_secret into hubspot_key
  from vault.decrypted_secrets where name='hubspot_service_key' limit 1;
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
               and mv.id=(
                 select id from public.comp_hubspot_mapping_versions
                 order by case status when 'active' then 0 when 'draft' then 1 else 2 end,version_number desc
                 limit 1
               )
           ) as mapped
    from public.hubspot_property_definitions p
    where p.hubspot_object_type=target_hubspot_object_type
      and p.is_active and not p.is_archived and not p.is_hidden
    order by mapped desc,p.property_name
    limit 100
  ) q;
  props_json:=coalesce(to_jsonb(string_to_array(props,',')),'[]'::jsonb);

  create temporary table if not exists _synced_generic_ids(id text primary key) on commit drop;
  truncate _synced_generic_ids;

  update public.hubspot_generic_records
  set in_sync_scope=false,scope_evaluated_at=now()
  where hubspot_object_type=target_hubspot_object_type;

  after_cursor:=null;
  loop
    if coalesce(setting.record_filter_mode,'all')='filtered' then
      request_body:=jsonb_build_object(
        'filterGroups',coalesce(setting.record_filter->'filterGroups','[]'::jsonb),
        'properties',props_json,
        'limit',100
      );
      if after_cursor is not null then request_body:=request_body||jsonb_build_object('after',after_cursor); end if;
      r:=extensions.http((
        'POST',
        'https://api.hubapi.com/crm/v3/objects/'||target_hubspot_object_type||'/search',
        array[
          extensions.http_header('Authorization','Bearer '||hubspot_key),
          extensions.http_header('Content-Type','application/json')
        ],
        'application/json',
        request_body::text
      )::extensions.http_request);
    else
      url:='https://api.hubapi.com/crm/v3/objects/'||target_hubspot_object_type||'?archived=false&limit=100';
      if coalesce(props,'')<>'' then url:=url||'&properties='||props; end if;
      if after_cursor is not null then url:=url||'&after='||after_cursor; end if;
      r:=extensions.http((
        'GET',url,
        array[
          extensions.http_header('Authorization','Bearer '||hubspot_key),
          extensions.http_header('Accept','application/json')
        ],
        null,null
      )::extensions.http_request);
    end if;

    if r.status<>200 then
      return jsonb_build_object(
        'hubspot_object_type',target_hubspot_object_type,'status','warning','http_status',r.status,
        'reason',left(r.content,300),'records_received',count_records,
        'filter_mode',coalesce(setting.record_filter_mode,'all')
      );
    end if;

    body:=r.content::jsonb;
    for rec in select value from jsonb_array_elements(coalesce(body->'results','[]'::jsonb)) loop
      select exists(
        select 1 from public.hubspot_generic_records g
        where g.hubspot_object_type=target_hubspot_object_type and g.hubspot_record_id=rec->>'id'
      ) into existed;

      insert into public.hubspot_generic_records(
        hubspot_object_type,internal_object_key,hubspot_record_id,properties,raw_hubspot_data,
        hubspot_created_at,hubspot_updated_at,last_synced_at,source_fingerprint,is_archived,
        in_sync_scope,scope_evaluated_at
      ) values(
        target_hubspot_object_type,obj.internal_object_key,rec->>'id',coalesce(rec->'properties','{}'::jsonb),rec,
        nullif(rec->>'createdAt','')::timestamptz,nullif(rec->>'updatedAt','')::timestamptz,now(),md5(rec::text),
        coalesce((rec->>'archived')::boolean,false),true,now()
      )
      on conflict(hubspot_object_type,hubspot_record_id) do update set
        internal_object_key=excluded.internal_object_key,
        properties=excluded.properties,
        raw_hubspot_data=excluded.raw_hubspot_data,
        hubspot_created_at=excluded.hubspot_created_at,
        hubspot_updated_at=excluded.hubspot_updated_at,
        last_synced_at=excluded.last_synced_at,
        source_fingerprint=excluded.source_fingerprint,
        is_archived=excluded.is_archived,
        in_sync_scope=true,
        scope_evaluated_at=now();

      insert into _synced_generic_ids(id) values(rec->>'id') on conflict(id) do nothing;
      count_records:=count_records+1;
      if existed then updated_count:=updated_count+1; else created_count:=created_count+1; end if;
    end loop;

    after_cursor:=body->'paging'->'next'->>'after';
    exit when after_cursor is null;
    perform pg_catalog.pg_sleep(0.12);
  end loop;

  if target_hubspot_object_type='MEETING_EVENT' and count_records>0 then
    delete from public.hubspot_generic_associations a
    using _synced_generic_ids s
    where a.source_hubspot_object_type=target_hubspot_object_type
      and a.source_hubspot_record_id=s.id;

    for target_type in select unnest(array['companies','deals']) loop
      batch_no:=0;
      loop
        select jsonb_agg(jsonb_build_object('id',id) order by id) into batch_ids
        from (
          select id from _synced_generic_ids order by id limit 100 offset batch_no*100
        ) q;
        exit when batch_ids is null;

        r:=extensions.http((
          'POST',
          'https://api.hubapi.com/crm/v4/associations/'||target_hubspot_object_type||'/'||target_type||'/batch/read',
          array[
            extensions.http_header('Authorization','Bearer '||hubspot_key),
            extensions.http_header('Content-Type','application/json')
          ],
          'application/json',
          jsonb_build_object('inputs',batch_ids)::text
        )::extensions.http_request);

        if r.status=200 then
          body:=r.content::jsonb;
          for assoc_result in select value from jsonb_array_elements(coalesce(body->'results','[]'::jsonb)) loop
            for assoc_to in select value from jsonb_array_elements(coalesce(assoc_result->'to','[]'::jsonb)) loop
              insert into public.hubspot_generic_associations(
                source_hubspot_object_type,source_internal_object_key,source_hubspot_record_id,
                target_object_type,target_hubspot_record_id,association_type,last_synced_at
              ) values(
                target_hubspot_object_type,obj.internal_object_key,assoc_result->'from'->>'id',
                case target_type when 'companies' then 'company' else 'deal' end,
                assoc_to->>'toObjectId',
                coalesce(assoc_to->'associationTypes'->0->>'typeId','hubspot_defined'),now()
              )
              on conflict(source_hubspot_object_type,source_hubspot_record_id,target_object_type,target_hubspot_record_id,association_type)
              do update set last_synced_at=excluded.last_synced_at;
              assoc_count:=assoc_count+1;
            end loop;
          end loop;
        end if;

        batch_no:=batch_no+1;
        perform pg_catalog.pg_sleep(0.12);
      end loop;
    end loop;
  end if;

  return jsonb_build_object(
    'hubspot_object_type',target_hubspot_object_type,
    'status','completed',
    'records_received',count_records,
    'created',created_count,
    'updated',updated_count,
    'properties_requested',coalesce(array_length(string_to_array(props,','),1),0),
    'associations_synced',assoc_count,
    'filter_mode',coalesce(setting.record_filter_mode,'all'),
    'out_of_scope_records',(
      select count(*) from public.hubspot_generic_records
      where hubspot_object_type=target_hubspot_object_type and not in_sync_scope
    )
  );
end;$$;

-- This is an internal sync primitive. The public admin-facing resync RPC invokes it.
revoke execute on function public.sync_hubspot_generic_object_records(text) from public, anon, authenticated;
