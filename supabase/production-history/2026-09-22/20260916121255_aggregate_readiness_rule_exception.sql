create or replace function public.validate_compensation_plan_version_readiness(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  base jsonb;
  approval_step_count integer;
  c record;
  blockers jsonb;
  warnings jsonb;
begin
  base:=public.validate_compensation_plan_version_readiness_core(selected_plan_version_id);
  select coalesce(jsonb_agg(b),'[]'::jsonb) into blockers
  from jsonb_array_elements(coalesce(base->'blockers','[]'::jsonb)) b
  where not (
    b->>'code' in ('missing_earned_rule','earned_rule_needs_preview')
    and exists(
      select 1 from public.comp_plan_components pc
      where pc.id=nullif(b->>'component_id','')::uuid
        and pc.measurement_source='book_of_business'
        and pc.calculation_type='threshold_bonus'
    )
  );
  warnings:=coalesce(base->'warnings','[]'::jsonb);
  select count(*) into approval_step_count from public.comp_plan_approval_steps where plan_version_id=selected_plan_version_id and is_required=true;
  if approval_step_count=0 then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_approval_steps','section','approvals','message','Configure at least one required approval step for this plan.')); end if;
  for c in select id,name,measurement_source,calculation_type,rule_configuration from public.comp_plan_components where plan_version_id=selected_plan_version_id and is_active=true order by calculation_order,name loop
    if c.measurement_source in ('amount','average_arr','first_year_arr','one_time_fee','total_contract_value') then
      if not exists(select 1 from public.comp_component_deal_rules dr where dr.plan_component_id=c.id and dr.is_active=true and dr.marks_earned=true) then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_deal_source_rules','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs both Deal Type and Deal Stage in its Earned conditions before it can generate earnings.',c.name))); end if;
      if not exists(select 1 from public.comp_user_attribution_rules ar where ar.plan_component_id=c.id and ar.attribution_purpose='earning' and ar.is_active=true) then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_credit_attribution','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs a HubSpot owner/CEM field so the system knows which employee gets credit.',c.name))); end if;
    elsif c.measurement_source='book_of_business' and c.calculation_type='threshold_bonus' then
      if jsonb_array_length(coalesce(c.rule_configuration->'aggregate_component_codes','[]'::jsonb))=0 then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_aggregate_sources','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs the Earning Types that count toward its running total.',c.name))); end if;
      if nullif(c.rule_configuration->>'threshold_amount','') is null then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_quota','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a quota or benchmark threshold.',c.name))); end if;
      if nullif(c.rule_configuration->>'bonus_amount','') is null then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_threshold_bonus','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs the bonus paid when the benchmark is exceeded.',c.name))); end if;
      warnings:=warnings||jsonb_build_array(jsonb_build_object('code','aggregate_year_end','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s tracks attainment during the year and creates the bonus earning at year end if the benchmark is exceeded.',c.name)));
    end if;
  end loop;
  base:=jsonb_set(base,'{blockers}',blockers);
  base:=jsonb_set(base,'{warnings}',warnings);
  base:=jsonb_set(base,'{blocker_count}',to_jsonb(jsonb_array_length(blockers)));
  base:=jsonb_set(base,'{warning_count}',to_jsonb(jsonb_array_length(warnings)));
  base:=jsonb_set(base,'{ready}',to_jsonb(jsonb_array_length(blockers)=0));
  return base;
end;
$$;