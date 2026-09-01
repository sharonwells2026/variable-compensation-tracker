create or replace function public.get_employee_approval_workflows(selected_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare current_employee uuid:=private.current_employee_id(); result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication is required.' using errcode='42501'; end if;
  if not private.has_permission('users.manage') and current_employee is distinct from selected_employee_id then
    raise exception 'You are not permitted to view this approval workflow.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'workflow_version_id',w.id,
    'workflow_name',w.workflow_name,
    'status',w.status,
    'effective_start_date',w.effective_start_date,
    'effective_end_date',w.effective_end_date,
    'notes',w.notes,
    'steps',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,
      'approval_order',s.approval_order,
      'step_name',s.step_name,
      'approval_level',s.approval_level,
      'is_required',s.is_required,
      'approver_employee_id',s.approver_employee_id,
      'approver_user_id',s.approver_user_id,
      'approver_name',coalesce(ae.full_name,ap.full_name),
      'approver_provisioning_status',case when s.approver_user_id is not null then 'active' else 'preinvite' end,
      'backup_approver_employee_id',s.backup_approver_employee_id,
      'backup_approver_user_id',s.backup_approver_user_id,
      'backup_approver_name',coalesce(be.full_name,bp.full_name),
      'backup_provisioning_status',case when s.backup_approver_employee_id is null then null when s.backup_approver_user_id is not null then 'active' else 'preinvite' end,
      'conditions',s.conditions
    ) order by s.approval_order)
    from public.employee_approval_chains s
    left join public.employees ae on ae.id=s.approver_employee_id
    left join public.profiles ap on ap.id=s.approver_user_id
    left join public.employees be on be.id=s.backup_approver_employee_id
    left join public.profiles bp on bp.id=s.backup_approver_user_id
    where s.workflow_version_id=w.id),'[]'::jsonb)
  ) order by w.effective_start_date desc),'[]'::jsonb)
  into result
  from public.employee_approval_workflow_versions w
  where w.employee_id=selected_employee_id;

  return result;
end;
$function$;
revoke all on function public.get_employee_approval_workflows(uuid) from public,anon;
grant execute on function public.get_employee_approval_workflows(uuid) to authenticated;
