create or replace function public.replace_employee_approval_workflow(
  selected_current_workflow_version_id uuid,
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
  actor uuid:=auth.uid();
  current_row public.employee_approval_workflow_versions%rowtype;
  create_result jsonb;
  replacement_id uuid;
  replacement_status text;
begin
  if actor is null or not private.has_permission('users.manage') then
    raise exception 'Workflow administration is not permitted.' using errcode='42501';
  end if;
  select * into current_row from public.employee_approval_workflow_versions where id=selected_current_workflow_version_id for update;
  if not found then raise exception 'Current workflow version was not found.' using errcode='P0002'; end if;
  if current_row.status<>'active' then raise exception 'Only an active workflow can be replaced.' using errcode='22023'; end if;
  if selected_effective_start_date is null or selected_effective_start_date<=current_row.effective_start_date then
    raise exception 'Replacement workflow must start after the current workflow start date.' using errcode='22023';
  end if;

  create_result:=public.create_employee_approval_workflow(
    current_row.employee_id,selected_workflow_name,selected_effective_start_date,
    selected_effective_end_date,selected_steps,selected_notes
  );
  replacement_id:=(create_result->>'workflow_version_id')::uuid;
  replacement_status:=create_result->>'status';

  if replacement_status='active' then
    perform public.end_employee_approval_workflow(current_row.id,selected_effective_start_date-1);
  end if;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(actor,'employee_approval_workflow_replacement_scheduled',
    case when replacement_status='active' then 'An administrator replaced an active approval workflow.' else 'An administrator scheduled a replacement workflow pending approver activation.' end,
    jsonb_build_object('workflow_version_id',current_row.id,'workflow_name',current_row.workflow_name),
    create_result,current_row.employee_id);

  return jsonb_build_object(
    'status',case when replacement_status='active' then 'replaced' else 'replacement_pending_approvers' end,
    'current_workflow_version_id',current_row.id,
    'replacement',create_result
  );
end;
$function$;
revoke all on function public.replace_employee_approval_workflow(uuid,text,date,date,jsonb,text) from public,anon;
grant execute on function public.replace_employee_approval_workflow(uuid,text,date,date,jsonb,text) to authenticated;

create or replace function public.activate_ready_employee_approval_workflow(selected_workflow_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare actor uuid:=auth.uid(); w public.employee_approval_workflow_versions%rowtype; unresolved integer; overlapping public.employee_approval_workflow_versions%rowtype;
begin
  if actor is null or not private.has_permission('users.manage') then raise exception 'You are not permitted to activate approval workflows.' using errcode='42501'; end if;
  select * into w from public.employee_approval_workflow_versions where id=selected_workflow_version_id for update;
  if not found then raise exception 'Approval workflow version not found.' using errcode='P0002'; end if;
  if w.status='active' then return jsonb_build_object('status','active','workflow_version_id',w.id,'unresolved_approver_count',0); end if;
  if w.status<>'draft' then raise exception 'Only a draft approval workflow can be activated.' using errcode='22023'; end if;

  update public.employee_approval_chains c
  set approver_user_id=coalesce(c.approver_user_id,private.resolve_employee_approver_user(c.approver_employee_id)),
      backup_approver_user_id=case when c.backup_approver_employee_id is null then null else coalesce(c.backup_approver_user_id,private.resolve_employee_approver_user(c.backup_approver_employee_id)) end,
      updated_at=now()
  where c.workflow_version_id=w.id;

  select count(*) into unresolved from public.employee_approval_chains c
  where c.workflow_version_id=w.id and (c.approver_user_id is null or (c.backup_approver_employee_id is not null and c.backup_approver_user_id is null));
  if unresolved>0 then return jsonb_build_object('status','not_ready','workflow_version_id',w.id,'unresolved_approver_count',unresolved); end if;

  select * into overlapping
  from public.employee_approval_workflow_versions x
  where x.employee_id=w.employee_id and x.status='active' and x.id<>w.id
    and daterange(x.effective_start_date,coalesce(x.effective_end_date+1,'infinity'::date),'[)') && daterange(w.effective_start_date,coalesce(w.effective_end_date+1,'infinity'::date),'[)')
  order by x.effective_start_date desc limit 1 for update;

  if found then
    if w.effective_start_date<=overlapping.effective_start_date then
      raise exception 'Planned workflow must begin after the current active workflow start date.' using errcode='22023';
    end if;
    perform public.end_employee_approval_workflow(overlapping.id,w.effective_start_date-1);
  end if;

  update public.employee_approval_workflow_versions set status='active',updated_at=now() where id=w.id;
  return jsonb_build_object('status','active','workflow_version_id',w.id,'unresolved_approver_count',0,'replaced_workflow_version_id',case when overlapping.id is null then null else overlapping.id end);
end;
$function$;
