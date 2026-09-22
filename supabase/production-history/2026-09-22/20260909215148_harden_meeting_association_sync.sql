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
  company_assoc_count integer:=0;
  deal_assoc_count integer:=0;
  batch_ids jsonb;
  assoc_result jsonb;
  assoc_to jsonb;
  target_type text;
  batch_no integer;
  attempt_no integer;
  assoc_warnings jsonb:='[]'::jsonb;
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
        'POST','https://api.hubapi.com/crm/v3/objects/'||target_hubspot_object_type||'/search',
        array[
          extensions.http_header('Authorization','Bearer '||hubspot_key),
          extensions.http_header('Content-Type','application/json')
        ],
        'application/json',request_body::text
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
    perform pg_catalog.pg_sleep(0.15);
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

        r:=null;
        for attempt_no in 1..4 loop
          r:=extensions.http((
            'POST',
            'https://api.hubapi.com/crm/v4/associations/'||target_hubspot_object_type||'/'||target_type||'/batch/read',
            array[
              extensions.http_header('Authorization','Bearer '||hubspot_key),
              extensions.http_header('Content-Type','application/json')
            ],
            'application/json',jsonb_build_object('inputs',batch_ids)::text
          )::extensions.http_request);
          exit when r.status=200;
          if r.status=429 or r.status>=500 then
            perform pg_catalog.pg_sleep(0.5*attempt_no);
          else
            exit;
          end if;
        end loop;

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
              if target_type='companies' then company_assoc_count:=company_assoc_count+1; else deal_assoc_count:=deal_assoc_count+1; end if;
            end loop;
          end loop;
        else
          assoc_warnings:=assoc_warnings||jsonb_build_array(jsonb_build_object(
            'target_type',target_type,
            'batch',batch_no,
            'http_status',r.status,
            'reason',left(r.content,300)
          ));
        end if;

        batch_no:=batch_no+1;
        perform pg_catalog.pg_sleep(0.25);
      end loop;
    end loop;
  end if;

  return jsonb_build_object(
    'hubspot_object_type',target_hubspot_object_type,
    'status',case when jsonb_array_length(assoc_warnings)>0 then 'completed_with_warnings' else 'completed' end,
    'records_received',count_records,
    'created',created_count,
    'updated',updated_count,
    'properties_requested',coalesce(array_length(string_to_array(props,','),1),0),
    'associations_synced',assoc_count,
    'association_counts',jsonb_build_object('company',company_assoc_count,'deal',deal_assoc_count),
    'association_warnings',assoc_warnings,
    'filter_mode',coalesce(setting.record_filter_mode,'all'),
    'out_of_scope_records',(
      select count(*) from public.hubspot_generic_records
      where hubspot_object_type=target_hubspot_object_type and not in_sync_scope
    )
  );
end;$$;

revoke execute on function public.sync_hubspot_generic_object_records(text) from public,anon,authenticated;