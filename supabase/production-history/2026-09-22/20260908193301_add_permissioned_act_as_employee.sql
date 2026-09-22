insert into private.app_permissions(permission_key,category,display_name,description)
values('users.act_as','Users','Act as another employee','Enter another employee''s workspace and perform explicitly supported on-behalf/test actions while preserving the real authenticated actor in audit history.')
on conflict(permission_key) do update set category=excluded.category,display_name=excluded.display_name,description=excluded.description;

insert into private.role_permissions(role_key,permission_key,allowed)
values('system_administrator','users.act_as',true)
on conflict(role_key,permission_key) do update set allowed=true,updated_at=now();

create or replace function public.get_employee_administration_data()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $function$
declare result jsonb;
begin
  if not (private.has_permission('users.manage') or private.has_permission('users.act_as')) then
    raise exception 'Employee access is not permitted.' using errcode='42501';
  end if;

  select jsonb_build_object('employees',coalesce(jsonb_agg(row_data order by row_data->>'full_name'),'[]'::jsonb)) into result
  from (
    select jsonb_build_object(
      'employee_id',e.id,'full_name',e.full_name,'email',e.email,'title',e.job_title,'department',e.department,'manager_name',mgr.full_name,'is_active',e.is_active,
      'profile_status',case when pr.id is null then 'not_provisioned' when pr.is_active then 'active' else 'inactive' end,
      'has_app_access',coalesce(pr.is_active,false),'draft_user_id',d.id,'draft_status',d.status,
      'draft_roles',coalesce((select jsonb_agg(r.role_key order by r.role_key) from private.draft_user_roles r where r.draft_user_id=d.id),'[]'::jsonb),
      'compensation_participant',flags.compensation_participant,'plan_name',cp.name,'plan_status',pv.status::text,
      'plan_effective_start_date',pa.effective_start_date,'plan_effective_end_date',pa.effective_end_date,'earnings_eligibility_date',pa.earnings_eligibility_date,
      'workflow_name',wv.workflow_name,'workflow_status',wv.status,
      'readiness',case when (pr.is_active or d.id is not null) and (not flags.compensation_participant or (pa.id is not null and pa.earnings_eligibility_date is not null and wv.id is not null)) then case when pr.is_active then 'ready' else 'preinvite_ready' end else 'needs_setup' end,
      'readiness_reasons',to_jsonb(array_remove(array[
        case when pr.id is null and d.id is not null then 'Application access is configured as a pre-invite draft.' when pr.id is null then 'Application access has not been provisioned.' when not pr.is_active then 'Application access is inactive.' end,
        case when flags.compensation_participant and pa.id is null then 'No compensation plan is assigned for today.' end,
        case when flags.compensation_participant and pa.id is not null and pa.earnings_eligibility_date is null then 'Earnings eligibility date is missing.' end,
        case when flags.compensation_participant and wv.id is null then 'No active approval workflow is configured for today.' end
      ],null))
    ) row_data
    from public.employees e
    left join public.employees mgr on mgr.id=e.manager_id
    left join lateral (select p.* from public.profiles p where p.employee_id=e.id order by p.is_active desc,p.updated_at desc limit 1) pr on true
    left join lateral (select x.* from public.app_user_drafts x where x.employee_id=e.id and x.status<>'cancelled' order by x.updated_at desc limit 1) d on true
    left join lateral (select (exists(select 1 from public.employee_plan_assignments a0 where a0.employee_id=e.id) or exists(select 1 from private.draft_user_roles dr where dr.draft_user_id=d.id and dr.role_key='employee') or exists(select 1 from private.user_roles ur where ur.user_id=pr.id and ur.role_key='employee')) as compensation_participant) flags on true
    left join lateral (select a.* from public.employee_plan_assignments a where a.employee_id=e.id and a.effective_start_date<=current_date and (a.effective_end_date is null or a.effective_end_date>=current_date) order by a.effective_start_date desc limit 1) pa on true
    left join public.comp_plan_versions pv on pv.id=pa.plan_version_id
    left join public.comp_plans cp on cp.id=pv.comp_plan_id
    left join lateral (select v.* from public.employee_approval_workflow_versions v where v.employee_id=e.id and v.status='active' and v.effective_start_date<=current_date and (v.effective_end_date is null or v.effective_end_date>=current_date) order by v.effective_start_date desc limit 1) wv on true
    where e.is_active
  ) q;
  return coalesce(result,jsonb_build_object('employees','[]'::jsonb));
end;
$function$;

create or replace function public.admin_test_submit_comp_earning_for_approval(target_earning_id uuid, verification_notes text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare actor uuid:=auth.uid(); earning_row public.comp_earnings%rowtype; assignment_row public.employee_plan_assignments%rowtype; effective_earning_eligibility_date date; first_request_id uuid;
begin
  if actor is null or not private.has_permission('users.act_as') then raise exception 'Act-as-employee permission is required.' using errcode='42501'; end if;
  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
  if not earning_row.is_current then raise exception 'A superseded compensation earning cannot be submitted.' using errcode='22023'; end if;
  if earning_row.earned_date>current_date then raise exception 'A future forecast earning cannot be submitted.' using errcode='22023'; end if;
  if earning_row.eligibility_status<>'eligible'::public.eligibility_status or coalesce(earning_row.eligible_amount,0)<=0 then raise exception 'Only an eligible earning can be submitted in act-as-employee mode.' using errcode='22023'; end if;
  if earning_row.plan_assignment_id is null then raise exception 'The earning is not linked to a compensation plan assignment.' using errcode='22023'; end if;
  select * into assignment_row from public.employee_plan_assignments where id=earning_row.plan_assignment_id;
  if not found then raise exception 'The earning compensation plan assignment no longer exists.' using errcode='P0002'; end if;
  if assignment_row.employee_id<>earning_row.employee_id or earning_row.earned_date<assignment_row.effective_start_date or (assignment_row.effective_end_date is not null and earning_row.earned_date>assignment_row.effective_end_date) then raise exception 'The earning is not governed by its linked plan assignment on the earned date.' using errcode='22023'; end if;
  effective_earning_eligibility_date:=private.resolve_comp_earning_eligibility_date(earning_row.plan_assignment_id,earning_row.plan_component_id);
  if effective_earning_eligibility_date is null or earning_row.earned_date<effective_earning_eligibility_date then raise exception 'The earning is not eligible under its linked compensation plan assignment.' using errcode='22023'; end if;
  if earning_row.employee_verification_status='verified'::public.verification_status and exists(select 1 from public.approval_requests r where r.comp_earning_id=target_earning_id and r.status='pending'::public.approval_status) then raise exception 'This earning has already been submitted for approval.' using errcode='22023'; end if;
  if private.comp_earning_all_approvals_complete(target_earning_id) then raise exception 'This earning has already completed approval.' using errcode='22023'; end if;
  if not exists(select 1 from public.employee_approval_chains c where c.employee_id=earning_row.employee_id and c.is_required=true and earning_row.earned_date>=c.effective_start_date and (c.effective_end_date is null or earning_row.earned_date<=c.effective_end_date)) then raise exception 'No approval chain is configured for this employee on the earning date.' using errcode='22023'; end if;
  update public.comp_earnings set employee_verification_status='verified'::public.verification_status,employee_verified_at=now(),employee_verification_notes=nullif(trim(coalesce(verification_notes,'')),''),manager_approval_status='pending'::public.approval_status,manager_approved_by=null,manager_approved_at=null,manager_approval_notes=null,approved_amount=0,payment_status=case when payment_status in ('scheduled'::public.payment_status,'partially_paid'::public.payment_status,'paid'::public.payment_status,'held'::public.payment_status) then payment_status else 'not_payable'::public.payment_status end where id=target_earning_id;
  first_request_id:=private.open_next_comp_earning_approval(target_earning_id,actor);
  if first_request_id is null then raise exception 'No approval request could be created for this earning.' using errcode='22023'; end if;
  insert into public.app_access_audit_events(actor_user_id,target_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(actor,actor,'act_as_employee_comp_earning_submitted','Authorized user submitted an employee earning while acting as another employee.',jsonb_build_object('employee_verification_status',earning_row.employee_verification_status,'manager_approval_status',earning_row.manager_approval_status,'approved_amount',earning_row.approved_amount,'payment_status',earning_row.payment_status),jsonb_build_object('earning_id',target_earning_id,'employee_id',earning_row.employee_id,'employee_verification_status','verified','approval_request_id',first_request_id,'effective_earning_eligibility_date',effective_earning_eligibility_date,'act_as_employee',true,'actor_user_id',actor),earning_row.employee_id);
  return jsonb_build_object('status','submitted','earning_id',target_earning_id,'employee_id',earning_row.employee_id,'approval_request_id',first_request_id,'act_as_employee',true);
end;
$function$;

revoke all on function public.admin_test_submit_comp_earning_for_approval(uuid,text) from public,anon;
grant execute on function public.admin_test_submit_comp_earning_for_approval(uuid,text) to authenticated;