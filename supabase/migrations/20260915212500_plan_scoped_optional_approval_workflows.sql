-- Plan Builder V2: make plan approval configuration drive earning approval runtime.
-- This is Compensation-domain workflow only. It does not change authentication or RevOS identity.

alter table public.employee_approval_workflow_versions
  add column if not exists plan_version_id uuid references public.comp_plan_versions(id) on delete cascade;

create index if not exists employee_approval_workflow_versions_plan_idx
  on public.employee_approval_workflow_versions(plan_version_id,employee_id,status);

alter table public.employee_approval_chains
  drop constraint if exists employee_approval_chains_employee_id_approval_order_effecti_key;

create unique index if not exists employee_approval_chains_workflow_order_unique
  on public.employee_approval_chains(workflow_version_id,approval_order)
  where workflow_version_id is not null;

create unique index if not exists employee_approval_chains_legacy_order_unique
  on public.employee_approval_chains(employee_id,approval_order,effective_start_date)
  where workflow_version_id is null;

create or replace function private.install_plan_approval_workflows(
  target_plan_version_id uuid,
  requested_by_user uuid
)
returns integer
language plpgsql
security definer
set search_path=''
as $function$
declare
  assignment record;
  step record;
  workflow_id uuid;
  workflow_count integer:=0;
  plan_name text;
begin
  select p.name into plan_name
  from public.comp_plan_versions pv
  join public.comp_plans p on p.id=pv.comp_plan_id
  where pv.id=target_plan_version_id;

  if plan_name is null then
    raise exception 'Plan version not found.' using errcode='22023';
  end if;

  if not exists(
    select 1 from public.comp_plan_approval_steps s
    where s.plan_version_id=target_plan_version_id and s.is_required=true
  ) then
    raise exception 'At least one required plan approval step is needed before activation.' using errcode='23514';
  end if;

  for assignment in
    select da.employee_id,da.effective_start_date,da.effective_end_date
    from public.comp_plan_draft_assignments da
    where da.plan_version_id=target_plan_version_id
    order by da.employee_id
  loop
    -- Re-running activation preparation for the same version remains idempotent.
    delete from public.employee_approval_workflow_versions w
    where w.employee_id=assignment.employee_id
      and w.plan_version_id=target_plan_version_id
      and w.status='draft';

    select w.id into workflow_id
    from public.employee_approval_workflow_versions w
    where w.employee_id=assignment.employee_id
      and w.plan_version_id=target_plan_version_id
      and w.status='active'
    order by w.created_at desc
    limit 1;

    if workflow_id is null then
      insert into public.employee_approval_workflow_versions(
        employee_id,workflow_name,effective_start_date,effective_end_date,status,notes,created_by,plan_version_id
      ) values(
        assignment.employee_id,
        plan_name||' approval workflow',
        assignment.effective_start_date,
        assignment.effective_end_date,
        'active',
        'Generated from the activated compensation plan approval workflow.',
        requested_by_user,
        target_plan_version_id
      ) returning id into workflow_id;

      for step in
        select s.*
        from public.comp_plan_approval_steps s
        where s.plan_version_id=target_plan_version_id
        order by s.approval_order
      loop
        insert into public.employee_approval_chains(
          employee_id,workflow_version_id,approval_order,step_name,
          approver_employee_id,approver_user_id,
          backup_approver_employee_id,backup_approver_user_id,
          approval_level,is_required,effective_start_date,effective_end_date,conditions,created_by
        ) values(
          assignment.employee_id,workflow_id,step.approval_order,step.step_name,
          step.approver_employee_id,private.resolve_employee_approver_user(step.approver_employee_id),
          step.backup_approver_employee_id,private.resolve_employee_approver_user(step.backup_approver_employee_id),
          step.approval_level,step.is_required,assignment.effective_start_date,assignment.effective_end_date,
          coalesce(step.conditions,'{}'::jsonb)||jsonb_build_object('plan_version_id',target_plan_version_id),
          requested_by_user
        );
      end loop;
      workflow_count:=workflow_count+1;
    end if;
  end loop;

  return workflow_count;
end;
$function$;

create or replace function private.open_next_comp_earning_approval(target_earning_id uuid, requested_by_user uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  earning_row public.comp_earnings%rowtype;
  earning_plan_version_id uuid;
  previous_required_order integer:=0;
  next_required public.employee_approval_chains%rowtype;
  optional_chain public.employee_approval_chains%rowtype;
  new_request_id uuid;
  optional_request_id uuid;
  has_plan_workflow boolean:=false;
begin
  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;

  select c.plan_version_id into earning_plan_version_id
  from public.comp_plan_components c where c.id=earning_row.plan_component_id;

  select exists(
    select 1
    from public.employee_approval_workflow_versions w
    where w.employee_id=earning_row.employee_id
      and w.plan_version_id=earning_plan_version_id
      and w.status in ('active','ended')
      and earning_row.earned_date>=w.effective_start_date
      and (w.effective_end_date is null or earning_row.earned_date<=w.effective_end_date)
  ) into has_plan_workflow;

  if exists(
    select 1 from public.approval_requests r
    where r.comp_earning_id=target_earning_id
      and r.status='pending'::public.approval_status
      and coalesce((r.chain_snapshot->>'is_required')::boolean,true)
  ) then
    raise exception 'This earning already has a pending required approval request.' using errcode='23505';
  end if;

  select coalesce(max(r.approval_order),0) into previous_required_order
  from public.approval_requests r
  where r.comp_earning_id=target_earning_id
    and coalesce((r.chain_snapshot->>'is_required')::boolean,true)
    and r.status='approved'::public.approval_status;

  select c.* into next_required
  from public.employee_approval_chains c
  join public.employee_approval_workflow_versions w on w.id=c.workflow_version_id
  where c.employee_id=earning_row.employee_id
    and c.is_required=true
    and c.approval_order>previous_required_order
    and w.status in ('active','ended')
    and earning_row.earned_date>=c.effective_start_date
    and (c.effective_end_date is null or earning_row.earned_date<=c.effective_end_date)
    and (
      (has_plan_workflow and w.plan_version_id=earning_plan_version_id)
      or (not has_plan_workflow and w.plan_version_id is null)
    )
  order by c.approval_order
  limit 1;

  -- Optional reviewers with "immediate" notification are opened once at submission.
  for optional_chain in
    select c.*
    from public.employee_approval_chains c
    join public.employee_approval_workflow_versions w on w.id=c.workflow_version_id
    where c.employee_id=earning_row.employee_id
      and c.is_required=false
      and coalesce(c.conditions->>'notify_when','turn')='immediate'
      and w.status in ('active','ended')
      and earning_row.earned_date>=c.effective_start_date
      and (c.effective_end_date is null or earning_row.earned_date<=c.effective_end_date)
      and ((has_plan_workflow and w.plan_version_id=earning_plan_version_id) or (not has_plan_workflow and w.plan_version_id is null))
      and not exists(select 1 from public.approval_requests r where r.comp_earning_id=target_earning_id and r.approval_order=c.approval_order)
    order by c.approval_order
  loop
    insert into public.approval_requests(comp_earning_id,approval_level,approval_order,requested_from,backup_requested_from,requested_by,requested_at,status,chain_snapshot)
    values(target_earning_id,optional_chain.approval_level,optional_chain.approval_order,optional_chain.approver_user_id,optional_chain.backup_approver_user_id,requested_by_user,now(),'pending'::public.approval_status,
      jsonb_build_object('employee_approval_chain_id',optional_chain.id,'employee_id',optional_chain.employee_id,'approval_order',optional_chain.approval_order,'approval_level',optional_chain.approval_level,'is_required',false,'approver_employee_id',optional_chain.approver_employee_id,'approver_user_id',optional_chain.approver_user_id,'backup_approver_employee_id',optional_chain.backup_approver_employee_id,'backup_approver_user_id',optional_chain.backup_approver_user_id,'effective_start_date',optional_chain.effective_start_date,'effective_end_date',optional_chain.effective_end_date,'earning_earned_date',earning_row.earned_date,'snapshotted_at',now(),'assignee_activation_required',optional_chain.approver_user_id is null,'notify_when','immediate'))
    returning id into optional_request_id;
    if optional_chain.approver_user_id is not null then
      insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
      values(optional_chain.approver_user_id,'compensation_optional_review','Optional compensation review','A compensation earning is available for your optional review. Your response does not block the required approval workflow.','normal','approval_request',optional_request_id::text,'/submissions','queued',now());
    end if;
  end loop;

  -- Optional "turn" reviewers between the prior and next required step are opened now,
  -- while the next required approver is also opened so the optional reviewer never blocks progression.
  for optional_chain in
    select c.*
    from public.employee_approval_chains c
    join public.employee_approval_workflow_versions w on w.id=c.workflow_version_id
    where c.employee_id=earning_row.employee_id
      and c.is_required=false
      and coalesce(c.conditions->>'notify_when','turn')='turn'
      and c.approval_order>previous_required_order
      and (next_required.id is null or c.approval_order<next_required.approval_order)
      and w.status in ('active','ended')
      and earning_row.earned_date>=c.effective_start_date
      and (c.effective_end_date is null or earning_row.earned_date<=c.effective_end_date)
      and ((has_plan_workflow and w.plan_version_id=earning_plan_version_id) or (not has_plan_workflow and w.plan_version_id is null))
      and not exists(select 1 from public.approval_requests r where r.comp_earning_id=target_earning_id and r.approval_order=c.approval_order)
    order by c.approval_order
  loop
    insert into public.approval_requests(comp_earning_id,approval_level,approval_order,requested_from,backup_requested_from,requested_by,requested_at,status,chain_snapshot)
    values(target_earning_id,optional_chain.approval_level,optional_chain.approval_order,optional_chain.approver_user_id,optional_chain.backup_approver_user_id,requested_by_user,now(),'pending'::public.approval_status,
      jsonb_build_object('employee_approval_chain_id',optional_chain.id,'employee_id',optional_chain.employee_id,'approval_order',optional_chain.approval_order,'approval_level',optional_chain.approval_level,'is_required',false,'approver_employee_id',optional_chain.approver_employee_id,'approver_user_id',optional_chain.approver_user_id,'backup_approver_employee_id',optional_chain.backup_approver_employee_id,'backup_approver_user_id',optional_chain.backup_approver_user_id,'effective_start_date',optional_chain.effective_start_date,'effective_end_date',optional_chain.effective_end_date,'earning_earned_date',earning_row.earned_date,'snapshotted_at',now(),'assignee_activation_required',optional_chain.approver_user_id is null,'notify_when','turn'))
    returning id into optional_request_id;
    if optional_chain.approver_user_id is not null then
      insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
      values(optional_chain.approver_user_id,'compensation_optional_review','Optional compensation review','A compensation earning is available for your optional review. Your response does not block the required approval workflow.','normal','approval_request',optional_request_id::text,'/submissions','queued',now());
    end if;
  end loop;

  if next_required.id is null then return null; end if;

  insert into public.approval_requests(comp_earning_id,approval_level,approval_order,requested_from,backup_requested_from,requested_by,requested_at,status,chain_snapshot)
  values(target_earning_id,next_required.approval_level,next_required.approval_order,next_required.approver_user_id,next_required.backup_approver_user_id,requested_by_user,now(),'pending'::public.approval_status,
    jsonb_build_object('employee_approval_chain_id',next_required.id,'employee_id',next_required.employee_id,'approval_order',next_required.approval_order,'approval_level',next_required.approval_level,'is_required',true,'approver_employee_id',next_required.approver_employee_id,'approver_user_id',next_required.approver_user_id,'backup_approver_employee_id',next_required.backup_approver_employee_id,'backup_approver_user_id',next_required.backup_approver_user_id,'effective_start_date',next_required.effective_start_date,'effective_end_date',next_required.effective_end_date,'earning_earned_date',earning_row.earned_date,'snapshotted_at',now(),'assignee_activation_required',next_required.approver_user_id is null))
  returning id into new_request_id;

  if next_required.approver_user_id is not null then
    insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
    values(next_required.approver_user_id,'compensation_approval_required','Compensation approval required','A compensation earning is waiting for your approval.','high','approval_request',new_request_id::text,'/submissions','queued',now());
  end if;
  if next_required.backup_approver_user_id is not null then
    insert into public.app_notifications(recipient_user_id,notification_type,title,message,priority,related_record_type,related_record_id,action_url,email_status,email_queued_at)
    values(next_required.backup_approver_user_id,'compensation_approval_backup','Backup compensation approval','You are the backup approver for a compensation earning.','normal','approval_request',new_request_id::text,'/submissions','queued',now());
  end if;
  return new_request_id;
end;
$function$;

create or replace function private.comp_earning_all_approvals_complete(target_earning_id uuid)
returns boolean
language sql
stable security definer
set search_path=''
as $function$
  select
    exists(
      select 1 from public.approval_requests r
      where r.comp_earning_id=target_earning_id
        and coalesce((r.chain_snapshot->>'is_required')::boolean,true)
    )
    and not exists(
      select 1 from public.approval_requests r
      where r.comp_earning_id=target_earning_id
        and coalesce((r.chain_snapshot->>'is_required')::boolean,true)
        and r.status<>'approved'::public.approval_status
    );
$function$;

-- Keep the existing approval action behavior for required steps, but make optional reviews advisory.
create or replace function public.act_on_comp_earning_approval(target_approval_request_id uuid, requested_action public.approval_status, action_comments text default null::text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
 actor uuid:=auth.uid(); request_row public.approval_requests%rowtype; earning_row public.comp_earnings%rowtype;
 next_request_id uuid; final_approval boolean:=false; handoff_count int:=0;
 normalized_comments text:=nullif(trim(coalesce(action_comments,'')),''); is_admin boolean:=false;
 request_is_required boolean:=true;
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
 request_is_required:=coalesce((request_row.chain_snapshot->>'is_required')::boolean,true);
 update public.approval_requests set status=requested_action,completed_at=now(),notes=normalized_comments where id=target_approval_request_id;
 insert into public.approval_actions(approval_request_id,action,action_by,action_at,amount_at_action,comments) values(target_approval_request_id,requested_action,actor,now(),earning_row.earned_amount,normalized_comments);

 if not request_is_required then
   insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
   values(actor,'comp_earning_optional_review_recorded',normalized_comments,jsonb_build_object('earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'action',requested_action,'approval_order',request_row.approval_order,'acted_as_system_admin',is_admin),earning_row.employee_id);
   return jsonb_build_object('status','optional_review_recorded','earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'action',requested_action,'fully_approved',private.comp_earning_all_approvals_complete(earning_row.id));
 end if;

 if requested_action='returned'::public.approval_status then
   update public.comp_earnings set employee_verification_status='correction_requested'::public.verification_status,manager_approval_status='returned'::public.approval_status,manager_approved_by=null,manager_approved_at=null,manager_approval_notes=normalized_comments,approved_amount=0,payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end where id=earning_row.id;
   return jsonb_build_object('status','returned','earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'acted_as_system_admin',is_admin);
 end if;
 if requested_action='rejected'::public.approval_status then
   update public.comp_earnings set manager_approval_status='rejected'::public.approval_status,manager_approved_by=null,manager_approved_at=null,manager_approval_notes=normalized_comments,approved_amount=0,payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end where id=earning_row.id;
   return jsonb_build_object('status','rejected','earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'acted_as_system_admin',is_admin);
 end if;
 if lower(request_row.approval_level) in ('manager','manager_approval','compensation_admin_review') then
   update public.comp_earnings set manager_approval_status='approved'::public.approval_status,manager_approved_by=actor,manager_approved_at=now(),manager_approval_notes=normalized_comments where id=earning_row.id;
 elsif lower(request_row.approval_level) in ('executive','executive_approval') then
   update public.comp_earnings set executive_approval_required=true,executive_approval_status='approved'::public.approval_status,executive_approved_by=actor,executive_approved_at=now(),executive_approval_notes=normalized_comments where id=earning_row.id;
 end if;
 next_request_id:=private.open_next_comp_earning_approval(earning_row.id,actor);
 if next_request_id is null then
   final_approval:=true;
   update public.comp_earnings set approved_amount=earned_amount where id=earning_row.id;
   handoff_count:=private.open_comp_earning_post_approval_handoffs(earning_row.id,actor);
   perform private.refresh_comp_earning_payroll_readiness(earning_row.id);
 end if;
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
 values(actor,case when final_approval then 'comp_earning_fully_approved' else 'comp_earning_approval_step_completed' end,normalized_comments,jsonb_build_object('earning_id',earning_row.id,'approval_request_id',target_approval_request_id,'approval_level',request_row.approval_level,'approval_order',request_row.approval_order,'next_approval_request_id',next_request_id,'fully_approved',final_approval,'post_approval_handoff_count',handoff_count,'acted_as_system_admin',is_admin,'acted_for_unprovisioned_assignee',is_admin and request_row.requested_from is null),earning_row.employee_id);
 return jsonb_build_object('status',case when final_approval then case when handoff_count>0 then 'post_approval_handoff_required' else 'fully_approved' end else 'next_approval_required' end,'earning_id',earning_row.id,'completed_approval_request_id',target_approval_request_id,'next_approval_request_id',next_request_id,'fully_approved',final_approval,'post_approval_handoff_count',handoff_count,'acted_as_system_admin',is_admin);
end;
$function$;

-- Activation installs plan-scoped employee approval workflows after draft assignments are promoted.
create or replace function public.activate_compensation_plan_version(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  selected_plan_id uuid; selected_start date; selected_end date; conflicting_active_id uuid; conflicting_active_start date;
  readiness jsonb; promoted_count integer:=0; installed_workflow_count integer:=0;
begin
  if not private.has_permission('plans.activate') then raise exception 'Plan activation is not permitted.' using errcode='42501'; end if;
  select pv.comp_plan_id,pv.effective_start_date,pv.effective_end_date into selected_plan_id,selected_start,selected_end from public.comp_plan_versions pv where pv.id=selected_plan_version_id and pv.status='draft' and pv.approved_at is not null for update;
  if selected_plan_id is null then raise exception 'The plan version must be draft and approved before activation.' using errcode='22023'; end if;
  readiness:=public.validate_compensation_plan_version_readiness(selected_plan_version_id);
  if coalesce((readiness->>'ready')::boolean,false) is not true then raise exception 'Plan version is no longer ready for activation: %',readiness->'blockers' using errcode='23514'; end if;
  if selected_start>current_date then raise exception 'A future-dated compensation plan version cannot be activated before its effective start date. Leave it approved in draft status until that date.' using errcode='22023'; end if;
  perform 1 from public.comp_plans where id=selected_plan_id for update;
  select pv.id,pv.effective_start_date into conflicting_active_id,conflicting_active_start from public.comp_plan_versions pv where pv.comp_plan_id=selected_plan_id and pv.status='active' and pv.id<>selected_plan_version_id order by pv.effective_start_date desc limit 1 for update;
  if conflicting_active_id is not null then
    if conflicting_active_start>=selected_start then raise exception 'The selected version does not start after the currently active version.' using errcode='22023'; end if;
    update public.comp_plan_versions set status='retired',effective_end_date=selected_start-1,updated_at=now() where id=conflicting_active_id;
  end if;
  insert into public.employee_plan_assignments(employee_id,plan_version_id,related_job_role_id,allocation_percent,effective_start_date,effective_end_date,assignment_notes,assigned_by,eligibility_waiting_period_days,earnings_eligibility_date)
  select da.employee_id,da.plan_version_id,null,da.allocation_percent,da.effective_start_date,da.effective_end_date,da.assignment_notes,auth.uid(),da.eligibility_waiting_period_days,da.effective_start_date+da.eligibility_waiting_period_days
  from public.comp_plan_draft_assignments da where da.plan_version_id=selected_plan_version_id
  on conflict(employee_id,plan_version_id) do update set allocation_percent=excluded.allocation_percent,effective_start_date=excluded.effective_start_date,effective_end_date=excluded.effective_end_date,assignment_notes=excluded.assignment_notes,assigned_by=excluded.assigned_by,eligibility_waiting_period_days=excluded.eligibility_waiting_period_days,earnings_eligibility_date=excluded.earnings_eligibility_date,updated_at=now();
  get diagnostics promoted_count=row_count;
  installed_workflow_count:=private.install_plan_approval_workflows(selected_plan_version_id,auth.uid());
  update public.comp_plan_versions set status='active',updated_at=now() where id=selected_plan_version_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(auth.uid(),'comp_plan_version_activated','A readiness-validated compensation plan version was activated; draft applicability and its plan-scoped approval workflow were promoted together.',jsonb_build_object('plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'previous_active_version_id',conflicting_active_id,'promoted_assignment_count',promoted_count,'installed_approval_workflow_count',installed_workflow_count,'readiness',readiness));
  return jsonb_build_object('status','active','plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'retired_prior_version_id',conflicting_active_id,'promoted_assignment_count',promoted_count,'installed_approval_workflow_count',installed_workflow_count,'readiness',readiness);
end;
$function$;
