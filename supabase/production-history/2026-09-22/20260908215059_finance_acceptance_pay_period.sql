alter table public.comp_earnings
  add column if not exists expected_pay_period_start date,
  add column if not exists expected_pay_period_end date,
  add column if not exists finance_accepted_by uuid,
  add column if not exists finance_accepted_at timestamptz;

create or replace function public.accept_comp_earning_for_pay_period(
  target_task_id uuid,
  requested_pay_period_start date,
  requested_pay_period_end date,
  requested_pay_period_label text default null,
  action_comments text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := auth.uid();
  t public.comp_earning_handoff_tasks%rowtype;
  normalized_label text;
  normalized_comments text := nullif(trim(coalesce(action_comments,'')),'');
  is_admin boolean := false;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode='42501';
  end if;

  if requested_pay_period_start is null or requested_pay_period_end is null then
    raise exception 'Payroll period start and end are required.' using errcode='22023';
  end if;

  if requested_pay_period_end < requested_pay_period_start then
    raise exception 'Payroll period end cannot precede its start.' using errcode='22023';
  end if;

  is_admin := private.has_app_role('system_administrator');

  select * into t
  from public.comp_earning_handoff_tasks
  where id=target_task_id
  for update;

  if not found then
    raise exception 'Handoff task not found.' using errcode='P0002';
  end if;

  if t.status <> 'pending' then
    raise exception 'This handoff task is no longer pending.' using errcode='22023';
  end if;

  if t.step_type <> 'finance_acknowledgement' then
    raise exception 'This task is not a Finance acceptance step.' using errcode='22023';
  end if;

  if not is_admin and actor is distinct from t.assigned_user_id then
    raise exception 'This handoff task is not assigned to you.' using errcode='42501';
  end if;

  if not private.has_permission('payments.view') then
    raise exception 'You are not permitted to accept payment handoffs.' using errcode='42501';
  end if;

  normalized_label := nullif(trim(coalesce(requested_pay_period_label,'')),'');
  if normalized_label is null then
    normalized_label := to_char(requested_pay_period_start,'Mon FMDD, YYYY') || ' - ' || to_char(requested_pay_period_end,'Mon FMDD, YYYY');
  end if;

  update public.comp_earning_handoff_tasks
  set status='acknowledged',
      comments=normalized_comments,
      completed_by=actor,
      completed_at=now(),
      updated_at=now()
  where id=t.id;

  update public.comp_earnings
  set expected_pay_period_start=requested_pay_period_start,
      expected_pay_period_end=requested_pay_period_end,
      expected_pay_period_label=normalized_label,
      finance_accepted_by=actor,
      finance_accepted_at=now()
  where id=t.comp_earning_id;

  perform private.refresh_comp_earning_payroll_readiness(t.comp_earning_id);

  insert into public.app_access_audit_events(
    actor_user_id,event_type,event_reason,new_state,related_employee_id
  )
  select actor,
         'comp_earning_finance_accepted',
         normalized_comments,
         jsonb_build_object(
           'handoff_task_id',t.id,
           'earning_id',t.comp_earning_id,
           'pay_period_start',requested_pay_period_start,
           'pay_period_end',requested_pay_period_end,
           'pay_period_label',normalized_label,
           'acted_as_system_admin',is_admin
         ),
         e.employee_id
  from public.comp_earnings e
  where e.id=t.comp_earning_id;

  return jsonb_build_object(
    'status','accepted',
    'handoff_task_id',t.id,
    'earning_id',t.comp_earning_id,
    'pay_period_start',requested_pay_period_start,
    'pay_period_end',requested_pay_period_end,
    'pay_period_label',normalized_label,
    'acted_as_system_admin',is_admin
  );
end;
$function$;

grant execute on function public.accept_comp_earning_for_pay_period(uuid,date,date,text,text) to authenticated;

create or replace function public.assign_comp_earning_pay_period(
  target_earning_id uuid,
  requested_pay_period_start date,
  requested_pay_period_end date,
  requested_pay_period_label text default null,
  action_comments text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := auth.uid();
  e public.comp_earnings%rowtype;
  normalized_label text;
begin
  if actor is null or not private.has_permission('payments.view') then
    raise exception 'You are not permitted to assign payroll periods.' using errcode='42501';
  end if;

  if requested_pay_period_start is null or requested_pay_period_end is null then
    raise exception 'Payroll period start and end are required.' using errcode='22023';
  end if;

  if requested_pay_period_end < requested_pay_period_start then
    raise exception 'Payroll period end cannot precede its start.' using errcode='22023';
  end if;

  select * into e from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;

  if e.payment_status not in ('ready_for_payroll'::public.payment_status,'partially_paid'::public.payment_status) then
    raise exception 'Only accepted, unpaid compensation can be assigned to a payroll period.' using errcode='22023';
  end if;

  normalized_label := nullif(trim(coalesce(requested_pay_period_label,'')),'');
  if normalized_label is null then
    normalized_label := to_char(requested_pay_period_start,'Mon FMDD, YYYY') || ' - ' || to_char(requested_pay_period_end,'Mon FMDD, YYYY');
  end if;

  update public.comp_earnings
  set expected_pay_period_start=requested_pay_period_start,
      expected_pay_period_end=requested_pay_period_end,
      expected_pay_period_label=normalized_label
  where id=target_earning_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values(actor,'comp_earning_pay_period_assigned',nullif(trim(coalesce(action_comments,'')),''),jsonb_build_object('earning_id',target_earning_id,'pay_period_start',requested_pay_period_start,'pay_period_end',requested_pay_period_end,'pay_period_label',normalized_label),e.employee_id);

  return jsonb_build_object('status','assigned','earning_id',target_earning_id,'pay_period_start',requested_pay_period_start,'pay_period_end',requested_pay_period_end,'pay_period_label',normalized_label);
end;
$function$;

grant execute on function public.assign_comp_earning_pay_period(uuid,date,date,text,text) to authenticated;