begin;

alter table public.employee_approval_chains
  add column if not exists approver_employee_id uuid references public.employees(id),
  add column if not exists backup_approver_employee_id uuid references public.employees(id);

alter table public.employee_approval_chains
  alter column approver_user_id drop not null;

create index if not exists employee_approval_chains_approver_employee_idx
  on public.employee_approval_chains(approver_employee_id);
create index if not exists employee_approval_chains_backup_employee_idx
  on public.employee_approval_chains(backup_approver_employee_id);

create or replace function private.draft_employee_has_permission(selected_employee_id uuid, required_permission text)
returns boolean
language sql
stable
security definer
set search_path=''
as $function$
  with latest_draft as (
    select d.id
    from public.app_user_drafts d
    where d.employee_id = selected_employee_id
      and d.status <> 'cancelled'
    order by d.updated_at desc
    limit 1
  )
  select coalesce(
    (select o.allowed
     from latest_draft d
     join private.draft_user_permission_overrides o on o.draft_user_id=d.id
     where o.permission_key=required_permission
     limit 1),
    exists(
      select 1
      from latest_draft d
      join private.draft_user_roles r on r.draft_user_id=d.id
      join private.role_permissions rp on rp.role_key=r.role_key
      where rp.permission_key=required_permission and rp.allowed=true
    ),
    false
  );
$function$;
revoke all on function private.draft_employee_has_permission(uuid,text) from public,anon,authenticated;

create or replace function private.resolve_employee_approver_user(selected_employee_id uuid)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select p.id
  from public.profiles p
  where p.employee_id=selected_employee_id
    and p.is_active=true
    and private.user_has_permission(p.id,'earnings.approve')
  order by p.updated_at desc
  limit 1;
$function$;
revoke all on function private.resolve_employee_approver_user(uuid) from public,anon,authenticated;

create or replace function private.validate_employee_approval_chain()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  workflow_row public.employee_approval_workflow_versions%rowtype;
  resolved_employee_id uuid;
begin
  if new.effective_end_date is not null and new.effective_end_date < new.effective_start_date then
    raise exception 'Approval-chain end date cannot precede its start date.' using errcode='22023';
  end if;
  if new.approval_order <= 0 then
    raise exception 'Approval order must be greater than zero.' using errcode='22023';
  end if;
  if nullif(trim(coalesce(new.step_name,'')),'') is null then
    raise exception 'Approval step name is required.' using errcode='22023';
  end if;
  if coalesce(new.conditions,'{}'::jsonb) <> '{}'::jsonb then
    raise exception 'Conditional approval routing is not enabled yet.' using errcode='22023';
  end if;
  if new.workflow_version_id is null then
    raise exception 'Approval step must belong to an approval workflow version.' using errcode='22023';
  end if;

  select * into workflow_row
  from public.employee_approval_workflow_versions
  where id=new.workflow_version_id;
  if not found then raise exception 'Approval workflow version does not exist.' using errcode='22023'; end if;
  if workflow_row.employee_id <> new.employee_id then
    raise exception 'Approval step employee must match the workflow employee.' using errcode='22023';
  end if;
  if new.effective_start_date < workflow_row.effective_start_date then
    raise exception 'Approval step cannot start before its workflow version.' using errcode='22023';
  end if;
  if workflow_row.effective_end_date is not null and (new.effective_end_date is null or new.effective_end_date > workflow_row.effective_end_date) then
    raise exception 'Approval step must end within its workflow version.' using errcode='22023';
  end if;

  if new.approver_employee_id is null and new.approver_user_id is not null then
    select p.employee_id into new.approver_employee_id from public.profiles p where p.id=new.approver_user_id;
  end if;
  if new.approver_employee_id is null then
    raise exception 'Primary approver employee is required.' using errcode='22023';
  end if;
  if new.approver_employee_id = new.employee_id then
    raise exception 'An employee cannot approve their own compensation.' using errcode='22023';
  end if;

  if new.approver_user_id is null then
    new.approver_user_id := private.resolve_employee_approver_user(new.approver_employee_id);
  end if;

  if new.approver_user_id is not null then
    select p.employee_id into resolved_employee_id
    from public.profiles p
    where p.id=new.approver_user_id and p.is_active=true;
    if resolved_employee_id is distinct from new.approver_employee_id then
      raise exception 'Primary approver user must be the active app user for the selected approver employee.' using errcode='22023';
    end if;
    if not private.user_has_permission(new.approver_user_id,'earnings.approve') then
      raise exception 'Primary approver does not have earnings approval permission.' using errcode='42501';
    end if;
  elsif not private.draft_employee_has_permission(new.approver_employee_id,'earnings.approve') then
    raise exception 'Primary approver must either be an active approver or have a pre-invite configuration with earnings approval permission.' using errcode='22023';
  end if;

  if new.backup_approver_employee_id is null and new.backup_approver_user_id is not null then
    select p.employee_id into new.backup_approver_employee_id from public.profiles p where p.id=new.backup_approver_user_id;
  end if;
  if new.backup_approver_employee_id is not null then
    if new.backup_approver_employee_id = new.employee_id then
      raise exception 'An employee cannot be their own backup compensation approver.' using errcode='22023';
    end if;
    if new.backup_approver_employee_id = new.approver_employee_id then
      raise exception 'Primary and backup approvers must be different employees.' using errcode='22023';
    end if;
    if new.backup_approver_user_id is null then
      new.backup_approver_user_id := private.resolve_employee_approver_user(new.backup_approver_employee_id);
    end if;
    if new.backup_approver_user_id is not null then
      select p.employee_id into resolved_employee_id from public.profiles p where p.id=new.backup_approver_user_id and p.is_active=true;
      if resolved_employee_id is distinct from new.backup_approver_employee_id then
        raise exception 'Backup approver user must be the active app user for the selected backup employee.' using errcode='22023';
      end if;
      if not private.user_has_permission(new.backup_approver_user_id,'earnings.approve') then
        raise exception 'Backup approver does not have earnings approval permission.' using errcode='42501';
      end if;
    elsif not private.draft_employee_has_permission(new.backup_approver_employee_id,'earnings.approve') then
      raise exception 'Backup approver must either be active or have a pre-invite configuration with earnings approval permission.' using errcode='22023';
    end if;
  else
    new.backup_approver_user_id := null;
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
set search_path=''
as $function$
declare
  actor uuid := auth.uid();
  workflow_id uuid;
  step_record record;
  step_count integer := 0;
  unresolved_count integer := 0;
  resolved_user_id uuid;
  selected_approver_employee_id uuid;
  selected_backup_employee_id uuid;
begin
  if actor is null or not private.has_permission('users.manage') then
    raise exception 'You are not permitted to configure approval workflows.' using errcode='42501';
  end if;
  if not exists(select 1 from public.employees e where e.id=selected_employee_id and e.is_active=true) then
    raise exception 'Selected employee must be active.' using errcode='22023';
  end if;
  if nullif(trim(coalesce(selected_workflow_name,'')),'') is null then raise exception 'Workflow name is required.' using errcode='22023'; end if;
  if selected_effective_start_date is null then raise exception 'Workflow effective start date is required.' using errcode='22023'; end if;
  if selected_effective_end_date is not null and selected_effective_end_date<selected_effective_start_date then raise exception 'Workflow end date cannot precede its start date.' using errcode='22023'; end if;
  if selected_steps is null or jsonb_typeof(selected_steps)<>'array' or jsonb_array_length(selected_steps)=0 then raise exception 'At least one approval step is required.' using errcode='22023'; end if;

  insert into public.employee_approval_workflow_versions(employee_id,workflow_name,effective_start_date,effective_end_date,status,notes,created_by)
  values(selected_employee_id,trim(selected_workflow_name),selected_effective_start_date,selected_effective_end_date,'draft',nullif(trim(coalesce(selected_notes,'')),''),actor)
  returning id into workflow_id;

  for step_record in select value,ordinality from jsonb_array_elements(selected_steps) with ordinality loop
    selected_approver_employee_id := nullif(step_record.value->>'approver_employee_id','')::uuid;
    if selected_approver_employee_id is null and nullif(step_record.value->>'approver_user_id','') is not null then
      select p.employee_id into selected_approver_employee_id from public.profiles p where p.id=(step_record.value->>'approver_user_id')::uuid;
    end if;
    selected_backup_employee_id := nullif(step_record.value->>'backup_approver_employee_id','')::uuid;
    if selected_backup_employee_id is null and nullif(step_record.value->>'backup_approver_user_id','') is not null then
      select p.employee_id into selected_backup_employee_id from public.profiles p where p.id=(step_record.value->>'backup_approver_user_id')::uuid;
    end if;

    resolved_user_id := private.resolve_employee_approver_user(selected_approver_employee_id);
    if resolved_user_id is null then unresolved_count := unresolved_count + 1; end if;

    insert into public.employee_approval_chains(
      employee_id,workflow_version_id,approval_order,step_name,
      approver_employee_id,approver_user_id,backup_approver_employee_id,backup_approver_user_id,
      approval_level,is_required,effective_start_date,effective_end_date,conditions,created_by
    ) values(
      selected_employee_id,workflow_id,step_record.ordinality::integer,
      nullif(trim(coalesce(step_record.value->>'step_name','')),''),
      selected_approver_employee_id,resolved_user_id,
      selected_backup_employee_id,private.resolve_employee_approver_user(selected_backup_employee_id),
      coalesce(nullif(trim(step_record.value->>'approval_level'),''),'manager'),
      coalesce((step_record.value->>'is_required')::boolean,true),
      selected_effective_start_date,selected_effective_end_date,
      coalesce(step_record.value->'conditions','{}'::jsonb),actor
    );
    step_count:=step_count+1;
  end loop;

  if unresolved_count=0 then
    update public.employee_approval_workflow_versions set status='active',updated_at=now() where id=workflow_id;
  end if;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values(actor,'employee_approval_workflow_created','An administrator created an effective-dated employee compensation approval workflow.',
    jsonb_build_object('workflow_version_id',workflow_id,'workflow_name',selected_workflow_name,'effective_start_date',selected_effective_start_date,'effective_end_date',selected_effective_end_date,'step_count',step_count,'unresolved_approver_count',unresolved_count),selected_employee_id);

  return jsonb_build_object('status',case when unresolved_count=0 then 'active' else 'draft_pending_approvers' end,'workflow_version_id',workflow_id,'employee_id',selected_employee_id,'step_count',step_count,'unresolved_approver_count',unresolved_count);
end;
$function$;

create or replace function public.activate_ready_employee_approval_workflow(selected_workflow_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare actor uuid:=auth.uid(); w public.employee_approval_workflow_versions%rowtype; unresolved integer;
begin
  if actor is null or not private.has_permission('users.manage') then raise exception 'You are not permitted to activate approval workflows.' using errcode='42501'; end if;
  select * into w from public.employee_approval_workflow_versions where id=selected_workflow_version_id for update;
  if not found then raise exception 'Approval workflow version not found.' using errcode='P0002'; end if;
  update public.employee_approval_chains c
    set approver_user_id=coalesce(c.approver_user_id,private.resolve_employee_approver_user(c.approver_employee_id)),
        backup_approver_user_id=case when c.backup_approver_employee_id is null then null else coalesce(c.backup_approver_user_id,private.resolve_employee_approver_user(c.backup_approver_employee_id)) end,
        updated_at=now()
  where c.workflow_version_id=w.id;
  select count(*) into unresolved from public.employee_approval_chains c
   where c.workflow_version_id=w.id and (c.approver_user_id is null or (c.backup_approver_employee_id is not null and c.backup_approver_user_id is null));
  if unresolved>0 then return jsonb_build_object('status','not_ready','workflow_version_id',w.id,'unresolved_approver_count',unresolved); end if;
  update public.employee_approval_workflow_versions set status='active',updated_at=now() where id=w.id;
  return jsonb_build_object('status','active','workflow_version_id',w.id,'unresolved_approver_count',0);
end;
$function$;
revoke all on function public.activate_ready_employee_approval_workflow(uuid) from public,anon;
grant execute on function public.activate_ready_employee_approval_workflow(uuid) to authenticated;

create or replace function private.open_next_comp_earning_approval(target_earning_id uuid, requested_by_user uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare earning_row public.comp_earnings%rowtype; next_chain public.employee_approval_chains%rowtype; previous_order integer:=0; new_request_id uuid;
begin
  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
  if exists(select 1 from public.approval_requests r where r.comp_earning_id=target_earning_id and r.status='pending'::public.approval_status) then raise exception 'This earning already has a pending approval request.' using errcode='23505'; end if;
  select coalesce(max(r.approval_order),0) into previous_order from public.approval_requests r where r.comp_earning_id=target_earning_id;
  select c.* into next_chain
  from public.employee_approval_chains c
  join public.employee_approval_workflow_versions w on w.id=c.workflow_version_id
  where c.employee_id=earning_row.employee_id and c.is_required=true and c.approval_order>previous_order
    and w.status in ('active','ended')
    and earning_row.earned_date>=c.effective_start_date and (c.effective_end_date is null or earning_row.earned_date<=c.effective_end_date)
    and c.approver_user_id is not null
  order by c.approval_order limit 1;
  if not found then return null; end if;
  insert into public.approval_requests(comp_earning_id,approval_level,approval_order,requested_from,backup_requested_from,requested_by,requested_at,status,chain_snapshot)
  values(target_earning_id,next_chain.approval_level,next_chain.approval_order,next_chain.approver_user_id,next_chain.backup_approver_user_id,requested_by_user,now(),'pending'::public.approval_status,
    jsonb_build_object('employee_approval_chain_id',next_chain.id,'employee_id',next_chain.employee_id,'approval_order',next_chain.approval_order,'approval_level',next_chain.approval_level,'approver_employee_id',next_chain.approver_employee_id,'approver_user_id',next_chain.approver_user_id,'backup_approver_employee_id',next_chain.backup_approver_employee_id,'backup_approver_user_id',next_chain.backup_approver_user_id,'effective_start_date',next_chain.effective_start_date,'effective_end_date',next_chain.effective_end_date,'earning_earned_date',earning_row.earned_date,'snapshotted_at',now())) returning id into new_request_id;
  insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id)
  values(next_chain.approver_user_id,'compensation_approval_required','Compensation approval required','A compensation earning is waiting for your approval.','high','approval_request',new_request_id::text);
  if next_chain.backup_approver_user_id is not null then insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id) values(next_chain.backup_approver_user_id,'compensation_approval_backup','Backup compensation approval','You are the backup approver for a compensation earning.','normal','approval_request',new_request_id::text); end if;
  return new_request_id;
end;
$function$;

create or replace function public.get_approval_workflow_admin_data()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare employees_json jsonb; approvers_json jsonb;
begin
  if auth.uid() is null or not private.has_permission('users.manage') then raise exception 'You are not permitted to administer approval workflows.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'employee_id',e.id,'full_name',e.full_name,'email',e.email,'job_title',e.job_title,'is_active',e.is_active,
    'current_workflow',(select jsonb_build_object('workflow_version_id',w.id,'workflow_name',w.workflow_name,'effective_start_date',w.effective_start_date,'effective_end_date',w.effective_end_date,'status',w.status,'step_count',(select count(*) from public.employee_approval_chains s where s.workflow_version_id=w.id)) from public.employee_approval_workflow_versions w where w.employee_id=e.id and w.status='active' and current_date>=w.effective_start_date and (w.effective_end_date is null or current_date<=w.effective_end_date) order by w.effective_start_date desc limit 1),
    'planned_workflow',(select jsonb_build_object('workflow_version_id',w.id,'workflow_name',w.workflow_name,'effective_start_date',w.effective_start_date,'effective_end_date',w.effective_end_date,'status',w.status,'step_count',(select count(*) from public.employee_approval_chains s where s.workflow_version_id=w.id),'unresolved_approver_count',(select count(*) from public.employee_approval_chains s where s.workflow_version_id=w.id and (s.approver_user_id is null or (s.backup_approver_employee_id is not null and s.backup_approver_user_id is null)))) from public.employee_approval_workflow_versions w where w.employee_id=e.id and w.status='draft' order by w.effective_start_date desc limit 1)
  ) order by e.full_name),'[]'::jsonb) into employees_json from public.employees e where e.is_active=true;

  select coalesce(jsonb_agg(jsonb_build_object(
    'employee_id',e.id,'full_name',e.full_name,'email',e.email,'user_id',private.resolve_employee_approver_user(e.id),
    'provisioning_status',case when private.resolve_employee_approver_user(e.id) is not null then 'active' when private.draft_employee_has_permission(e.id,'earnings.approve') then 'preinvite' else 'unavailable' end
  ) order by e.full_name),'[]'::jsonb) into approvers_json
  from public.employees e
  where e.is_active=true and (private.resolve_employee_approver_user(e.id) is not null or private.draft_employee_has_permission(e.id,'earnings.approve'));

  return jsonb_build_object('employees',employees_json,'eligible_approvers',approvers_json);
end;
$function$;

commit;
