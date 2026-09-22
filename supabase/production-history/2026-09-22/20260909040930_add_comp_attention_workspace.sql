create or replace function public.get_comp_attention_workspace_data()
returns jsonb
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
 if not (private.has_permission('workspace.view_administration') or private.has_permission('earnings.view') or private.has_permission('earnings.override') or private.has_permission('payments.view')) then raise exception 'Permission denied.' using errcode='42501'; end if;
 select jsonb_build_object(
  'metrics',jsonb_build_object(
    'missing_plan_assignment',(select count(*) from public.employees e where e.is_active and not exists(select 1 from public.employee_plan_assignments a where a.employee_id=e.id and current_date between a.effective_start_date and coalesce(a.effective_end_date,'9999-12-31'))),
    'waiting_eligibility',(select count(*) from public.comp_earnings where is_current and eligibility_status='pending_condition'),
    'returned_or_correction',(select count(*) from public.comp_earnings where is_current and (employee_verification_status='correction_requested' or manager_approval_status='returned' or executive_approval_status='returned')),
    'ready_for_payroll',(select count(*) from public.comp_earnings where is_current and payment_status='ready_for_payroll'),
    'open_credit_reviews',(select count(*) from public.comp_deal_credit_reviews where review_status='pending'),
    'open_corrections',(select count(*) from public.comp_credit_correction_requests where status in ('pending_review','approved_for_correction','ready_to_apply','adjustment_pending'))
  ),
  'missing_plan_assignments',coalesce((select jsonb_agg(jsonb_build_object('employee_id',e.id,'employee_name',e.full_name,'email',e.email) order by e.full_name) from public.employees e where e.is_active and not exists(select 1 from public.employee_plan_assignments a where a.employee_id=e.id and current_date between a.effective_start_date and coalesce(a.effective_end_date,'9999-12-31'))),'[]'::jsonb),
  'waiting_eligibility',coalesce((select jsonb_agg(jsonb_build_object('earning_id',ce.id,'employee_id',ce.employee_id,'employee_name',e.full_name,'earning_name',ce.earning_name,'earned_amount',ce.earned_amount,'earned_date',ce.earned_date,'condition',ce.eligibility_condition_description,'source_external_id',ce.source_external_id) order by ce.earned_date desc) from public.comp_earnings ce join public.employees e on e.id=ce.employee_id where ce.is_current and ce.eligibility_status='pending_condition'),'[]'::jsonb),
  'returned_or_correction',coalesce((select jsonb_agg(jsonb_build_object('earning_id',ce.id,'employee_id',ce.employee_id,'employee_name',e.full_name,'earning_name',ce.earning_name,'earned_amount',ce.earned_amount,'employee_verification_status',ce.employee_verification_status,'manager_approval_status',ce.manager_approval_status,'executive_approval_status',ce.executive_approval_status) order by ce.updated_at desc) from public.comp_earnings ce join public.employees e on e.id=ce.employee_id where ce.is_current and (ce.employee_verification_status='correction_requested' or ce.manager_approval_status='returned' or ce.executive_approval_status='returned')),'[]'::jsonb),
  'ready_for_payroll',coalesce((select jsonb_agg(jsonb_build_object('earning_id',ce.id,'employee_id',ce.employee_id,'employee_name',e.full_name,'earning_name',ce.earning_name,'approved_amount',ce.approved_amount,'expected_pay_period_label',ce.expected_pay_period_label) order by ce.updated_at desc) from public.comp_earnings ce join public.employees e on e.id=ce.employee_id where ce.is_current and ce.payment_status='ready_for_payroll'),'[]'::jsonb),
  'open_corrections',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'hubspot_deal_id',r.hubspot_deal_id,'status',r.status,'correction_path',r.correction_path,'current_employee_id',r.current_employee_id,'requested_employee_id',r.requested_employee_id,'requested_at',r.requested_at) order by r.requested_at desc) from public.comp_credit_correction_requests r where r.status in ('pending_review','approved_for_correction','ready_to_apply','adjustment_pending')),'[]'::jsonb)
 ) into result;
 return result;
end;$$;
revoke all on function public.get_comp_attention_workspace_data() from public,anon;
grant execute on function public.get_comp_attention_workspace_data() to authenticated;