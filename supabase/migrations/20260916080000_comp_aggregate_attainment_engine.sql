-- Plan Builder V2 aggregate / attainment engine.
-- This migration is intentionally configuration-driven: an aggregate Earning Type
-- stores its source component codes in rule_configuration.aggregate.

create or replace function public.evaluate_compensation_rule(
  selected_calculation_type text,
  selected_rule_configuration jsonb,
  selected_source_amount numeric default null,
  selected_contract_term_years numeric default null,
  selected_unit_count numeric default null,
  selected_measurement_date date default current_date
)
returns jsonb
language plpgsql
immutable
set search_path to ''
as $function$
declare
  config jsonb := coalesce(selected_rule_configuration, '{}'::jsonb);
  resolved_rate numeric;
  resolved_fixed_amount numeric;
  calculated_amount numeric;
  matched_tier jsonb;
  matched_rate_history jsonb;
  calculation_status text := 'ready';
  calculation_explanation text;
  threshold_amount numeric;
  bonus_amount numeric;
  comparison_key text;
  threshold_met boolean;
  milestone jsonb;
  milestone_total numeric := 0;
begin
  if nullif(trim(coalesce(selected_calculation_type, '')), '') is null then
    return jsonb_build_object('status','unsupported','reason','calculation_type_required');
  end if;

  if selected_calculation_type = 'percentage' then
    if jsonb_typeof(config->'rate_history') = 'array' then
      select rate_item into matched_rate_history
      from jsonb_array_elements(config->'rate_history') rate_item
      where selected_measurement_date >= coalesce(nullif(rate_item->>'effective_start_date','')::date,'-infinity'::date)
        and selected_measurement_date <= coalesce(nullif(rate_item->>'effective_end_date','')::date,'infinity'::date)
      order by coalesce(nullif(rate_item->>'effective_start_date','')::date,'-infinity'::date) desc
      limit 1;
      if matched_rate_history is not null then resolved_rate := nullif(matched_rate_history->>'rate','')::numeric; end if;
    else
      resolved_rate := nullif(config->>'rate','')::numeric;
    end if;
    if selected_source_amount is null then calculation_status:='missing_input'; calculation_explanation:='Source amount is required.';
    elsif resolved_rate is null then calculation_status:='configuration_error'; calculation_explanation:='No applicable percentage rate was configured.';
    else calculated_amount:=round(selected_source_amount*resolved_rate,2); calculation_explanation:=selected_source_amount::text||' × '||resolved_rate::text; end if;

  elsif selected_calculation_type = 'tiered_percentage' then
    if selected_source_amount is null then calculation_status:='missing_input'; calculation_explanation:='Source amount is required.';
    elsif selected_contract_term_years is null then calculation_status:='missing_input'; calculation_explanation:='Contract term is required for a tiered percentage.';
    else
      select tier into matched_tier from jsonb_array_elements(coalesce(config->'tiers','[]'::jsonb)) tier
      where selected_contract_term_years >= coalesce(nullif(tier->>'minimum_contract_years','')::numeric,0)
        and (nullif(tier->>'maximum_contract_years','') is null or selected_contract_term_years <= (tier->>'maximum_contract_years')::numeric)
      order by coalesce(nullif(tier->>'minimum_contract_years','')::numeric,0) desc limit 1;
      resolved_rate:=nullif(matched_tier->>'rate','')::numeric;
      if matched_tier is null or resolved_rate is null then calculation_status:='configuration_error'; calculation_explanation:='No percentage tier matches the contract term.';
      else calculated_amount:=round(selected_source_amount*resolved_rate,2); calculation_explanation:=selected_source_amount::text||' × '||resolved_rate::text||' for '||selected_contract_term_years::text||' contract years'; end if;
    end if;

  elsif selected_calculation_type = 'fixed_amount' then
    resolved_fixed_amount:=coalesce(nullif(config->>'amount','')::numeric,nullif(config->>'fixed_amount','')::numeric);
    if resolved_fixed_amount is null then calculation_status:='configuration_error'; calculation_explanation:='Fixed amount is not configured.';
    else calculated_amount:=round(resolved_fixed_amount,2); calculation_explanation:='Fixed amount '||resolved_fixed_amount::text; end if;

  elsif selected_calculation_type = 'tiered_fixed_amount' then
    if selected_contract_term_years is null then calculation_status:='missing_input'; calculation_explanation:='Contract term is required for a tiered fixed amount.';
    else
      select tier into matched_tier from jsonb_array_elements(coalesce(config->'tiers','[]'::jsonb)) tier
      where selected_contract_term_years >= coalesce(nullif(tier->>'minimum_contract_years','')::numeric,0)
        and (nullif(tier->>'maximum_contract_years','') is null or selected_contract_term_years <= (tier->>'maximum_contract_years')::numeric)
      order by coalesce(nullif(tier->>'minimum_contract_years','')::numeric,0) desc limit 1;
      resolved_fixed_amount:=coalesce(nullif(matched_tier->>'amount','')::numeric,nullif(matched_tier->>'fixed_amount','')::numeric);
      if matched_tier is null or resolved_fixed_amount is null then calculation_status:='configuration_error'; calculation_explanation:='No fixed-amount tier matches the contract term.';
      else calculated_amount:=round(resolved_fixed_amount,2); calculation_explanation:='Fixed amount '||resolved_fixed_amount::text||' for '||selected_contract_term_years::text||' contract years'; end if;
    end if;

  elsif selected_calculation_type = 'fixed_amount_per_unit' then
    resolved_fixed_amount:=coalesce(nullif(config->>'amount_per_unit','')::numeric,nullif(config->>'amount_per_completed_qdc','')::numeric);
    if selected_unit_count is null then calculation_status:='missing_input'; calculation_explanation:='Unit count is required.';
    elsif resolved_fixed_amount is null then calculation_status:='configuration_error'; calculation_explanation:='Amount per unit is not configured.';
    else calculated_amount:=round(selected_unit_count*resolved_fixed_amount,2); calculation_explanation:=selected_unit_count::text||' × '||resolved_fixed_amount::text; end if;

  elsif selected_calculation_type = 'threshold_bonus' then
    threshold_amount:=coalesce(nullif(config#>>'{aggregate,benchmark_amount}','')::numeric,nullif(config->>'threshold_amount','')::numeric);
    bonus_amount:=coalesce(nullif(config#>>'{aggregate,payout_amount}','')::numeric,nullif(config->>'bonus_amount','')::numeric);
    comparison_key:=coalesce(nullif(config#>>'{aggregate,comparison}',''),nullif(config->>'comparison',''),'greater_than_or_equal');
    if selected_source_amount is null then calculation_status:='missing_input'; calculation_explanation:='Aggregate attainment value is required.';
    elsif threshold_amount is null or bonus_amount is null then calculation_status:='configuration_error'; calculation_explanation:='Threshold and bonus amounts are required.';
    else
      threshold_met:=case comparison_key when 'greater_than' then selected_source_amount>threshold_amount when 'equal' then selected_source_amount=threshold_amount else selected_source_amount>=threshold_amount end;
      calculated_amount:=case when threshold_met then round(bonus_amount,2) else 0 end;
      calculation_explanation:=selected_source_amount::text||case comparison_key when 'greater_than' then ' > ' when 'equal' then ' = ' else ' >= ' end||threshold_amount::text||case when threshold_met then ' (threshold met)' else ' (threshold not met)' end;
    end if;

  elsif selected_calculation_type = 'milestone_bonus' then
    if selected_source_amount is null then calculation_status:='missing_input'; calculation_explanation:='Aggregate attainment value is required.';
    elsif jsonb_typeof(config->'milestones')<>'array' then calculation_status:='configuration_error'; calculation_explanation:='Milestones are not configured.';
    else
      for milestone in select * from jsonb_array_elements(config->'milestones') loop
        if selected_source_amount >= coalesce(nullif(milestone->>'threshold','')::numeric,0) then milestone_total:=milestone_total+coalesce(nullif(milestone->>'bonus','')::numeric,0); end if;
      end loop;
      calculated_amount:=round(milestone_total,2);
      calculation_explanation:='Milestone attainment at '||selected_source_amount::text||' produced '||milestone_total::text;
    end if;

  else
    calculation_status:='unsupported'; calculation_explanation:='Calculation type '||selected_calculation_type||' is not supported by the evaluator.';
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'status',calculation_status,'calculation_type',selected_calculation_type,'calculated_amount',calculated_amount,
    'source_amount',selected_source_amount,'unit_count',selected_unit_count,'contract_term_years',selected_contract_term_years,
    'resolved_rate',resolved_rate,'resolved_fixed_amount',resolved_fixed_amount,'matched_tier',matched_tier,
    'matched_rate_history',matched_rate_history,'threshold_amount',threshold_amount,'threshold_met',threshold_met,
    'measurement_date',selected_measurement_date,'explanation',calculation_explanation
  ));
end;
$function$;

create or replace function public.preview_comp_component_aggregate(
  target_component_id uuid,
  selected_measurement_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  access jsonb;
  component_row record;
  aggregate_config jsonb;
  source_codes jsonb;
  period_key text;
  period_start date;
  period_end date;
  baseline_amount numeric;
  benchmark_amount numeric;
  rows_json jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not ((coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') or (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit')) then
    raise exception 'Not authorized to preview compensation aggregates' using errcode='42501';
  end if;

  select c.id,c.plan_version_id,c.name,c.component_code,c.calculation_type,c.measurement_period,c.rule_configuration,
         pv.status::text as version_status,pv.effective_start_date,pv.effective_end_date
  into component_row
  from public.comp_plan_components c join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where c.id=target_component_id;
  if component_row.id is null then raise exception 'Earning Type not found' using errcode='P0002'; end if;

  aggregate_config:=coalesce(component_row.rule_configuration->'aggregate','{}'::jsonb);
  source_codes:=coalesce(aggregate_config->'source_component_codes','[]'::jsonb);
  period_key:=coalesce(nullif(aggregate_config->>'period',''),nullif(component_row.measurement_period,''),'annual');
  baseline_amount:=coalesce(nullif(aggregate_config->>'baseline_amount','')::numeric,0);
  benchmark_amount:=coalesce(nullif(aggregate_config->>'benchmark_amount','')::numeric,nullif(component_row.rule_configuration->>'threshold_amount','')::numeric);

  if period_key='monthly' then
    period_start:=date_trunc('month',selected_measurement_date)::date;
    period_end:=(date_trunc('month',selected_measurement_date)+interval '1 month-1 day')::date;
  elsif period_key='quarterly' then
    period_start:=date_trunc('quarter',selected_measurement_date)::date;
    period_end:=(date_trunc('quarter',selected_measurement_date)+interval '3 months-1 day')::date;
  else
    period_key:='annual';
    period_start:=date_trunc('year',selected_measurement_date)::date;
    period_end:=(date_trunc('year',selected_measurement_date)+interval '1 year-1 day')::date;
  end if;

  with assigned as (
    select da.employee_id,e.full_name
    from public.comp_plan_draft_assignments da join public.employees e on e.id=da.employee_id
    where component_row.version_status='draft' and da.plan_version_id=component_row.plan_version_id
    union all
    select a.employee_id,e.full_name
    from public.employee_plan_assignments a join public.employees e on e.id=a.employee_id
    where component_row.version_status<>'draft' and a.plan_version_id=component_row.plan_version_id
      and selected_measurement_date between a.effective_start_date and coalesce(a.effective_end_date,'infinity'::date)
  ), source_components as (
    select c.id,c.component_code,c.name,c.measurement_source
    from public.comp_plan_components c
    where c.plan_version_id=component_row.plan_version_id and c.is_active and c.id<>target_component_id
      and (jsonb_array_length(source_codes)=0 or source_codes ? c.component_code)
  ), raw_matches as (
    select a.employee_id,a.full_name,sc.id as source_component_id,sc.component_code,sc.name as source_component_name,
           d.hubspot_deal_id,d.deal_name,d.close_date,
           case sc.measurement_source
             when 'average_arr' then d.average_arr
             when 'first_year_arr' then d.first_year_arr
             when 'one_time_fee' then d.one_time_fee
             when 'total_contract_value' then d.total_contract_value
             else d.amount
           end as source_amount,
           private.resolve_comp_user_attribution(a.employee_id,sc.id,d.hubspot_deal_id,'earning',null) as attribution
    from assigned a
    join source_components sc on true
    join public.comp_component_deal_rules dr on dr.plan_component_id=sc.id and dr.is_active and dr.calculation_action='include' and dr.marks_earned
    join public.hubspot_deals d on d.hubspot_pipeline_id=dr.hubspot_pipeline_id and d.hubspot_stage_id=dr.hubspot_stage_id and d.hubspot_deal_type=dr.hubspot_deal_type
    where d.close_date between greatest(period_start,component_row.effective_start_date,coalesce(dr.effective_start_date,period_start))
      and least(period_end,coalesce(component_row.effective_end_date,'infinity'::date),coalesce(dr.effective_end_date,'infinity'::date))
  ), deduped as (
    select distinct on(employee_id,source_component_id,hubspot_deal_id)
      employee_id,full_name,source_component_id,component_code,source_component_name,hubspot_deal_id,deal_name,close_date,source_amount
    from raw_matches
    where coalesce((attribution->>'matched')::boolean,false)=true
    order by employee_id,source_component_id,hubspot_deal_id,close_date desc
  ), totals as (
    select a.employee_id,a.full_name,
           coalesce(sum(d.source_amount),0) as qualifying_total,
           count(d.hubspot_deal_id) as qualifying_record_count
    from assigned a left join deduped d on d.employee_id=a.employee_id
    group by a.employee_id,a.full_name
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'employee_id',t.employee_id,'employee_name',t.full_name,'period_start',period_start,'period_end',period_end,
      'qualifying_total',t.qualifying_total,'baseline_amount',baseline_amount,
      'attainment_value',t.qualifying_total+baseline_amount,'benchmark_amount',benchmark_amount,
      'attainment_percent',case when benchmark_amount is null or benchmark_amount=0 then null else round(((t.qualifying_total+baseline_amount)/benchmark_amount)*100,2) end,
      'qualifying_record_count',t.qualifying_record_count,
      'calculation',public.evaluate_compensation_rule(component_row.calculation_type,component_row.rule_configuration,t.qualifying_total+baseline_amount,null,null,selected_measurement_date)
    ) order by t.full_name),'[]'::jsonb)
  into rows_json from totals t;

  return jsonb_build_object(
    'component_id',component_row.id,'component_name',component_row.name,'component_code',component_row.component_code,
    'plan_version_id',component_row.plan_version_id,'plan_status',component_row.version_status,
    'period',period_key,'period_start',period_start,'period_end',period_end,'measurement_date',selected_measurement_date,
    'source_component_codes',source_codes,'baseline_amount',baseline_amount,'benchmark_amount',benchmark_amount,
    'rows',rows_json
  );
end;
$function$;

grant execute on function public.preview_comp_component_aggregate(uuid,date) to authenticated;
