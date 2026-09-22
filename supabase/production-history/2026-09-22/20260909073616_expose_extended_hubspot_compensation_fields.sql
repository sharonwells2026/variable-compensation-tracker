create or replace view public.hubspot_deal_scope as
select
  d.id,d.hubspot_deal_id,d.deal_name,d.hubspot_company_id,d.hubspot_owner_id,d.hubspot_pipeline_id,d.hubspot_stage_id,d.hubspot_deal_type,
  d.average_arr,d.first_year_arr,d.total_contract_value,d.one_time_fee,d.contract_term_label,d.contract_term_years,d.contract_term_months,
  d.contract_start_date,d.contract_end_date,d.payment_frequency,d.contract_url,d.subscription_updated_date,d.invoice_paid_date,d.close_date,
  d.hubspot_record_url,d.raw_hubspot_data,d.hubspot_created_at,d.hubspot_updated_at,d.last_synced_at,d.created_at,d.updated_at,d.source_fingerprint,d.last_change_detected_at,
  p.pipeline_name,s.stage_name,
  case
    when s.id is null then false
    when lower(trim(s.stage_name))='closed lost' and lower(trim(coalesce(d.hubspot_deal_type,'')))='newbusiness' then false
    when lower(trim(s.stage_name))='closed lost' and lower(trim(coalesce(d.hubspot_deal_type,'')))='existingbusiness' then false
    else true
  end as is_compensation_scope,
  case
    when s.id is null then 'Stage is not configured for compensation'
    when lower(trim(s.stage_name))='closed lost' and lower(trim(coalesce(d.hubspot_deal_type,'')))='newbusiness' then 'Closed Lost New Business'
    when lower(trim(s.stage_name))='closed lost' and lower(trim(coalesce(d.hubspot_deal_type,'')))='existingbusiness' then 'Closed Lost Expansion'
    else 'Included'
  end as scope_reason,
  d.amount,
  d.new_business_arr,
  d.expansion_arr,
  d.renewal_arr,
  d.non_recurring_revenue,
  d.opportunity_type,
  d.purchased_modules,
  d.solutions_advisor_id,
  d.business_development_owner_id,
  d.qdc_completed_date,
  d.is_closed_won
from public.hubspot_deals d
left join public.hubspot_pipelines p on p.hubspot_pipeline_id=d.hubspot_pipeline_id
left join public.hubspot_pipeline_stages s on s.hubspot_pipeline_id=d.hubspot_pipeline_id and s.hubspot_stage_id=d.hubspot_stage_id;

create or replace view public.hubspot_compensation_deals as
select * from public.hubspot_deal_scope where is_compensation_scope=true;