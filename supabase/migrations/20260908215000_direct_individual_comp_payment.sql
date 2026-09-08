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

  select * into earning_row
  from public.comp_earnings
  where id = target_earning_id
  for update;

  if not found then
    raise exception 'Compensation earning not found.' using errcode = 'P0002';
  end if;

  if not earning_row.is_current then
    raise exception 'A superseded earning cannot be paid.' using errcode = '22023';
  end if;

  if earning_row.payment_status not in ('ready_for_payroll'::public.payment_status,'partially_paid'::public.payment_status) then
    raise exception 'This earning is not currently accepted and unpaid.' using errcode = '22023';
  end if;

  remaining_amount := greatest(coalesce(earning_row.approved_amount,0) - coalesce(earning_row.paid_amount,0),0);
  if remaining_amount <= 0 then
    raise exception 'No approved unpaid amount remains.' using errcode = '22023';
  end if;

  select full_name into employee_name from public.employees where id = earning_row.employee_id;

  insert into public.payroll_batches (
    batch_name,
    scheduled_payment_date,
    actual_payment_date,
    status,
    payment_reference,
    payment_method,
    notes,
    created_by,
    finalized_by,
    finalized_at,
    batch_origin
  ) values (
    coalesce(employee_name,'Employee') || ' individual payment ' || requested_actual_payment_date::text,
    requested_actual_payment_date,
    requested_actual_payment_date,
    'paid',
    nullif(trim(coalesce(requested_payment_reference,'')),''),
    nullif(trim(coalesce(requested_payment_method,'')),''),
    nullif(trim(coalesce(requested_notes,'')),''),
    actor,
    actor,
    now(),
    'direct_payment'
  ) returning id into batch_id;

  insert into public.payroll_payment_items (
    payroll_batch_id,
    comp_earning_id,
    employee_id,
    amount_paid,
    payment_details
  ) values (
    batch_id,
    target_earning_id,
    earning_row.employee_id,
    remaining_amount,
    nullif(trim(concat_ws(' | ',
      nullif(trim(coalesce(requested_payment_method,'')),''),
      nullif(trim(coalesce(requested_payment_reference,'')),''),
      nullif(trim(coalesce(requested_notes,'')),''))), '')
  ) returning id into item_id;

  update public.comp_earnings
  set paid_amount = coalesce(paid_amount,0) + remaining_amount,
      payment_status = 'paid'::public.payment_status
  where id = target_earning_id;

  insert into public.app_access_audit_events (
    actor_user_id,
    event_type,
    event_reason,
    new_state,
    related_employee_id
  ) values (
    actor,
    'comp_earning_payment_recorded',
    'Individual compensation payment marked paid.',
    jsonb_build_object(
      'earning_id', target_earning_id,
      'payroll_batch_id', batch_id,
      'payroll_payment_item_id', item_id,
      'amount_paid', remaining_amount,
      'actual_payment_date', requested_actual_payment_date,
      'payment_reference', nullif(trim(coalesce(requested_payment_reference,'')),''),
      'payment_method', nullif(trim(coalesce(requested_payment_method,'')),'')
    ),
    earning_row.employee_id
  );

  return jsonb_build_object(
    'status','paid',
    'earning_id',target_earning_id,
    'amount_paid',remaining_amount,
    'actual_payment_date',requested_actual_payment_date,
    'payroll_batch_id',batch_id
  );
end;
$function$;

grant execute on function public.mark_comp_earning_paid(uuid,date,text,text,text) to authenticated;
