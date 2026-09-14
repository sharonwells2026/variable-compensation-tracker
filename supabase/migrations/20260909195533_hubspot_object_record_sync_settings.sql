create table if not exists public.hubspot_object_sync_settings (
  hubspot_object_type text primary key references public.hubspot_object_definitions(hubspot_object_type) on update cascade,
  record_sync_enabled boolean not null default false,
  sync_reason text,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
alter table public.hubspot_object_sync_settings enable row level security;
revoke all on public.hubspot_object_sync_settings from anon, authenticated;

insert into public.hubspot_object_sync_settings(hubspot_object_type,record_sync_enabled,sync_reason)
select hubspot_object_type,true,case hubspot_object_type
  when 'DEAL' then 'Required v1 compensation source object'
  when 'COMPANY' then 'Required v1 compensation source object'
  when 'MEETING_EVENT' then 'Required v1 meeting activity source object'
end
from public.hubspot_object_definitions
where hubspot_object_type in ('DEAL','COMPANY','MEETING_EVENT')
on conflict(hubspot_object_type) do update set record_sync_enabled=true,sync_reason=excluded.sync_reason,updated_at=now();

insert into public.hubspot_object_sync_settings(hubspot_object_type,record_sync_enabled,sync_reason)
select o.hubspot_object_type,false,'Available for future opt-in'
from public.hubspot_object_definitions o
where not exists(select 1 from public.hubspot_object_sync_settings s where s.hubspot_object_type=o.hubspot_object_type)
on conflict do nothing;

create or replace function public.get_hubspot_object_sync_settings()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare access jsonb;
begin
  access:=public.get_current_user_access();
  if not private.can_view_hubspot_comp_mapping(access) then raise exception 'Not authorized to view HubSpot sync settings'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'hubspot_object_type',o.hubspot_object_type,'internal_object_key',o.internal_object_key,'object_category',o.object_category,
    'description',o.description,'read_access',o.read_access,'record_sync_enabled',coalesce(s.record_sync_enabled,false),
    'sync_reason',s.sync_reason,'updated_at',s.updated_at
  ) order by coalesce(s.record_sync_enabled,false) desc,o.object_category,o.hubspot_object_type)
  from public.hubspot_object_definitions o
  left join public.hubspot_object_sync_settings s on s.hubspot_object_type=o.hubspot_object_type),'[]'::jsonb);
end;$$;
revoke all on function public.get_hubspot_object_sync_settings() from public, anon;
grant execute on function public.get_hubspot_object_sync_settings() to authenticated;

create or replace function public.set_hubspot_object_record_sync(target_hubspot_object_type text, enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare access jsonb; obj public.hubspot_object_definitions%rowtype;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to change HubSpot sync settings'; end if;
  select * into obj from public.hubspot_object_definitions where hubspot_object_type=target_hubspot_object_type;
  if obj.hubspot_object_type is null then raise exception 'Unknown HubSpot object type %',target_hubspot_object_type; end if;
  if enabled and obj.read_access<>'AVAILABLE' then raise exception 'HubSpot object % is not readable with the current connection',target_hubspot_object_type; end if;
  insert into public.hubspot_object_sync_settings(hubspot_object_type,record_sync_enabled,sync_reason,updated_by,updated_at)
  values(target_hubspot_object_type,enabled,case when enabled then 'Enabled by administrator' else 'Disabled by administrator' end,auth.uid(),now())
  on conflict(hubspot_object_type) do update set record_sync_enabled=excluded.record_sync_enabled,sync_reason=excluded.sync_reason,updated_by=excluded.updated_by,updated_at=now();
  return jsonb_build_object('hubspot_object_type',target_hubspot_object_type,'record_sync_enabled',enabled);
end;$$;
revoke all on function public.set_hubspot_object_record_sync(text,boolean) from public, anon;
grant execute on function public.set_hubspot_object_record_sync(text,boolean) to authenticated;

create or replace function public.resync_hubspot_integration()
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $$
declare
  access jsonb; run_id uuid; schema_catalog jsonb; pipeline_result jsonb; obj record; prop_result jsonb; record_result jsonb;
  schema_items jsonb:='[]'::jsonb; data_items jsonb:='[]'::jsonb; warnings jsonb:='[]'::jsonb; change_result jsonb; enabled_count integer:=0;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to re-sync HubSpot integration'; end if;
  insert into public.hubspot_integration_resync_runs(status,requested_by) values('running',auth.uid()) returning id into run_id;
  begin schema_catalog:=public.sync_hubspot_object_catalog(); exception when others then schema_catalog:=jsonb_build_object('status','warning','error',sqlerrm); end;
  if coalesce(schema_catalog->>'status','')<>'ok' then warnings:=warnings||jsonb_build_array(schema_catalog); end if;
  begin pipeline_result:=public.sync_hubspot_pipelines(); exception when others then pipeline_result:=jsonb_build_object('status','warning','error',sqlerrm); warnings:=warnings||jsonb_build_array(pipeline_result); end;

  for obj in select hubspot_object_type,internal_object_key,read_access from public.hubspot_object_definitions where is_active order by object_category,hubspot_object_type loop
    if obj.read_access='AVAILABLE' then
      begin prop_result:=public.sync_hubspot_object_properties(obj.hubspot_object_type); schema_items:=schema_items||jsonb_build_array(prop_result);
      exception when others then warnings:=warnings||jsonb_build_array(jsonb_build_object('object',obj.hubspot_object_type,'phase','properties','error',sqlerrm)); end;
    end if;
  end loop;

  for obj in
    select o.hubspot_object_type,o.internal_object_key
    from public.hubspot_object_definitions o join public.hubspot_object_sync_settings s on s.hubspot_object_type=o.hubspot_object_type
    where o.is_active and o.read_access='AVAILABLE' and s.record_sync_enabled
    order by o.hubspot_object_type
  loop
    enabled_count:=enabled_count+1;
    begin record_result:=public.sync_hubspot_generic_object_records(obj.hubspot_object_type); data_items:=data_items||jsonb_build_array(record_result);
    exception when others then warnings:=warnings||jsonb_build_array(jsonb_build_object('object',obj.hubspot_object_type,'phase','records','error',sqlerrm)); end;
  end loop;

  begin perform public.sync_hubspot_deals(); exception when others then warnings:=warnings||jsonb_build_array(jsonb_build_object('object','DEAL','phase','normalized_records','error',sqlerrm)); end;
  begin perform public.sync_hubspot_deal_company_associations(); exception when others then warnings:=warnings||jsonb_build_array(jsonb_build_object('object','DEAL_COMPANY_ASSOCIATIONS','phase','associations','error',sqlerrm)); end;
  begin perform public.sync_hubspot_companies(); exception when others then warnings:=warnings||jsonb_build_array(jsonb_build_object('object','COMPANY','phase','normalized_records','error',sqlerrm)); end;
  change_result:=public.refresh_hubspot_comp_configuration_changes();
  update public.hubspot_integration_resync_runs set status=case when jsonb_array_length(warnings)>0 then 'completed_with_warnings' else 'completed' end,completed_at=now(),
    schema_summary=jsonb_build_object('object_catalog',schema_catalog,'pipelines',pipeline_result,'objects_refreshed',jsonb_array_length(schema_items),'details',schema_items),
    data_summary=jsonb_build_object('record_sync_objects',enabled_count,'details',data_items),change_summary=change_result,warnings=warnings where id=run_id;
  return jsonb_build_object('run_id',run_id,'status',case when jsonb_array_length(warnings)>0 then 'completed_with_warnings' else 'completed' end,
    'schema',jsonb_build_object('object_catalog',schema_catalog,'pipelines',pipeline_result,'objects_refreshed',jsonb_array_length(schema_items)),
    'data',jsonb_build_object('record_sync_objects',enabled_count,'details',data_items),'changes',change_result,'warnings',warnings);
exception when others then update public.hubspot_integration_resync_runs set status='failed',completed_at=now(),error_message=sqlerrm where id=run_id; raise;
end;$$;
revoke all on function public.resync_hubspot_integration() from public, anon;
grant execute on function public.resync_hubspot_integration() to authenticated;