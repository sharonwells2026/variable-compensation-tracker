revoke execute on function public.sync_hubspot_generic_object_records(text) from authenticated;
revoke execute on function public.sync_hubspot_object_catalog() from authenticated;
revoke execute on function public.sync_hubspot_object_properties(text) from authenticated;
revoke execute on function public.sync_hubspot_pipelines() from authenticated;

-- Keep only the admin-facing orchestration/configuration RPCs callable by signed-in users.
-- Their function bodies perform their own permission checks.
grant execute on function public.resync_hubspot_integration() to authenticated;
grant execute on function public.get_hubspot_integration_status() to authenticated;
grant execute on function public.get_hubspot_object_sync_settings() to authenticated;
grant execute on function public.set_hubspot_object_record_sync(text, boolean) to authenticated;
