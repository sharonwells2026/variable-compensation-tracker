create or replace function public.get_finance_payment_workspace_data()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := auth.uid();
  result jsonb;
begin
  if actor is null or not private.has_permission('payments.view') then
    raise exception 'You are not permitted to view Finance payment data.' using errcode='42501';
  end if;

  select jsonb_build_object(
    'accepted_unpaid', coalesce((
      select jsonb_agg(jsonb_build_object(
        'earning_id',e.id,
        'employee_id',e.employee_id,
        'employee_name',emp.full_name,
        'earning_name',e.earning_name,
        'earned_date',e.earned_date,
        'earned_amount',e.earned_amount,
        'approved_amount',e.approved_amount,
        'paid_amount',e.paid_amount,
        'remaining_amount',greatest(coalesce(e.approved_amount,0)-coalesce(e.paid_amount,0),0),
        'payment_status',e.payment_status,
        'pay_period_start',e.expected_pay_period_start,
        'pay_period_end',e.expected_pay_period_end,
        'pay_period_label',e.expected_pay_period_label,
        'finance_accepted_at',e.finance_accepted_at
      ) order by e.finance_accepted_at nulls last,e.earned_date,emp.full_name)
      from public.comp_earnings e
      join public.employees emp on emp.id=e.employee_id
      where e.is_current
        and e.payment_status in ('ready_for_payroll'::public.payment_status,'partially_paid'::public.payment_status)
        and e.approved_amount>coalesce(e.paid_amount,0)
    ),'[]'::jsonb),
    'paid', coalesce((
      select jsonb_agg(jsonb_build_object(
        'earning_id',e.id,
        'employee_id',e.employee_id,
        'employee_name',emp.full_name,
        'earning_name',e.earning_name,
        'earned_date',e.earned_date,
        'earned_amount',e.earned_amount,
        'approved_amount',e.approved_amount,
        'paid_amount',e.paid_amount,
        'payment_status',e.payment_status,
        'pay_period_start',e.expected_pay_period_start,
        'pay_period_end',e.expected_pay_period_end,
        'pay_period_label',e.expected_pay_period_label,
        'actual_payment_date',(
          select pb.actual_payment_date
          from public.payroll_payment_items ppi
          join public.payroll_batches pb on pb.id=ppi.payroll_batch_id
          where ppi.comp_earning_id=e.id and pb.status='paid'
          order by pb.actual_payment_date desc nulls last,pb.finalized_at desc nulls last
          limit 1
        ),
        'payment_reference',(
          select pb.payment_reference
          from public.payroll_payment_items ppi
          join public.payroll_batches pb on pb.id=ppi.payroll_batch_id
          where ppi.comp_earning_id=e.id and pb.status='paid'
          order by pb.actual_payment_date desc nulls last,pb.finalized_at desc nulls last
          limit 1
        ),
        'payment_method',(
          select pb.payment_method
          from public.payroll_payment_items ppi
          join public.payroll_batches pb on pb.id=ppi.payroll_batch_id
          where ppi.comp_earning_id=e.id and pb.status='paid'
          order by pb.actual_payment_date desc nulls last,pb.finalized_at desc nulls last
          limit 1
        )
      ) order by e.updated_at desc)
      from public.comp_earnings e
      join public.employees emp on emp.id=e.employee_id
      where e.is_current and e.payment_status='paid'::public.payment_status
    ),'[]'::jsonb)
  ) into result;

  return result;
end;
$function$;

grant execute on function public.get_finance_payment_workspace_data() to authenticated;

create or replace function public.mark_comp_earning_paid(
  target_earning_id uuid,
  requested_actual_payment_date date,
  requested_payment_reference text default null,
  requested_payment_method text default null,
  requested_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
  earning_row public.comp_earnings%rowtype;
  employee_name text;
  remaining_amount numeric;
  batch_id uuid;
  item_id uuid;
begin
  if actor is null or not private.has_permission('payments.mark_paid') then
    raise exception 'You are not permitted to mark compensation payments paid.' using errcode = '42501';
  end if;

  if requested_actual_payment_date is null then
    raise exception 'Actual payment date is required.' using errcode = '22023';
  end if;

  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
  if not earning_row.is_current then raise exception 'A superseded earning cannot be paid.' using errcode='22023'; end if;
  if earning_row.payment_status not in ('ready_for_payroll'::public.payment_status,'partially_paid'::public.payment_status) then
    raise exception 'This earning is not currently accepted and unpaid.' using errcode='22023';
  end if;
  if earning_row.expected_pay_period_start is null or earning_row.expected_pay_period_end is null then
    raise exception 'A payroll period must be assigned before this earning can be marked paid.' using errcode='22023';
  end if;

  remaining_amount := greatest(coalesce(earning_row.approved_amount,0)-coalesce(earning_row.paid_amount,0),0);
  if remaining_amount<=0 then raise exception 'No approved unpaid amount remains.' using errcode='22023'; end if;

  select full_name into employee_name from public.employees where id=earning_row.employee_id;

  insert into public.payroll_batches(batch_name,payroll_period_start,payroll_period_end,scheduled_payment_date,actual_payment_date,status,payment_reference,payment_method,notes,created_by,finalized_by,finalized_at,batch_origin)
  values(coalesce(employee_name,'Employee')||' individual payment '||requested_actual_payment_date::text,
         earning_row.expected_pay_period_start,earning_row.expected_pay_period_end,requested_actual_payment_date,requested_actual_payment_date,'paid',
         nullif(trim(coalesce(requested_payment_reference,'')),''),nullif(trim(coalesce(requested_payment_method,'')),''),nullif(trim(coalesce(requested_notes,'')),''),actor,actor,now(),'direct_payment')
  returning id into batch_id;

  insert into public.payroll_payment_items(payroll_batch_id,comp_earning_id,employee_id,amount_paid,payment_details)
  values(batch_id,target_earning_id,earning_row.employee_id,remaining_amount,
         nullif(trim(concat_ws(' | ',nullif(trim(coalesce(requested_payment_method,'')),''),nullif(trim(coalesce(requested_payment_reference,'')),''),nullif(trim(coalesce(requested_notes,'')),''))),''))
  returning id into item_id;

  update public.comp_earnings
  set paid_amount=coalesce(paid_amount,0)+remaining_amount,payment_status='paid'::public.payment_status
  where id=target_earning_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values(actor,'comp_earning_payment_recorded','Individual compensation payment marked paid.',jsonb_build_object('earning_id',target_earning_id,'payroll_batch_id',batch_id,'payroll_payment_item_id',item_id,'amount_paid',remaining_amount,'actual_payment_date',requested_actual_payment_date,'pay_period_start',earning_row.expected_pay_period_start,'pay_period_end',earning_row.expected_pay_period_end,'payment_reference',nullif(trim(coalesce(requested_payment_reference,'')),''),'payment_method',nullif(trim(coalesce(requested_payment_method,'')),'')),earning_row.employee_id);

  return jsonb_build_object('status','paid','earning_id',target_earning_id,'amount_paid',remaining_amount,'actual_payment_date',requested_actual_payment_date,'payroll_batch_id',batch_id);
end;
$function$;

grant execute on function public.mark_comp_earning_paid(uuid,date,text,text,text) to authenticated;