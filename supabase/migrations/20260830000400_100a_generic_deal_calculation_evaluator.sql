-- 100A - Generic Deal Calculation Evaluator
-- Applied manually to production and verified before source-control sync.

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
set search_path = ''
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
      if matched_rate_history is not null then
        resolved_rate := nullif(matched_rate_history->>'rate','')::numeric;
      end if;
    else
      resolved_rate := nullif(config->>'rate','')::numeric;
    end if;
    if selected_source_amount is null then
      calculation_status := 'missing_input'; calculation_explanation := 'Source amount is required.';
    elsif resolved_rate is null then
      calculation_status := 'configuration_error'; calculation_explanation := 'No applicable percentage rate was configured.';
    else
      calculated_amount := round(selected_source_amount * resolved_rate,2);
      calculation_explanation := selected_source_amount::text || ' × ' || resolved_rate::text;
    end if;

  elsif selected_calculation_type = 'tiered_percentage' then
    if selected_source_amount is null then
      calculation_status := 'missing_input'; calculation_explanation := 'Source amount is required.';
    elsif selected_contract_term_years is null then
      calculation_status := 'missing_input'; calculation_explanation := 'Contract term is required for a tiered percentage.';
    else
      select tier into matched_tier
      from jsonb_array_elements(coalesce(config->'tiers','[]'::jsonb)) tier
      where selected_contract_term_years >= coalesce(nullif(tier->>'minimum_contract_years','')::numeric,0)
        and (nullif(tier->>'maximum_contract_years','') is null or selected_contract_term_years <= (tier->>'maximum_contract_years')::numeric)
      order by coalesce(nullif(tier->>'minimum_contract_years','')::numeric,0) desc
      limit 1;
      resolved_rate := nullif(matched_tier->>'rate','')::numeric;
      if matched_tier is null or resolved_rate is null then
        calculation_status := 'configuration_error'; calculation_explanation := 'No percentage tier matches the contract term.';
      else
        calculated_amount := round(selected_source_amount * resolved_rate,2);
        calculation_explanation := selected_source_amount::text || ' × ' || resolved_rate::text || ' for ' || selected_contract_term_years::text || ' contract years';
      end if;
    end if;

  elsif selected_calculation_type = 'fixed_amount' then
    resolved_fixed_amount := coalesce(nullif(config->>'amount','')::numeric,nullif(config->>'fixed_amount','')::numeric);
    if resolved_fixed_amount is null then
      calculation_status := 'configuration_error'; calculation_explanation := 'Fixed amount is not configured.';
    else
      calculated_amount := round(resolved_fixed_amount,2); calculation_explanation := 'Fixed amount ' || resolved_fixed_amount::text;
    end if;

  elsif selected_calculation_type = 'tiered_fixed_amount' then
    if selected_contract_term_years is null then
      calculation_status := 'missing_input'; calculation_explanation := 'Contract term is required for a tiered fixed amount.';
    else
      select tier into matched_tier
      from jsonb_array_elements(coalesce(config->'tiers','[]'::jsonb)) tier
      where selected_contract_term_years >= coalesce(nullif(tier->>'minimum_contract_years','')::numeric,0)
        and (nullif(tier->>'maximum_contract_years','') is null or selected_contract_term_years <= (tier->>'maximum_contract_years')::numeric)
      order by coalesce(nullif(tier->>'minimum_contract_years','')::numeric,0) desc
      limit 1;
      resolved_fixed_amount := coalesce(nullif(matched_tier->>'amount','')::numeric,nullif(matched_tier->>'fixed_amount','')::numeric);
      if matched_tier is null or resolved_fixed_amount is null then
        calculation_status := 'configuration_error'; calculation_explanation := 'No fixed-amount tier matches the contract term.';
      else
        calculated_amount := round(resolved_fixed_amount,2);
        calculation_explanation := 'Fixed amount ' || resolved_fixed_amount::text || ' for ' || selected_contract_term_years::text || ' contract years';
      end if;
    end if;

  elsif selected_calculation_type = 'fixed_amount_per_unit' then
    resolved_fixed_amount := coalesce(nullif(config->>'amount_per_unit','')::numeric,nullif(config->>'amount_per_completed_qdc','')::numeric);
    if selected_unit_count is null then
      calculation_status := 'missing_input'; calculation_explanation := 'Unit count is required.';
    elsif resolved_fixed_amount is null then
      calculation_status := 'configuration_error'; calculation_explanation := 'Amount per unit is not configured.';
    else
      calculated_amount := round(selected_unit_count * resolved_fixed_amount,2);
      calculation_explanation := selected_unit_count::text || ' × ' || resolved_fixed_amount::text;
    end if;

  else
    calculation_status := 'unsupported';
    calculation_explanation := 'Calculation type ' || selected_calculation_type || ' is not supported by the deal evaluator.';
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'status',calculation_status,
    'calculation_type',selected_calculation_type,
    'calculated_amount',calculated_amount,
    'source_amount',selected_source_amount,
    'unit_count',selected_unit_count,
    'contract_term_years',selected_contract_term_years,
    'resolved_rate',resolved_rate,
    'resolved_fixed_amount',resolved_fixed_amount,
    'matched_tier',matched_tier,
    'matched_rate_history',matched_rate_history,
    'measurement_date',selected_measurement_date,
    'explanation',calculation_explanation
  ));
end;
$function$;

revoke all on function public.evaluate_compensation_rule(text,jsonb,numeric,numeric,numeric,date) from public, anon, authenticated;
