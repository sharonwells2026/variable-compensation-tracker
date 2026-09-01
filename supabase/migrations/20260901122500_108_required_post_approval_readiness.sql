-- 108: required post-approval participants determine workflow activation readiness.
-- Optional executive reviewers remain visible/notified but do not block activation or payment.

create or replace function public.activate_ready_employee_approval_workflow(selected_workflow_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare actor uuid:=auth.uid(); w public.employee_approval_workflow_versions%rowtype; unresolved integer; overlapping public.employee_approval_workflow_versions%rowtype;
begin
 if actor is null or not private.has_permission('users.manage') then raise exception 'You are not permitted to activate approval workflows.' using errcode='42501'; end if;
 select * into w from public.employee_approval_workflow_versions where id=selected_workflow_version_id for update;
 if not found then raise exception 'Approval workflow version not found.' using errcode='P0002'; end if;
 if w.status='active' then return jsonb_build_object('status','active','workflow_version_id',w.id,'unresolved_assignee_count',0); end if;
 if w.status<>'draft' then raise exception 'Only a draft approval workflow can be activated.' using errcode='22023'; end if;
 update public.employee_approval_chains c set approver_user_id=coalesce(c.approver_user_id,private.resolve_employee_approver_user(c.approver_employee_id)),backup_approver_user_id=case when c.backup_approver_employee_id is null then null else coalesce(c.backup_approver_user_id,private.resolve_employee_approver_user(c.backup_approver_employee_id)) end,updated_at=now() where c.workflow_version_id=w.id;
 update public.employee_post_approval_steps s set assignee_user_id=coalesce(s.assignee_user_id,private.resolve_post_approval_assignee_user(s.assignee_employee_id,s.step_type)),updated_at=now() where s.workflow_version_id=w.id;
 select count(*) into unresolved from (
   select 1 from public.employee_approval_chains c where c.workflow_version_id=w.id and (c.approver_user_id is null or (c.backup_approver_employee_id is not null and c.backup_approver_user_id is null))
   union all
   select 1 from public.employee_post_approval_steps s where s.workflow_version_id=w.id and s.is_required_for_payment=true and s.assignee_user_id is null
 ) q;
 if unresolved>0 then return jsonb_build_object('status','not_ready','workflow_version_id',w.id,'unresolved_assignee_count',unresolved,'unresolved_approver_count',unresolved); end if;
 select * into overlapping from public.employee_approval_workflow_versions x where x.employee_id=w.employee_id and x.status='active' and x.id<>w.id and daterange(x.effective_start_date,coalesce(x.effective_end_date+1,'infinity'::date),'[)') && daterange(w.effective_start_date,coalesce(w.effective_end_date+1,'infinity'::date),'[)') order by x.effective_start_date desc limit 1 for update;
 if found then if w.effective_start_date<=overlapping.effective_start_date then raise exception 'Planned workflow must begin after the current active workflow start date.' using errcode='22023'; end if; perform public.end_employee_approval_workflow(overlapping.id,w.effective_start_date-1); end if;
 update public.employee_approval_workflow_versions set status='active',updated_at=now() where id=w.id;
 return jsonb_build_object('status','active','workflow_version_id',w.id,'unresolved_assignee_count',0,'unresolved_approver_count',0,'replaced_workflow_version_id',case when overlapping.id is null then null else overlapping.id end);
end;$function$;

create or replace function public.get_approval_workflow_admin_data()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare employees_json jsonb; approvers_json jsonb;
begin
 if auth.uid() is null or not private.has_permission('users.manage') then raise exception 'You are not permitted to administer approval workflows.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'employee_id',e.id,'full_name',e.full_name,'email',e.email,'job_title',e.job_title,'is_active',e.is_active,
  'current_workflow',(select jsonb_build_object('workflow_version_id',w.id,'workflow_name',w.workflow_name,'effective_start_date',w.effective_start_date,'effective_end_date',w.effective_end_date,'status',w.status,'step_count',(select count(*) from public.employee_approval_chains s where s.workflow_version_id=w.id)) from public.employee_approval_workflow_versions w where w.employee_id=e.id and w.status='active' and current_date>=w.effective_start_date and (w.effective_end_date is null or current_date<=w.effective_end_date) order by w.effective_start_date desc limit 1),
  'planned_workflow',(select jsonb_build_object('workflow_version_id',w.id,'workflow_name',w.workflow_name,'effective_start_date',w.effective_start_date,'effective_end_date',w.effective_end_date,'status',w.status,'step_count',(select count(*) from public.employee_approval_chains s where s.workflow_version_id=w.id),'post_approval_step_count',(select count(*) from public.employee_post_approval_steps s where s.workflow_version_id=w.id),'unresolved_approver_count',((select count(*) from public.employee_approval_chains s where s.workflow_version_id=w.id and (s.approver_user_id is null or (s.backup_approver_employee_id is not null and s.backup_approver_user_id is null)))+(select count(*) from public.employee_post_approval_steps s where s.workflow_version_id=w.id and s.is_required_for_payment=true and s.assignee_user_id is null)),'unresolved_post_assignee_count',(select count(*) from public.employee_post_approval_steps s where s.workflow_version_id=w.id and s.is_required_for_payment=true and s.assignee_user_id is null)) from public.employee_approval_workflow_versions w where w.employee_id=e.id and w.status='draft' order by w.effective_start_date desc limit 1)
 ) order by e.full_name),'[]'::jsonb) into employees_json from public.employees e where e.is_active=true;
 select coalesce(jsonb_agg(jsonb_build_object('employee_id',e.id,'full_name',e.full_name,'email',e.email,'user_id',private.resolve_employee_approver_user(e.id),'provisioning_status',case when private.resolve_employee_approver_user(e.id) is not null then 'active' when private.draft_employee_has_permission(e.id,'earnings.approve') then 'preinvite' else 'unavailable' end) order by e.full_name),'[]'::jsonb) into approvers_json from public.employees e where e.is_active=true and (private.resolve_employee_approver_user(e.id) is not null or private.draft_employee_has_permission(e.id,'earnings.approve'));
 return jsonb_build_object('employees',employees_json,'eligible_approvers',approvers_json);
end;$function$;
