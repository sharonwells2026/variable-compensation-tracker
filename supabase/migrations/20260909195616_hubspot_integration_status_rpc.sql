create or replace function public.get_hubspot_integration_status()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare access jsonb; latest public.hubspot_integration_resync_runs%rowtype;
begin
 access:=public.get_current_user_access();
 if not private.can_view_hubspot_comp_mapping(access) then raise exception 'Not authorized to view HubSpot integration status'; end if;
 select * into latest from public.hubspot_integration_resync_runs order by started_at desc limit 1;
 return jsonb_build_object(
  'objects',coalesce(public.get_hubspot_object_sync_settings(),'[]'::jsonb),
  'latest_run',case when latest.id is null then null else jsonb_build_object(
    'id',latest.id,'status',latest.status,'started_at',latest.started_at,'completed_at',latest.completed_at,
    'schema_summary',latest.schema_summary,'data_summary',latest.data_summary,'change_summary',latest.change_summary,
    'warnings',latest.warnings,'error_message',latest.error_message) end,
  'summary',jsonb_build_object(
    'registered_objects',(select count(*) from public.hubspot_object_definitions where is_active),
    'readable_objects',(select count(*) from public.hubspot_object_definitions where is_active and read_access='AVAILABLE'),
    'record_sync_objects',(select count(*) from public.hubspot_object_sync_settings where record_sync_enabled),
    'properties',(select count(*) from public.hubspot_property_definitions where is_active and not is_archived),
    'open_configuration_changes',(select count(*) from public.comp_hubspot_config_changes where review_status='open'))
 );
end;$$;
revoke all on function public.get_hubspot_integration_status() from public, anon;
grant execute on function public.get_hubspot_integration_status() to authenticated;