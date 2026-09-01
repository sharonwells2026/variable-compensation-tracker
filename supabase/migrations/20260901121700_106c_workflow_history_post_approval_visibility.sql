create or replace function public.get_employee_approval_workflows(selected_employee_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare current_employee uuid:=private.current_employee_id(); result jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication is required.' using errcode='42501'; end if;
 if not private.has_permission('users.manage') and current_employee is distinct from selected_employee_id then raise exception 'You are not permitted to view this approval workflow.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'workflow_version_id',w.id,'workflow_name',w.workflow_name,'status',w.status,'effective_start_date',w.effective_start_date,'effective_end_date',w.effective_end_date,'notes',w.notes,
   'steps',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'approval_order',c.approval_order,'step_name',c.step_name,'approval_level',c.approval_level,'is_required',c.is_required,'approver_employee_id',c.approver_employee_id,'approver_user_id',c.approver_user_id,'approver_name',ae.full_name,'approver_provisioning_status',case when c.approver_user_id is not null then 'active' else 'preinvite' end,'backup_approver_employee_id',c.backup_approver_employee_id,'backup_approver_user_id',c.backup_approver_user_id,'backup_approver_name',be.full_name,'conditions',c.conditions) order by c.approval_order) from public.employee_approval_chains c left join public.employees ae on ae.id=c.approver_employee_id left join public.employees be on be.id=c.backup_approver_employee_id where c.workflow_version_id=w.id),'[]'::jsonb),
   'post_approval_steps',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'stage_order',s.stage_order,'step_name',s.step_name,'step_type',s.step_type,'assignee_employee_id',s.assignee_employee_id,'assignee_user_id',s.assignee_user_id,'assignee_name',se.full_name,'assignee_provisioning_status',case when s.assignee_user_id is not null then 'active' else 'preinvite' end,'is_required_for_payment',s.is_required_for_payment,'requires_payment_details',s.requires_payment_details) order by s.stage_order,s.step_type) from public.employee_post_approval_steps s join public.employees se on se.id=s.assignee_employee_id where s.workflow_version_id=w.id),'[]'::jsonb)
 ) order by w.effective_start_date desc),'[]'::jsonb) into result from public.employee_approval_workflow_versions w where w.employee_id=selected_employee_id;
 return result;
end;$function$;
revoke all on function public.get_employee_approval_workflows(uuid) from public,anon;
grant execute on function public.get_employee_approval_workflows(uuid) to authenticated;
