create or replace function public.preview_comp_credit_correction_replacement(target_candidate_key text, target_employee_id uuid, target_credit_percentage numeric)
returns jsonb
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  c public.comp_deal_earning_candidates_v2%rowtype;
  compatibility jsonb;
  target_assignment_id uuid;
  target_component_id uuid;
  target_component public.comp_plan_components%rowtype;
  target_period public.comp_periods%rowtype;
  existing_calc public.comp_calculations%rowtype;
  source_amount numeric;
  credited_basis numeric;
  corrected_earned numeric;
  rate numeric;
  calc_type text;
  target_name text;
  workflow_required boolean:=true;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('earnings.edit') or private.has_permission('earnings.override')) then raise exception 'Permission denied.' using errcode='42501'; end if;
  if target_credit_percentage is null or target_credit_percentage<=0 or target_credit_percentage>100 then raise exception 'Credit percentage must be greater than 0 and no more than 100.' using errcode='22023'; end if;
  select * into c from public.comp_deal_earning_candidates_v2 where candidate_key=target_candidate_key;
  if not found then raise exception 'Compensation candidate not found.' using errcode='P0002'; end if;
  compatibility:=public.validate_comp_credit_correction_target(target_candidate_key,target_employee_id);
  if not coalesce((compatibility->>'valid')::boolean,false) then
    return jsonb_build_object('valid',false,'status',compatibility->>'status','validation',compatibility);
  end if;
  target_assignment_id:=(compatibility->>'target_plan_assignment_id')::uuid;
  target_component_id:=(compatibility->>'target_plan_component_id')::uuid;
  select * into target_component from public.comp_plan_components where id=target_component_id;
  select full_name into target_name from public.employees where id=target_employee_id;
  select * into target_period from public.comp_periods where c.earned_date between start_date and end_date order by start_date desc limit 1;
  if not found then
    return jsonb_build_object('valid',false,'status','comp_period_missing','message','No compensation period exists for the earning date.','earned_date',c.earned_date,'validation',compatibility);
  end if;
  select * into existing_calc from public.comp_calculations where employee_id=target_employee_id and comp_period_id=target_period.id order by calculation_version desc limit 1;
  source_amount:=coalesce(c.source_amount,0);
  credited_basis:=round(source_amount*(target_credit_percentage/100.0),2);
  calc_type:=target_component.calculation_type;
  if calc_type='percentage' then
    rate:=nullif(target_component.rule_configuration->>'rate','')::numeric;
    if rate is null then return jsonb_build_object('valid',false,'status','component_rule_incomplete','message','The target percentage component has no rate configured.','target_plan_component_id',target_component.id); end if;
    corrected_earned:=round(credited_basis*rate,2);
  elsif calc_type in ('fixed','fixed_amount') then
    corrected_earned:=coalesce(nullif(target_component.rule_configuration->>'amount','')::numeric,nullif(target_component.rule_configuration->>'fixed_amount','')::numeric,0);
    rate:=null;
  else
    return jsonb_build_object('valid',false,'status','unsupported_calculation_type','message','Replacement preview does not yet support this calculation type.','calculation_type',calc_type,'target_plan_component_id',target_component.id);
  end if;
  return jsonb_build_object(
    'valid',true,
    'status','ready_for_replacement_preview',
    'candidate_key',c.candidate_key,
    'hubspot_deal_id',c.hubspot_deal_id,
    'deal_name',c.deal_name,
    'company_name',c.company_name,
    'earned_date',c.earned_date,
    'source_amount',source_amount,
    'original_employee_id',c.employee_id,
    'original_employee_name',c.full_name,
    'original_credit_percentage',c.credit_percentage,
    'original_earned_amount',c.calculated_earning_amount,
    'target_employee_id',target_employee_id,
    'target_employee_name',target_name,
    'target_credit_percentage',target_credit_percentage,
    'credited_basis',credited_basis,
    'target_plan_assignment_id',target_assignment_id,
    'target_plan_component_id',target_component_id,
    'target_component_name',target_component.name,
    'target_component_code',target_component.component_code,
    'calculation_type',calc_type,
    'rate',rate,
    'corrected_earned_amount',corrected_earned,
    'comp_period_id',target_period.id,
    'comp_period_name',target_period.name,
    'comp_period_status',target_period.status,
    'existing_calculation_id',case when existing_calc.id is null then null else existing_calc.id end,
    'existing_calculation_version',case when existing_calc.id is null then null else existing_calc.calculation_version end,
    'calculation_container_action',case when existing_calc.id is null then 'create_for_target_employee_period' else 'create_next_version_for_target_employee_period' end,
    'workflow_restart_required',workflow_required,
    'validation',compatibility
  );
end;
$$;
revoke all on function public.preview_comp_credit_correction_replacement(text,uuid,numeric) from public,anon;
grant execute on function public.preview_comp_credit_correction_replacement(text,uuid,numeric) to authenticated;