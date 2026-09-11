create or replace function public.reset_live_test_data(confirmation_text text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := (select auth.uid());
  before_state jsonb;
begin
  if actor is null or not private.has_permission('settings.manage') then
    raise exception 'Settings administration is required to reset live-test data.' using errcode='42501';
  end if;
  if confirmation_text is distinct from 'RESET LIVE TEST DATA' then
    raise exception 'Confirmation text did not match. No data was changed.' using errcode='22023';
  end if;

  before_state := public.preview_live_test_reset();
  update public.app_access_audit_events set related_plan_id = null where related_plan_id is not null;

  truncate table
    public.approval_actions,
    public.approval_request_messages,
    public.approval_requests,
    public.comp_credit_correction_requests,
    public.comp_deal_credit_reviews,
    public.comp_earning_handoff_tasks,
    public.comp_earning_lifecycle_events,
    public.compensation_review_batch_items,
    public.compensation_review_batches,
    public.earning_adjustments,
    public.earning_disputes,
    public.earning_eligibility_events,
    public.earning_payment_schedules,
    public.historical_comp_records,
    public.missing_earning_claims,
    public.payroll_payment_items,
    public.payroll_batches,
    public.reconciliation_actions,
    public.deal_credit_allocations,
    public.contract_group_deals,
    public.comp_earnings,
    public.comp_calculations,
    public.employee_plan_assignments,
    public.plan_version_acknowledgments,
    public.app_user_drafts,
    public.comp_plans,
    public.comp_deal_earning_candidates,
    public.comp_deal_earning_candidates_v2,
    public.comp_deal_earning_refresh_delta,
    public.hubspot_compensation_deals,
    public.hubspot_deal_company_associations,
    public.hubspot_deal_scope,
    public.hubspot_generic_associations,
    public.hubspot_record_changes,
    public.hubspot_deals,
    public.hubspot_companies,
    public.hubspot_generic_records,
    public.hubspot_integration_resync_runs,
    public.hubspot_sync_runs
  restart identity cascade;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state)
  values(actor,'live_test_data_reset','Controlled live-test reset. Users, employees, roles, permissions, and HubSpot configuration were preserved.',before_state,jsonb_build_object('status','reset_complete'));

  return jsonb_build_object(
    'status','reset_complete',
    'preserved',jsonb_build_array('auth users','profiles','employees','roles','permissions','role assignments','HubSpot integration configuration','HubSpot rule-data configuration'),
    'next_step','Run a fresh HubSpot resync, then create compensation plans from the UI.'
  );
end;
$function$;
revoke all on function public.reset_live_test_data(text) from public;
grant execute on function public.reset_live_test_data(text) to authenticated;
