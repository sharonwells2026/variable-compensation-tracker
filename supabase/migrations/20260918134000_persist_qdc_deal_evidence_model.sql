-- Persist the live deal-level QDC evidence model so fresh environments reproduce production.
-- One compensable QDC candidate per employee + component + deal.
-- Either a completed QDC meeting OR QDC Stage=QDC Completed with a completion date qualifies.

create or replace view public.comp_qdc_data_quality_exceptions_v2
with (security_invoker=true)
as
select d.hubspot_deal_id,d.deal_name,d.hubspot_record_url,d.qdc_completed_date,
       d.raw_hubspot_data->'properties'->>'qdc_stage' as qdc_stage,
       case
         when d.qdc_completed_date is not null
          and coalesce(d.raw_hubspot_data->'properties'->>'qdc_stage','')<>'QDC Completed'
           then 'completion_date_without_completed_stage'
         when d.qdc_completed_date is null
          and d.raw_hubspot_data->'properties'->>'qdc_stage'='QDC Completed'
           then 'completed_stage_without_completion_date'
       end as exception_type,
       case
         when d.qdc_completed_date is not null
          and coalesce(d.raw_hubspot_data->'properties'->>'qdc_stage','')<>'QDC Completed'
           then concat('QDC completed date is ',d.qdc_completed_date::text,' but QDC Stage is ',
                       coalesce(nullif(d.raw_hubspot_data->'properties'->>'qdc_stage',''),'blank'),
                       '. Review whether the deal should count as a completed QDC.')
         else 'QDC Stage is QDC Completed but QDC Completed Date is blank. Review the missing completion date or verify with associated completed QDC meeting evidence.'
       end as review_question
from public.hubspot_deals d
where (d.qdc_completed_date is not null and coalesce(d.raw_hubspot_data->'properties'->>'qdc_stage','')<>'QDC Completed')
   or (d.qdc_completed_date is null and d.raw_hubspot_data->'properties'->>'qdc_stage'='QDC Completed');

comment on view public.comp_qdc_data_quality_exceptions_v2 is
'Bidirectional QDC stage/date mismatches requiring review. A valid completed QDC meeting may independently qualify the deal.';

grant select on public.comp_qdc_data_quality_exceptions_v2 to authenticated;

create or replace view public.comp_qdc_deal_candidates_v3
with (security_invoker=true)
as
with meeting_evidence as (
 select a.target_hubspot_record_id hubspot_deal_id,
        min(coalesce(nullif(g.properties->>'hs_meeting_start_time','')::timestamptz,
                     nullif(g.properties->>'hs_timestamp','')::timestamptz)) first_completed_qdc_meeting_at,
        count(distinct g.hubspot_record_id) completed_qdc_meeting_count,
        jsonb_agg(distinct jsonb_build_object(
          'hubspot_meeting_id',g.hubspot_record_id,
          'meeting_at',coalesce(nullif(g.properties->>'hs_meeting_start_time','')::timestamptz,
                                nullif(g.properties->>'hs_timestamp','')::timestamptz),
          'activity_type',g.properties->>'hs_activity_type',
          'meeting_outcome',g.properties->>'hs_meeting_outcome',
          'meeting_title',g.properties->>'hs_meeting_title')) meetings
 from public.hubspot_generic_associations a
 join public.hubspot_generic_records g
   on g.hubspot_object_type=a.source_hubspot_object_type and g.hubspot_record_id=a.source_hubspot_record_id
 where a.source_hubspot_object_type='MEETING_EVENT' and a.target_object_type='deal'
   and g.in_sync_scope=true and g.is_archived=false
   and g.properties->>'hs_activity_type'='QDC [Meeting]'
   and g.properties->>'hs_meeting_outcome'='COMPLETED'
   and coalesce(nullif(g.properties->>'hs_meeting_start_time','')::timestamptz,
                nullif(g.properties->>'hs_timestamp','')::timestamptz) is not null
 group by a.target_hubspot_record_id
), evidence as (
 select d.hubspot_deal_id,d.deal_name,d.hubspot_record_url,
        case when d.raw_hubspot_data->'properties'->>'qdc_stage'='QDC Completed'
                  and d.qdc_completed_date is not null then d.qdc_completed_date end deal_qdc_completed_date,
        d.raw_hubspot_data->'properties'->>'qdc_stage' qdc_stage,
        me.first_completed_qdc_meeting_at,me.completed_qdc_meeting_count,me.meetings
 from public.hubspot_deals d left join meeting_evidence me on me.hubspot_deal_id=d.hubspot_deal_id
 where (d.raw_hubspot_data->'properties'->>'qdc_stage'='QDC Completed' and d.qdc_completed_date is not null)
    or me.first_completed_qdc_meeting_at is not null
), assigned as (
 select e.id employee_id,e.full_name,e.email,a.id plan_assignment_id,p.id comp_plan_id,p.name plan_name,
        pv.id plan_version_id,pv.version_number,pv.status::text plan_status,c.id plan_component_id,c.component_code,
        c.name plan_component_name,c.calculation_type,c.measurement_source,c.measurement_period,c.rule_configuration,
        ev.*,greatest(a.effective_start_date,pv.effective_start_date,
          coalesce(nullif(c.rule_configuration->>'effective_start_date','')::date,'-infinity'::date)) window_start,
        least(coalesce(a.effective_end_date,'infinity'::date),coalesce(pv.effective_end_date,'infinity'::date),
          coalesce(nullif(c.rule_configuration->>'effective_end_date','')::date,'infinity'::date)) window_end
 from public.employees e
 join public.employee_plan_assignments a on a.employee_id=e.id
 join public.comp_plan_versions pv on pv.id=a.plan_version_id
 join public.comp_plans p on p.id=pv.comp_plan_id
 join public.comp_plan_components c on c.plan_version_id=pv.id and c.is_active=true
 cross join evidence ev
 where c.calculation_type='fixed_amount_per_unit' and c.measurement_source='hubspot_meeting'
   and coalesce(c.rule_configuration->>'meeting_type','')='QDC'
   and coalesce((c.rule_configuration->>'count_each_completed_meeting')::boolean,false)=true
)
select md5(employee_id::text||':'||plan_component_id::text||':'||hubspot_deal_id) candidate_key,
       employee_id,full_name,email,plan_assignment_id,comp_plan_id,plan_name,plan_version_id,version_number,plan_status,
       plan_component_id,component_code,plan_component_name,calculation_type,measurement_source,measurement_period,
       hubspot_deal_id,deal_name,hubspot_record_url,
       case when deal_qdc_completed_date between window_start and window_end
                  and first_completed_qdc_meeting_at::date between window_start and window_end
              then least(deal_qdc_completed_date,first_completed_qdc_meeting_at::date)
            when deal_qdc_completed_date between window_start and window_end then deal_qdc_completed_date
            else first_completed_qdc_meeting_at::date end earned_date,
       1::numeric unit_count,
       coalesce(nullif(rule_configuration->>'amount_per_completed_qdc','')::numeric,
                nullif(rule_configuration->>'amount_per_unit','')::numeric) amount_per_unit,
       round(coalesce(nullif(rule_configuration->>'amount_per_completed_qdc','')::numeric,
                      nullif(rule_configuration->>'amount_per_unit','')::numeric),2) calculated_earning_amount,
       case when coalesce(nullif(rule_configuration->>'amount_per_completed_qdc','')::numeric,
                          nullif(rule_configuration->>'amount_per_unit','')::numeric) is null
            then 'configuration_error' else 'ready' end calculation_status,
       case when deal_qdc_completed_date is not null and first_completed_qdc_meeting_at is not null then 'meeting_and_deal'
            when first_completed_qdc_meeting_at is not null then 'meeting' else 'deal' end evidence_path,
       jsonb_build_object('deal_qdc_stage',qdc_stage,'deal_qdc_completed_date',deal_qdc_completed_date,
         'completed_qdc_meeting_count',coalesce(completed_qdc_meeting_count,0),'meetings',coalesce(meetings,'[]'::jsonb),
         'deduplication_key','employee + component + deal','payout_unit','one QDC per qualifying deal') source_evidence
from assigned
where deal_qdc_completed_date between window_start and window_end
   or first_completed_qdc_meeting_at::date between window_start and window_end;

grant select on public.comp_qdc_deal_candidates_v3 to authenticated;
