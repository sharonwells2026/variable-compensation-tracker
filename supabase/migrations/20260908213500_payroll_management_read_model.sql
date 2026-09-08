create or replace function public.get_comp_payroll_management_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  result jsonb;
begin
  if actor is null or not private.has_permission('payments.view') then
    raise exception 'You are not permitted to view payroll management.' using errcode='42501';
  end if;

  select jsonb_build_object(
    'ready_earnings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'earning_id', e.id,
        'employee_id', e.employee_id,
        'employee_name', emp.full_name,
        'earning_name', e.earning_name,
        'earned_date', e.earned_date,
        'earned_amount', e.earned_amount,
        'approved_amount', e.approved_amount,
        'payment_status', e.payment_status,
        'remaining_amount', greatest(e.approved_amount - coalesce((
          select sum(i.amount_paid)
          from public.payroll_payment_items i
          join public.payroll_batches b on b.id=i.payroll_batch_id
          where i.comp_earning_id=e.id and b.status in ('draft','scheduled','finalized','paid')
        ),0),0)
      ) order by emp.full_name,e.earned_date,e.id)
      from public.comp_earnings e
      join public.employees emp on emp.id=e.employee_id
      where e.is_current
        and e.approved_amount > 0
        and e.payment_status in ('ready_for_payroll'::public.payment_status,'partially_paid'::public.payment_status)
    ), '[]'::jsonb),
    'batches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'batch_name', b.batch_name,
        'payroll_period_start', b.payroll_period_start,
        'payroll_period_end', b.payroll_period_end,
        'scheduled_payment_date', b.scheduled_payment_date,
        'actual_payment_date', b.actual_payment_date,
        'status', b.status,
        'payment_reference', b.payment_reference,
        'payment_method', b.payment_method,
        'notes', b.notes,
        'created_at', b.created_at,
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', i.id,
            'earning_id', i.comp_earning_id,
            'employee_id', i.employee_id,
            'employee_name', emp2.full_name,
            'earning_name', e2.earning_name,
            'amount', i.amount_paid,
            'payment_details', i.payment_details
          ) order by emp2.full_name,e2.earned_date,i.id)
          from public.payroll_payment_items i
          join public.comp_earnings e2 on e2.id=i.comp_earning_id
          join public.employees emp2 on emp2.id=i.employee_id
          where i.payroll_batch_id=b.id
        ), '[]'::jsonb)
      ) order by b.created_at desc,b.id)
      from public.payroll_batches b
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

revoke execute on function public.get_comp_payroll_management_data() from public, anon;
grant execute on function public.get_comp_payroll_management_data() to authenticated;
