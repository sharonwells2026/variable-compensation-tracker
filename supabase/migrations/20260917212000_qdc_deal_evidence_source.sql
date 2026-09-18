-- QDC deal-field evidence path.
-- A deal qualifies through this path only when BOTH QDC Stage = QDC Completed
-- and QDC Completed date is populated. The date alone is not sufficient.

do $outer$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='sync_hubspot_deals';

  if position('''qdc_stage''' in d)=0 then
    d := replace(
      d,
      '''business_development_owner'',''qdc_completed_date''',
      '''business_development_owner'',''qdc_stage'',''qdc_completed_date'''
    );
    execute d;
  end if;
end
$outer$;

create or replace view public.comp_qdc_deal_evidence_v2
with (security_invoker=true)
as
select
  d.hubspot_deal_id,
  d.deal_name,
  d.hubspot_record_url,
  d.business_development_owner_id,
  d.qdc_completed_date as qualified_date,
  d.raw_hubspot_data->'properties'->>'qdc_stage' as qdc_stage,
  'deal_qdc_fields'::text as evidence_type,
  jsonb_build_object(
    'qdc_stage',d.raw_hubspot_data->'properties'->>'qdc_stage',
    'qdc_completed_date',d.qdc_completed_date,
    'qualification_rule','QDC Stage = QDC Completed AND QDC Completed date populated'
  ) as evidence
from public.hubspot_deals d
where d.raw_hubspot_data->'properties'->>'qdc_stage'='QDC Completed'
  and d.qdc_completed_date is not null;

comment on view public.comp_qdc_deal_evidence_v2 is
'Deal-level QDC qualification evidence. Requires both qdc_stage=QDC Completed and qdc_completed_date; date alone does not qualify.';

grant select on public.comp_qdc_deal_evidence_v2 to authenticated;
