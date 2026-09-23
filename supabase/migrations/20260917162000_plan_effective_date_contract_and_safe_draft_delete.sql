alter table public.comp_plan_draft_assignments
  add column if not exists employee_start_date date,
  add column if not exists plan_waiting_period_days integer not null default 0;

alter table public.comp_plan_draft_assignments
  drop constraint if exists comp_plan_draft_assignments_plan_waiting_period_days_check;
alter table public.comp_plan_draft_assignments
  add constraint comp_plan_draft_assignments_plan_waiting_period_days_check
  check (plan_waiting_period_days >= 0);

alter table public.employee_plan_assignments
  add column if not exists employee_start_date date,
  add column if not exists plan_waiting_period_days integer not null default 0;

alter table public.employee_plan_assignments
  drop constraint if exists employee_plan_assignments_plan_waiting_period_days_check;
alter table public.employee_plan_assignments
  add constraint employee_plan_assignments_plan_waiting_period_days_check
  check (plan_waiting_period_days >= 0);

update public.comp_plan_draft_assignments d
set employee_start_date=e.hire_date,
    plan_waiting_period_days=greatest(d.effective_start_date-e.hire_date,0)
from public.employees e
where e.id=d.employee_id
  and e.hire_date is not null
  and (d.employee_start_date is null or d.plan_waiting_period_days=0);

update public.employee_plan_assignments a
set employee_start_date=e.hire_date,
    plan_waiting_period_days=greatest(a.effective_start_date-e.hire_date,0)
from public.employees e
where e.id=a.employee_id
  and e.hire_date is not null
  and (a.employee_start_date is null or a.plan_waiting_period_days=0);

create or replace function public.save_comp_plan_draft_assignment(
  selected_plan_version_id uuid,
  selected_employee_id uuid,
  selected_effective_start_date date,
  selected_effective_end_date date default null,
  selected_allocation_percent numeric default 100,
  selected_eligibility_waiting_period_days integer default 0,
  selected_assignment_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  version_status public.plan_version_status;
  saved_id uuid;
  employee_start date;
  plan_waiting_days integer;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan applicability editing is not permitted.' using errcode='42501'; end if;

  select status into version_status from public.comp_plan_versions where id=selected_plan_version_id for update;
  if version_status is null then raise exception 'Plan version does not exist.' using errcode='22023'; end if;
  if version_status <> 'draft' then raise exception 'Only draft plan versions can be configured before activation.' using errcode='42501'; end if;

  select hire_date into employee_start from public.employees where id=selected_employee_id and is_active=true;
  if employee_start is null then raise exception 'Employee start date is required before assigning a compensation plan.' using errcode='22023'; end if;
  if selected_effective_start_date < employee_start then raise exception 'Plan effective date cannot be before employee start date.' using errcode='22023'; end if;

  plan_waiting_days:=selected_effective_start_date-employee_start;
  if selected_allocation_percent <= 0 or selected_allocation_percent > 100 then raise exception 'Allocation percent must be greater than 0 and no more than 100.' using errcode='22023'; end if;
  if selected_eligibility_waiting_period_days < 0 then raise exception 'Earning eligibility waiting period cannot be negative.' using errcode='22023'; end if;
  if selected_effective_end_date is not null and selected_effective_end_date < selected_effective_start_date then raise exception 'Assignment end date cannot precede plan effective date.' using errcode='22023'; end if;

  insert into public.comp_plan_draft_assignments(
    plan_version_id,employee_id,allocation_percent,effective_start_date,effective_end_date,
    eligibility_waiting_period_days,employee_start_date,plan_waiting_period_days,
    assignment_notes,created_by,updated_by
  ) values(
    selected_plan_version_id,selected_employee_id,selected_allocation_percent,selected_effective_start_date,selected_effective_end_date,
    selected_eligibility_waiting_period_days,employee_start,plan_waiting_days,
    nullif(trim(coalesce(selected_assignment_notes,'')),''),(select auth.uid()),(select auth.uid())
  )
  on conflict(plan_version_id,employee_id) do update set
    allocation_percent=excluded.allocation_percent,
    effective_start_date=excluded.effective_start_date,
    effective_end_date=excluded.effective_end_date,
    eligibility_waiting_period_days=excluded.eligibility_waiting_period_days,
    employee_start_date=excluded.employee_start_date,
    plan_waiting_period_days=excluded.plan_waiting_period_days,
    assignment_notes=excluded.assignment_notes,
    updated_by=(select auth.uid()),
    updated_at=now()
  returning id into saved_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values(
    (select auth.uid()),
    'comp_plan_draft_assignment_saved',
    'A draft plan applicability assignment was saved. Employee start date, plan waiting period, and calculated plan effective date are stored separately from earning-payment eligibility.',
    jsonb_build_object(
      'draft_assignment_id',saved_id,
      'plan_version_id',selected_plan_version_id,
      'employee_id',selected_employee_id,
      'employee_start_date',employee_start,
      'plan_waiting_period_days',plan_waiting_days,
      'effective_start_date',selected_effective_start_date,
      'effective_end_date',selected_effective_end_date,
      'allocation_percent',selected_allocation_percent,
      'earning_eligibility_waiting_period_days',selected_eligibility_waiting_period_days
    ),
    selected_employee_id
  );

  return jsonb_build_object(
    'status','draft_saved',
    'draft_assignment_id',saved_id,
    'plan_version_id',selected_plan_version_id,
    'employee_start_date',employee_start,
    'plan_waiting_period_days',plan_waiting_days,
    'effective_start_date',selected_effective_start_date
  );
end;
$$;

create or replace function public.get_compensation_plan_admin_data()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare payload jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_app_role('system_administrator') or private.has_permission('plans.view') or private.has_permission('plans.edit')) then raise exception 'Plan access required.' using errcode='42501'; end if;
  select jsonb_build_object(
    'plans',coalesce((select jsonb_agg(jsonb_build_object(
      'plan_id',p.id,'name',p.name,'plan_code',p.plan_code,'description',p.description,'plan_type',p.plan_type,'is_active',p.is_active,
      'versions',coalesce((select jsonb_agg(jsonb_build_object(
        'version_id',v.id,'version_number',v.version_number,'status',v.status,'effective_start_date',v.effective_start_date,'effective_end_date',v.effective_end_date,'currency_code',v.currency_code,'notes',v.notes,'approved_at',v.approved_at,
        'components',coalesce((select jsonb_agg(jsonb_build_object('component_id',c.id,'name',c.name,'component_code',c.component_code,'description',c.description,'calculation_type',c.calculation_type,'measurement_source',c.measurement_source,'measurement_period',c.measurement_period,'calculation_order',c.calculation_order,'rule_configuration',c.rule_configuration,'maximum_payout',c.maximum_payout,'is_active',c.is_active,'payout_timing_method',c.payout_timing_method,'allow_manager_payout_override',c.allow_manager_payout_override,'measurement_label',c.measurement_label,'additional_eligibility_waiting_days',c.additional_eligibility_waiting_days) order by c.calculation_order,c.name) from public.comp_plan_components c where c.plan_version_id=v.id),'[]'::jsonb),
        'assignments',coalesce((select jsonb_agg(jsonb_build_object('assignment_id',a.id,'employee_id',a.employee_id,'employee_name',e.full_name,'allocation_percent',a.allocation_percent,'employee_start_date',a.employee_start_date,'plan_waiting_period_days',a.plan_waiting_period_days,'effective_start_date',a.effective_start_date,'effective_end_date',a.effective_end_date,'earning_eligibility_waiting_period_days',a.eligibility_waiting_period_days,'earnings_eligibility_date',a.earnings_eligibility_date) order by e.full_name,a.effective_start_date desc) from public.employee_plan_assignments a join public.employees e on e.id=a.employee_id where a.plan_version_id=v.id),'[]'::jsonb),
        'draft_assignments',coalesce((select jsonb_agg(jsonb_build_object('draft_assignment_id',d.id,'employee_id',d.employee_id,'employee_name',e.full_name,'allocation_percent',d.allocation_percent,'employee_start_date',d.employee_start_date,'plan_waiting_period_days',d.plan_waiting_period_days,'effective_start_date',d.effective_start_date,'effective_end_date',d.effective_end_date,'earning_eligibility_waiting_period_days',d.eligibility_waiting_period_days,'earnings_eligibility_date',d.effective_start_date+d.eligibility_waiting_period_days,'assignment_notes',d.assignment_notes) order by e.full_name,d.effective_start_date desc) from public.comp_plan_draft_assignments d join public.employees e on e.id=d.employee_id where d.plan_version_id=v.id),'[]'::jsonb)
      ) order by v.version_number desc) from public.comp_plan_versions v where v.comp_plan_id=p.id),'[]'::jsonb)
    ) order by p.name) from public.comp_plans p),'[]'::jsonb),
    'employees',coalesce((select jsonb_agg(jsonb_build_object('employee_id',e.id,'employee_name',e.full_name,'email',e.email,'job_title',e.job_title,'department',e.department,'hire_date',e.hire_date) order by e.full_name) from public.employees e where e.is_active),'[]'::jsonb)
  ) into payload;
  return payload;
end;
$$;

create or replace function public.activate_compensation_plan_version(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  selected_plan_id uuid;
  selected_start date;
  selected_end date;
  conflicting_active_id uuid;
  conflicting_active_start date;
  readiness jsonb;
  promoted_count integer:=0;
  installed_workflow_count integer:=0;
begin
  if not private.has_permission('plans.activate') then raise exception 'Plan activation is not permitted.' using errcode='42501'; end if;
  select pv.comp_plan_id,pv.effective_start_date,pv.effective_end_date into selected_plan_id,selected_start,selected_end from public.comp_plan_versions pv where pv.id=selected_plan_version_id and pv.status='draft' and pv.approved_at is not null for update;
  if selected_plan_id is null then raise exception 'The plan version must be draft and approved before activation.' using errcode='22023'; end if;
  readiness:=public.validate_compensation_plan_version_readiness(selected_plan_version_id);
  if coalesce((readiness->>'ready')::boolean,false) is not true then raise exception 'Plan version is no longer ready for activation: %',readiness->'blockers' using errcode='23514'; end if;
  if selected_start>current_date then raise exception 'A future-dated compensation plan version cannot be activated before its effective start date. Leave it approved in draft status until that date.' using errcode='22023'; end if;
  perform 1 from public.comp_plans where id=selected_plan_id for update;
  select pv.id,pv.effective_start_date into conflicting_active_id,conflicting_active_start from public.comp_plan_versions pv where pv.comp_plan_id=selected_plan_id and pv.status='active' and pv.id<>selected_plan_version_id order by pv.effective_start_date desc limit 1 for update;
  if conflicting_active_id is not null then
    if conflicting_active_start>=selected_start then raise exception 'The selected version does not start after the currently active version.' using errcode='22023'; end if;
    update public.comp_plan_versions set status='retired',effective_end_date=selected_start-1,updated_at=now() where id=conflicting_active_id;
  end if;

  insert into public.employee_plan_assignments(
    employee_id,plan_version_id,related_job_role_id,allocation_percent,effective_start_date,effective_end_date,
    assignment_notes,assigned_by,eligibility_waiting_period_days,earnings_eligibility_date,
    employee_start_date,plan_waiting_period_days
  )
  select
    da.employee_id,da.plan_version_id,null,da.allocation_percent,da.effective_start_date,da.effective_end_date,
    da.assignment_notes,auth.uid(),da.eligibility_waiting_period_days,da.effective_start_date+da.eligibility_waiting_period_days,
    da.employee_start_date,da.plan_waiting_period_days
  from public.comp_plan_draft_assignments da
  where da.plan_version_id=selected_plan_version_id
  on conflict(employee_id,plan_version_id) do update set
    allocation_percent=excluded.allocation_percent,
    effective_start_date=excluded.effective_start_date,
    effective_end_date=excluded.effective_end_date,
    assignment_notes=excluded.assignment_notes,
    assigned_by=excluded.assigned_by,
    eligibility_waiting_period_days=excluded.eligibility_waiting_period_days,
    earnings_eligibility_date=excluded.earnings_eligibility_date,
    employee_start_date=excluded.employee_start_date,
    plan_waiting_period_days=excluded.plan_waiting_period_days,
    updated_at=now();
  get diagnostics promoted_count=row_count;

  installed_workflow_count:=private.install_plan_approval_workflows(selected_plan_version_id,auth.uid());
  update public.comp_plan_versions set status='active',updated_at=now() where id=selected_plan_version_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(auth.uid(),'comp_plan_version_activated','A readiness-validated compensation plan version was activated; draft applicability and its plan-scoped approval workflow were promoted together.',jsonb_build_object('plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'previous_active_version_id',conflicting_active_id,'promoted_assignment_count',promoted_count,'installed_approval_workflow_count',installed_workflow_count,'readiness',readiness));
  return jsonb_build_object('status','active','plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'retired_prior_version_id',conflicting_active_id,'promoted_assignment_count',promoted_count,'installed_approval_workflow_count',installed_workflow_count,'readiness',readiness);
end;
$$;

create or replace function public.preview_comp_plan_draft_delete(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  actor uuid:=auth.uid();
  pv record;
  assignment_count integer;
  earning_count integer;
  dependent_version_count integer;
  agreement_count integer;
  blockers jsonb:='[]'::jsonb;
begin
  if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan editing is not permitted.' using errcode='42501'; end if;

  select v.id,v.comp_plan_id,v.version_number,v.status,p.name into pv
  from public.comp_plan_versions v join public.comp_plans p on p.id=v.comp_plan_id
  where v.id=selected_plan_version_id;
  if pv.id is null then raise exception 'Plan version does not exist.' using errcode='22023'; end if;

  select count(*) into assignment_count from public.employee_plan_assignments where plan_version_id=selected_plan_version_id;
  select count(*) into earning_count from public.comp_earnings e join public.comp_plan_components c on c.id=e.plan_component_id where c.plan_version_id=selected_plan_version_id;
  select count(*) into dependent_version_count from public.comp_plan_versions where based_on_version_id=selected_plan_version_id;
  select count(*) into agreement_count from public.comp_plan_agreements where plan_version_id=selected_plan_version_id;

  if pv.status<>'draft' then blockers:=blockers||jsonb_build_array('Only draft versions can be deleted.'); end if;
  if assignment_count>0 then blockers:=blockers||jsonb_build_array('This version has active employee assignments.'); end if;
  if earning_count>0 then blockers:=blockers||jsonb_build_array('This version has compensation earnings.'); end if;
  if dependent_version_count>0 then blockers:=blockers||jsonb_build_array('Another plan version was created from this version.'); end if;

  return jsonb_build_object(
    'plan_version_id',pv.id,
    'plan_id',pv.comp_plan_id,
    'plan_name',pv.name,
    'version_number',pv.version_number,
    'status',pv.status,
    'deletable',jsonb_array_length(blockers)=0,
    'blockers',blockers,
    'active_assignment_count',assignment_count,
    'earning_count',earning_count,
    'dependent_version_count',dependent_version_count,
    'agreement_count',agreement_count
  );
end;
$$;

grant execute on function public.preview_comp_plan_draft_delete(uuid) to authenticated;

create or replace function public.delete_compensation_plan_draft_version(selected_plan_version_id uuid,confirmation_text text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  actor uuid:=auth.uid();
  check_result jsonb;
  target_plan_id uuid;
  target_plan_name text;
  target_version integer;
  storage_paths text[]:=array[]::text[];
  remaining_versions integer;
  deleted_plan boolean:=false;
begin
  if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan editing is not permitted.' using errcode='42501'; end if;
  if confirmation_text is distinct from 'DELETE DRAFT' then raise exception 'Confirmation text did not match. No data was changed.' using errcode='22023'; end if;

  check_result:=public.preview_comp_plan_draft_delete(selected_plan_version_id);
  if coalesce((check_result->>'deletable')::boolean,false) is not true then
    raise exception 'Draft plan version cannot be deleted: %',check_result->'blockers' using errcode='23514';
  end if;

  target_plan_id:=(check_result->>'plan_id')::uuid;
  target_plan_name:=check_result->>'plan_name';
  target_version:=(check_result->>'version_number')::integer;

  select coalesce(array_agg(distinct storage_path),array[]::text[]) into storage_paths
  from public.comp_plan_agreements where plan_version_id=selected_plan_version_id and storage_path is not null;

  delete from public.app_user_drafts where plan_version_id=selected_plan_version_id;
  delete from public.comp_plan_versions where id=selected_plan_version_id;

  if cardinality(storage_paths)>0 then
    delete from storage.objects o
    where o.bucket_id='compensation-agreements'
      and o.name=any(storage_paths)
      and not exists(select 1 from public.comp_plan_agreements a where a.storage_path=o.name);
  end if;

  select count(*) into remaining_versions from public.comp_plan_versions where comp_plan_id=target_plan_id;
  if remaining_versions=0 then
    delete from public.comp_plans where id=target_plan_id;
    deleted_plan:=true;
  end if;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(actor,'comp_plan_draft_version_deleted','A draft-only compensation plan version with no active assignments or earnings was permanently deleted.',jsonb_build_object('plan_id',target_plan_id,'plan_name',target_plan_name,'deleted_plan_version_id',selected_plan_version_id,'version_number',target_version,'parent_plan_deleted',deleted_plan));

  return jsonb_build_object('status','deleted','plan_version_id',selected_plan_version_id,'plan_id',target_plan_id,'parent_plan_deleted',deleted_plan);
end;
$$;

grant execute on function public.delete_compensation_plan_draft_version(uuid,text) to authenticated;
