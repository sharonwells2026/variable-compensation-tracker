-- 101G Canonical Payroll Service
-- Exact production contract reconstructed from validated live definitions on 2026-08-31.

create or replace function public.create_comp_payroll_batch(
  requested_batch_name text,
  requested_period_start date default null,
  requested_period_end date default null,
  requested_payment_date date default null,
  requested_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid:=(select auth.uid());
  new_batch_id uuid;
begin
  if actor is null or not private.has_permission('payments.schedule') then
    raise exception 'You are not permitted to create payroll batches.' using errcode='42501';
  end if;
  if nullif(trim(coalesce(requested_batch_name,'')),'') is null then
    raise exception 'Payroll batch name is required.' using errcode='22023';
  end if;
  if requested_period_start is not null and requested_period_end is not null and requested_period_end<requested_period_start then
    raise exception 'Payroll period end cannot precede its start.' using errcode='22023';
  end if;

  insert into public.payroll_batches(batch_name,payroll_period_start,payroll_period_end,scheduled_payment_date,status,notes,created_by,batch_origin)
  values(trim(requested_batch_name),requested_period_start,requested_period_end,requested_payment_date,'draft',nullif(trim(coalesce(requested_notes,'')),''),actor,'application')
  returning id into new_batch_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(actor,'payroll_batch_created','Compensation payroll batch created.',jsonb_build_object('payroll_batch_id',new_batch_id,'batch_name',trim(requested_batch_name),'payroll_period_start',requested_period_start,'payroll_period_end',requested_period_end,'scheduled_payment_date',requested_payment_date));
  return new_batch_id;
end;
$function$;
revoke all on function public.create_comp_payroll_batch(text,date,date,date,text) from public,anon;
grant execute on function public.create_comp_payroll_batch(text,date,date,date,text) to authenticated;

create or replace function public.add_comp_earning_to_payroll_batch(
  target_payroll_batch_id uuid,
  target_earning_id uuid,
  requested_amount numeric default null,
  requested_payment_details text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid:=(select auth.uid());
  batch_row public.payroll_batches%rowtype;
  earning_row public.comp_earnings%rowtype;
  already_paid numeric:=0;
  already_scheduled numeric:=0;
  available_amount numeric:=0;
  payment_amount numeric;
  new_item_id uuid;
begin
  if actor is null or not private.has_permission('payments.schedule') then raise exception 'You are not permitted to schedule compensation payments.' using errcode='42501'; end if;
  select * into batch_row from public.payroll_batches where id=target_payroll_batch_id for update;
  if not found then raise exception 'Payroll batch not found.' using errcode='P0002'; end if;
  if batch_row.status<>'draft' then raise exception 'Earnings may only be added to a draft payroll batch.' using errcode='22023'; end if;

  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
  if not earning_row.is_current then raise exception 'A superseded earning cannot be paid.' using errcode='22023'; end if;
  if earning_row.payment_status not in ('ready_for_payroll'::public.payment_status,'partially_paid'::public.payment_status) then raise exception 'This earning is not ready for payroll.' using errcode='22023'; end if;
  if earning_row.approved_amount<=0 then raise exception 'This earning does not have an approved amount.' using errcode='22023'; end if;

  select coalesce(sum(item.amount_paid),0) into already_paid
  from public.payroll_payment_items item join public.payroll_batches batch on batch.id=item.payroll_batch_id
  where item.comp_earning_id=target_earning_id and batch.status='paid';

  select coalesce(sum(item.amount_paid),0) into already_scheduled
  from public.payroll_payment_items item join public.payroll_batches batch on batch.id=item.payroll_batch_id
  where item.comp_earning_id=target_earning_id and batch.status in ('draft','scheduled','finalized');

  available_amount:=earning_row.approved_amount-already_paid-already_scheduled;
  if available_amount<=0 then raise exception 'No unpaid approved amount remains available for scheduling.' using errcode='22023'; end if;
  payment_amount:=coalesce(requested_amount,available_amount);
  if payment_amount<=0 then raise exception 'Scheduled payment amount must be greater than zero.' using errcode='22023'; end if;
  if payment_amount>available_amount then raise exception 'Scheduled payment exceeds the remaining approved unpaid amount.' using errcode='22023'; end if;

  insert into public.payroll_payment_items(payroll_batch_id,comp_earning_id,employee_id,amount_paid,payment_details)
  values(target_payroll_batch_id,target_earning_id,earning_row.employee_id,payment_amount,nullif(trim(coalesce(requested_payment_details,'')),''))
  returning id into new_item_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values(actor,'earning_added_to_payroll_batch','Approved compensation earning added to payroll batch.',jsonb_build_object('payroll_batch_id',target_payroll_batch_id,'payroll_payment_item_id',new_item_id,'earning_id',target_earning_id,'scheduled_amount',payment_amount),earning_row.employee_id);
  return new_item_id;
end;
$function$;
revoke all on function public.add_comp_earning_to_payroll_batch(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.add_comp_earning_to_payroll_batch(uuid,uuid,numeric,text) to authenticated;

create or replace function public.schedule_comp_payroll_batch(target_payroll_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid:=(select auth.uid());
  batch_row public.payroll_batches%rowtype;
  item_count integer;
begin
  if actor is null or not private.has_permission('payments.schedule') then raise exception 'You are not permitted to schedule payroll.' using errcode='42501'; end if;
  select * into batch_row from public.payroll_batches where id=target_payroll_batch_id for update;
  if not found then raise exception 'Payroll batch not found.' using errcode='P0002'; end if;
  if batch_row.status<>'draft' then raise exception 'Only a draft payroll batch can be scheduled.' using errcode='22023'; end if;
  select count(*) into item_count from public.payroll_payment_items where payroll_batch_id=target_payroll_batch_id;
  if item_count=0 then raise exception 'A payroll batch cannot be scheduled without payment items.' using errcode='22023'; end if;

  if exists(
    select 1 from public.payroll_payment_items item
    join public.comp_earnings earning on earning.id=item.comp_earning_id
    where item.payroll_batch_id=target_payroll_batch_id
      and (not earning.is_current or earning.payment_status not in ('ready_for_payroll'::public.payment_status,'partially_paid'::public.payment_status) or earning.approved_amount<=0)
  ) then raise exception 'One or more payroll items are no longer eligible to be scheduled.' using errcode='22023'; end if;

  update public.payroll_batches set status='scheduled' where id=target_payroll_batch_id;
  update public.comp_earnings earning set payment_status='scheduled'::public.payment_status
  where earning.id in (select item.comp_earning_id from public.payroll_payment_items item where item.payroll_batch_id=target_payroll_batch_id);

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(actor,'payroll_batch_scheduled','Compensation payroll batch scheduled and locked.',jsonb_build_object('payroll_batch_id',target_payroll_batch_id,'item_count',item_count));

  return jsonb_build_object('status','scheduled','payroll_batch_id',target_payroll_batch_id,'item_count',item_count);
end;
$function$;
revoke all on function public.schedule_comp_payroll_batch(uuid) from public,anon;
grant execute on function public.schedule_comp_payroll_batch(uuid) to authenticated;

create or replace function public.mark_comp_payroll_batch_paid(
  target_payroll_batch_id uuid,
  requested_actual_payment_date date,
  requested_payment_reference text default null,
  requested_payment_method text default null,
  requested_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid:=(select auth.uid());
  batch_row public.payroll_batches%rowtype;
  payment_item record;
  cumulative_paid numeric;
  item_count integer:=0;
begin
  if actor is null or not private.has_permission('payments.mark_paid') then raise exception 'You are not permitted to mark compensation payments paid.' using errcode='42501'; end if;
  if requested_actual_payment_date is null then raise exception 'Actual payment date is required.' using errcode='22023'; end if;

  select * into batch_row from public.payroll_batches where id=target_payroll_batch_id for update;
  if not found then raise exception 'Payroll batch not found.' using errcode='P0002'; end if;
  if batch_row.status not in ('scheduled','finalized') then raise exception 'Only a scheduled or finalized payroll batch can be marked paid.' using errcode='22023'; end if;

  for payment_item in
    select item.id,item.comp_earning_id,item.employee_id,item.amount_paid
    from public.payroll_payment_items item
    where item.payroll_batch_id=target_payroll_batch_id
    order by item.id
  loop
    item_count:=item_count+1;
    perform 1 from public.comp_earnings where id=payment_item.comp_earning_id for update;

    select coalesce(sum(item.amount_paid),0) into cumulative_paid
    from public.payroll_payment_items item join public.payroll_batches batch on batch.id=item.payroll_batch_id
    where item.comp_earning_id=payment_item.comp_earning_id
      and (batch.status='paid' or batch.id=target_payroll_batch_id);

    if cumulative_paid>(select approved_amount from public.comp_earnings where id=payment_item.comp_earning_id) then
      raise exception 'Payment would exceed the approved compensation amount.' using errcode='22023';
    end if;

    update public.comp_earnings set
      paid_amount=cumulative_paid,
      payment_status=case when cumulative_paid>=approved_amount then 'paid'::public.payment_status else 'partially_paid'::public.payment_status end
    where id=payment_item.comp_earning_id;

    insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
    values(actor,'comp_earning_payment_recorded','Compensation payment recorded through payroll.',jsonb_build_object('payroll_batch_id',target_payroll_batch_id,'payroll_payment_item_id',payment_item.id,'earning_id',payment_item.comp_earning_id,'amount_paid_this_batch',payment_item.amount_paid,'cumulative_paid_amount',cumulative_paid,'actual_payment_date',requested_actual_payment_date),payment_item.employee_id);
  end loop;

  if item_count=0 then raise exception 'Payroll batch contains no payment items.' using errcode='22023'; end if;

  update public.payroll_batches set
    status='paid',actual_payment_date=requested_actual_payment_date,
    payment_reference=nullif(trim(coalesce(requested_payment_reference,'')),''),
    payment_method=nullif(trim(coalesce(requested_payment_method,'')),''),
    notes=coalesce(nullif(trim(coalesce(requested_notes,'')),''),notes),
    finalized_by=actor,finalized_at=now()
  where id=target_payroll_batch_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(actor,'payroll_batch_paid','Compensation payroll batch marked paid.',jsonb_build_object('payroll_batch_id',target_payroll_batch_id,'actual_payment_date',requested_actual_payment_date,'payment_reference',nullif(trim(coalesce(requested_payment_reference,'')),''),'item_count',item_count));

  return jsonb_build_object('status','paid','payroll_batch_id',target_payroll_batch_id,'item_count',item_count,'actual_payment_date',requested_actual_payment_date);
end;
$function$;
revoke all on function public.mark_comp_payroll_batch_paid(uuid,date,text,text,text) from public,anon;
grant execute on function public.mark_comp_payroll_batch_paid(uuid,date,text,text,text) to authenticated;
