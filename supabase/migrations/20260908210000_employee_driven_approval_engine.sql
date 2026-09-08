-- Employee-driven earning approval engine.
-- Required approvers may be pre-provisioned but uninvited; workflow steps remain
-- represented and are not silently skipped. System Administrator may exercise
-- unassigned steps for controlled testing, with the real actor preserved in audit.

create or replace function private.open_next_comp_earning_approval(target_earning_id uuid, requested_by_user uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare earning_row public.comp_earnings%rowtype; next_chain public.employee_approval_chains%rowtype; previous_order integer:=0; new_request_id uuid;
begin
 select * into earning_row from public.comp_earnings where id=target_earning_id for update;
 if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
 if exists(select 1 from public.approval_requests r where r.comp_earning_id=target_earning_id and r.status='pending'::public.approval_status) then raise exception 'This earning already has a pending approval request.' using errcode='23505'; end if;
 select coalesce(max(r.approval_order),0) into previous_order from public.approval_requests r where r.comp_earning_id=target_earning_id;
 select c.* into next_chain from public.employee_approval_chains c join public.employee_approval_workflow_versions w on w.id=c.workflow_version_id
 where c.employee_id=earning_row.employee_id and c.is_required=true and c.approval_order>previous_order and w.status in ('active','ended') and earning_row.earned_date>=c.effective_start_date and (c.effective_end_date is null or earning_row.earned_date<=c.effective_end_date)
 order by c.approval_order limit 1;
 if not found then return null; end if;
 insert into public.approval_requests(comp_earning_id,approval_level,approval_order,requested_from,backup_requested_from,requested_by,requested_at,status,chain_snapshot)
 values(target_earning_id,next_chain.approval_level,next_chain.approval_order,next_chain.approver_user_id,next_chain.backup_approver_user_id,requested_by_user,now(),'pending'::public.approval_status,
 jsonb_build_object('employee_approval_chain_id',next_chain.id,'employee_id',next_chain.employee_id,'approval_order',next_chain.approval_order,'approval_level',next_chain.approval_level,'approver_employee_id',next_chain.approver_employee_id,'approver_user_id',next_chain.approver_user_id,'backup_approver_employee_id',next_chain.backup_approver_employee_id,'backup_approver_user_id',next_chain.backup_approver_user_id,'effective_start_date',next_chain.effective_start_date,'effective_end_date',next_chain.effective_end_date,'earning_earned_date',earning_row.earned_date,'snapshotted_at',now(),'assignee_activation_required',next_chain.approver_user_id is null)) returning id into new_request_id;
 if next_chain.approver_user_id is not null then
   insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
   values(next_chain.approver_user_id,'compensation_approval_required','Compensation approval required','A compensation earning is waiting for your approval.','high','approval_request',new_request_id::text,'/submissions','queued',now());
 end if;
 if next_chain.backup_approver_user_id is not null then
   insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
   values(next_chain.backup_approver_user_id,'compensation_approval_backup','Backup compensation approval','You are the backup approver for a compensation earning.','normal','approval_request',new_request_id::text,'/submissions','queued',now());
 end if;
 return new_request_id;
end $$;

create or replace function private.open_comp_earning_post_approval_handoffs(target_earning_id uuid, requested_by_user uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare e public.comp_earnings%rowtype; w public.employee_approval_workflow_versions%rowtype; s public.employee_post_approval_steps%rowtype; uid uuid; task_id uuid; count_opened int:=0;
begin
 select * into e from public.comp_earnings where id=target_earning_id for update;
 if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
 select * into w from public.employee_approval_workflow_versions where employee_id=e.employee_id and status in ('active','ended') and e.earned_date>=effective_start_date and (effective_end_date is null or e.earned_date<=effective_end_date) order by effective_start_date desc limit 1;
 if not found then return 0; end if;
 for s in select * from public.employee_post_approval_steps where workflow_version_id=w.id and e.earned_date>=effective_start_date and (effective_end_date is null or e.earned_date<=effective_end_date) order by stage_order,id loop
   uid:=coalesce(s.assignee_user_id,private.resolve_post_approval_assignee_user(s.assignee_employee_id,s.step_type));
   insert into public.comp_earning_handoff_tasks(comp_earning_id,workflow_version_id,configured_step_id,stage_order,step_name,step_type,assigned_employee_id,assigned_user_id,is_required_for_payment,requires_payment_details)
   values(e.id,w.id,s.id,s.stage_order,s.step_name,s.step_type,s.assignee_employee_id,uid,s.is_required_for_payment,s.requires_payment_details)
   on conflict(comp_earning_id,configured_step_id) do update set assigned_user_id=excluded.assigned_user_id,updated_at=now() returning id into task_id;
   if uid is not null then
     insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
     values(uid,case when s.step_type='finance_acknowledgement' then 'compensation_finance_handoff' else 'compensation_optional_executive_review' end,case when s.step_type='finance_acknowledgement' then 'Compensation ready for payment handoff' else 'Optional compensation review' end,case when s.step_type='finance_acknowledgement' then 'An approved compensation earning is waiting for your acknowledgement and payment information.' else 'An approved compensation earning is available for your optional review.' end,case when s.is_required_for_payment then 'high' else 'normal' end,'comp_earning_handoff_task',task_id::text,'/payments','queued',now());
   end if;
   count_opened:=count_opened+1;
 end loop;
 return count_opened;
end $$;

create or replace function public.act_on_comp_earning_approval(target_approval_request_id uuid, requested_action public.approval_status, action_comments text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); request_row public.approval_requests%rowtype; earning_row public.comp_earnings%rowtype; next_request_id uuid; final_approval boolean:=false; handoff_count int:=0; normalized_comments text:=nullif(trim(coalesce(action_comments,'')),''); is_admin boolean:=false;
begin
 if actor is null or not private.has_permission('earnings.approve') then raise exception 'You are not permitted to approve compensation earnings.' using errcode='42501'; end if;
 is_admin:=private.has_app_role('system_administrator');
 if requested_action not in ('approved'::public.approval_status,'rejected'::public.approval_status,'returned'::public.approval_status) then raise exception 'Approval action must be approved, rejected, or returned.' using errcode='22023'; end if;
 if requested_action in ('rejected'::public.approval_status,'returned'::public.approval_status) and normalized_comments is null then raise exception 'Comments are required when rejecting or returning an earning.' using errcode='22023'; end if;
 select * into request_row from public.approval_requests where id=target_approval_request_id for update;
 if not found then raise exception 'Approval request not found.' using errcode='P0002'; end if;
 if request_row.status<>'pending'::public.approval_status then raise exception 'This approval request is no longer pending.' using errcode='22023'; end if;
 if not is_admin and actor is distinct from request_row.requested_from and actor is distinct from request_row.backup_requested_from then raise exception 'This approval request is not assigned to you.' using errcode='42501'; end if;
 select * into earning_row from public.comp_earnings where id=request_row.comp_earning_id for update;
 if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
 if earning_row.employee_verification_status<>'verified'::public.verification_status then raise exception 'The employee has not verified this earning.' using errcode='22023'; end if;
 update public.approval_requests set status=requested_action,completed_at=now(),notes=normalized_comments where id=target_approval_request_id;
 insert into public.approval_actions(approval_request_id,action,action_by,action_at,amount_at_action,comments) values(target_approval_request_id,requested_action,actor,now(),earning_row.earned_amount,normalized_comments);
 if requested_action='returned'::public.approval_status then update public.comp_earnings set employee_verification_status='correction_requested'::public.verification_status,manager_approval_status='returned'::public.approval_status,manager_approved_by=null,manager_approved_at=null,manager_approval_notes=normalized_comments,approved_amount=0,payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end where id=earning_row.id; return jsonb_build_object('status','returned','earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'acted_as_system_admin',is_admin); end if;
 if requested_action='rejected'::public.approval_status then update public.comp_earnings set manager_approval_status='rejected'::public.approval_status,manager_approved_by=null,manager_approved_at=null,manager_approval_notes=normalized_comments,approved_amount=0,payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end where id=earning_row.id; return jsonb_build_object('status','rejected','earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'acted_as_system_admin',is_admin); end if;
 if lower(request_row.approval_level) in ('manager','manager_approval','compensation_admin_review') then update public.comp_earnings set manager_approval_status='approved'::public.approval_status,manager_approved_by=actor,manager_approved_at=now(),manager_approval_notes=normalized_comments where id=earning_row.id;
 elsif lower(request_row.approval_level) in ('executive','executive_approval') then update public.comp_earnings set executive_approval_required=true,executive_approval_status='approved'::public.approval_status,executive_approved_by=actor,executive_approved_at=now(),executive_approval_notes=normalized_comments where id=earning_row.id; end if;
 next_request_id:=private.open_next_comp_earning_approval(earning_row.id,actor);
 if next_request_id is null then final_approval:=true; update public.comp_earnings set approved_amount=earned_amount where id=earning_row.id; handoff_count:=private.open_comp_earning_post_approval_handoffs(earning_row.id,actor); perform private.refresh_comp_earning_payroll_readiness(earning_row.id); end if;
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id) values(actor,case when final_approval then 'comp_earning_fully_approved' else 'comp_earning_approval_step_completed' end,normalized_comments,jsonb_build_object('earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'approval_level',request_row.approval_level,'approval_order',request_row.approval_order,'next_approval_request_id',next_request_id,'fully_approved',final_approval,'post_approval_handoff_count',handoff_count,'acted_as_system_admin',is_admin,'acted_for_unprovisioned_assignee',is_admin and request_row.requested_from is null),earning_row.employee_id);
 return jsonb_build_object('status',case when final_approval then case when handoff_count>0 then 'post_approval_handoff_required' else 'fully_approved' end else 'next_approval_required' end,'earning_id',earning_row.id,'completed_approval_request_id',target_approval_request_id,'next_approval_request_id',next_request_id,'fully_approved',final_approval,'post_approval_handoff_count',handoff_count,'acted_as_system_admin',is_admin);
end $$;

create or replace function public.get_my_comp_earning_approval_requests(include_completed boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); is_admin boolean:=false; result jsonb;
begin
 if actor is null then raise exception 'Authentication is required.' using errcode='42501'; end if;
 if not private.has_permission('earnings.approve') then raise exception 'Approval access is not permitted.' using errcode='42501'; end if;
 is_admin:=private.has_app_role('system_administrator');
 select coalesce(jsonb_agg(jsonb_build_object('approval_request_id',r.id,'earning_id',e.id,'employee_id',e.employee_id,'employee_name',emp.full_name,'employee_email',emp.email,'earning_name',e.earning_name,'earning_description',e.earning_description,'earned_date',e.earned_date,'earned_amount',e.earned_amount,'eligible_amount',e.eligible_amount,'approved_amount',e.approved_amount,'approval_level',r.approval_level,'approval_order',r.approval_order,'status',r.status,'requested_at',r.requested_at,'completed_at',r.completed_at,'notes',r.notes,'requested_from',r.requested_from,'backup_requested_from',r.backup_requested_from,'approver_employee_id',r.chain_snapshot->>'approver_employee_id','approver_name',approver.full_name,'assignee_activation_required',coalesce((r.chain_snapshot->>'assignee_activation_required')::boolean,false) or r.requested_from is null,'source_snapshot',e.source_snapshot,'payment_status',e.payment_status,'employee_verification_status',e.employee_verification_status) order by case when r.status='pending'::public.approval_status then 0 else 1 end,r.requested_at desc),'[]'::jsonb) into result
 from public.approval_requests r join public.comp_earnings e on e.id=r.comp_earning_id join public.employees emp on emp.id=e.employee_id left join public.employees approver on approver.id=nullif(r.chain_snapshot->>'approver_employee_id','')::uuid
 where (include_completed or r.status='pending'::public.approval_status) and (is_admin or r.requested_from=actor or r.backup_requested_from=actor);
 return result;
end $$;
revoke all on function public.get_my_comp_earning_approval_requests(boolean) from public,anon;
grant execute on function public.get_my_comp_earning_approval_requests(boolean) to authenticated;

create or replace function public.get_my_comp_earning_handoff_tasks(include_completed boolean default false)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); is_admin boolean:=false; result jsonb;
begin
 if actor is null then raise exception 'Authentication is required.' using errcode='42501'; end if;
 is_admin:=private.has_app_role('system_administrator');
 if not (is_admin or private.has_permission('payments.view') or private.has_permission('earnings.approve')) then raise exception 'Handoff access is not permitted.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('task_id',t.id,'earning_id',t.comp_earning_id,'workflow_version_id',t.workflow_version_id,'stage_order',t.stage_order,'step_name',t.step_name,'step_type',t.step_type,'is_required_for_payment',t.is_required_for_payment,'requires_payment_details',t.requires_payment_details,'status',t.status,'payment_details',t.payment_details,'comments',t.comments,'completed_at',t.completed_at,'created_at',t.created_at,'assigned_user_id',t.assigned_user_id,'assigned_employee_id',t.assigned_employee_id,'assigned_employee_name',assignee.full_name,'assignee_activation_required',t.assigned_user_id is null,'employee_id',e.employee_id,'employee_name',emp.full_name,'employee_email',emp.email,'earning_name',e.earning_name,'earning_description',e.earning_description,'earned_date',e.earned_date,'earned_amount',e.earned_amount,'eligible_amount',e.eligible_amount,'approved_amount',e.approved_amount,'eligibility_status',e.eligibility_status,'payment_status',e.payment_status,'expected_payment_date',e.expected_payment_date,'expected_pay_period_label',e.expected_pay_period_label) order by case when t.status='pending' then 0 else 1 end,t.created_at desc),'[]'::jsonb) into result
 from public.comp_earning_handoff_tasks t join public.comp_earnings e on e.id=t.comp_earning_id join public.employees emp on emp.id=e.employee_id left join public.employees assignee on assignee.id=t.assigned_employee_id
 where (include_completed or t.status='pending') and (is_admin or t.assigned_user_id=actor);
 return result;
end $$;
