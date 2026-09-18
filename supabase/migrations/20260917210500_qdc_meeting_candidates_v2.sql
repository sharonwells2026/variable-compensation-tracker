-- Authoritative one-QDC-per-completed-HubSpot-meeting candidate layer.
-- Distinct HubSpot meeting record IDs are the primary dedup key. Rescheduled/canceled/no-show
-- records never qualify. Calendar/change IDs are retained as audit evidence, not used to collapse
-- genuinely separate completed meetings.

create or replace view public.comp_qdc_meeting_candidates_v2
with (security_invoker=true)
as
with meetings as (
  select
    g.hubspot_record_id as hubspot_meeting_id,
    g.properties,
    coalesce(nullif(g.properties->>'hs_meeting_start_time','')::timestamptz,
             nullif(g.properties->>'hs_timestamp','')::timestamptz) as meeting_at,
    g.properties->>'hubspot_owner_id' as hubspot_owner_id,
    g.properties->>'hs_activity_type' as activity_type,
    g.properties->>'hs_meeting_outcome' as meeting_outcome,
    g.properties->>'hs_meeting_calendar_event_hash' as calendar_event_hash,
    g.properties->>'hs_meeting_change_id' as meeting_change_id,
    g.properties->>'hs_meeting_title' as meeting_title
  from public.hubspot_generic_records g
  where g.hubspot_object_type='MEETING_EVENT'
    and g.in_sync_scope=true
    and g.is_archived=false
),
qualified as (
  select *
  from meetings
  where activity_type='QDC [Meeting]'
    and meeting_outcome='COMPLETED'
    and meeting_at is not null
),
assigned as (
  select
    q.*,e.id as employee_id,e.full_name,e.email,
    a.id as plan_assignment_id,a.plan_version_id,
    row_number() over(
      partition by e.id,c.id,q.hubspot_meeting_id
      order by a.effective_start_date desc,a.id
    ) as candidate_rank,
    c.id as plan_component_id,c.component_code,c.name as plan_component_name,
    c.calculation_type,c.measurement_source,c.measurement_period,c.rule_configuration,
    pv.status::text as plan_status,pv.version_number,pv.comp_plan_id,
    p.name as plan_name
  from qualified q
  join public.employees e on e.hubspot_owner_id=q.hubspot_owner_id
  join public.employee_plan_assignments a on a.employee_id=e.id
  join public.comp_plan_versions pv on pv.id=a.plan_version_id
  join public.comp_plans p on p.id=pv.comp_plan_id
  join public.comp_plan_components c on c.plan_version_id=pv.id and c.is_active=true
  where c.calculation_type='fixed_amount_per_unit'
    and c.measurement_source='hubspot_meeting'
    and coalesce(c.rule_configuration->>'meeting_type','')='QDC'
    and coalesce(c.rule_configuration->>'meeting_outcome','')='Completed'
    and q.meeting_at::date >= greatest(
      a.effective_start_date,pv.effective_start_date,
      coalesce(nullif(c.rule_configuration->>'effective_start_date','')::date,'-infinity'::date)
    )
    and q.meeting_at::date <= least(
      coalesce(a.effective_end_date,'infinity'::date),
      coalesce(pv.effective_end_date,'infinity'::date),
      coalesce(nullif(c.rule_configuration->>'effective_end_date','')::date,'infinity'::date)
    )
)
select
  md5(employee_id::text||':'||plan_component_id::text||':'||hubspot_meeting_id) as candidate_key,
  employee_id,full_name,email,plan_assignment_id,comp_plan_id,plan_name,plan_version_id,
  version_number,plan_status,plan_component_id,component_code,plan_component_name,
  calculation_type,measurement_source,measurement_period,
  hubspot_meeting_id,meeting_title,meeting_at,meeting_at::date as earned_date,
  hubspot_owner_id,activity_type,meeting_outcome,calendar_event_hash,meeting_change_id,
  1::numeric as unit_count,
  coalesce(nullif(rule_configuration->>'amount_per_completed_qdc','')::numeric,
           nullif(rule_configuration->>'amount_per_unit','')::numeric) as amount_per_unit,
  round(coalesce(nullif(rule_configuration->>'amount_per_completed_qdc','')::numeric,
                 nullif(rule_configuration->>'amount_per_unit','')::numeric),2) as calculated_earning_amount,
  case
    when coalesce(nullif(rule_configuration->>'amount_per_completed_qdc','')::numeric,
                  nullif(rule_configuration->>'amount_per_unit','')::numeric) is null then 'configuration_error'
    else 'ready'
  end as calculation_status,
  'hubspot_meeting_event'::text as source_type,
  jsonb_build_object(
    'hubspot_meeting_id',hubspot_meeting_id,
    'activity_type',activity_type,
    'meeting_outcome',meeting_outcome,
    'meeting_at',meeting_at,
    'hubspot_owner_id',hubspot_owner_id,
    'calendar_event_hash',calendar_event_hash,
    'meeting_change_id',meeting_change_id,
    'deduplication_key','hubspot_meeting_id',
    'business_event','completed_qdc'
  ) as source_evidence
from assigned
where candidate_rank=1;

comment on view public.comp_qdc_meeting_candidates_v2 is
'Authoritative completed-QDC compensation candidates from HubSpot MEETING_EVENT. One earning candidate per employee/component/HubSpot meeting record; only QDC [Meeting] + COMPLETED qualifies.';

grant select on public.comp_qdc_meeting_candidates_v2 to authenticated;
