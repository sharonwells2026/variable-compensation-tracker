-- 097 - Production Baseline and Security Hardening
-- Applied manually to production and verified before source-control sync.

create or replace function public.get_my_compensation_plan()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with current_employee as (
    select e.id, e.full_name, e.email, e.job_title, e.department
    from public.profiles pr
    join public.employees e on e.id = pr.employee_id
    where pr.id = auth.uid()
      and e.is_active = true
    limit 1
  ),
  current_assignment as (
    select
      epa.id as assignment_id,
      epa.employee_id,
      epa.plan_version_id,
      epa.effective_start_date as assignment_effective_start_date,
      epa.effective_end_date as assignment_effective_end_date,
      epa.allocation_percent,
      cp.id as plan_id,
      cp.name as plan_name,
      cp.plan_code,
      cp.description as plan_description,
      cpv.version_number,
      cpv.status as plan_status,
      cpv.effective_start_date as version_effective_start_date,
      cpv.effective_end_date as version_effective_end_date
    from current_employee ce
    join public.employee_plan_assignments epa on epa.employee_id = ce.id
    join public.comp_plan_versions cpv on cpv.id = epa.plan_version_id
    join public.comp_plans cp on cp.id = cpv.comp_plan_id
    where epa.effective_start_date <= current_date
      and (epa.effective_end_date is null or epa.effective_end_date >= current_date)
    order by epa.effective_start_date desc, cpv.version_number desc
    limit 1
  )
  select jsonb_build_object(
    'employee', (
      select jsonb_build_object(
        'id', ce.id,
        'full_name', ce.full_name,
        'email', ce.email,
        'job_title', ce.job_title,
        'department', ce.department
      )
      from current_employee ce
    ),
    'plan', (
      select jsonb_build_object(
        'assignment_id', ca.assignment_id,
        'plan_id', ca.plan_id,
        'plan_version_id', ca.plan_version_id,
        'name', ca.plan_name,
        'plan_code', ca.plan_code,
        'description', ca.plan_description,
        'version_number', ca.version_number,
        'status', ca.plan_status,
        'effective_start_date', ca.version_effective_start_date,
        'effective_end_date', ca.version_effective_end_date,
        'assignment_effective_start_date', ca.assignment_effective_start_date,
        'assignment_effective_end_date', ca.assignment_effective_end_date,
        'allocation_percent', ca.allocation_percent
      )
      from current_assignment ca
    ),
    'components', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'component_code', c.component_code,
          'description', c.description,
          'calculation_type', c.calculation_type,
          'measurement_source', c.measurement_source,
          'measurement_period', c.measurement_period,
          'measurement_label', c.measurement_label,
          'calculation_order', c.calculation_order,
          'maximum_payout', c.maximum_payout,
          'rule_configuration', c.rule_configuration,
          'is_active', c.is_active
        ) order by c.calculation_order
      )
      from current_assignment ca
      join public.comp_plan_components c on c.plan_version_id = ca.plan_version_id
      where c.is_active = true
    ), '[]'::jsonb)
  );
$function$;

revoke all on function public.get_my_compensation_plan() from public;
grant execute on function public.get_my_compensation_plan() to authenticated;

create or replace function public.set_app_user_draft_employee_profile(
  selected_draft_user_id uuid,
  selected_job_title text default null,
  selected_department text default null,
  selected_manager_employee_id uuid default null,
  selected_primary_org_unit_id uuid default null,
  selected_plan_version_id uuid default null,
  selected_effective_start_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  draft public.app_user_drafts%rowtype;
begin
  if not private.has_permission('users.manage') then
    raise exception 'User administration is not permitted.' using errcode = '42501';
  end if;

  select * into draft
  from public.app_user_drafts
  where id = selected_draft_user_id
  for update;

  if draft.id is null then
    raise exception 'The selected draft user does not exist.' using errcode = '22023';
  end if;

  if draft.status not in ('draft','ready') then
    raise exception 'This user can no longer be edited before invitation.' using errcode = '22023';
  end if;

  if selected_manager_employee_id is not null
     and not exists (
       select 1 from public.employees e
       where e.id = selected_manager_employee_id and e.is_active = true
     ) then
    raise exception 'The selected manager does not exist or is inactive.' using errcode = '22023';
  end if;

  if selected_primary_org_unit_id is not null
     and not exists (
       select 1 from public.organization_units ou
       where ou.id = selected_primary_org_unit_id and ou.is_active = true
     ) then
    raise exception 'The selected organization unit does not exist or is inactive.' using errcode = '22023';
  end if;

  if selected_plan_version_id is not null
     and not exists (
       select 1 from public.comp_plan_versions pv
       where pv.id = selected_plan_version_id
     ) then
    raise exception 'The selected plan version does not exist.' using errcode = '22023';
  end if;

  update public.app_user_drafts
  set
    job_title = nullif(trim(coalesce(selected_job_title,'')),''),
    department = nullif(trim(coalesce(selected_department,'')),''),
    manager_employee_id = selected_manager_employee_id,
    primary_org_unit_id = selected_primary_org_unit_id,
    plan_version_id = selected_plan_version_id,
    employee_effective_start_date = coalesce(selected_effective_start_date,current_date),
    updated_by = auth.uid(),
    updated_at = now()
  where id = selected_draft_user_id;

  insert into public.app_access_audit_events (
    actor_user_id, event_type, event_reason, new_state, related_employee_id
  ) values (
    auth.uid(),
    'draft_employee_profile_updated',
    'An administrator updated employee configuration before invitation.',
    jsonb_build_object(
      'draft_user_id', selected_draft_user_id,
      'job_title', selected_job_title,
      'department', selected_department,
      'manager_employee_id', selected_manager_employee_id,
      'primary_org_unit_id', selected_primary_org_unit_id,
      'plan_version_id', selected_plan_version_id,
      'effective_start_date', selected_effective_start_date
    ),
    draft.employee_id
  );

  return jsonb_build_object(
    'status','updated',
    'draft_user_id',selected_draft_user_id,
    'job_title',selected_job_title,
    'department',selected_department,
    'manager_employee_id',selected_manager_employee_id,
    'primary_org_unit_id',selected_primary_org_unit_id,
    'plan_version_id',selected_plan_version_id,
    'effective_start_date',coalesce(selected_effective_start_date,current_date)
  );
end;
$function$;

revoke all on function public.set_app_user_draft_employee_profile(uuid,text,text,uuid,uuid,uuid,date) from public;
grant execute on function public.set_app_user_draft_employee_profile(uuid,text,text,uuid,uuid,uuid,date) to authenticated;

revoke all on function public.capture_hubspot_company_changes() from public;
revoke all on function public.capture_hubspot_deal_changes() from public;
revoke all on function public.classify_hubspot_change() from public;
revoke all on function public.rls_auto_enable() from public;
