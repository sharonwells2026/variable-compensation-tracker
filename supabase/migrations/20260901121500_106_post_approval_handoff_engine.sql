begin;

insert into public.notification_types(notification_type,display_name,description,default_priority,is_active)
values
 ('compensation_approval_required','Compensation approval required','A compensation earning is waiting for the recipient approval.','high',true),
 ('compensation_approval_backup','Backup compensation approval','The recipient is the backup approver for a compensation earning.','normal',true),
 ('compensation_finance_handoff','Compensation payment handoff','An approved compensation earning is ready for finance acknowledgement and payment information.','high',true),
 ('compensation_optional_executive_review','Optional executive review','An approved compensation earning is available for optional executive review.','normal',true)
on conflict (notification_type) do update set display_name=excluded.display_name,description=excluded.description,is_active=true;

create table if not exists public.employee_post_approval_steps (
 id uuid primary key default gen_random_uuid(), workflow_version_id uuid not null references public.employee_approval_workflow_versions(id) on delete cascade,
 employee_id uuid not null references public.employees(id) on delete cascade, stage_order integer not null default 1 check(stage_order>0),
 step_name text not null check(nullif(trim(step_name),'') is not null), step_type text not null check(step_type in ('finance_acknowledgement','optional_executive_review')),
 assignee_employee_id uuid not null references public.employees(id), assignee_user_id uuid references auth.users(id),
 is_required_for_payment boolean not null default false, requires_payment_details boolean not null default false,
 effective_start_date date not null, effective_end_date date, created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint employee_post_approval_steps_dates check(effective_end_date is null or effective_end_date>=effective_start_date),
 constraint employee_post_approval_steps_unique unique(workflow_version_id,step_type,assignee_employee_id)
);
create index if not exists employee_post_approval_steps_workflow_idx on public.employee_post_approval_steps(workflow_version_id,stage_order);

create table if not exists public.comp_earning_handoff_tasks (
 id uuid primary key default gen_random_uuid(), comp_earning_id uuid not null references public.comp_earnings(id) on delete cascade,
 workflow_version_id uuid not null references public.employee_approval_workflow_versions(id), configured_step_id uuid not null references public.employee_post_approval_steps(id),
 stage_order integer not null, step_name text not null, step_type text not null, assigned_employee_id uuid not null references public.employees(id), assigned_user_id uuid references auth.users(id),
 is_required_for_payment boolean not null default false, requires_payment_details boolean not null default false,
 status text not null default 'pending' check(status in ('pending','acknowledged','approved','declined','cancelled')),
 payment_details text, comments text, completed_by uuid references auth.users(id), completed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint comp_earning_handoff_tasks_unique unique(comp_earning_id,configured_step_id)
);
create index if not exists comp_earning_handoff_tasks_earning_idx on public.comp_earning_handoff_tasks(comp_earning_id,status);
create index if not exists comp_earning_handoff_tasks_assignee_idx on public.comp_earning_handoff_tasks(assigned_user_id,status);

create or replace function private.resolve_post_approval_assignee_user(selected_employee_id uuid, selected_step_type text)
returns uuid language sql stable security definer set search_path=''
as $function$
 select p.id from public.profiles p where p.employee_id=selected_employee_id and p.is_active=true
 and case when selected_step_type='finance_acknowledgement' then private.user_has_permission(p.id,'payments.view') else private.user_has_permission(p.id,'earnings.approve') end
 order by p.updated_at desc limit 1;
$function$;
revoke all on function private.resolve_post_approval_assignee_user(uuid,text) from public,anon,authenticated;

create or replace function private.draft_employee_can_post_approval(selected_employee_id uuid, selected_step_type text)
returns boolean language sql stable security definer set search_path=''
as $function$
 select case when selected_step_type='finance_acknowledgement' then private.draft_employee_has_permission(selected_employee_id,'payments.view') else private.draft_employee_has_permission(selected_employee_id,'earnings.approve') end;
$function$;
revoke all on function private.draft_employee_can_post_approval(uuid,text) from public,anon,authenticated;

create or replace function public.set_employee_post_approval_steps(selected_workflow_version_id uuid, selected_steps jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor uuid:=auth.uid(); w public.employee_approval_workflow_versions%rowtype; s record; uid uuid; unresolved int:=0; inserted_count int:=0;
begin
 if actor is null or not private.has_permission('users.manage') then raise exception 'You are not permitted to configure post-approval routing.' using errcode='42501'; end if;
 select * into w from public.employee_approval_workflow_versions where id=selected_workflow_version_id for update;
 if not found then raise exception 'Approval workflow version not found.' using errcode='P0002'; end if;
 if selected_steps is null or jsonb_typeof(selected_steps)<>'array' then raise exception 'Post-approval steps must be an array.' using errcode='22023'; end if;
 delete from public.employee_post_approval_steps where workflow_version_id=w.id;
 for s in select value,ordinality from jsonb_array_elements(selected_steps) with ordinality loop
  if (s.value->>'step_type') not in ('finance_acknowledgement','optional_executive_review') then raise exception 'Unsupported post-approval step type.' using errcode='22023'; end if;
  uid:=private.resolve_post_approval_assignee_user((s.value->>'assignee_employee_id')::uuid,s.value->>'step_type');
  if uid is null and not private.draft_employee_can_post_approval((s.value->>'assignee_employee_id')::uuid,s.value->>'step_type') then raise exception 'Selected post-approval assignee is neither active nor pre-invite configured with the required permission.' using errcode='22023'; end if;
  if uid is null then unresolved:=unresolved+1; end if;
  insert into public.employee_post_approval_steps(workflow_version_id,employee_id,stage_order,step_name,step_type,assignee_employee_id,assignee_user_id,is_required_for_payment,requires_payment_details,effective_start_date,effective_end_date,created_by)
  values(w.id,w.employee_id,coalesce((s.value->>'stage_order')::int,s.ordinality::int),coalesce(nullif(trim(s.value->>'step_name'),''),case when s.value->>'step_type'='finance_acknowledgement' then 'Finance acknowledgement' else 'Optional executive review' end),s.value->>'step_type',(s.value->>'assignee_employee_id')::uuid,uid,coalesce((s.value->>'is_required_for_payment')::boolean,false),coalesce((s.value->>'requires_payment_details')::boolean,false),w.effective_start_date,w.effective_end_date,actor);
  inserted_count:=inserted_count+1;
 end loop;
 if unresolved>0 and w.status='active' then update public.employee_approval_workflow_versions set status='draft',updated_at=now() where id=w.id; end if;
 return jsonb_build_object('status',case when unresolved>0 then 'planned' else 'configured' end,'workflow_version_id',w.id,'step_count',inserted_count,'unresolved_assignees',unresolved);
end;$function$;
revoke all on function public.set_employee_post_approval_steps(uuid,jsonb) from public,anon;
grant execute on function public.set_employee_post_approval_steps(uuid,jsonb) to authenticated;

create or replace function private.open_comp_earning_post_approval_handoffs(target_earning_id uuid, requested_by_user uuid)
returns integer language plpgsql security definer set search_path=''
as $function$
declare e public.comp_earnings%rowtype; w public.employee_approval_workflow_versions%rowtype; s public.employee_post_approval_steps%rowtype; uid uuid; task_id uuid; count_opened int:=0;
begin
 select * into e from public.comp_earnings where id=target_earning_id for update; if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
 select * into w from public.employee_approval_workflow_versions where employee_id=e.employee_id and status in ('active','ended') and e.earned_date>=effective_start_date and (effective_end_date is null or e.earned_date<=effective_end_date) order by effective_start_date desc limit 1; if not found then return 0; end if;
 for s in select * from public.employee_post_approval_steps where workflow_version_id=w.id and e.earned_date>=effective_start_date and (effective_end_date is null or e.earned_date<=effective_end_date) order by stage_order,id loop
  uid:=coalesce(s.assignee_user_id,private.resolve_post_approval_assignee_user(s.assignee_employee_id,s.step_type));
  if uid is null then if s.is_required_for_payment then raise exception 'A required post-approval assignee is not an active application user.' using errcode='22023'; else continue; end if; end if;
  insert into public.comp_earning_handoff_tasks(comp_earning_id,workflow_version_id,configured_step_id,stage_order,step_name,step_type,assigned_employee_id,assigned_user_id,is_required_for_payment,requires_payment_details)
  values(e.id,w.id,s.id,s.stage_order,s.step_name,s.step_type,s.assignee_employee_id,uid,s.is_required_for_payment,s.requires_payment_details)
  on conflict(comp_earning_id,configured_step_id) do update set assigned_user_id=excluded.assigned_user_id,updated_at=now() returning id into task_id;
  insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
  values(uid,case when s.step_type='finance_acknowledgement' then 'compensation_finance_handoff' else 'compensation_optional_executive_review' end,case when s.step_type='finance_acknowledgement' then 'Compensation ready for payment handoff' else 'Optional compensation review' end,case when s.step_type='finance_acknowledgement' then 'An approved compensation earning is waiting for your acknowledgement and payment information.' else 'An approved compensation earning is available for your optional review.' end,case when s.is_required_for_payment then 'high' else 'normal' end,'comp_earning_handoff_task',task_id::text,'/','queued',now());
  count_opened:=count_opened+1;
 end loop;
 return count_opened;
end;$function$;
revoke all on function private.open_comp_earning_post_approval_handoffs(uuid,uuid) from public,anon,authenticated;

create or replace function private.refresh_comp_earning_payroll_readiness(target_earning_id uuid)
returns void language plpgsql security definer set search_path=''
as $function$
declare e public.comp_earnings%rowtype; approvals_complete boolean; handoffs_complete boolean;
begin
 select * into e from public.comp_earnings where id=target_earning_id for update; if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
 approvals_complete:=private.comp_earning_all_approvals_complete(target_earning_id);
 handoffs_complete:=not exists(select 1 from public.comp_earning_handoff_tasks h where h.comp_earning_id=target_earning_id and h.is_required_for_payment=true and h.status not in ('acknowledged','approved'));
 if e.payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then return; end if;
 if approvals_complete and handoffs_complete and e.eligibility_status in ('eligible'::public.eligibility_status,'waived'::public.eligibility_status) and e.eligible_amount>0 and e.approved_amount>0 then update public.comp_earnings set payment_status='ready_for_payroll'::public.payment_status where id=target_earning_id; else update public.comp_earnings set payment_status='not_payable'::public.payment_status where id=target_earning_id; end if;
end;$function$;

create or replace function public.act_on_comp_earning_handoff(target_task_id uuid, requested_action text, requested_payment_details text default null, action_comments text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor uuid:=auth.uid(); t public.comp_earning_handoff_tasks%rowtype; normalized_details text:=nullif(trim(coalesce(requested_payment_details,'')),''); normalized_comments text:=nullif(trim(coalesce(action_comments,'')),''); final_status text;
begin
 if actor is null then raise exception 'Authentication is required.' using errcode='42501'; end if;
 select * into t from public.comp_earning_handoff_tasks where id=target_task_id for update; if not found then raise exception 'Handoff task not found.' using errcode='P0002'; end if;
 if t.status<>'pending' then raise exception 'This handoff task is no longer pending.' using errcode='22023'; end if;
 if actor is distinct from t.assigned_user_id then raise exception 'This handoff task is not assigned to you.' using errcode='42501'; end if;
 if t.step_type='finance_acknowledgement' then
  if not private.has_permission('payments.view') then raise exception 'You are not permitted to acknowledge payment handoffs.' using errcode='42501'; end if;
  if requested_action<>'acknowledged' then raise exception 'Finance handoff action must be acknowledged.' using errcode='22023'; end if;
  if t.requires_payment_details and normalized_details is null then raise exception 'Payment information is required for this acknowledgement.' using errcode='22023'; end if;
  final_status:='acknowledged';
 else
  if not private.has_permission('earnings.approve') then raise exception 'You are not permitted to perform executive compensation review.' using errcode='42501'; end if;
  if requested_action not in ('approved','declined') then raise exception 'Optional executive review action must be approved or declined.' using errcode='22023'; end if;
  final_status:=requested_action;
 end if;
 update public.comp_earning_handoff_tasks set status=final_status,payment_details=normalized_details,comments=normalized_comments,completed_by=actor,completed_at=now(),updated_at=now() where id=t.id;
 perform private.refresh_comp_earning_payroll_readiness(t.comp_earning_id);
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id) select actor,'comp_earning_handoff_completed',normalized_comments,jsonb_build_object('handoff_task_id',t.id,'earning_id',t.comp_earning_id,'step_type',t.step_type,'status',final_status,'payment_details_provided',normalized_details is not null),e.employee_id from public.comp_earnings e where e.id=t.comp_earning_id;
 return jsonb_build_object('status',final_status,'handoff_task_id',t.id,'earning_id',t.comp_earning_id);
end;$function$;
revoke all on function public.act_on_comp_earning_handoff(uuid,text,text,text) from public,anon;
grant execute on function public.act_on_comp_earning_handoff(uuid,text,text,text) to authenticated;

create or replace function private.open_next_comp_earning_approval(target_earning_id uuid, requested_by_user uuid)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare earning_row public.comp_earnings%rowtype; next_chain public.employee_approval_chains%rowtype; previous_order integer:=0; new_request_id uuid;
begin
 select * into earning_row from public.comp_earnings where id=target_earning_id for update; if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
 if exists(select 1 from public.approval_requests r where r.comp_earning_id=target_earning_id and r.status='pending'::public.approval_status) then raise exception 'This earning already has a pending approval request.' using errcode='23505'; end if;
 select coalesce(max(r.approval_order),0) into previous_order from public.approval_requests r where r.comp_earning_id=target_earning_id;
 select c.* into next_chain from public.employee_approval_chains c join public.employee_approval_workflow_versions w on w.id=c.workflow_version_id where c.employee_id=earning_row.employee_id and c.is_required=true and c.approval_order>previous_order and w.status in ('active','ended') and earning_row.earned_date>=c.effective_start_date and (c.effective_end_date is null or earning_row.earned_date<=c.effective_end_date) and c.approver_user_id is not null order by c.approval_order limit 1;
 if not found then return null; end if;
 insert into public.approval_requests(comp_earning_id,approval_level,approval_order,requested_from,backup_requested_from,requested_by,requested_at,status,chain_snapshot) values(target_earning_id,next_chain.approval_level,next_chain.approval_order,next_chain.approver_user_id,next_chain.backup_approver_user_id,requested_by_user,now(),'pending'::public.approval_status,jsonb_build_object('employee_approval_chain_id',next_chain.id,'employee_id',next_chain.employee_id,'approval_order',next_chain.approval_order,'approval_level',next_chain.approval_level,'approver_employee_id',next_chain.approver_employee_id,'approver_user_id',next_chain.approver_user_id,'backup_approver_employee_id',next_chain.backup_approver_employee_id,'backup_approver_user_id',next_chain.backup_approver_user_id,'effective_start_date',next_chain.effective_start_date,'effective_end_date',next_chain.effective_end_date,'earning_earned_date',earning_row.earned_date,'snapshotted_at',now())) returning id into new_request_id;
 insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at) values(next_chain.approver_user_id,'compensation_approval_required','Compensation approval required','A compensation earning is waiting for your approval.','high','approval_request',new_request_id::text,'/','queued',now());
 if next_chain.backup_approver_user_id is not null then insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at) values(next_chain.backup_approver_user_id,'compensation_approval_backup','Backup compensation approval','You are the backup approver for a compensation earning.','normal','approval_request',new_request_id::text,'/','queued',now()); end if;
 return new_request_id;
end;$function$;

create or replace function public.activate_ready_employee_approval_workflow(selected_workflow_version_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor uuid:=auth.uid(); w public.employee_approval_workflow_versions%rowtype; unresolved integer; overlapping public.employee_approval_workflow_versions%rowtype;
begin
 if actor is null or not private.has_permission('users.manage') then raise exception 'You are not permitted to activate approval workflows.' using errcode='42501'; end if;
 select * into w from public.employee_approval_workflow_versions where id=selected_workflow_version_id for update; if not found then raise exception 'Approval workflow version not found.' using errcode='P0002'; end if;
 if w.status='active' then return jsonb_build_object('status','active','workflow_version_id',w.id,'unresolved_assignee_count',0); end if;
 if w.status<>'draft' then raise exception 'Only a draft approval workflow can be activated.' using errcode='22023'; end if;
 update public.employee_approval_chains c set approver_user_id=coalesce(c.approver_user_id,private.resolve_employee_approver_user(c.approver_employee_id)),backup_approver_user_id=case when c.backup_approver_employee_id is null then null else coalesce(c.backup_approver_user_id,private.resolve_employee_approver_user(c.backup_approver_employee_id)) end,updated_at=now() where c.workflow_version_id=w.id;
 update public.employee_post_approval_steps s set assignee_user_id=coalesce(s.assignee_user_id,private.resolve_post_approval_assignee_user(s.assignee_employee_id,s.step_type)),updated_at=now() where s.workflow_version_id=w.id;
 select count(*) into unresolved from (select 1 from public.employee_approval_chains c where c.workflow_version_id=w.id and (c.approver_user_id is null or (c.backup_approver_employee_id is not null and c.backup_approver_user_id is null)) union all select 1 from public.employee_post_approval_steps s where s.workflow_version_id=w.id and s.assignee_user_id is null) q;
 if unresolved>0 then return jsonb_build_object('status','not_ready','workflow_version_id',w.id,'unresolved_assignee_count',unresolved); end if;
 select * into overlapping from public.employee_approval_workflow_versions x where x.employee_id=w.employee_id and x.status='active' and x.id<>w.id and daterange(x.effective_start_date,coalesce(x.effective_end_date+1,'infinity'::date),'[)') && daterange(w.effective_start_date,coalesce(w.effective_end_date+1,'infinity'::date),'[)') order by x.effective_start_date desc limit 1 for update;
 if found then if w.effective_start_date<=overlapping.effective_start_date then raise exception 'Planned workflow must begin after the current active workflow start date.' using errcode='22023'; end if; perform public.end_employee_approval_workflow(overlapping.id,w.effective_start_date-1); end if;
 update public.employee_approval_workflow_versions set status='active',updated_at=now() where id=w.id;
 return jsonb_build_object('status','active','workflow_version_id',w.id,'unresolved_assignee_count',0,'replaced_workflow_version_id',case when overlapping.id is null then null else overlapping.id end);
end;$function$;

-- act_on_comp_earning_approval is replaced so final approval opens post-approval handoff tasks before payroll readiness.
create or replace function public.act_on_comp_earning_approval(target_approval_request_id uuid, requested_action public.approval_status, action_comments text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare actor uuid:=auth.uid(); request_row public.approval_requests%rowtype; earning_row public.comp_earnings%rowtype; next_request_id uuid; final_approval boolean:=false; handoff_count int:=0; normalized_comments text:=nullif(trim(coalesce(action_comments,'')),'');
begin
 if actor is null or not private.has_permission('earnings.approve') then raise exception 'You are not permitted to approve compensation earnings.' using errcode='42501'; end if;
 if requested_action not in ('approved'::public.approval_status,'rejected'::public.approval_status,'returned'::public.approval_status) then raise exception 'Approval action must be approved, rejected, or returned.' using errcode='22023'; end if;
 if requested_action in ('rejected'::public.approval_status,'returned'::public.approval_status) and normalized_comments is null then raise exception 'Comments are required when rejecting or returning an earning.' using errcode='22023'; end if;
 select * into request_row from public.approval_requests where id=target_approval_request_id for update; if not found then raise exception 'Approval request not found.' using errcode='P0002'; end if;
 if request_row.status<>'pending'::public.approval_status then raise exception 'This approval request is no longer pending.' using errcode='22023'; end if;
 if actor is distinct from request_row.requested_from and actor is distinct from request_row.backup_requested_from then raise exception 'This approval request is not assigned to you.' using errcode='42501'; end if;
 select * into earning_row from public.comp_earnings where id=request_row.comp_earning_id for update; if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
 if earning_row.employee_verification_status<>'verified'::public.verification_status then raise exception 'The employee has not verified this earning.' using errcode='22023'; end if;
 update public.approval_requests set status=requested_action,completed_at=now(),notes=normalized_comments where id=target_approval_request_id;
 insert into public.approval_actions(approval_request_id,action,action_by,action_at,amount_at_action,comments) values(target_approval_request_id,requested_action,actor,now(),earning_row.earned_amount,normalized_comments);
 if requested_action='returned'::public.approval_status then update public.comp_earnings set employee_verification_status='correction_requested'::public.verification_status,manager_approval_status='returned'::public.approval_status,manager_approved_by=null,manager_approved_at=null,manager_approval_notes=normalized_comments,approved_amount=0,payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end where id=earning_row.id; return jsonb_build_object('status','returned','earning_id',earning_row.id,'approval_request_id',target_approval_request_id); end if;
 if requested_action='rejected'::public.approval_status then update public.comp_earnings set manager_approval_status='rejected'::public.approval_status,manager_approved_by=null,manager_approved_at=null,manager_approval_notes=normalized_comments,approved_amount=0,payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end where id=earning_row.id; return jsonb_build_object('status','rejected','earning_id',earning_row.id,'approval_request_id',target_approval_request_id); end if;
 if lower(request_row.approval_level)='manager' then update public.comp_earnings set manager_approval_status='approved'::public.approval_status,manager_approved_by=actor,manager_approved_at=now(),manager_approval_notes=normalized_comments where id=earning_row.id; elsif lower(request_row.approval_level)='executive' then update public.comp_earnings set executive_approval_required=true,executive_approval_status='approved'::public.approval_status,executive_approved_by=actor,executive_approved_at=now(),executive_approval_notes=normalized_comments where id=earning_row.id; end if;
 next_request_id:=private.open_next_comp_earning_approval(earning_row.id,actor);
 if next_request_id is null then final_approval:=true; update public.comp_earnings set approved_amount=earned_amount where id=earning_row.id; handoff_count:=private.open_comp_earning_post_approval_handoffs(earning_row.id,actor); perform private.refresh_comp_earning_payroll_readiness(earning_row.id); end if;
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id) values(actor,case when final_approval then 'comp_earning_fully_approved' else 'comp_earning_approval_step_completed' end,normalized_comments,jsonb_build_object('earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'approval_level',request_row.approval_level,'approval_order',request_row.approval_order,'next_approval_request_id',next_request_id,'fully_approved',final_approval,'post_approval_handoff_count',handoff_count),earning_row.employee_id);
 return jsonb_build_object('status',case when final_approval then case when handoff_count>0 then 'post_approval_handoff_required' else 'fully_approved' end else 'next_approval_required' end,'earning_id',earning_row.id,'completed_approval_request_id',target_approval_request_id,'next_approval_request_id',next_request_id,'fully_approved',final_approval,'post_approval_handoff_count',handoff_count);
end;$function$;

commit;
