create or replace function public.unapprove_comp_earning(target_earning_id uuid, unapproval_reason text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := auth.uid();
  earning_row public.comp_earnings%rowtype;
  request_row public.approval_requests%rowtype;
  normalized_reason text := nullif(trim(coalesce(unapproval_reason,'')),'');
begin
  if actor is null or not private.has_permission('earnings.approve') then
    raise exception 'You are not permitted to reverse compensation approvals.' using errcode='42501';
  end if;
  if normalized_reason is null then
    raise exception 'A reason is required when reversing an approval.' using errcode='22023';
  end if;
  select * into earning_row from public.comp_earnings where id=target_earning_id for update;
  if not found then raise exception 'Compensation earning not found.' using errcode='P0002'; end if;
  if coalesce(earning_row.paid_amount,0)>0 or earning_row.payment_status='paid'::public.payment_status then
    raise exception 'A paid earning cannot be unapproved. Use the correction process instead.' using errcode='23514';
  end if;
  if coalesce(earning_row.approved_amount,0)<=0 then
    raise exception 'This earning is not fully approved.' using errcode='22023';
  end if;
  select * into request_row from public.approval_requests where comp_earning_id=target_earning_id and status='approved'::public.approval_status order by approval_order desc,completed_at desc nulls last limit 1 for update;
  if not found then raise exception 'No completed approval step could be reopened.' using errcode='P0002'; end if;
  update public.approval_requests set status='pending'::public.approval_status,completed_at=null,notes=concat_ws(E'\n',nullif(notes,''),'Approval reversed: '||normalized_reason) where id=request_row.id;
  delete from public.comp_earning_handoff_tasks where comp_earning_id=target_earning_id and status in ('pending','completed');
  update public.comp_earnings
  set approved_amount=0,payment_status='not_payable'::public.payment_status,expected_payment_date=null,expected_pay_period_label=null,expected_pay_period_start=null,expected_pay_period_end=null,finance_accepted_by=null,finance_accepted_at=null,
      manager_approval_status=case when lower(request_row.approval_level) in ('manager','manager_approval','compensation_admin_review') then 'pending'::public.approval_status else manager_approval_status end,
      manager_approved_by=case when lower(request_row.approval_level) in ('manager','manager_approval','compensation_admin_review') then null else manager_approved_by end,
      manager_approved_at=case when lower(request_row.approval_level) in ('manager','manager_approval','compensation_admin_review') then null else manager_approved_at end,
      executive_approval_status=case when lower(request_row.approval_level) in ('executive','executive_approval') then 'pending'::public.approval_status else executive_approval_status end,
      executive_approved_by=case when lower(request_row.approval_level) in ('executive','executive_approval') then null else executive_approved_by end,
      executive_approved_at=case when lower(request_row.approval_level) in ('executive','executive_approval') then null else executive_approved_at end
  where id=target_earning_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(actor,'comp_earning_approval_reversed',normalized_reason,jsonb_build_object('earning_id',target_earning_id,'approval_request_id',request_row.id,'approved_amount',earning_row.approved_amount,'payment_status',earning_row.payment_status),jsonb_build_object('earning_id',target_earning_id,'approval_request_id',request_row.id,'approval_status','pending','approved_amount',0,'payment_status','not_payable'),earning_row.employee_id);
  return jsonb_build_object('status','unapproved','earning_id',target_earning_id,'reopened_approval_request_id',request_row.id);
end;
$function$;
revoke all on function public.unapprove_comp_earning(uuid,text) from public;
grant execute on function public.unapprove_comp_earning(uuid,text) to authenticated;

create or replace function public.approve_compensation_plan_version(selected_plan_version_id uuid, approval_notes text default null::text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare readiness jsonb; component_count integer; approval_step_count integer;
begin
  if not private.has_permission('plans.approve') then raise exception 'Plan approval is not permitted.' using errcode='42501'; end if;
  if not exists (select 1 from public.comp_plan_versions where id=selected_plan_version_id and status='draft') then raise exception 'Only draft versions can be approved.' using errcode='22023'; end if;
  select count(*) into approval_step_count from public.comp_plan_approval_steps where plan_version_id=selected_plan_version_id and is_required=true;
  if approval_step_count=0 then raise exception 'Configure at least one required approval step on this plan before approving it.' using errcode='23514'; end if;
  readiness:=public.validate_compensation_plan_version_readiness(selected_plan_version_id);
  if coalesce((readiness->>'ready')::boolean,false) is not true then raise exception 'Plan version is not ready for approval: %',readiness->'blockers' using errcode='23514'; end if;
  component_count:=coalesce((readiness->>'component_count')::integer,0);
  update public.comp_plan_versions set approved_by=auth.uid(),approved_at=pg_catalog.now(),notes=case when nullif(trim(coalesce(approval_notes,'')),'') is null then notes when notes is null then trim(approval_notes) else notes||E'\nApproval: '||trim(approval_notes) end,updated_at=pg_catalog.now() where id=selected_plan_version_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state) values(auth.uid(),'comp_plan_version_approved','A readiness-validated draft compensation plan version was approved for activation.',jsonb_build_object('plan_version_id',selected_plan_version_id,'component_count',component_count,'approval_step_count',approval_step_count,'readiness',readiness));
  return jsonb_build_object('status','approved','plan_version_id',selected_plan_version_id,'component_count',component_count,'approval_step_count',approval_step_count,'readiness',readiness);
end;
$function$;
revoke all on function public.approve_compensation_plan_version(uuid,text) from public;
grant execute on function public.approve_compensation_plan_version(uuid,text) to authenticated;

create or replace function public.validate_compensation_plan_version_readiness(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare base jsonb; approval_step_count integer;
begin
  base:=public.validate_compensation_plan_version_readiness_core(selected_plan_version_id);
  select count(*) into approval_step_count from public.comp_plan_approval_steps where plan_version_id=selected_plan_version_id and is_required=true;
  if approval_step_count=0 then
    base:=jsonb_set(base,'{blockers}',coalesce(base->'blockers','[]'::jsonb)||jsonb_build_array(jsonb_build_object('code','missing_approval_steps','section','approvals','message','Configure at least one required approval step for this plan.')));
    base:=jsonb_set(base,'{blocker_count}',to_jsonb(jsonb_array_length(base->'blockers')));
    base:=jsonb_set(base,'{ready}','false'::jsonb);
  end if;
  return base;
end;
$function$;
revoke all on function public.validate_compensation_plan_version_readiness(uuid) from public;
grant execute on function public.validate_compensation_plan_version_readiness(uuid) to authenticated;