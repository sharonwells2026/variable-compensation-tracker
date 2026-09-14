create or replace function public.preview_live_test_reset()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid:=(select auth.uid());
  result jsonb;
begin
  if actor is null or not private.has_permission('settings.manage') then
    raise exception 'Settings administration is required to preview a live-test reset.' using errcode='42501';
  end if;
  select jsonb_build_object(
    'preserved',jsonb_build_array('auth users','profiles','employees','roles','permission catalog','role permissions','global user permission overrides','HubSpot integration/object/property configuration'),
    'cleared_on_reset',jsonb_build_object(
      'plans',(select count(*) from public.comp_plans),
      'plan_versions',(select count(*) from public.comp_plan_versions),
      'plan_components',(select count(*) from public.comp_plan_components),
      'plan_assignments',(select count(*) from public.employee_plan_assignments),
      'draft_assignments',(select count(*) from public.comp_plan_draft_assignments),
      'plan_agreements',(select count(*) from public.comp_plan_agreements),
      'plan_approval_steps',(select count(*) from public.comp_plan_approval_steps),
      'earnings',(select count(*) from public.comp_earnings),
      'approval_requests',(select count(*) from public.approval_requests),
      'review_batches',(select count(*) from public.compensation_review_batches),
      'hubspot_deals',(select count(*) from public.hubspot_deals),
      'hubspot_companies',(select count(*) from public.hubspot_companies),
      'hubspot_generic_records',(select count(*) from public.hubspot_generic_records),
      'hubspot_record_changes',(select count(*) from public.hubspot_record_changes),
      'hubspot_sync_runs',(select count(*) from public.hubspot_sync_runs)
    ),
    'note','This is a preview only. No data was changed.'
  ) into result;
  return result;
end;
$function$;
revoke all on function public.preview_live_test_reset() from public;
grant execute on function public.preview_live_test_reset() to authenticated;