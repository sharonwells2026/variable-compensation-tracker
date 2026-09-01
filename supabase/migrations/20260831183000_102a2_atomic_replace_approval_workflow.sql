-- 102A.2 Atomic approval workflow replacement
-- Installed in production on 2026-08-31.

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
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
  current_workflow public.employee_approval_workflow_versions%rowtype;
  new_result jsonb;
  replacement_end_date date;
begin
  if actor is null or not private.has_permission('users.manage') then
    raise exception 'You are not permitted to configure approval workflows.' using errcode = '42501';
  end if;
  select * into current_workflow from public.employee_approval_workflow_versions where id = selected_current_workflow_version_id for update;
  if not found then raise exception 'Current approval workflow version not found.' using errcode = 'P0002'; end if;
  if current_workflow.status <> 'active' then raise exception 'Only an active approval workflow can be replaced.' using errcode = '22023'; end if;
  if selected_effective_start_date is null then raise exception 'Replacement workflow effective start date is required.' using errcode = '22023'; end if;
  if selected_effective_start_date <= current_workflow.effective_start_date then raise exception 'Replacement workflow must begin after the current workflow start date.' using errcode = '22023'; end if;
  replacement_end_date := selected_effective_start_date - 1;
  perform public.end_employee_approval_workflow(selected_current_workflow_version_id,replacement_end_date);
  new_result := public.create_employee_approval_workflow(current_workflow.employee_id,selected_workflow_name,selected_effective_start_date,selected_effective_end_date,selected_steps,selected_notes);
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(actor,'employee_approval_workflow_replaced','An administrator replaced an employee compensation approval workflow prospectively.',jsonb_build_object('workflow_version_id',current_workflow.id,'workflow_name',current_workflow.workflow_name,'effective_start_date',current_workflow.effective_start_date,'effective_end_date',replacement_end_date),new_result,current_workflow.employee_id);
  return jsonb_build_object('status','replaced','ended_workflow_version_id',current_workflow.id,'ended_effective_date',replacement_end_date,'replacement',new_result);
end;
$function$;
revoke all on function public.replace_employee_approval_workflow(uuid,text,date,date,jsonb,text) from public, anon;
grant execute on function public.replace_employee_approval_workflow(uuid,text,date,date,jsonb,text) to authenticated;
