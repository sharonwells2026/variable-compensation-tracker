create or replace view public.comp_deal_earning_candidates_v2
with (security_invoker = true)
as
with qualified_deals as (
  select
    e.id as employee_id,
    e.full_name,
    e.email,
    e.hubspot_owner_id as employee_hubspot_owner_id,
    epa.id as plan_assignment_id,
    cp.id as comp_plan_id,
    cp.name as plan_name,
    pv.id as plan_version_id,
    pv.version_number,
    pv.status::text as plan_status,
    c.id as plan_component_id,
    c.component_code,
    c.name as plan_component_name,
    c.calculation_type,
    c.measurement_source,
    c.measurement_label,
    c.rule_configuration as component_configuration,
    dr.id as deal_rule_id,
    dr.amount_source,
    dr.amount_label,
    dr.marks_earned,
    dr.marks_eligible,
    dr.marks_paid,
    d.hubspot_deal_id,
    d.deal_name,
    d.hubspot_owner_id as deal_owner_id,
    d.hubspot_pipeline_id,
    p.pipeline_name,
    d.hubspot_stage_id,
    s.stage_name,
    d.hubspot_deal_type,
    d.close_date,
    d.invoice_paid_date,
    d.contract_term_years,
    d.contract_term_months,
    d.hubspot_record_url,
    company.hubspot_company_id,
    company.company_name,
    company.customer_experience_manager_id as company_cem_id,
    case dr.amount_source
      when 'amount' then d.amount
      when 'average_arr' then d.average_arr
      when 'first_year_arr' then d.first_year_arr
      when 'one_time_fee' then d.one_time_fee
      when 'total_contract_value' then d.total_contract_value
      else null::numeric
    end as source_amount
  from public.employees e
  join public.employee_plan_assignments epa
    on epa.employee_id = e.id
  join public.comp_plan_versions pv
    on pv.id = epa.plan_version_id
  join public.comp_plans cp
    on cp.id = pv.comp_plan_id
  join public.comp_plan_components c
    on c.plan_version_id = pv.id
   and c.is_active = true
  join public.comp_component_deal_rules dr
    on dr.plan_component_id = c.id
   and dr.is_active = true
   and dr.calculation_action = 'include'
   and dr.marks_earned = true
  join public.hubspot_deals d
    on d.hubspot_pipeline_id = dr.hubspot_pipeline_id
   and d.hubspot_stage_id = dr.hubspot_stage_id
   and d.hubspot_deal_type = dr.hubspot_deal_type
  join public.hubspot_pipelines p
    on p.hubspot_pipeline_id = d.hubspot_pipeline_id
  join public.hubspot_pipeline_stages s
    on s.hubspot_pipeline_id = d.hubspot_pipeline_id
   and s.hubspot_stage_id = d.hubspot_stage_id
  left join lateral (
    select a.hubspot_company_id
    from public.hubspot_deal_company_associations a
    where a.hubspot_deal_id = d.hubspot_deal_id
    order by a.is_primary desc, a.last_synced_at desc
    limit 1
  ) association on true
  left join public.hubspot_companies company
    on company.hubspot_company_id = association.hubspot_company_id
  where d.close_date is not null
    and d.close_date >= greatest(
      epa.effective_start_date,
      pv.effective_start_date,
      dr.effective_start_date
    )
    and d.close_date <= least(
      coalesce(epa.effective_end_date, 'infinity'::date),
      coalesce(pv.effective_end_date, 'infinity'::date),
      coalesce(dr.effective_end_date, 'infinity'::date)
    )
),
attributed as (
  select
    q.*,
    ar.id as attribution_rule_id,
    ar.hubspot_user_field_keys,
    ar.match_logic as attribution_match_logic,
    ar.credit_percentage,
    ar.priority as attribution_priority,
    ar.allow_stacking,
    ar.rule_configuration as attribution_configuration,
    private.evaluate_hubspot_user_attribution(
      q.employee_id,
      q.hubspot_deal_id,
      ar.hubspot_user_field_keys,
      ar.match_logic
    ) as attribution_result
  from qualified_deals q
  join lateral (
    select r.*
    from public.comp_user_attribution_rules r
    where r.plan_component_id = q.plan_component_id
      and r.attribution_purpose = 'earning'
      and r.is_active = true
      and q.close_date >= r.effective_start_date
      and q.close_date <= coalesce(r.effective_end_date, 'infinity'::date)
      and (
        r.qualifying_pipeline_ids = '[]'::jsonb
        or r.qualifying_pipeline_ids ? q.hubspot_pipeline_id
      )
      and (
        r.qualifying_deal_types = '[]'::jsonb
        or r.qualifying_deal_types ? q.hubspot_deal_type
      )
    order by r.priority, r.created_at
    limit 1
  ) ar on true
),
calculated as (
  select
    a.*,
    public.evaluate_compensation_rule(
      a.calculation_type,
      a.component_configuration,
      a.source_amount,
      a.contract_term_years,
      null,
      a.close_date
    ) as calculation_result
  from attributed a
  where coalesce((a.attribution_result ->> 'matched')::boolean, false) = true
)
select
  md5(employee_id::text || ':' || plan_component_id::text || ':' || hubspot_deal_id) as candidate_key,
  employee_id,
  full_name,
  email,
  employee_hubspot_owner_id,
  plan_assignment_id,
  comp_plan_id,
  plan_name,
  plan_version_id,
  version_number,
  plan_status,
  plan_component_id,
  component_code,
  plan_component_name,
  calculation_type,
  measurement_source,
  measurement_label,
  deal_rule_id,
  attribution_rule_id,
  hubspot_user_field_keys,
  attribution_match_logic,
  credit_percentage,
  attribution_priority,
  allow_stacking,
  hubspot_deal_id,
  deal_name,
  deal_owner_id,
  hubspot_pipeline_id,
  pipeline_name,
  hubspot_stage_id,
  stage_name,
  hubspot_deal_type,
  hubspot_company_id,
  company_name,
  company_cem_id,
  close_date as earned_date,
  case when marks_eligible = true and invoice_paid_date is not null
       then invoice_paid_date else null::date end as eligible_date,
  amount_source,
  amount_label,
  source_amount,
  contract_term_years,
  contract_term_months,
  nullif(calculation_result ->> 'resolved_rate', '')::numeric as resolved_rate,
  nullif(calculation_result ->> 'resolved_fixed_amount', '')::numeric as resolved_fixed_amount,
  round(
    nullif(calculation_result ->> 'calculated_amount', '')::numeric
      * (credit_percentage / 100::numeric),
    2
  ) as calculated_earning_amount,
  calculation_result ->> 'status' as calculation_status,
  calculation_result ->> 'explanation' as calculation_explanation,
  calculation_result,
  attribution_result,
  case when marks_eligible = true and invoice_paid_date is not null
       then 'eligible' else 'pending_condition' end as eligibility_status,
  marks_earned,
  marks_eligible,
  marks_paid,
  invoice_paid_date,
  hubspot_record_url,
  component_configuration,
  attribution_configuration
from calculated;

comment on view public.comp_deal_earning_candidates_v2 is
'100H parallel generic deal earning candidate preview. Uses generic calculation and HubSpot user attribution engines. Does not replace the legacy production candidate view or write earnings.';