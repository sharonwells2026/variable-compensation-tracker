create or replace view public.comp_qdc_earning_candidates_v1
with (security_invoker=true)
as
select
  md5(e.id::text||':'||c.id::text||':'||d.hubspot_deal_id||':'||d.qdc_completed_date::text) as candidate_key,
  e.id as employee_id,e.full_name,e.email,a.id as plan_assignment_id,
  p.id as comp_plan_id,p.name as plan_name,pv.id as plan_version_id,
  pv.version_number,pv.status::text as plan_status,c.id as plan_component_id,
  c.component_code,c.name as plan_component_name,c.calculation_type,
  c.measurement_source,c.measurement_period,d.hubspot_deal_id,d.deal_name,
  d.hubspot_record_url,d.qdc_completed_date as earned_date,1::numeric as unit_count,
  coalesce(nullif(c.rule_configuration->>'amount_per_completed_qdc','')::numeric,
           nullif(c.rule_configuration->>'amount_per_unit','')::numeric) as amount_per_unit,
  round(coalesce(nullif(c.rule_configuration->>'amount_per_completed_qdc','')::numeric,
                 nullif(c.rule_configuration->>'amount_per_unit','')::numeric),2) as calculated_earning_amount,
  case when d.qdc_completed_date is null then 'missing_event_date'
       when coalesce(nullif(c.rule_configuration->>'amount_per_completed_qdc','')::numeric,
                     nullif(c.rule_configuration->>'amount_per_unit','')::numeric) is null then 'configuration_error'
       else 'ready' end as calculation_status,
  'hubspot_deal_qdc_completed_date'::text as source_type,
  jsonb_build_object('source_field','qdc_completed_date','business_event','completed_qdc',
    'source_bridge','HubSpot deal property used until enriched meeting-event normalization is available') as source_evidence
from public.employees e
join public.employee_plan_assignments a on a.employee_id=e.id
join public.comp_plan_versions pv on pv.id=a.plan_version_id
join public.comp_plans p on p.id=pv.comp_plan_id
join public.comp_plan_components c on c.plan_version_id=pv.id and c.is_active=true
join public.hubspot_deals d on d.qdc_completed_date is not null
where c.calculation_type='fixed_amount_per_unit'
  and coalesce((c.rule_configuration->>'count_each_completed_meeting')::boolean,false)=true
  and coalesce(c.rule_configuration->>'meeting_type','')='QDC'
  and d.qdc_completed_date>=greatest(a.effective_start_date,pv.effective_start_date,
      coalesce(nullif(c.rule_configuration->>'effective_start_date','')::date,'-infinity'::date))
  and d.qdc_completed_date<=least(coalesce(a.effective_end_date,'infinity'::date),
      coalesce(pv.effective_end_date,'infinity'::date));

comment on view public.comp_qdc_earning_candidates_v1 is
'Preview candidate layer for fixed-per-QDC compensation. Uses normalized HubSpot Deal QDC Completed Date as an explicit bridge source until enriched HubSpot Meeting event fields are available. Non-active plan versions remain preview-only.';
