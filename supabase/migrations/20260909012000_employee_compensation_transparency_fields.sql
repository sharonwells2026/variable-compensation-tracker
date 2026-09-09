create or replace function public.get_compensation_employee_data(target_employee_id uuid default null::uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  current_employee_id uuid := private.current_employee_id();
  resolved_employee_id uuid := coalesce(target_employee_id,current_employee_id);
  result jsonb;
begin
  if resolved_employee_id is null then raise exception 'Employee access is not permitted.' using errcode='42501'; end if;
  if resolved_employee_id=current_employee_id then
    if not private.can_access_employee(resolved_employee_id,'earnings.view') then raise exception 'Employee access is not permitted.' using errcode='42501'; end if;
  elsif not private.can_act_as_employee(resolved_employee_id) then
    raise exception 'Act-as access is not permitted for this employee.' using errcode='42501';
  end if;

  select jsonb_build_object(
    'employee',jsonb_build_object('id',employee.id,'full_name',employee.full_name,'email',employee.email,'job_title',employee.job_title,'department',employee.department,'is_active',employee.is_active),
    'plans',coalesce((select jsonb_agg(jsonb_build_object('assignment_id',assignment.id,'plan_version_id',version.id,'plan_name',plan.name,'version_number',version.version_number,'status',version.status,'effective_start_date',assignment.effective_start_date,'effective_end_date',assignment.effective_end_date,'acknowledged',exists(select 1 from public.plan_version_acknowledgments acknowledgment where acknowledgment.plan_version_id=version.id and acknowledgment.employee_id=resolved_employee_id)) order by assignment.effective_start_date desc) from public.employee_plan_assignments assignment join public.comp_plan_versions version on version.id=assignment.plan_version_id join public.comp_plans plan on plan.id=version.comp_plan_id where assignment.employee_id=resolved_employee_id),'[]'::jsonb),
    'components',coalesce((select jsonb_agg(jsonb_build_object('component_id',component.id,'component_name',component.name,'component_code',component.component_code,'description',component.description,'calculation_type',component.calculation_type,'measurement_source',component.measurement_source,'measurement_period',component.measurement_period,'rule_configuration',component.rule_configuration,'earned_amount',coalesce(summary.earned_amount,0),'eligible_amount',coalesce(summary.eligible_amount,0),'paid_amount',coalesce(summary.paid_amount,0),'earning_count',coalesce(summary.earning_count,0)) order by component.calculation_order) from public.employee_plan_assignments assignment join public.comp_plan_components component on component.plan_version_id=assignment.plan_version_id left join lateral (select sum(earning.earned_amount) filter(where earning.is_current) earned_amount,sum(earning.eligible_amount) filter(where earning.is_current) eligible_amount,sum(earning.paid_amount) filter(where earning.is_current) paid_amount,count(*) filter(where earning.is_current) earning_count from public.comp_earnings earning where earning.employee_id=resolved_employee_id and earning.plan_component_id=component.id) summary on true where assignment.employee_id=resolved_employee_id and component.is_active=true),'[]'::jsonb),
    'earnings',coalesce((select jsonb_agg(jsonb_build_object(
      'earning_id',earning.id,'plan_component_id',earning.plan_component_id,'component_name',component.name,'component_code',component.component_code,'earning_name',earning.earning_name,'earning_description',earning.earning_description,'source_external_id',earning.source_external_id,'source_url',earning.source_url,'earned_date',earning.earned_date,'earned_amount',earning.earned_amount,'eligibility_status',earning.eligibility_status,'eligibility_condition_type',earning.eligibility_condition_type,'eligibility_condition_description',earning.eligibility_condition_description,'eligibility_evidence',earning.eligibility_evidence,'eligible_date',earning.eligible_date,'eligible_amount',earning.eligible_amount,'employee_verification_status',earning.employee_verification_status,'manager_approval_status',earning.manager_approval_status,'payment_status',earning.payment_status,'paid_amount',earning.paid_amount,'expected_pay_period_start',earning.expected_pay_period_start,'expected_pay_period_end',earning.expected_pay_period_end,'expected_pay_period_label',earning.expected_pay_period_label,'source_snapshot',earning.source_snapshot,
      'current_approval_level',pending.approval_level,'current_approval_order',pending.approval_order,'current_approver_name',pending.approver_name,'current_approval_requested_at',pending.requested_at
    ) order by earning.earned_date desc,earning.created_at desc)
    from public.comp_earnings earning
    left join public.comp_plan_components component on component.id=earning.plan_component_id
    left join lateral (
      select r.approval_level,r.approval_order,r.requested_at,coalesce(p.full_name,pe.full_name,'Approver') as approver_name
      from public.approval_requests r
      left join public.profiles p on p.id=r.requested_from
      left join public.employees pe on pe.id=p.employee_id
      where r.comp_earning_id=earning.id and r.status='pending'::public.approval_status
      order by r.approval_order desc,r.requested_at desc limit 1
    ) pending on true
    where earning.employee_id=resolved_employee_id and earning.is_current=true),'[]'::jsonb)
  ) into result from public.employees employee where employee.id=resolved_employee_id;
  return result;
end;
$function$;