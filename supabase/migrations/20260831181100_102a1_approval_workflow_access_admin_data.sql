-- 102A.1 Approval Workflow Access and Admin Data
-- Installed and verified in production on 2026-08-31.

create or replace function public.get_employee_approval_workflows(selected_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  current_employee uuid := private.current_employee_id();
  result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if not private.has_permission('users.manage') and current_employee is distinct from selected_employee_id then
    raise exception 'You are not permitted to view this approval workflow.' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'workflow_version_id',workflow.id,'workflow_name',workflow.workflow_name,'status',workflow.status,
    'effective_start_date',workflow.effective_start_date,'effective_end_date',workflow.effective_end_date,
    'notes',workflow.notes,'steps',coalesce((select jsonb_agg(jsonb_build_object(
      'id',step.id,'approval_order',step.approval_order,'step_name',step.step_name,'approval_level',step.approval_level,
      'is_required',step.is_required,'approver_user_id',step.approver_user_id,'approver_name',approver.full_name,
      'backup_approver_user_id',step.backup_approver_user_id,'backup_approver_name',backup.full_name,'conditions',step.conditions
    ) order by step.approval_order)
    from public.employee_approval_chains step
    left join public.profiles approver on approver.id=step.approver_user_id
    left join public.profiles backup on backup.id=step.backup_approver_user_id
    where step.workflow_version_id=workflow.id),'[]'::jsonb)
  ) order by workflow.effective_start_date desc),'[]'::jsonb)
  into result
  from public.employee_approval_workflow_versions workflow
  where workflow.employee_id=selected_employee_id;
  return result;
end;
$function$;
revoke all on function public.get_employee_approval_workflows(uuid) from public, anon;
grant execute on function public.get_employee_approval_workflows(uuid) to authenticated;

create or replace function public.preview_employee_approval_workflow(selected_employee_id uuid,selected_earned_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  current_employee uuid := private.current_employee_id();
  workflow_row public.employee_approval_workflow_versions%rowtype;
  steps_json jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication is required.' using errcode='42501'; end if;
  if not private.has_permission('users.manage') and current_employee is distinct from selected_employee_id then
    raise exception 'You are not permitted to preview this approval workflow.' using errcode='42501';
  end if;
  if selected_earned_date is null then raise exception 'Earned date is required.' using errcode='22023'; end if;
  select * into workflow_row from public.employee_approval_workflow_versions workflow
  where workflow.employee_id=selected_employee_id and workflow.status in ('active','ended')
    and selected_earned_date>=workflow.effective_start_date
    and (workflow.effective_end_date is null or selected_earned_date<=workflow.effective_end_date)
  order by workflow.effective_start_date desc limit 1;
  if not found then return jsonb_build_object('status','no_workflow','employee_id',selected_employee_id,'earned_date',selected_earned_date,'steps','[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'approval_order',step.approval_order,'step_name',step.step_name,'approval_level',step.approval_level,'required',step.is_required,
    'approver_user_id',step.approver_user_id,'approver_name',approver.full_name,
    'backup_approver_user_id',step.backup_approver_user_id,'backup_approver_name',backup.full_name
  ) order by step.approval_order),'[]'::jsonb)
  into steps_json
  from public.employee_approval_chains step
  left join public.profiles approver on approver.id=step.approver_user_id
  left join public.profiles backup on backup.id=step.backup_approver_user_id
  where step.workflow_version_id=workflow_row.id and step.is_required=true
    and selected_earned_date>=step.effective_start_date
    and (step.effective_end_date is null or selected_earned_date<=step.effective_end_date);
  return jsonb_build_object('status','resolved','employee_id',selected_employee_id,'earned_date',selected_earned_date,
    'workflow_version_id',workflow_row.id,'workflow_name',workflow_row.workflow_name,
    'effective_start_date',workflow_row.effective_start_date,'effective_end_date',workflow_row.effective_end_date,'steps',steps_json);
end;
$function$;
revoke all on function public.preview_employee_approval_workflow(uuid,date) from public, anon;
grant execute on function public.preview_employee_approval_workflow(uuid,date) to authenticated;

create or replace function public.get_approval_workflow_admin_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  employees_json jsonb;
  approvers_json jsonb;
begin
  if (select auth.uid()) is null or not private.has_permission('users.manage') then
    raise exception 'You are not permitted to administer approval workflows.' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'employee_id',employee.id,'full_name',employee.full_name,'email',employee.email,'job_title',employee.job_title,'is_active',employee.is_active,
    'current_workflow',(select jsonb_build_object('workflow_version_id',workflow.id,'workflow_name',workflow.workflow_name,
      'effective_start_date',workflow.effective_start_date,'effective_end_date',workflow.effective_end_date,'status',workflow.status,
      'step_count',(select count(*) from public.employee_approval_chains step where step.workflow_version_id=workflow.id))
      from public.employee_approval_workflow_versions workflow
      where workflow.employee_id=employee.id and workflow.status='active' and current_date>=workflow.effective_start_date
        and (workflow.effective_end_date is null or current_date<=workflow.effective_end_date)
      order by workflow.effective_start_date desc limit 1)
  ) order by employee.full_name),'[]'::jsonb) into employees_json
  from public.employees employee where employee.is_active=true;
  select coalesce(jsonb_agg(jsonb_build_object('user_id',profile.id,'employee_id',profile.employee_id,'full_name',profile.full_name,'email',profile.email)
    order by profile.full_name),'[]'::jsonb) into approvers_json
  from public.profiles profile where profile.is_active=true and private.user_has_permission(profile.id,'earnings.approve');
  return jsonb_build_object('employees',employees_json,'eligible_approvers',approvers_json);
end;
$function$;
revoke all on function public.get_approval_workflow_admin_data() from public, anon;
grant execute on function public.get_approval_workflow_admin_data() to authenticated;
