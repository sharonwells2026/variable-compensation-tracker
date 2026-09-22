create or replace function private.compute_comp_component_attainment(target_component_id uuid,target_employee_id uuid,target_year integer)
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  c public.comp_plan_components%rowtype;
  cfg jsonb;
  agg jsonb;
  component_codes text[];
  source_total numeric:=0;
  baseline numeric:=0;
  total_value numeric:=0;
  threshold_value numeric:=0;
  bonus_value numeric:=0;
  attainment numeric:=0;
  met boolean:=false;
  comparison_key text;
  plan_version uuid;
begin
  select * into c from public.comp_plan_components where id=target_component_id;
  if c.id is null then raise exception 'Earning Type not found'; end if;
  cfg:=coalesce(c.rule_configuration,'{}'::jsonb);
  agg:=coalesce(cfg->'aggregate','{}'::jsonb);
  plan_version:=c.plan_version_id;
  select coalesce(array_agg(value),array[]::text[]) into component_codes
  from jsonb_array_elements_text(coalesce(agg->'source_component_codes',cfg->'aggregate_component_codes','[]'::jsonb));
  baseline:=coalesce(nullif(agg->>'baseline_amount','')::numeric,nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
  threshold_value:=coalesce(nullif(agg->>'benchmark_amount','')::numeric,nullif(cfg->>'threshold_amount','')::numeric,0);
  bonus_value:=coalesce(nullif(agg->>'payout_amount','')::numeric,nullif(cfg->>'bonus_amount','')::numeric,0);
  comparison_key:=coalesce(nullif(agg->>'comparison',''),nullif(cfg->>'comparison',''),'greater_than');
  select coalesce(sum(x.source_amount),0) into source_total
  from (
    select candidate.plan_component_id,candidate.hubspot_deal_id,max(candidate.source_amount) source_amount
    from public.comp_deal_earning_candidates_v2 candidate
    join public.comp_plan_components source_component on source_component.id=candidate.plan_component_id
    where candidate.employee_id=target_employee_id
      and candidate.plan_version_id=plan_version
      and extract(year from candidate.earned_date)::int=target_year
      and (cardinality(component_codes)=0 or source_component.component_code=any(component_codes))
      and candidate.calculation_status='ready'
      and candidate.source_amount is not null
    group by candidate.plan_component_id,candidate.hubspot_deal_id
  ) x;
  total_value:=source_total+baseline;
  attainment:=case when threshold_value>0 then round((total_value/threshold_value)*100,2) else 0 end;
  met:=case comparison_key when 'greater_than_or_equal' then total_value>=threshold_value when 'equal' then total_value=threshold_value else total_value>threshold_value end;
  return jsonb_build_object('component_id',target_component_id,'employee_id',target_employee_id,'year',target_year,'source_component_codes',to_jsonb(component_codes),'source_total',source_total,'baseline_amount',baseline,'measurement_value',total_value,'threshold',threshold_value,'attainment_percent',attainment,'threshold_met',met,'bonus_amount',bonus_value,'comparison',comparison_key);
end;
$$;

create or replace function public.validate_compensation_plan_version_readiness(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare base jsonb; approval_step_count integer; c record; blockers jsonb; warnings jsonb; agg jsonb; source_codes jsonb;
begin
  base:=public.validate_compensation_plan_version_readiness_core(selected_plan_version_id);
  select coalesce(jsonb_agg(b),'[]'::jsonb) into blockers
  from jsonb_array_elements(coalesce(base->'blockers','[]'::jsonb)) b
  where not (b->>'code' in ('missing_earned_rule','earned_rule_needs_preview') and exists(select 1 from public.comp_plan_components pc where pc.id=nullif(b->>'component_id','')::uuid and pc.measurement_source='book_of_business' and pc.calculation_type='threshold_bonus'));
  warnings:=coalesce(base->'warnings','[]'::jsonb);
  select count(*) into approval_step_count from public.comp_plan_approval_steps where plan_version_id=selected_plan_version_id and is_required=true;
  if approval_step_count=0 then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_approval_steps','section','approvals','message','Configure at least one required approval step for this plan.')); end if;
  for c in select id,name,measurement_source,calculation_type,rule_configuration from public.comp_plan_components where plan_version_id=selected_plan_version_id and is_active=true order by calculation_order,name loop
    if c.measurement_source in ('amount','average_arr','first_year_arr','one_time_fee','total_contract_value') then
      if not exists(select 1 from public.comp_component_deal_rules dr where dr.plan_component_id=c.id and dr.is_active=true and dr.marks_earned=true) then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_deal_source_rules','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs both Deal Type and Deal Stage in its Earned conditions before it can generate earnings.',c.name))); end if;
      if not exists(select 1 from public.comp_user_attribution_rules ar where ar.plan_component_id=c.id and ar.attribution_purpose='earning' and ar.is_active=true) then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_credit_attribution','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs a HubSpot owner/CEM field so the system knows which employee gets credit.',c.name))); end if;
    elsif c.measurement_source='book_of_business' and c.calculation_type='threshold_bonus' then
      agg:=coalesce(c.rule_configuration->'aggregate','{}'::jsonb);
      source_codes:=coalesce(agg->'source_component_codes',c.rule_configuration->'aggregate_component_codes','[]'::jsonb);
      if jsonb_array_length(source_codes)=0 then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_aggregate_sources','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs the Earning Types that count toward its running total.',c.name))); end if;
      if coalesce(nullif(agg->>'benchmark_amount',''),nullif(c.rule_configuration->>'threshold_amount','')) is null then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_quota','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a quota or benchmark threshold.',c.name))); end if;
      if coalesce(nullif(agg->>'payout_amount',''),nullif(c.rule_configuration->>'bonus_amount','')) is null then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_threshold_bonus','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs the bonus paid when the benchmark is exceeded.',c.name))); end if;
      warnings:=warnings||jsonb_build_array(jsonb_build_object('code','aggregate_year_end','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s tracks attainment during the year and creates the bonus earning at year end if the benchmark is exceeded.',c.name)));
    end if;
  end loop;
  base:=jsonb_set(base,'{blockers}',blockers); base:=jsonb_set(base,'{warnings}',warnings); base:=jsonb_set(base,'{blocker_count}',to_jsonb(jsonb_array_length(blockers))); base:=jsonb_set(base,'{warning_count}',to_jsonb(jsonb_array_length(warnings))); base:=jsonb_set(base,'{ready}',to_jsonb(jsonb_array_length(blockers)=0)); return base;
end;
$$;