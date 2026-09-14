create table if not exists public.comp_plan_draft_assignments (
  id uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references public.comp_plan_versions(id) on delete cascade,
  employee_id uuid not null references public.employees(id),
  allocation_percent numeric not null default 100 check (allocation_percent >= 0 and allocation_percent <= 100),
  effective_start_date date not null,
  effective_end_date date null,
  eligibility_waiting_period_days integer not null default 0 check (eligibility_waiting_period_days >= 0),
  assignment_notes text null,
  created_by uuid null,
  updated_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comp_plan_draft_assignments_dates_chk check (effective_end_date is null or effective_end_date >= effective_start_date),
  constraint comp_plan_draft_assignments_unique unique (plan_version_id, employee_id)
);

alter table public.comp_plan_draft_assignments enable row level security;
revoke all on public.comp_plan_draft_assignments from anon;
revoke all on public.comp_plan_draft_assignments from authenticated;

create or replace function public.save_comp_plan_draft_assignment(
  selected_plan_version_id uuid,
  selected_employee_id uuid,
  selected_effective_start_date date,
  selected_effective_end_date date default null,
  selected_allocation_percent numeric default 100,
  selected_eligibility_waiting_period_days integer default 0,
  selected_assignment_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  version_status public.plan_version_status;
  saved_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan applicability editing is not permitted.' using errcode='42501'; end if;

  select status into version_status from public.comp_plan_versions where id=selected_plan_version_id for update;
  if version_status is null then raise exception 'Plan version does not exist.' using errcode='22023'; end if;
  if version_status <> 'draft' then raise exception 'Only draft plan versions can be configured before activation.' using errcode='42501'; end if;
  if not exists(select 1 from public.employees where id=selected_employee_id and is_active=true) then raise exception 'Employee does not exist or is inactive.' using errcode='22023'; end if;
  if selected_allocation_percent < 0 or selected_allocation_percent > 100 then raise exception 'Allocation percent must be between 0 and 100.' using errcode='22023'; end if;
  if selected_eligibility_waiting_period_days < 0 then raise exception 'Waiting period cannot be negative.' using errcode='22023'; end if;
  if selected_effective_end_date is not null and selected_effective_end_date < selected_effective_start_date then raise exception 'Assignment end date cannot precede start date.' using errcode='22023'; end if;

  insert into public.comp_plan_draft_assignments(plan_version_id,employee_id,allocation_percent,effective_start_date,effective_end_date,eligibility_waiting_period_days,assignment_notes,created_by,updated_by)
  values(selected_plan_version_id,selected_employee_id,selected_allocation_percent,selected_effective_start_date,selected_effective_end_date,selected_eligibility_waiting_period_days,nullif(trim(coalesce(selected_assignment_notes,'')),''),(select auth.uid()),(select auth.uid()))
  on conflict(plan_version_id,employee_id) do update set
    allocation_percent=excluded.allocation_percent,
    effective_start_date=excluded.effective_start_date,
    effective_end_date=excluded.effective_end_date,
    eligibility_waiting_period_days=excluded.eligibility_waiting_period_days,
    assignment_notes=excluded.assignment_notes,
    updated_by=(select auth.uid()),updated_at=now()
  returning id into saved_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values((select auth.uid()),'comp_plan_draft_assignment_saved','A draft plan applicability assignment was saved. It does not affect employee compensation until plan activation.',
    jsonb_build_object('draft_assignment_id',saved_id,'plan_version_id',selected_plan_version_id,'employee_id',selected_employee_id,'effective_start_date',selected_effective_start_date,'effective_end_date',selected_effective_end_date,'allocation_percent',selected_allocation_percent,'eligibility_waiting_period_days',selected_eligibility_waiting_period_days),selected_employee_id);

  return jsonb_build_object('status','draft_saved','draft_assignment_id',saved_id,'plan_version_id',selected_plan_version_id);
end;
$function$;

create or replace function public.delete_comp_plan_draft_assignment(selected_draft_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  target public.comp_plan_draft_assignments%rowtype;
  version_status public.plan_version_status;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan applicability editing is not permitted.' using errcode='42501'; end if;

  select d.* into target from public.comp_plan_draft_assignments d where d.id=selected_draft_assignment_id for update;
  if target.id is null then raise exception 'Draft assignment does not exist.' using errcode='22023'; end if;
  select pv.status into version_status from public.comp_plan_versions pv where pv.id=target.plan_version_id;
  if version_status <> 'draft' then raise exception 'Only draft plan applicability can be changed.' using errcode='42501'; end if;

  delete from public.comp_plan_draft_assignments where id=target.id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,old_state,related_employee_id)
  values((select auth.uid()),'comp_plan_draft_assignment_deleted','A draft plan applicability assignment was removed.',jsonb_build_object('draft_assignment_id',target.id,'plan_version_id',target.plan_version_id,'employee_id',target.employee_id),target.employee_id);
  return jsonb_build_object('status','deleted','draft_assignment_id',target.id);
end;
$function$;

grant execute on function public.save_comp_plan_draft_assignment(uuid,uuid,date,date,numeric,integer,text) to authenticated;
grant execute on function public.delete_comp_plan_draft_assignment(uuid) to authenticated;
revoke execute on function public.save_comp_plan_draft_assignment(uuid,uuid,date,date,numeric,integer,text) from anon;
revoke execute on function public.delete_comp_plan_draft_assignment(uuid) from anon;

create or replace function public.get_compensation_plan_admin_data()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $function$
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
        'assignments',coalesce((select jsonb_agg(jsonb_build_object('assignment_id',a.id,'employee_id',a.employee_id,'employee_name',e.full_name,'allocation_percent',a.allocation_percent,'effective_start_date',a.effective_start_date,'effective_end_date',a.effective_end_date,'earnings_eligibility_date',a.earnings_eligibility_date) order by e.full_name,a.effective_start_date desc) from public.employee_plan_assignments a join public.employees e on e.id=a.employee_id where a.plan_version_id=v.id),'[]'::jsonb),
        'draft_assignments',coalesce((select jsonb_agg(jsonb_build_object('draft_assignment_id',d.id,'employee_id',d.employee_id,'employee_name',e.full_name,'allocation_percent',d.allocation_percent,'effective_start_date',d.effective_start_date,'effective_end_date',d.effective_end_date,'eligibility_waiting_period_days',d.eligibility_waiting_period_days,'earnings_eligibility_date',d.effective_start_date+d.eligibility_waiting_period_days,'assignment_notes',d.assignment_notes) order by e.full_name,d.effective_start_date desc) from public.comp_plan_draft_assignments d join public.employees e on e.id=d.employee_id where d.plan_version_id=v.id),'[]'::jsonb)
      ) order by v.version_number desc) from public.comp_plan_versions v where v.comp_plan_id=p.id),'[]'::jsonb)
    ) order by p.name) from public.comp_plans p),'[]'::jsonb),
    'employees',coalesce((select jsonb_agg(jsonb_build_object('employee_id',e.id,'employee_name',e.full_name,'email',e.email,'job_title',e.job_title,'department',e.department) order by e.full_name) from public.employees e where e.is_active),'[]'::jsonb)
  ) into payload;
  return payload;
end;
$function$;

create or replace function public.activate_compensation_plan_version(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare selected_plan_id uuid; selected_start date; selected_end date; conflicting_active_id uuid; conflicting_active_start date; promoted_count integer:=0;
begin
  if not private.has_permission('plans.activate') then raise exception 'Plan activation is not permitted.' using errcode='42501'; end if;
  select pv.comp_plan_id,pv.effective_start_date,pv.effective_end_date into selected_plan_id,selected_start,selected_end from public.comp_plan_versions pv where pv.id=selected_plan_version_id and pv.status='draft' and pv.approved_at is not null for update;
  if selected_plan_id is null then raise exception 'The plan version must be draft and approved before activation.' using errcode='22023'; end if;
  if selected_start > current_date then raise exception 'A future-dated compensation plan version cannot be activated before its effective start date. Leave it approved in draft status until that date.' using errcode='22023'; end if;
  perform 1 from public.comp_plans where id=selected_plan_id for update;
  select pv.id,pv.effective_start_date into conflicting_active_id,conflicting_active_start from public.comp_plan_versions pv where pv.comp_plan_id=selected_plan_id and pv.status='active' and pv.id<>selected_plan_version_id order by pv.effective_start_date desc limit 1 for update;
  if conflicting_active_id is not null then
    if conflicting_active_start >= selected_start then raise exception 'The selected version does not start after the currently active version.' using errcode='22023'; end if;
    update public.comp_plan_versions set status='retired',effective_end_date=selected_start-1,updated_at=now() where id=conflicting_active_id;
  end if;
  update public.comp_plan_versions set status='active',updated_at=now() where id=selected_plan_version_id;
  insert into public.employee_plan_assignments(employee_id,plan_version_id,allocation_percent,effective_start_date,effective_end_date,assignment_notes,assigned_by,eligibility_waiting_period_days,earnings_eligibility_date)
  select d.employee_id,d.plan_version_id,d.allocation_percent,d.effective_start_date,d.effective_end_date,d.assignment_notes,(select auth.uid()),d.eligibility_waiting_period_days,d.effective_start_date+d.eligibility_waiting_period_days
  from public.comp_plan_draft_assignments d where d.plan_version_id=selected_plan_version_id and not exists(select 1 from public.employee_plan_assignments a where a.plan_version_id=d.plan_version_id and a.employee_id=d.employee_id);
  get diagnostics promoted_count = row_count;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values((select auth.uid()),'comp_plan_version_activated','An approved compensation plan version was activated on or after its effective date. Draft applicability assignments were promoted to live employee plan assignments.',jsonb_build_object('plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'previous_active_version_id',conflicting_active_id,'promoted_assignment_count',promoted_count));
  return jsonb_build_object('status','active','plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'retired_prior_version_id',conflicting_active_id,'promoted_assignment_count',promoted_count);
end;
$function$;
