-- ============================================================
-- 099 - Plan Administration Service Layer
-- Applied manually to production and verified before source-control sync.
-- Full definitions reconciled from live production.
-- ============================================================

create or replace function public.create_compensation_plan(
  selected_name text,
  selected_plan_code text,
  selected_description text default null,
  selected_plan_type text default 'variable_compensation',
  selected_effective_start_date date default current_date,
  selected_currency_code text default 'USD',
  selected_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  new_plan_id uuid;
  new_version_id uuid;
  normalized_code text := upper(trim(selected_plan_code));
begin
  if not private.has_permission('plans.create') then
    raise exception 'Plan creation is not permitted.' using errcode = '42501';
  end if;
  if trim(coalesce(selected_name,'')) = '' then
    raise exception 'Plan name is required.' using errcode = '22023';
  end if;
  if normalized_code = '' then
    raise exception 'Plan code is required.' using errcode = '22023';
  end if;
  if exists (select 1 from public.comp_plans where plan_code = normalized_code) then
    raise exception 'A plan already exists with code %.', normalized_code using errcode = '23505';
  end if;
  insert into public.comp_plans (name,plan_code,description,plan_type,owner_id,is_active)
  values (
    trim(selected_name),normalized_code,
    nullif(trim(coalesce(selected_description,'')),''),
    nullif(trim(coalesce(selected_plan_type,'')),''),
    auth.uid(),true
  ) returning id into new_plan_id;
  insert into public.comp_plan_versions (
    comp_plan_id,version_number,status,effective_start_date,currency_code,notes
  ) values (
    new_plan_id,1,'draft',selected_effective_start_date,
    upper(trim(coalesce(selected_currency_code,'USD'))),
    nullif(trim(coalesce(selected_notes,'')),'')
  ) returning id into new_version_id;
  insert into public.app_access_audit_events (actor_user_id,event_type,event_reason,new_state)
  values (
    auth.uid(),'comp_plan_created',
    'A compensation plan and initial draft version were created.',
    jsonb_build_object('plan_id',new_plan_id,'plan_version_id',new_version_id,'plan_code',normalized_code,'version_number',1)
  );
  return jsonb_build_object('status','created','plan_id',new_plan_id,'plan_version_id',new_version_id,'version_number',1);
end;
$function$;

revoke all on function public.create_compensation_plan(text,text,text,text,date,text,text) from public;
grant execute on function public.create_compensation_plan(text,text,text,text,date,text,text) to authenticated;

create or replace function public.create_compensation_plan_version(
  selected_plan_id uuid,
  selected_effective_start_date date,
  selected_effective_end_date date default null,
  selected_currency_code text default 'USD',
  selected_notes text default null,
  copy_components_from_version_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  next_version_number integer;
  new_version_id uuid;
begin
  if not private.has_permission('plans.create') then
    raise exception 'Plan version creation is not permitted.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.comp_plans where id = selected_plan_id and is_active = true) then
    raise exception 'The selected plan does not exist or is inactive.' using errcode = '22023';
  end if;
  if selected_effective_end_date is not null and selected_effective_end_date < selected_effective_start_date then
    raise exception 'Effective end date cannot be before start date.' using errcode = '22023';
  end if;
  select coalesce(max(version_number),0) + 1
  into next_version_number
  from public.comp_plan_versions
  where comp_plan_id = selected_plan_id;
  insert into public.comp_plan_versions (
    comp_plan_id,version_number,status,effective_start_date,effective_end_date,currency_code,notes
  ) values (
    selected_plan_id,next_version_number,'draft',selected_effective_start_date,selected_effective_end_date,
    upper(trim(coalesce(selected_currency_code,'USD'))),nullif(trim(coalesce(selected_notes,'')),'')
  ) returning id into new_version_id;
  if copy_components_from_version_id is not null then
    if not exists (
      select 1 from public.comp_plan_versions
      where id = copy_components_from_version_id and comp_plan_id = selected_plan_id
    ) then
      raise exception 'Source version does not belong to this plan.' using errcode = '22023';
    end if;
    insert into public.comp_plan_components (
      plan_version_id,name,component_code,description,calculation_type,measurement_source,
      measurement_period,calculation_order,rule_configuration,maximum_payout,is_active,
      payout_timing_method,allow_manager_payout_override,measurement_label
    )
    select
      new_version_id,name,component_code,description,calculation_type,measurement_source,
      measurement_period,calculation_order,rule_configuration,maximum_payout,is_active,
      payout_timing_method,allow_manager_payout_override,measurement_label
    from public.comp_plan_components
    where plan_version_id = copy_components_from_version_id;
  end if;
  insert into public.app_access_audit_events (actor_user_id,event_type,event_reason,new_state)
  values (
    auth.uid(),'comp_plan_version_created','A new draft compensation plan version was created.',
    jsonb_build_object('plan_id',selected_plan_id,'plan_version_id',new_version_id,'version_number',next_version_number,'copied_from_version_id',copy_components_from_version_id)
  );
  return jsonb_build_object('status','draft','plan_version_id',new_version_id,'version_number',next_version_number);
end;
$function$;

revoke all on function public.create_compensation_plan_version(uuid,date,date,text,text,uuid) from public;
grant execute on function public.create_compensation_plan_version(uuid,date,date,text,text,uuid) to authenticated;

create or replace function public.save_compensation_plan_component(
  selected_plan_version_id uuid,
  selected_component_id uuid default null,
  selected_name text default null,
  selected_component_code text default null,
  selected_description text default null,
  selected_calculation_type text default null,
  selected_measurement_source text default null,
  selected_measurement_period text default 'monthly',
  selected_calculation_order integer default 1,
  selected_rule_configuration jsonb default '{}'::jsonb,
  selected_maximum_payout numeric default null,
  selected_is_active boolean default true,
  selected_payout_timing_method public.payout_timing_method default 'annual',
  selected_allow_manager_payout_override boolean default true,
  selected_measurement_label text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  saved_component_id uuid;
  version_status public.plan_version_status;
begin
  if not private.has_permission('plans.edit') then
    raise exception 'Plan editing is not permitted.' using errcode = '42501';
  end if;
  select status into version_status
  from public.comp_plan_versions
  where id = selected_plan_version_id
  for update;
  if version_status is null then
    raise exception 'Plan version does not exist.' using errcode = '22023';
  end if;
  if version_status <> 'draft' then
    raise exception 'Only draft plan versions can be edited.' using errcode = '42501';
  end if;
  if trim(coalesce(selected_name,'')) = '' then
    raise exception 'Component name is required.' using errcode = '22023';
  end if;
  if trim(coalesce(selected_component_code,'')) = '' then
    raise exception 'Component code is required.' using errcode = '22023';
  end if;
  if trim(coalesce(selected_calculation_type,'')) = '' then
    raise exception 'Calculation type is required.' using errcode = '22023';
  end if;
  if selected_calculation_order <= 0 then
    raise exception 'Calculation order must be greater than zero.' using errcode = '22023';
  end if;
  if selected_component_id is null then
    insert into public.comp_plan_components (
      plan_version_id,name,component_code,description,calculation_type,measurement_source,
      measurement_period,calculation_order,rule_configuration,maximum_payout,is_active,
      payout_timing_method,allow_manager_payout_override,measurement_label
    ) values (
      selected_plan_version_id,trim(selected_name),upper(trim(selected_component_code)),
      nullif(trim(coalesce(selected_description,'')),''),trim(selected_calculation_type),
      nullif(trim(coalesce(selected_measurement_source,'')),''),trim(coalesce(selected_measurement_period,'monthly')),
      selected_calculation_order,coalesce(selected_rule_configuration,'{}'::jsonb),selected_maximum_payout,
      selected_is_active,selected_payout_timing_method,selected_allow_manager_payout_override,
      nullif(trim(coalesce(selected_measurement_label,'')),'')
    ) returning id into saved_component_id;
  else
    if not exists (
      select 1 from public.comp_plan_components
      where id = selected_component_id and plan_version_id = selected_plan_version_id
    ) then
      raise exception 'Component does not belong to this plan version.' using errcode = '22023';
    end if;
    update public.comp_plan_components
    set
      name = trim(selected_name),
      component_code = upper(trim(selected_component_code)),
      description = nullif(trim(coalesce(selected_description,'')),''),
      calculation_type = trim(selected_calculation_type),
      measurement_source = nullif(trim(coalesce(selected_measurement_source,'')),''),
      measurement_period = trim(coalesce(selected_measurement_period,'monthly')),
      calculation_order = selected_calculation_order,
      rule_configuration = coalesce(selected_rule_configuration,'{}'::jsonb),
      maximum_payout = selected_maximum_payout,
      is_active = selected_is_active,
      payout_timing_method = selected_payout_timing_method,
      allow_manager_payout_override = selected_allow_manager_payout_override,
      measurement_label = nullif(trim(coalesce(selected_measurement_label,'')),''),
      updated_at = now()
    where id = selected_component_id
    returning id into saved_component_id;
  end if;
  insert into public.app_access_audit_events (actor_user_id,event_type,event_reason,new_state)
  values (
    auth.uid(),
    case when selected_component_id is null then 'comp_plan_component_created' else 'comp_plan_component_updated' end,
    'A draft compensation plan component was saved.',
    jsonb_build_object('plan_version_id',selected_plan_version_id,'component_id',saved_component_id,'component_code',upper(trim(selected_component_code)))
  );
  return jsonb_build_object('status','saved','component_id',saved_component_id);
end;
$function$;

revoke all on function public.save_compensation_plan_component(uuid,uuid,text,text,text,text,text,text,integer,jsonb,numeric,boolean,public.payout_timing_method,boolean,text) from public;
grant execute on function public.save_compensation_plan_component(uuid,uuid,text,text,text,text,text,text,integer,jsonb,numeric,boolean,public.payout_timing_method,boolean,text) to authenticated;

create or replace function public.approve_compensation_plan_version(
  selected_plan_version_id uuid,
  approval_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  component_count integer;
begin
  if not private.has_permission('plans.approve') then
    raise exception 'Plan approval is not permitted.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.comp_plan_versions
    where id = selected_plan_version_id and status = 'draft'
  ) then
    raise exception 'Only draft versions can be approved.' using errcode = '22023';
  end if;
  select count(*) into component_count
  from public.comp_plan_components
  where plan_version_id = selected_plan_version_id and is_active = true;
  if component_count = 0 then
    raise exception 'A plan version must contain at least one active component before approval.' using errcode = '23514';
  end if;
  update public.comp_plan_versions
  set
    approved_by = auth.uid(),
    approved_at = now(),
    notes = case
      when nullif(trim(coalesce(approval_notes,'')),'') is null then notes
      when notes is null then trim(approval_notes)
      else notes || E'\nApproval: ' || trim(approval_notes)
    end,
    updated_at = now()
  where id = selected_plan_version_id;
  insert into public.app_access_audit_events (actor_user_id,event_type,event_reason,new_state)
  values (
    auth.uid(),'comp_plan_version_approved','A draft compensation plan version was approved for activation.',
    jsonb_build_object('plan_version_id',selected_plan_version_id,'component_count',component_count)
  );
  return jsonb_build_object('status','approved','plan_version_id',selected_plan_version_id,'component_count',component_count);
end;
$function$;

revoke all on function public.approve_compensation_plan_version(uuid,text) from public;
grant execute on function public.approve_compensation_plan_version(uuid,text) to authenticated;

create or replace function public.activate_compensation_plan_version(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  selected_plan_id uuid;
  selected_start date;
begin
  if not private.has_permission('plans.activate') then
    raise exception 'Plan activation is not permitted.' using errcode = '42501';
  end if;
  select comp_plan_id,effective_start_date
  into selected_plan_id,selected_start
  from public.comp_plan_versions
  where id = selected_plan_version_id
    and status = 'draft'
    and approved_at is not null
  for update;
  if selected_plan_id is null then
    raise exception 'The plan version must be draft and approved before activation.' using errcode = '22023';
  end if;
  update public.comp_plan_versions
  set
    status = 'retired',
    effective_end_date = case
      when effective_start_date < selected_start then least(coalesce(effective_end_date,selected_start - 1),selected_start - 1)
      else effective_end_date
    end,
    updated_at = now()
  where comp_plan_id = selected_plan_id
    and status = 'active'
    and id <> selected_plan_version_id;
  update public.comp_plan_versions
  set status = 'active',updated_at = now()
  where id = selected_plan_version_id;
  insert into public.app_access_audit_events (actor_user_id,event_type,event_reason,new_state)
  values (
    auth.uid(),'comp_plan_version_activated','An approved compensation plan version was activated.',
    jsonb_build_object('plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id)
  );
  return jsonb_build_object('status','active','plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id);
end;
$function$;

revoke all on function public.activate_compensation_plan_version(uuid) from public;
grant execute on function public.activate_compensation_plan_version(uuid) to authenticated;

create or replace function public.retire_compensation_plan_version(
  selected_plan_version_id uuid,
  selected_effective_end_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  version_start date;
begin
  if not private.has_permission('plans.activate') then
    raise exception 'Plan retirement is not permitted.' using errcode = '42501';
  end if;
  select effective_start_date into version_start
  from public.comp_plan_versions
  where id = selected_plan_version_id
    and status in ('active','draft')
  for update;
  if version_start is null then
    raise exception 'The selected version cannot be retired.' using errcode = '22023';
  end if;
  if selected_effective_end_date < version_start then
    raise exception 'Retirement date cannot precede the version start date.' using errcode = '22023';
  end if;
  update public.comp_plan_versions
  set status='retired',effective_end_date=selected_effective_end_date,updated_at=now()
  where id = selected_plan_version_id;
  insert into public.app_access_audit_events (actor_user_id,event_type,event_reason,new_state)
  values (
    auth.uid(),'comp_plan_version_retired','A compensation plan version was retired.',
    jsonb_build_object('plan_version_id',selected_plan_version_id,'effective_end_date',selected_effective_end_date)
  );
  return jsonb_build_object('status','retired','plan_version_id',selected_plan_version_id,'effective_end_date',selected_effective_end_date);
end;
$function$;

revoke all on function public.retire_compensation_plan_version(uuid,date) from public;
grant execute on function public.retire_compensation_plan_version(uuid,date) to authenticated;

create or replace function public.assign_compensation_plan_to_employee(
  selected_employee_id uuid,
  selected_plan_version_id uuid,
  selected_effective_start_date date,
  selected_effective_end_date date default null,
  selected_allocation_percent numeric default 100,
  selected_assignment_notes text default null,
  selected_eligibility_waiting_period_days integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  new_assignment_id uuid;
begin
  if not private.has_permission('plans.edit') then
    raise exception 'Plan assignment is not permitted.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.employees where id=selected_employee_id and is_active=true) then
    raise exception 'Employee does not exist or is inactive.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.comp_plan_versions where id=selected_plan_version_id and status='active') then
    raise exception 'Only active plan versions can be assigned.' using errcode = '42501';
  end if;
  if selected_allocation_percent < 0 or selected_allocation_percent > 100 then
    raise exception 'Allocation percent must be between 0 and 100.' using errcode = '22023';
  end if;
  if selected_eligibility_waiting_period_days < 0 then
    raise exception 'Waiting period cannot be negative.' using errcode = '22023';
  end if;
  if selected_effective_end_date is not null and selected_effective_end_date < selected_effective_start_date then
    raise exception 'Assignment end date cannot precede start date.' using errcode = '22023';
  end if;
  insert into public.employee_plan_assignments (
    employee_id,plan_version_id,allocation_percent,effective_start_date,effective_end_date,
    assignment_notes,assigned_by,eligibility_waiting_period_days,earnings_eligibility_date
  ) values (
    selected_employee_id,selected_plan_version_id,selected_allocation_percent,selected_effective_start_date,
    selected_effective_end_date,nullif(trim(coalesce(selected_assignment_notes,'')),''),auth.uid(),
    selected_eligibility_waiting_period_days,selected_effective_start_date + selected_eligibility_waiting_period_days
  ) returning id into new_assignment_id;
  insert into public.app_access_audit_events (actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values (
    auth.uid(),'comp_plan_assigned','An active compensation plan version was assigned to an employee.',
    jsonb_build_object(
      'assignment_id',new_assignment_id,'plan_version_id',selected_plan_version_id,
      'effective_start_date',selected_effective_start_date,'effective_end_date',selected_effective_end_date,
      'allocation_percent',selected_allocation_percent
    ),selected_employee_id
  );
  return jsonb_build_object('status','assigned','assignment_id',new_assignment_id);
end;
$function$;

revoke all on function public.assign_compensation_plan_to_employee(uuid,uuid,date,date,numeric,text,integer) from public;
grant execute on function public.assign_compensation_plan_to_employee(uuid,uuid,date,date,numeric,text,integer) to authenticated;
