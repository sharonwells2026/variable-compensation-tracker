-- 102A Employee Approval Workflow Configuration Engine
-- Fully replayable canonical migration reconstructed from the validated production install.

create table if not exists public.employee_approval_workflow_versions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  workflow_name text not null,
  effective_start_date date not null,
  effective_end_date date,
  status text not null default 'active',
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_approval_workflow_versions_name_check check (nullif(trim(workflow_name), '') is not null),
  constraint employee_approval_workflow_versions_date_check check (effective_end_date is null or effective_end_date >= effective_start_date),
  constraint employee_approval_workflow_versions_status_check check (status in ('draft','active','ended','cancelled'))
);

create index if not exists employee_approval_workflow_versions_employee_dates_idx
on public.employee_approval_workflow_versions (employee_id,effective_start_date,effective_end_date);

alter table public.employee_approval_chains
  add column if not exists workflow_version_id uuid,
  add column if not exists step_name text,
  add column if not exists conditions jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.employee_approval_chains'::regclass
      and conname='employee_approval_chains_workflow_version_id_fkey'
  ) then
    alter table public.employee_approval_chains
      add constraint employee_approval_chains_workflow_version_id_fkey
      foreign key (workflow_version_id)
      references public.employee_approval_workflow_versions(id)
      on delete cascade;
  end if;
end $$;

create index if not exists employee_approval_chains_workflow_order_idx
on public.employee_approval_chains (workflow_version_id,approval_order);

create or replace function private.user_has_permission(selected_user_id uuid,required_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    (
      select override.allowed
      from private.user_permission_overrides override
      where override.user_id=selected_user_id
        and override.permission_key=required_permission
      limit 1
    ),
    exists (
      select 1
      from private.user_roles user_role
      join private.role_permissions role_permission
        on role_permission.role_key=user_role.role_key
      where user_role.user_id=selected_user_id
        and role_permission.permission_key=required_permission
        and role_permission.allowed=true
    ),
    false
  );
$function$;

revoke all on function private.user_has_permission(uuid,text) from public,anon,authenticated;

create or replace function private.validate_employee_approval_workflow_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.effective_end_date is not null and new.effective_end_date < new.effective_start_date then
    raise exception 'Approval workflow end date cannot precede its start date.' using errcode='22023';
  end if;

  if new.status='active' and exists (
    select 1
    from public.employee_approval_workflow_versions existing
    where existing.employee_id=new.employee_id
      and existing.status='active'
      and existing.id<>new.id
      and daterange(existing.effective_start_date,coalesce(existing.effective_end_date+1,'infinity'::date),'[)')
          && daterange(new.effective_start_date,coalesce(new.effective_end_date+1,'infinity'::date),'[)')
  ) then
    raise exception 'This active approval workflow overlaps another active workflow for the employee.' using errcode='22023';
  end if;

  return new;
end;
$function$;

revoke all on function private.validate_employee_approval_workflow_version() from public,anon,authenticated;

drop trigger if exists employee_approval_workflow_versions_validate on public.employee_approval_workflow_versions;
create trigger employee_approval_workflow_versions_validate
before insert or update on public.employee_approval_workflow_versions
for each row execute function private.validate_employee_approval_workflow_version();

create or replace function private.validate_employee_approval_chain()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  workflow_row public.employee_approval_workflow_versions%rowtype;
begin
  if new.effective_end_date is not null and new.effective_end_date < new.effective_start_date then
    raise exception 'Approval-chain end date cannot precede its start date.' using errcode='22023';
  end if;

  if new.approval_order<=0 then
    raise exception 'Approval order must be greater than zero.' using errcode='22023';
  end if;

  if nullif(trim(coalesce(new.step_name,'')),'') is null then
    raise exception 'Approval step name is required.' using errcode='22023';
  end if;

  if coalesce(new.conditions,'{}'::jsonb)<>'{}'::jsonb then
    raise exception 'Conditional approval routing is not enabled yet.' using errcode='22023';
  end if;

  if new.workflow_version_id is null then
    raise exception 'Approval step must belong to an approval workflow version.' using errcode='22023';
  end if;

  select * into workflow_row
  from public.employee_approval_workflow_versions
  where id=new.workflow_version_id;

  if not found then
    raise exception 'Approval workflow version does not exist.' using errcode='22023';
  end if;

  if workflow_row.employee_id<>new.employee_id then
    raise exception 'Approval step employee must match the workflow employee.' using errcode='22023';
  end if;

  if new.effective_start_date<workflow_row.effective_start_date then
    raise exception 'Approval step cannot start before its workflow version.' using errcode='22023';
  end if;

  if workflow_row.effective_end_date is not null
     and (new.effective_end_date is null or new.effective_end_date>workflow_row.effective_end_date) then
    raise exception 'Approval step must end within its workflow version.' using errcode='22023';
  end if;

  if new.backup_approver_user_id is not null and new.backup_approver_user_id=new.approver_user_id then
    raise exception 'Primary and backup approvers must be different users.' using errcode='22023';
  end if;

  if not exists (select 1 from public.profiles profile where profile.id=new.approver_user_id and profile.is_active=true) then
    raise exception 'Primary approver must be an active application user.' using errcode='22023';
  end if;

  if not private.user_has_permission(new.approver_user_id,'earnings.approve') then
    raise exception 'Primary approver does not have earnings approval permission.' using errcode='42501';
  end if;

  if new.backup_approver_user_id is not null then
    if not exists (select 1 from public.profiles profile where profile.id=new.backup_approver_user_id and profile.is_active=true) then
      raise exception 'Backup approver must be an active application user.' using errcode='22023';
    end if;
    if not private.user_has_permission(new.backup_approver_user_id,'earnings.approve') then
      raise exception 'Backup approver does not have earnings approval permission.' using errcode='42501';
    end if;
  end if;

  if exists (select 1 from public.profiles profile where profile.id=new.approver_user_id and profile.employee_id=new.employee_id) then
    raise exception 'An employee cannot approve their own compensation.' using errcode='22023';
  end if;

  if new.backup_approver_user_id is not null and exists (
    select 1 from public.profiles profile
    where profile.id=new.backup_approver_user_id and profile.employee_id=new.employee_id
  ) then
    raise exception 'An employee cannot be their own backup compensation approver.' using errcode='22023';
  end if;

  if exists (
    select 1 from public.employee_approval_chains existing
    where existing.workflow_version_id=new.workflow_version_id
      and existing.approval_order=new.approval_order
      and existing.id<>new.id
  ) then
    raise exception 'Each approval order may appear only once in a workflow version.' using errcode='22023';
  end if;

  return new;
end;
$function$;

revoke all on function private.validate_employee_approval_chain() from public,anon,authenticated;

drop trigger if exists employee_approval_chains_validate on public.employee_approval_chains;
create trigger employee_approval_chains_validate
before insert or update on public.employee_approval_chains
for each row execute function private.validate_employee_approval_chain();

create or replace function public.create_employee_approval_workflow(
  selected_employee_id uuid,
  selected_workflow_name text,
  selected_effective_start_date date,
  selected_effective_end_date date,
  selected_steps jsonb,
  selected_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
  workflow_id uuid;
  step_record record;
  step_count integer := 0;
begin
  if actor is null or not private.has_permission('users.manage') then
    raise exception 'You are not permitted to configure approval workflows.' using errcode='42501';
  end if;

  if not exists (select 1 from public.employees employee where employee.id=selected_employee_id and employee.is_active=true) then
    raise exception 'Selected employee must be active.' using errcode='22023';
  end if;

  if nullif(trim(coalesce(selected_workflow_name,'')),'') is null then
    raise exception 'Workflow name is required.' using errcode='22023';
  end if;

  if selected_effective_start_date is null then
    raise exception 'Workflow effective start date is required.' using errcode='22023';
  end if;

  if selected_effective_end_date is not null and selected_effective_end_date<selected_effective_start_date then
    raise exception 'Workflow end date cannot precede its start date.' using errcode='22023';
  end if;

  if selected_steps is null or jsonb_typeof(selected_steps)<>'array' or jsonb_array_length(selected_steps)=0 then
    raise exception 'At least one approval step is required.' using errcode='22023';
  end if;

  insert into public.employee_approval_workflow_versions(
    employee_id,workflow_name,effective_start_date,effective_end_date,status,notes,created_by
  ) values (
    selected_employee_id,trim(selected_workflow_name),selected_effective_start_date,selected_effective_end_date,
    'active',nullif(trim(coalesce(selected_notes,'')),''),actor
  ) returning id into workflow_id;

  for step_record in
    select value,ordinality from jsonb_array_elements(selected_steps) with ordinality
  loop
    step_count:=step_count+1;
    insert into public.employee_approval_chains(
      employee_id,workflow_version_id,approval_order,step_name,approver_user_id,backup_approver_user_id,
      approval_level,is_required,effective_start_date,effective_end_date,conditions,created_by
    ) values (
      selected_employee_id,workflow_id,step_record.ordinality::integer,
      nullif(trim(coalesce(step_record.value->>'step_name','')),''),
      (step_record.value->>'approver_user_id')::uuid,
      nullif(step_record.value->>'backup_approver_user_id','')::uuid,
      coalesce(nullif(trim(step_record.value->>'approval_level'),''),'manager'),
      coalesce((step_record.value->>'is_required')::boolean,true),
      selected_effective_start_date,selected_effective_end_date,
      coalesce(step_record.value->'conditions','{}'::jsonb),actor
    );
  end loop;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values(actor,'employee_approval_workflow_created','An administrator created an effective-dated employee compensation approval workflow.',
    jsonb_build_object('workflow_version_id',workflow_id,'workflow_name',selected_workflow_name,
      'effective_start_date',selected_effective_start_date,'effective_end_date',selected_effective_end_date,'step_count',step_count),
    selected_employee_id);

  return jsonb_build_object('status','created','workflow_version_id',workflow_id,'employee_id',selected_employee_id,'step_count',step_count);
end;
$function$;

revoke all on function public.create_employee_approval_workflow(uuid,text,date,date,jsonb,text) from public,anon;
grant execute on function public.create_employee_approval_workflow(uuid,text,date,date,jsonb,text) to authenticated;

create or replace function public.end_employee_approval_workflow(selected_workflow_version_id uuid,selected_end_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
  workflow_row public.employee_approval_workflow_versions%rowtype;
begin
  if actor is null or not private.has_permission('users.manage') then
    raise exception 'You are not permitted to configure approval workflows.' using errcode='42501';
  end if;

  select * into workflow_row
  from public.employee_approval_workflow_versions
  where id=selected_workflow_version_id
  for update;

  if not found then raise exception 'Approval workflow version not found.' using errcode='P0002'; end if;
  if selected_end_date is null or selected_end_date<workflow_row.effective_start_date then
    raise exception 'Valid workflow end date is required.' using errcode='22023';
  end if;

  update public.employee_approval_workflow_versions
  set effective_end_date=selected_end_date,status='ended',updated_at=now()
  where id=selected_workflow_version_id;

  update public.employee_approval_chains
  set effective_end_date=selected_end_date,updated_at=now()
  where workflow_version_id=selected_workflow_version_id
    and (effective_end_date is null or effective_end_date>selected_end_date);

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values(actor,'employee_approval_workflow_ended','An administrator ended an employee compensation approval workflow.',
    jsonb_build_object('workflow_version_id',selected_workflow_version_id,'effective_end_date',selected_end_date),workflow_row.employee_id);

  return jsonb_build_object('status','ended','workflow_version_id',selected_workflow_version_id,'effective_end_date',selected_end_date);
end;
$function$;

revoke all on function public.end_employee_approval_workflow(uuid,date) from public,anon;
grant execute on function public.end_employee_approval_workflow(uuid,date) to authenticated;

create or replace function public.get_employee_approval_workflows(selected_employee_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'workflow_version_id',workflow.id,
    'workflow_name',workflow.workflow_name,
    'status',workflow.status,
    'effective_start_date',workflow.effective_start_date,
    'effective_end_date',workflow.effective_end_date,
    'notes',workflow.notes,
    'steps',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',step.id,'approval_order',step.approval_order,'step_name',step.step_name,'approval_level',step.approval_level,
        'is_required',step.is_required,'approver_user_id',step.approver_user_id,'approver_name',approver.full_name,
        'backup_approver_user_id',step.backup_approver_user_id,'backup_approver_name',backup.full_name,'conditions',step.conditions
      ) order by step.approval_order)
      from public.employee_approval_chains step
      left join public.profiles approver on approver.id=step.approver_user_id
      left join public.profiles backup on backup.id=step.backup_approver_user_id
      where step.workflow_version_id=workflow.id
    ),'[]'::jsonb)
  ) order by workflow.effective_start_date desc),'[]'::jsonb)
  from public.employee_approval_workflow_versions workflow
  where workflow.employee_id=selected_employee_id;
$function$;

revoke all on function public.get_employee_approval_workflows(uuid) from public,anon;
grant execute on function public.get_employee_approval_workflows(uuid) to authenticated;

create or replace function public.preview_employee_approval_workflow(selected_employee_id uuid,selected_earned_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  workflow_row public.employee_approval_workflow_versions%rowtype;
  steps_json jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication is required.' using errcode='42501'; end if;

  select * into workflow_row
  from public.employee_approval_workflow_versions workflow
  where workflow.employee_id=selected_employee_id
    and workflow.status in ('active','ended')
    and selected_earned_date>=workflow.effective_start_date
    and (workflow.effective_end_date is null or selected_earned_date<=workflow.effective_end_date)
  order by workflow.effective_start_date desc
  limit 1;

  if not found then
    return jsonb_build_object('status','no_workflow','employee_id',selected_employee_id,'earned_date',selected_earned_date,'steps','[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'approval_order',step.approval_order,'step_name',step.step_name,'approval_level',step.approval_level,'required',step.is_required,
    'approver_user_id',step.approver_user_id,'approver_name',approver.full_name,
    'backup_approver_user_id',step.backup_approver_user_id,'backup_approver_name',backup.full_name
  ) order by step.approval_order),'[]'::jsonb)
  into steps_json
  from public.employee_approval_chains step
  left join public.profiles approver on approver.id=step.approver_user_id
  left join public.profiles backup on backup.id=step.backup_approver_user_id
  where step.workflow_version_id=workflow_row.id
    and step.is_required=true
    and selected_earned_date>=step.effective_start_date
    and (step.effective_end_date is null or selected_earned_date<=step.effective_end_date);

  return jsonb_build_object(
    'status','resolved','employee_id',selected_employee_id,'earned_date',selected_earned_date,
    'workflow_version_id',workflow_row.id,'workflow_name',workflow_row.workflow_name,
    'effective_start_date',workflow_row.effective_start_date,'effective_end_date',workflow_row.effective_end_date,
    'steps',steps_json
  );
end;
$function$;

revoke all on function public.preview_employee_approval_workflow(uuid,date) from public,anon;
grant execute on function public.preview_employee_approval_workflow(uuid,date) to authenticated;

comment on table public.employee_approval_workflow_versions is '102A effective-dated employee compensation approval workflow versions. Historical versions are preserved rather than overwritten.';
comment on column public.employee_approval_chains.workflow_version_id is 'Approval workflow version that owns this ordered approval step.';
comment on column public.employee_approval_chains.step_name is 'Administrator-facing label for the approval step, such as Manager Review or CEO Approval.';
comment on column public.employee_approval_chains.conditions is 'Reserved JSON configuration for future conditional approval routing. V1 requires an empty object because runtime condition evaluation is not yet enabled.';
