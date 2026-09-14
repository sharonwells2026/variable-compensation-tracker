create table if not exists public.comp_plan_approval_steps (
  id uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references public.comp_plan_versions(id) on delete cascade,
  approval_order integer not null check (approval_order > 0),
  step_name text not null,
  approval_level text not null default 'manager',
  approver_employee_id uuid not null references public.employees(id),
  backup_approver_employee_id uuid null references public.employees(id),
  is_required boolean not null default true,
  conditions jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(plan_version_id, approval_order)
);

create index if not exists comp_plan_approval_steps_version_idx on public.comp_plan_approval_steps(plan_version_id, approval_order);
alter table public.comp_plan_approval_steps enable row level security;
grant select on public.comp_plan_approval_steps to authenticated;

create or replace function public.get_comp_plan_approval_configuration(selected_plan_version_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.view') and not private.has_permission('plans.edit') then raise exception 'Plan access is not permitted.' using errcode='42501'; end if;
  if not exists(select 1 from public.comp_plan_versions where id=selected_plan_version_id) then raise exception 'Plan version does not exist.' using errcode='22023'; end if;
  select jsonb_build_object('plan_version_id',selected_plan_version_id,'steps',coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'approval_order',s.approval_order,'step_name',s.step_name,'approval_level',s.approval_level,
    'approver_employee_id',s.approver_employee_id,'approver_name',a.full_name,
    'backup_approver_employee_id',s.backup_approver_employee_id,'backup_approver_name',b.full_name,
    'is_required',s.is_required,'conditions',s.conditions) order by s.approval_order) filter(where s.id is not null),'[]'::jsonb)) into result
  from public.comp_plan_approval_steps s
  left join public.employees a on a.id=s.approver_employee_id
  left join public.employees b on b.id=s.backup_approver_employee_id
  where s.plan_version_id=selected_plan_version_id;
  return result;
end $$;

create or replace function public.save_comp_plan_approval_configuration(selected_plan_version_id uuid, selected_steps jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare actor uuid:=auth.uid(); version_status public.plan_version_status; r record; step_count integer:=0; prior jsonb;
begin
  if actor is null or not private.has_permission('plans.edit') then raise exception 'Plan approval configuration is not permitted.' using errcode='42501'; end if;
  select status into version_status from public.comp_plan_versions where id=selected_plan_version_id for update;
  if version_status is null then raise exception 'Plan version does not exist.' using errcode='22023'; end if;
  if version_status<>'draft' then raise exception 'Only draft plan versions can have approval requirements edited.' using errcode='42501'; end if;
  if selected_steps is null or jsonb_typeof(selected_steps)<>'array' then raise exception 'Approval steps must be supplied as a list.' using errcode='22023'; end if;
  select coalesce(jsonb_agg(to_jsonb(s) order by s.approval_order),'[]'::jsonb) into prior from public.comp_plan_approval_steps s where s.plan_version_id=selected_plan_version_id;
  delete from public.comp_plan_approval_steps where plan_version_id=selected_plan_version_id;
  for r in select value,ordinality from jsonb_array_elements(selected_steps) with ordinality loop
    if nullif(trim(coalesce(r.value->>'approver_employee_id','')),'') is null then raise exception 'Every approval step requires an approver.' using errcode='22023'; end if;
    if not exists(select 1 from public.employees e where e.id=(r.value->>'approver_employee_id')::uuid and e.is_active=true) then raise exception 'Every approval step approver must be an active employee.' using errcode='22023'; end if;
    if nullif(r.value->>'backup_approver_employee_id','') is not null and not exists(select 1 from public.employees e where e.id=(r.value->>'backup_approver_employee_id')::uuid and e.is_active=true) then raise exception 'Backup approvers must be active employees.' using errcode='22023'; end if;
    insert into public.comp_plan_approval_steps(plan_version_id,approval_order,step_name,approval_level,approver_employee_id,backup_approver_employee_id,is_required,conditions,created_by)
    values(selected_plan_version_id,r.ordinality::integer,coalesce(nullif(trim(r.value->>'step_name'),''),'Approval '||r.ordinality),coalesce(nullif(trim(r.value->>'approval_level'),''),'manager'),(r.value->>'approver_employee_id')::uuid,nullif(r.value->>'backup_approver_employee_id','')::uuid,coalesce((r.value->>'is_required')::boolean,true),coalesce(r.value->'conditions','{}'::jsonb),actor);
    step_count:=step_count+1;
  end loop;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state)
  values(actor,'comp_plan_approval_configuration_updated','Approval requirements for a draft compensation plan version were updated.',prior,jsonb_build_object('plan_version_id',selected_plan_version_id,'step_count',step_count));
  return public.get_comp_plan_approval_configuration(selected_plan_version_id);
end $$;

grant execute on function public.get_comp_plan_approval_configuration(uuid) to authenticated;
grant execute on function public.save_comp_plan_approval_configuration(uuid,jsonb) to authenticated;
