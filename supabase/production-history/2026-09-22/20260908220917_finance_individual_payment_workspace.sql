create or replace function public.get_finance_payment_workspace_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
  result jsonb;
begin
  if actor is null or not private.has_permission('payments.view') then
    raise exception 'You are not permitted to view Finance payments.' using errcode='42501';
  end if;

  select jsonb_build_object(
    'accepted_unpaid', coalesce((
      select jsonb_agg(jsonb_build_object(
        'earning_id', e.id,
        'employee_id', e.employee_id,
        'employee_name', emp.full_name,
        'earning_name', e.earning_name,
        'earned_date', e.earned_date,
        'earned_amount', e.earned_amount,
        'approved_amount', e.approved_amount,
        'paid_amount', coalesce(e.paid_amount,0),
        'remaining_amount', greatest(coalesce(e.approved_amount,0)-coalesce(e.paid_amount,0),0),
        'payment_status', e.payment_status,
        'pay_period_start', e.expected_pay_period_start,
        'pay_period_end', e.expected_pay_period_end,
        'pay_period_label', e.expected_pay_period_label,
        'finance_accepted_at', e.finance_accepted_at
      ) order by coalesce(e.expected_pay_period_start,e.earned_date),emp.full_name,e.earned_date,e.id)
      from public.comp_earnings e
      join public.employees emp on emp.id=e.employee_id
      where e.is_current
        and e.approved_amount > 0
        and e.payment_status in ('ready_for_payroll'::public.payment_status,'partially_paid'::public.payment_status)
    ), '[]'::jsonb),
    'paid', coalesce((
      select jsonb_agg(jsonb_build_object(
        'earning_id', e.id,
        'employee_id', e.employee_id,
        'employee_name', emp.full_name,
        'earning_name', e.earning_name,
        'earned_date', e.earned_date,
        'approved_amount', e.approved_amount,
        'paid_amount', e.paid_amount,
        'payment_status', e.payment_status,
        'pay_period_start', e.expected_pay_period_start,
        'pay_period_end', e.expected_pay_period_end,
        'pay_period_label', e.expected_pay_period_label,
        'actual_payment_date', pay.actual_payment_date,
        'payment_reference', pay.payment_reference,
        'payment_method', pay.payment_method
      ) order by pay.actual_payment_date desc nulls last,emp.full_name,e.id)
      from public.comp_earnings e
      join public.employees emp on emp.id=e.employee_id
      left join lateral (
        select b.actual_payment_date,b.payment_reference,b.payment_method
        from public.payroll_payment_items i
        join public.payroll_batches b on b.id=i.payroll_batch_id
        where i.comp_earning_id=e.id and b.status='paid'
        order by b.actual_payment_date desc nulls last,b.created_at desc
        limit 1
      ) pay on true
      where e.is_current and e.payment_status='paid'::public.payment_status
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$function$;

revoke all on function public.get_finance_payment_workspace_data() from public;
grant execute on function public.get_finance_payment_workspace_data() to authenticated;