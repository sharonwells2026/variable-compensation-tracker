-- Compensation evaluator extension checkpoint.
--
-- Design decisions validated against Sharon Wells' signed plan and synced HubSpot data:
-- 1. Deal-based percentage compensation may use an effective-dated rate_history.
-- 2. Tiered percentage compensation may resolve rate from contract_term_years.
-- 3. The amount_source remains authoritative for the payout basis; Sharon's GovAffairs
--    AE new-business tiers use HubSpot Deal Amount, not TCV or ARR.
-- 4. Historical actual/approved payouts must not rewrite plan configuration.
-- 5. This migration intentionally adds reusable rate resolution helpers first; the
--    candidate view can consume them without mutating historical earnings.

create or replace function public.resolve_comp_component_rate(
  p_calculation_type text,
  p_rule_configuration jsonb,
  p_effective_date date,
  p_contract_term_years numeric default null
)
returns numeric
language sql
stable
set search_path = public
as $$
  select case
    when p_calculation_type = 'tiered_percentage' then (
      select nullif(tier ->> 'rate', '')::numeric
      from jsonb_array_elements(coalesce(p_rule_configuration -> 'tiers', '[]'::jsonb)) tier
      where p_contract_term_years is not null
        and p_contract_term_years >= coalesce(nullif(tier ->> 'minimum_contract_years', '')::numeric, p_contract_term_years)
        and p_contract_term_years <= coalesce(nullif(tier ->> 'maximum_contract_years', '')::numeric, p_contract_term_years)
      order by coalesce(nullif(tier ->> 'minimum_contract_years', '')::numeric, 0) desc
      limit 1
    )
    when jsonb_typeof(p_rule_configuration -> 'rate_history') = 'array' then (
      select nullif(rate_row ->> 'rate', '')::numeric
      from jsonb_array_elements(p_rule_configuration -> 'rate_history') rate_row
      where p_effective_date >= nullif(rate_row ->> 'effective_start_date', '')::date
        and p_effective_date <= coalesce(nullif(rate_row ->> 'effective_end_date', '')::date, 'infinity'::date)
      order by nullif(rate_row ->> 'effective_start_date', '')::date desc
      limit 1
    )
    else nullif(p_rule_configuration ->> 'rate', '')::numeric
  end;
$$;

revoke all on function public.resolve_comp_component_rate(text,jsonb,date,numeric) from public;
grant execute on function public.resolve_comp_component_rate(text,jsonb,date,numeric) to authenticated;

comment on function public.resolve_comp_component_rate(text,jsonb,date,numeric) is
'Resolves flat, effective-dated, or contract-term-tiered compensation rates. Returns NULL when required tier/effective-date inputs do not resolve, so callers can surface a data-quality blocker rather than silently calculate zero.';
