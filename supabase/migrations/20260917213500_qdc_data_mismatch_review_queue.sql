-- QDC data-quality exceptions: a completion date without QDC Stage = QDC Completed
-- must be reviewed, not silently paid or discarded.

create or replace view public.comp_qdc_data_quality_exceptions_v1
with (security_invoker=true)
as
select
  d.hubspot_deal_id,d.deal_name,d.hubspot_record_url,
  d.business_development_owner_id,d.qdc_completed_date,
  d.raw_hubspot_data->'properties'->>'qdc_stage' as qdc_stage,
  case
    when d.raw_hubspot_data->'properties'->>'qdc_stage' is null then 'completion_date_with_blank_stage'
    else 'completion_date_stage_mismatch'
  end as exception_type,
  concat(
    'QDC completed date is ',d.qdc_completed_date::text,
    ' but QDC Stage is ',
    coalesce(nullif(d.raw_hubspot_data->'properties'->>'qdc_stage',''),'blank'),
    '. Review whether this deal should count as a completed QDC.'
  ) as review_question
from public.hubspot_deals d
where d.qdc_completed_date is not null
  and coalesce(d.raw_hubspot_data->'properties'->>'qdc_stage','')<>'QDC Completed';

comment on view public.comp_qdc_data_quality_exceptions_v1 is
'QDC data mismatches requiring human review. These rows are warnings only and do not qualify for payout unless separately approved through the compensation review workflow.';

grant select on public.comp_qdc_data_quality_exceptions_v1 to authenticated;
