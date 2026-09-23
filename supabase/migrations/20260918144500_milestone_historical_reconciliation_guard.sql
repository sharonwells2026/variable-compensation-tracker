-- Historical milestone reconciliation guard.
-- Current HubSpot reconstruction is compared to known reconciled historical bonus anchors.
-- A difference is review-only and must never automatically rewrite or pay historical compensation.

create or replace view public.comp_milestone_reconciliation_exceptions_v1
with (security_invoker=true)
as
with components as (
 select c.id plan_component_id,c.plan_version_id,c.component_code,c.name component_name,c.rule_configuration,
        a.id plan_assignment_id,a.employee_id
 from public.comp_plan_components c
 join public.employee_plan_assignments a on a.plan_version_id=c.plan_version_id
 where c.is_active=true and c.calculation_type='milestone_bonus'
), won as (
 select cp.*,extract(year from d.close_date)::int attainment_year,d.hubspot_deal_id,d.deal_name,d.close_date,
        coalesce(d.first_year_arr,d.amount,d.average_arr,0) arr_used
 from components cp cross join public.hubspot_deals d
 where d.hubspot_deal_type='newbusiness'
   and d.hubspot_pipeline_id in ('20788895','56062501')
   and d.hubspot_stage_id in ('110553179','110577979','110609073','110691177','111910703','111970621','111910704','111910705')
   and d.close_date>=greatest((cp.rule_configuration->>'effective_start_date')::date,
                              (select effective_start_date from public.comp_plan_versions where id=cp.plan_version_id),
                              (select effective_start_date from public.employee_plan_assignments where id=cp.plan_assignment_id))
   and d.close_date<=least(coalesce((cp.rule_configuration->>'effective_end_date')::date,'infinity'::date),
                           coalesce((select effective_end_date from public.comp_plan_versions where id=cp.plan_version_id),'infinity'::date),
                           coalesce((select effective_end_date from public.employee_plan_assignments where id=cp.plan_assignment_id),'infinity'::date))
), annual as (
 select plan_component_id,plan_assignment_id,employee_id,attainment_year,sum(arr_used) current_source_arr,
        jsonb_agg(jsonb_build_object('deal_id',hubspot_deal_id,'deal_name',deal_name,'close_date',close_date,'arr_used',arr_used)
                  order by close_date,hubspot_deal_id) source_deals
 from won group by plan_component_id,plan_assignment_id,employee_id,attainment_year
), expected as (
 select a.*,
        coalesce(sum((m->>'bonus')::numeric) filter(where a.current_source_arr>=(m->>'threshold')::numeric),0) current_source_bonus
 from annual a join public.comp_plan_components c on c.id=a.plan_component_id
 cross join lateral jsonb_array_elements(c.rule_configuration->'milestones') m
 group by a.plan_component_id,a.plan_assignment_id,a.employee_id,a.attainment_year,a.current_source_arr,a.source_deals
)
select *,
 case when employee_id='a7bc17fb-3e03-4be6-b614-f81b278d4713' and attainment_year=2025 and current_source_bonus<>10000
      then 'historical_reconciliation_mismatch' else 'review_source_history' end exception_type,
 case when employee_id='a7bc17fb-3e03-4be6-b614-f81b278d4713' and attainment_year=2025 then 10000::numeric end historical_reconciled_bonus,
 case when employee_id='a7bc17fb-3e03-4be6-b614-f81b278d4713' and attainment_year=2025 then current_source_bonus-10000::numeric end bonus_difference
from expected;

comment on view public.comp_milestone_reconciliation_exceptions_v1 is
'Current HubSpot milestone reconstruction versus historical reconciliation anchors. Differences require review and never automatically alter historical compensation.';

grant select on public.comp_milestone_reconciliation_exceptions_v1 to authenticated;
