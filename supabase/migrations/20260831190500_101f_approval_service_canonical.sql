-- 101F Canonical Approval Service
-- Exact production contract reconstructed from validated live definitions on 2026-08-31.

alter table public.approval_requests
  add column if not exists approval_order integer,
  add column if not exists backup_requested_from uuid,
  add column if not exists chain_snapshot jsonb not null default '{}'::jsonb;

create unique index if not exists approval_requests_one_pending_per_earning_idx
on public.approval_requests(comp_earning_id)
where status='pending'::public.approval_status;

create index if not exists approval_requests_earning_order_idx
on public.approval_requests(comp_earning_id,approval_order,requested_at);

create or replace function private.comp_earning_all_approvals_complete(target_earning_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $function$
  select
    exists(select 1 from public.approval_requests request where request.comp_earning_id=target_earning_id)
    and not exists(
      select 1 from public.approval_requests request
      where request.comp_earning_id=target_earning_id
        and request.status<>'approved'::public.approval_status
    );
$function$;
revoke all on function private.comp_earning_all_approvals_complete(uuid) from public,anon,authenticated;

create or replace function private.refresh_comp_earning_payroll_readiness(target_earning_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $function$
declare
  earning_row public.comp_earnings%rowtype;
  approvals_complete boolean;
begin
  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;

  approvals_complete:=private.comp_earning_all_approvals_complete(target_earning_id);

  if earning_row.payment_status in (
    'scheduled'::public.payment_status,
    'partially_paid'::public.payment_status,
    'paid'::public.payment_status,
    'held'::public.payment_status
  ) then return; end if;

  if approvals_complete
     and earning_row.eligibility_status in ('eligible'::public.eligibility_status,'waived'::public.eligibility_status)
     and earning_row.eligible_amount>0
     and earning_row.approved_amount>0 then
    update public.comp_earnings set payment_status='ready_for_payroll'::public.payment_status where id=target_earning_id;
  else
    update public.comp_earnings set payment_status='not_payable'::public.payment_status where id=target_earning_id;
  end if;
end;
$function$;
revoke all on function private.refresh_comp_earning_payroll_readiness(uuid) from public,anon,authenticated;

create or replace function private.open_next_comp_earning_approval(target_earning_id uuid,requested_by_user uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  earning_row public.comp_earnings%rowtype;
  next_chain public.employee_approval_chains%rowtype;
  previous_order integer:=0;
  new_request_id uuid;
begin
  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;

  if exists(select 1 from public.approval_requests request where request.comp_earning_id=target_earning_id and request.status='pending'::public.approval_status) then
    raise exception 'This earning already has a pending approval request.' using errcode='23505';
  end if;

  select coalesce(max(request.approval_order),0) into previous_order
  from public.approval_requests request where request.comp_earning_id=target_earning_id;

  select chain.* into next_chain
  from public.employee_approval_chains chain
  where chain.employee_id=earning_row.employee_id
    and chain.is_required=true
    and chain.approval_order>previous_order
    and earning_row.earned_date>=chain.effective_start_date
    and (chain.effective_end_date is null or earning_row.earned_date<=chain.effective_end_date)
  order by chain.approval_order limit 1;

  if not found then return null; end if;

  insert into public.approval_requests(
    comp_earning_id,approval_level,approval_order,requested_from,backup_requested_from,
    requested_by,requested_at,status,chain_snapshot
  ) values (
    target_earning_id,next_chain.approval_level,next_chain.approval_order,
    next_chain.approver_user_id,next_chain.backup_approver_user_id,requested_by_user,now(),
    'pending'::public.approval_status,
    jsonb_build_object(
      'employee_approval_chain_id',next_chain.id,
      'employee_id',next_chain.employee_id,
      'approval_order',next_chain.approval_order,
      'approval_level',next_chain.approval_level,
      'approver_user_id',next_chain.approver_user_id,
      'backup_approver_user_id',next_chain.backup_approver_user_id,
      'effective_start_date',next_chain.effective_start_date,
      'effective_end_date',next_chain.effective_end_date,
      'earning_earned_date',earning_row.earned_date,
      'snapshotted_at',now()
    )
  ) returning id into new_request_id;

  insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id)
  values(next_chain.approver_user_id,'compensation_approval_required','Compensation approval required','A compensation earning is waiting for your approval.','high','approval_request',new_request_id::text);

  if next_chain.backup_approver_user_id is not null then
    insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id)
    values(next_chain.backup_approver_user_id,'compensation_approval_backup','Backup compensation approval','You are the backup approver for a compensation earning.','normal','approval_request',new_request_id::text);
  end if;

  return new_request_id;
end;
$function$;
revoke all on function private.open_next_comp_earning_approval(uuid,uuid) from public,anon,authenticated;

create or replace function public.submit_my_comp_earning_for_approval(target_earning_id uuid,verification_notes text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  current_employee uuid:=private.current_employee_id();
  earning_row public.comp_earnings%rowtype;
  assignment_row public.employee_plan_assignments%rowtype;
  effective_earning_eligibility_date date;
  first_request_id uuid;
begin
  if (select auth.uid()) is null or current_employee is null or not private.has_permission('earnings.submit_own') then
    raise exception 'You are not permitted to submit compensation earnings.' using errcode='42501';
  end if;

  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
  if earning_row.employee_id<>current_employee then raise exception 'You may only submit your own compensation earnings.' using errcode='42501'; end if;
  if not earning_row.is_current then raise exception 'A superseded compensation earning cannot be submitted.' using errcode='22023'; end if;
  if earning_row.earned_date>current_date then raise exception 'A future forecast earning cannot be submitted.' using errcode='22023'; end if;
  if earning_row.plan_assignment_id is null then raise exception 'The earning is not linked to a compensation plan assignment.' using errcode='22023'; end if;

  select * into assignment_row from public.employee_plan_assignments where id=earning_row.plan_assignment_id;
  if not found then raise exception 'The earning compensation plan assignment no longer exists.' using errcode='P0002'; end if;

  if assignment_row.employee_id<>earning_row.employee_id
     or earning_row.earned_date<assignment_row.effective_start_date
     or (assignment_row.effective_end_date is not null and earning_row.earned_date>assignment_row.effective_end_date) then
    raise exception 'The earning is not governed by its linked plan assignment on the earned date.' using errcode='22023';
  end if;

  effective_earning_eligibility_date:=private.resolve_comp_earning_eligibility_date(earning_row.plan_assignment_id,earning_row.plan_component_id);
  if effective_earning_eligibility_date is null then raise exception 'The compensation plan assignment does not have an earnings eligibility date.' using errcode='22023'; end if;
  if earning_row.earned_date<effective_earning_eligibility_date then raise exception 'This earning occurred before the employee became eligible to earn this compensation component.' using errcode='22023'; end if;

  if earning_row.employee_verification_status='verified'::public.verification_status
     and exists(select 1 from public.approval_requests request where request.comp_earning_id=target_earning_id and request.status='pending'::public.approval_status) then
    raise exception 'This earning has already been submitted for approval.' using errcode='22023';
  end if;

  if private.comp_earning_all_approvals_complete(target_earning_id) then
    raise exception 'This earning has already completed approval.' using errcode='22023';
  end if;

  if not exists(
    select 1 from public.employee_approval_chains chain
    where chain.employee_id=current_employee and chain.is_required=true
      and earning_row.earned_date>=chain.effective_start_date
      and (chain.effective_end_date is null or earning_row.earned_date<=chain.effective_end_date)
  ) then raise exception 'No approval chain is configured for this employee on the earning date.' using errcode='22023'; end if;

  update public.comp_earnings set
    employee_verification_status='verified'::public.verification_status,
    employee_verified_at=now(),
    employee_verification_notes=nullif(trim(coalesce(verification_notes,'')),''),
    manager_approval_status='pending'::public.approval_status,
    manager_approved_by=null,
    manager_approved_at=null,
    manager_approval_notes=null,
    approved_amount=0,
    payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end
  where id=target_earning_id;

  first_request_id:=private.open_next_comp_earning_approval(target_earning_id,(select auth.uid()));
  if first_request_id is null then raise exception 'No approval request could be created for this earning.' using errcode='22023'; end if;

  insert into public.app_access_audit_events(actor_user_id,target_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(
    (select auth.uid()),(select auth.uid()),'comp_earning_submitted',
    'Employee verified and submitted a compensation earning for approval.',
    jsonb_build_object('employee_verification_status',earning_row.employee_verification_status,'manager_approval_status',earning_row.manager_approval_status,'approved_amount',earning_row.approved_amount,'payment_status',earning_row.payment_status),
    jsonb_build_object('earning_id',target_earning_id,'employee_verification_status','verified','approval_request_id',first_request_id,'effective_earning_eligibility_date',effective_earning_eligibility_date),
    current_employee
  );

  return jsonb_build_object('status','submitted','earning_id',target_earning_id,'approval_request_id',first_request_id,'effective_earning_eligibility_date',effective_earning_eligibility_date);
end;
$function$;
revoke all on function public.submit_my_comp_earning_for_approval(uuid,text) from public,anon;
grant execute on function public.submit_my_comp_earning_for_approval(uuid,text) to authenticated;

create or replace function public.act_on_comp_earning_approval(target_approval_request_id uuid,requested_action public.approval_status,action_comments text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid:=(select auth.uid());
  request_row public.approval_requests%rowtype;
  earning_row public.comp_earnings%rowtype;
  next_request_id uuid;
  final_approval boolean:=false;
  normalized_comments text:=nullif(trim(coalesce(action_comments,'')),'');
begin
  if actor is null or not private.has_permission('earnings.approve') then raise exception 'You are not permitted to approve compensation earnings.' using errcode='42501'; end if;
  if requested_action not in ('approved'::public.approval_status,'rejected'::public.approval_status,'returned'::public.approval_status) then raise exception 'Approval action must be approved, rejected, or returned.' using errcode='22023'; end if;
  if requested_action in ('rejected'::public.approval_status,'returned'::public.approval_status) and normalized_comments is null then raise exception 'Comments are required when rejecting or returning an earning.' using errcode='22023'; end if;

  select * into request_row from public.approval_requests where id=target_approval_request_id for update;
  if not found then raise exception 'Approval request not found.' using errcode='P0002'; end if;
  if request_row.status<>'pending'::public.approval_status then raise exception 'This approval request is no longer pending.' using errcode='22023'; end if;
  if actor is distinct from request_row.requested_from and actor is distinct from request_row.backup_requested_from then raise exception 'This approval request is not assigned to you.' using errcode='42501'; end if;

  select * into earning_row from public.comp_earnings where id=request_row.comp_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
  if earning_row.employee_verification_status<>'verified'::public.verification_status then raise exception 'The employee has not verified this earning.' using errcode='22023'; end if;

  update public.approval_requests set status=requested_action,completed_at=now(),notes=normalized_comments where id=target_approval_request_id;
  insert into public.approval_actions(approval_request_id,action,action_by,action_at,amount_at_action,comments)
  values(target_approval_request_id,requested_action,actor,now(),earning_row.earned_amount,normalized_comments);

  if requested_action='returned'::public.approval_status then
    update public.comp_earnings set
      employee_verification_status='correction_requested'::public.verification_status,
      manager_approval_status='returned'::public.approval_status,
      manager_approved_by=null,manager_approved_at=null,manager_approval_notes=normalized_comments,approved_amount=0,
      payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end
    where id=earning_row.id;
    insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
    values(actor,'comp_earning_returned',normalized_comments,jsonb_build_object('earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'status','returned'),earning_row.employee_id);
    return jsonb_build_object('status','returned','earning_id',earning_row.id,'approval_request_id',target_approval_request_id);
  end if;

  if requested_action='rejected'::public.approval_status then
    update public.comp_earnings set
      manager_approval_status='rejected'::public.approval_status,
      manager_approved_by=null,manager_approved_at=null,manager_approval_notes=normalized_comments,approved_amount=0,
      payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end
    where id=earning_row.id;
    insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
    values(actor,'comp_earning_rejected',normalized_comments,jsonb_build_object('earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'status','rejected'),earning_row.employee_id);
    return jsonb_build_object('status','rejected','earning_id',earning_row.id,'approval_request_id',target_approval_request_id);
  end if;

  if lower(request_row.approval_level)='manager' then
    update public.comp_earnings set manager_approval_status='approved'::public.approval_status,manager_approved_by=actor,manager_approved_at=now(),manager_approval_notes=normalized_comments where id=earning_row.id;
  elsif lower(request_row.approval_level)='executive' then
    update public.comp_earnings set executive_approval_required=true,executive_approval_status='approved'::public.approval_status,executive_approved_by=actor,executive_approved_at=now(),executive_approval_notes=normalized_comments where id=earning_row.id;
  end if;

  next_request_id:=private.open_next_comp_earning_approval(earning_row.id,actor);
  if next_request_id is null then
    final_approval:=true;
    update public.comp_earnings set approved_amount=earned_amount where id=earning_row.id;
    perform private.refresh_comp_earning_payroll_readiness(earning_row.id);
  end if;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values(actor,case when final_approval then 'comp_earning_fully_approved' else 'comp_earning_approval_step_completed' end,normalized_comments,
    jsonb_build_object('earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'approval_level',request_row.approval_level,'approval_order',request_row.approval_order,'next_approval_request_id',next_request_id,'fully_approved',final_approval),earning_row.employee_id);

  return jsonb_build_object('status',case when final_approval then 'fully_approved' else 'next_approval_required' end,'earning_id',earning_row.id,'completed_approval_request_id',target_approval_request_id,'next_approval_request_id',next_request_id,'fully_approved',final_approval);
end;
$function$;
revoke all on function public.act_on_comp_earning_approval(uuid,public.approval_status,text) from public,anon;
grant execute on function public.act_on_comp_earning_approval(uuid,public.approval_status,text) to authenticated;
