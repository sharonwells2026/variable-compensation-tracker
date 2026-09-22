begin;

create or replace function private.open_next_comp_earning_approval(target_earning_id uuid, requested_by_user uuid)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare earning_row public.comp_earnings%rowtype; next_chain public.employee_approval_chains%rowtype; previous_order integer:=0; new_request_id uuid;
begin
 select * into earning_row from public.comp_earnings where id=target_earning_id for update;
 if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
 if exists(select 1 from public.approval_requests r where r.comp_earning_id=target_earning_id and r.status='pending'::public.approval_status) then raise exception 'This earning already has a pending approval request.' using errcode='23505'; end if;
 select coalesce(max(r.approval_order),0) into previous_order from public.approval_requests r where r.comp_earning_id=target_earning_id;
 select c.* into next_chain from public.employee_approval_chains c join public.employee_approval_workflow_versions w on w.id=c.workflow_version_id
 where c.employee_id=earning_row.employee_id and c.is_required=true and c.approval_order>previous_order and w.status in ('active','ended') and earning_row.earned_date>=c.effective_start_date and (c.effective_end_date is null or earning_row.earned_date<=c.effective_end_date) and c.approver_user_id is not null order by c.approval_order limit 1;
 if not found then return null; end if;
 insert into public.approval_requests(comp_earning_id,approval_level,approval_order,requested_from,backup_requested_from,requested_by,requested_at,status,chain_snapshot)
 values(target_earning_id,next_chain.approval_level,next_chain.approval_order,next_chain.approver_user_id,next_chain.backup_approver_user_id,requested_by_user,now(),'pending'::public.approval_status,jsonb_build_object('employee_approval_chain_id',next_chain.id,'employee_id',next_chain.employee_id,'approval_order',next_chain.approval_order,'approval_level',next_chain.approval_level,'approver_employee_id',next_chain.approver_employee_id,'approver_user_id',next_chain.approver_user_id,'backup_approver_employee_id',next_chain.backup_approver_employee_id,'backup_approver_user_id',next_chain.backup_approver_user_id,'effective_start_date',next_chain.effective_start_date,'effective_end_date',next_chain.effective_end_date,'earning_earned_date',earning_row.earned_date,'snapshotted_at',now())) returning id into new_request_id;
 insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
 values(next_chain.approver_user_id,'compensation_approval_required','Compensation approval required','A compensation earning is waiting for your approval.','high','approval_request',new_request_id::text,'/','queued',now());
 if next_chain.backup_approver_user_id is not null then
   insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
   values(next_chain.backup_approver_user_id,'compensation_approval_backup','Backup compensation approval','You are the backup approver for a compensation earning.','normal','approval_request',new_request_id::text,'/','queued',now());
 end if;
 return new_request_id;
end;$function$;

create or replace function public.activate_ready_employee_approval_workflow(selected_workflow_version_id uuid)
returns jsonb language plpgsql security definer set search_path=''
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
   select 1 from public.employee_post_approval_steps s where s.workflow_version_id=w.id and s.assignee_user_id is null
 ) q;
 if unresolved>0 then return jsonb_build_object('status','not_ready','workflow_version_id',w.id,'unresolved_assignee_count',unresolved); end if;

 select * into overlapping from public.employee_approval_workflow_versions x where x.employee_id=w.employee_id and x.status='active' and x.id<>w.id and daterange(x.effective_start_date,coalesce(x.effective_end_date+1,'infinity'::date),'[)') && daterange(w.effective_start_date,coalesce(w.effective_end_date+1,'infinity'::date),'[)') order by x.effective_start_date desc limit 1 for update;
 if found then
   if w.effective_start_date<=overlapping.effective_start_date then raise exception 'Planned workflow must begin after the current active workflow start date.' using errcode='22023'; end if;
   perform public.end_employee_approval_workflow(overlapping.id,w.effective_start_date-1);
 end if;
 update public.employee_approval_workflow_versions set status='active',updated_at=now() where id=w.id;
 return jsonb_build_object('status','active','workflow_version_id',w.id,'unresolved_assignee_count',0,'replaced_workflow_version_id',case when overlapping.id is null then null else overlapping.id end);
end;$function$;

commit;