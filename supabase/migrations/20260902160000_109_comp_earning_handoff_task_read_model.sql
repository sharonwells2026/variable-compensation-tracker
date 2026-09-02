create or replace function public.get_my_comp_earning_handoff_tasks(include_completed boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  actor uuid := auth.uid();
  result jsonb;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'task_id', t.id,
    'earning_id', t.comp_earning_id,
    'workflow_version_id', t.workflow_version_id,
    'stage_order', t.stage_order,
    'step_name', t.step_name,
    'step_type', t.step_type,
    'is_required_for_payment', t.is_required_for_payment,
    'requires_payment_details', t.requires_payment_details,
    'status', t.status,
    'payment_details', t.payment_details,
    'comments', t.comments,
    'completed_at', t.completed_at,
    'created_at', t.created_at,
    'employee_id', e.employee_id,
    'employee_name', emp.full_name,
    'employee_email', emp.email,
    'earning_name', e.earning_name,
    'earning_description', e.earning_description,
    'earned_date', e.earned_date,
    'earned_amount', e.earned_amount,
    'eligible_amount', e.eligible_amount,
    'approved_amount', e.approved_amount,
    'eligibility_status', e.eligibility_status,
    'payment_status', e.payment_status,
    'expected_payment_date', e.expected_payment_date,
    'expected_pay_period_label', e.expected_pay_period_label
  ) order by case when t.status='pending' then 0 else 1 end, t.created_at desc), '[]'::jsonb)
  into result
  from public.comp_earning_handoff_tasks t
  join public.comp_earnings e on e.id=t.comp_earning_id
  join public.employees emp on emp.id=e.employee_id
  where t.assigned_user_id=actor
    and (include_completed or t.status='pending');

  return result;
end;
$function$;

revoke all on function public.get_my_comp_earning_handoff_tasks(boolean) from public;
grant execute on function public.get_my_comp_earning_handoff_tasks(boolean) to authenticated;
