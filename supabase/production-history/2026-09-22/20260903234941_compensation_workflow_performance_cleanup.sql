drop index if exists public.hubspot_deals_external_id_uidx;
drop index if exists public.hubspot_pipelines_external_id_uidx;

create index if not exists approval_actions_request_idx on public.approval_actions(approval_request_id);
create index if not exists approval_actions_actor_idx on public.approval_actions(action_by);
create index if not exists approval_requests_requested_by_idx on public.approval_requests(requested_by);
create index if not exists approval_requests_backup_idx on public.approval_requests(backup_requested_from);

create index if not exists comp_earnings_calculation_idx on public.comp_earnings(calculation_id);
create index if not exists comp_earnings_plan_assignment_idx on public.comp_earnings(plan_assignment_id);
create index if not exists comp_earnings_plan_component_idx on public.comp_earnings(plan_component_id);
create index if not exists comp_earnings_manager_approved_by_idx on public.comp_earnings(manager_approved_by);
create index if not exists comp_earnings_executive_approved_by_idx on public.comp_earnings(executive_approved_by);
create index if not exists comp_earnings_supersedes_idx on public.comp_earnings(supersedes_earning_id);
create index if not exists comp_earnings_reconciled_by_idx on public.comp_earnings(reconciled_by);

create index if not exists comp_earning_lifecycle_earning_idx on public.comp_earning_lifecycle_events(comp_earning_id);
create index if not exists comp_earning_lifecycle_sync_run_idx on public.comp_earning_lifecycle_events(hubspot_sync_run_id);

create index if not exists payroll_payment_items_earning_idx on public.payroll_payment_items(comp_earning_id);
create index if not exists payroll_batches_created_by_idx on public.payroll_batches(created_by);
create index if not exists payroll_batches_finalized_by_idx on public.payroll_batches(finalized_by);

create index if not exists earning_payment_schedules_scheduled_by_idx on public.earning_payment_schedules(scheduled_by);
create index if not exists earning_eligibility_events_earning_idx on public.earning_eligibility_events(comp_earning_id);

comment on index public.comp_earnings_plan_component_idx is 'Supports high-traffic compensation ledger filtering and joins by plan component.';