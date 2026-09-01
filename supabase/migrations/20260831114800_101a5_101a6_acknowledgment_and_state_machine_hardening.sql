-- ============================================================
-- 101A(5)-101A(6) Plan lifecycle completion
-- Captures production changes installed and validated 2026-08-31.
-- ============================================================

-- Protect legacy credit rules after plan approval/activation.
create or replace function private.enforce_comp_credit_rule_editability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  selected_component_id uuid;
  selected_version_id uuid;
begin
  selected_component_id := case when tg_op='DELETE' then old.plan_component_id else new.plan_component_id end;
  select c.plan_version_id into selected_version_id from public.comp_plan_components c where c.id=selected_component_id;
  if selected_version_id is null then
    raise exception 'Compensation plan component does not exist.' using errcode='22023';
  end if;
  perform private.assert_plan_version_editable(selected_version_id);
  return case when tg_op='DELETE' then old else new end;
end;
$function$;

drop trigger if exists comp_credit_rules_enforce_editability on public.comp_credit_rules;
create trigger comp_credit_rules_enforce_editability
before insert or update or delete on public.comp_credit_rules
for each row execute function private.enforce_comp_credit_rule_editability();

-- Authenticated employee self-service plan acknowledgment.
create or replace function public.acknowledge_my_compensation_plan(
  selected_plan_version_id uuid,
  selected_acknowledgment_text text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid;
  current_employee_id uuid;
  assigned_plan_version_id uuid;
  plan_status public.plan_version_status;
  existing_acknowledgment_id uuid;
  new_acknowledgment_id uuid;
  plan_snapshot jsonb;
begin
  current_user_id:=auth.uid();
  if current_user_id is null then
    raise exception 'Authentication is required to acknowledge a compensation plan.' using errcode='42501';
  end if;

  select e.id into current_employee_id
  from public.profiles p
  join public.employees e on e.id=p.employee_id
  where p.id=current_user_id and p.is_active=true and e.is_active=true
  limit 1;

  if current_employee_id is null then
    raise exception 'The authenticated user is not linked to an active employee.' using errcode='42501';
  end if;

  select epa.plan_version_id,pv.status
  into assigned_plan_version_id,plan_status
  from public.employee_plan_assignments epa
  join public.comp_plan_versions pv on pv.id=epa.plan_version_id
  where epa.employee_id=current_employee_id
    and epa.plan_version_id=selected_plan_version_id
  order by epa.effective_start_date desc
  limit 1;

  if assigned_plan_version_id is null then
    raise exception 'This compensation plan version is not assigned to the authenticated employee.' using errcode='42501';
  end if;

  if plan_status <> 'active' then
    raise exception 'Only an active assigned compensation plan version may be acknowledged.' using errcode='22023';
  end if;

  if nullif(trim(coalesce(selected_acknowledgment_text,'')),'') is null then
    raise exception 'Acknowledgment text is required.' using errcode='22023';
  end if;

  select a.id into existing_acknowledgment_id
  from public.plan_version_acknowledgments a
  where a.plan_version_id=selected_plan_version_id
    and a.employee_id=current_employee_id;

  if existing_acknowledgment_id is not null then
    return jsonb_build_object(
      'status','already_acknowledged',
      'acknowledgment_id',existing_acknowledgment_id,
      'plan_version_id',selected_plan_version_id,
      'employee_id',current_employee_id
    );
  end if;

  select jsonb_build_object(
    'plan',jsonb_build_object(
      'plan_id',cp.id,
      'plan_code',cp.plan_code,
      'name',cp.name,
      'description',cp.description,
      'plan_version_id',pv.id,
      'version_number',pv.version_number,
      'status',pv.status,
      'effective_start_date',pv.effective_start_date,
      'effective_end_date',pv.effective_end_date,
      'currency_code',pv.currency_code,
      'approved_at',pv.approved_at
    ),
    'assignment',jsonb_build_object(
      'employee_id',epa.employee_id,
      'assignment_id',epa.id,
      'effective_start_date',epa.effective_start_date,
      'effective_end_date',epa.effective_end_date,
      'allocation_percent',epa.allocation_percent,
      'eligibility_waiting_period_days',epa.eligibility_waiting_period_days,
      'earnings_eligibility_date',epa.earnings_eligibility_date
    ),
    'components',coalesce((
      select jsonb_agg(jsonb_build_object(
        'component_id',c.id,
        'component_code',c.component_code,
        'name',c.name,
        'description',c.description,
        'calculation_type',c.calculation_type,
        'measurement_source',c.measurement_source,
        'measurement_period',c.measurement_period,
        'measurement_label',c.measurement_label,
        'maximum_payout',c.maximum_payout,
        'rule_configuration',c.rule_configuration
      ) order by c.calculation_order,c.component_code)
      from public.comp_plan_components c
      where c.plan_version_id=selected_plan_version_id and c.is_active=true
    ),'[]'::jsonb),
    'snapshot_created_at',pg_catalog.now()
  ) into plan_snapshot
  from public.employee_plan_assignments epa
  join public.comp_plan_versions pv on pv.id=epa.plan_version_id
  join public.comp_plans cp on cp.id=pv.comp_plan_id
  where epa.employee_id=current_employee_id
    and epa.plan_version_id=selected_plan_version_id
  order by epa.effective_start_date desc
  limit 1;

  insert into public.plan_version_acknowledgments(
    plan_version_id,employee_id,acknowledged_by,acknowledged_at,acknowledgment_text,plan_snapshot
  ) values (
    selected_plan_version_id,current_employee_id,current_user_id,pg_catalog.now(),trim(selected_acknowledgment_text),plan_snapshot
  ) returning id into new_acknowledgment_id;

  insert into public.app_access_audit_events(
    actor_user_id,event_type,event_reason,related_employee_id,new_state
  ) values (
    current_user_id,
    'comp_plan_version_acknowledged',
    'Employee acknowledged their assigned compensation plan version.',
    current_employee_id,
    jsonb_build_object(
      'acknowledgment_id',new_acknowledgment_id,
      'plan_version_id',selected_plan_version_id,
      'employee_id',current_employee_id
    )
  );

  return jsonb_build_object(
    'status','acknowledged',
    'acknowledgment_id',new_acknowledgment_id,
    'plan_version_id',selected_plan_version_id,
    'employee_id',current_employee_id
  );
end;
$function$;

revoke all on function public.acknowledge_my_compensation_plan(uuid,text) from public,anon;
grant execute on function public.acknowledge_my_compensation_plan(uuid,text) to authenticated;

-- Harden plan version lifecycle state machine and approval immutability.
create or replace function private.enforce_comp_plan_version_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.approved_at is not null then
    if new.approved_at is distinct from old.approved_at
       or new.approved_by is distinct from old.approved_by then
      raise exception 'Compensation plan approval metadata is immutable after approval.' using errcode='55000';
    end if;
  end if;

  if old.approved_at is not null then
    if new.comp_plan_id is distinct from old.comp_plan_id
       or new.version_number is distinct from old.version_number
       or new.effective_start_date is distinct from old.effective_start_date
       or new.currency_code is distinct from old.currency_code
       or new.notes is distinct from old.notes then
      raise exception 'Approved compensation plan versions are immutable. Create a new draft version to change plan terms.' using errcode='55000';
    end if;
  end if;

  if old.approved_at is not null and new.approved_at is null then
    raise exception 'Approval cannot be removed from an approved compensation plan version.' using errcode='55000';
  end if;

  if old.status='active' and new.status='draft' then
    raise exception 'An active compensation plan version cannot return to draft status.' using errcode='22023';
  end if;

  if old.status='retired' and new.status<>'retired' then
    raise exception 'A retired compensation plan version cannot be reactivated or returned to draft status.' using errcode='22023';
  end if;

  if new.status='active' and (new.approved_at is null or new.approved_by is null) then
    raise exception 'A compensation plan version must be approved before activation.' using errcode='22023';
  end if;

  if old.approved_at is not null
     and new.effective_end_date is distinct from old.effective_end_date
     and new.status<>'retired' then
    raise exception 'The effective end date of an approved compensation plan version may only change as part of retirement.' using errcode='55000';
  end if;

  if new.status='retired'
     and new.effective_end_date is not null
     and new.effective_end_date<new.effective_start_date then
    raise exception 'A retired compensation plan version cannot end before its effective start date.' using errcode='22023';
  end if;

  return new;
end;
$function$;
