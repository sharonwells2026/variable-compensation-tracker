create or replace function public.admin_test_submit_comp_earning_for_approval(target_earning_id uuid, verification_notes text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := auth.uid();
  earning_row public.comp_earnings%rowtype;
  assignment_row public.employee_plan_assignments%rowtype;
  effective_earning_eligibility_date date;
  first_request_id uuid;
begin
  if actor is null or not private.has_app_role('system_administrator') then
    raise exception 'System Administrator test mode is required.' using errcode='42501';
  end if;

  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
  if not earning_row.is_current then raise exception 'A superseded compensation earning cannot be submitted.' using errcode='22023'; end if;
  if earning_row.earned_date > current_date then raise exception 'A future forecast earning cannot be submitted.' using errcode='22023'; end if;
  if earning_row.eligibility_status <> 'eligible'::public.eligibility_status or coalesce(earning_row.eligible_amount,0)<=0 then
    raise exception 'Only an eligible earning can be submitted in employee test mode.' using errcode='22023';
  end if;
  if earning_row.plan_assignment_id is null then raise exception 'The earning is not linked to a compensation plan assignment.' using errcode='22023'; end if;

  select * into assignment_row from public.employee_plan_assignments where id=earning_row.plan_assignment_id;
  if not found then raise exception 'The earning compensation plan assignment no longer exists.' using errcode='P0002'; end if;
  if assignment_row.employee_id<>earning_row.employee_id or earning_row.earned_date<assignment_row.effective_start_date or (assignment_row.effective_end_date is not null and earning_row.earned_date>assignment_row.effective_end_date) then
    raise exception 'The earning is not governed by its linked plan assignment on the earned date.' using errcode='22023';
  end if;

  effective_earning_eligibility_date:=private.resolve_comp_earning_eligibility_date(earning_row.plan_assignment_id,earning_row.plan_component_id);
  if effective_earning_eligibility_date is null or earning_row.earned_date<effective_earning_eligibility_date then
    raise exception 'The earning is not eligible under its linked compensation plan assignment.' using errcode='22023';
  end if;

  if earning_row.employee_verification_status='verified'::public.verification_status and exists(select 1 from public.approval_requests r where r.comp_earning_id=target_earning_id and r.status='pending'::public.approval_status) then
    raise exception 'This earning has already been submitted for approval.' using errcode='22023';
  end if;
  if private.comp_earning_all_approvals_complete(target_earning_id) then raise exception 'This earning has already completed approval.' using errcode='22023'; end if;
  if not exists(select 1 from public.employee_approval_chains c where c.employee_id=earning_row.employee_id and c.is_required=true and earning_row.earned_date>=c.effective_start_date and (c.effective_end_date is null or earning_row.earned_date<=c.effective_end_date)) then
    raise exception 'No approval chain is configured for this employee on the earning date.' using errcode='22023';
  end if;

  update public.comp_earnings set employee_verification_status='verified'::public.verification_status, employee_verified_at=now(), employee_verification_notes=nullif(trim(coalesce(verification_notes,'')),''), manager_approval_status='pending'::public.approval_status, manager_approved_by=null, manager_approved_at=null, manager_approval_notes=null, approved_amount=0, payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end where id=target_earning_id;

  first_request_id:=private.open_next_comp_earning_approval(target_earning_id,actor);
  if first_request_id is null then raise exception 'No approval request could be created for this earning.' using errcode='22023'; end if;

  insert into public.app_access_audit_events(actor_user_id,target_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(actor,actor,'admin_test_comp_earning_submitted','System Administrator submitted an employee earning through employee test mode.',jsonb_build_object('employee_verification_status',earning_row.employee_verification_status,'manager_approval_status',earning_row.manager_approval_status,'approved_amount',earning_row.approved_amount,'payment_status',earning_row.payment_status),jsonb_build_object('earning_id',target_earning_id,'employee_id',earning_row.employee_id,'employee_verification_status','verified','approval_request_id',first_request_id,'effective_earning_eligibility_date',effective_earning_eligibility_date,'test_mode',true,'acted_as_system_admin',true),earning_row.employee_id);

  return jsonb_build_object('status','submitted','earning_id',target_earning_id,'employee_id',earning_row.employee_id,'approval_request_id',first_request_id,'test_mode',true);
end;
$function$;
revoke all on function public.admin_test_submit_comp_earning_for_approval(uuid,text) from public,anon;
grant execute on function public.admin_test_submit_comp_earning_for_approval(uuid,text) to authenticated;