with sharon as (
  select id from public.employees where lower(email)=lower('sharonwells@engagifii.com') limit 1
), sources(source_label,source_type,evidence_role,authoritative_for,import_status,notes) as (
  values
  ('Monthly submitted-for-payout detail','workbook_section','earning_detail',array['earned','submitted_for_payout']::text[],'mapped','Rows headed Deal Closed/Won / Component / Rate / Earned / Submitted For Payout. Transaction-level evidence; use for historical earned/submission staging, not as proof of actual payment.'),
  ('Eligibility and payment status detail','workbook_section','eligibility_detail',array['eligible','payment_candidate']::text[],'mapped','Rows headed Customer / Close Date / ARR / Rate / Earned / Eligible / To Be Paid (Customer has paid) / Amount Paid / Date Paid. Preserve eligibility separately from actual paid evidence.'),
  ('Paid payout ledger','workbook_section','payment_detail',array['paid','payment_date','payout_status']::text[],'mapped','Rows headed Deal Closed/Won / Owner / Owner Email / Plan / Component / Rate / Paid (USD) / Payout Date / Status. Highest-priority workbook evidence for historical paid classification.'),
  ('Milestone tracking by year','workbook_section','earning_detail',array['milestone_earned','milestone_submitted']::text[],'mapped','YTD ARR milestone tables with milestone reached, bonus earned and submitted-for-payout fields. Use transaction/milestone evidence, not summary totals alone.'),
  ('Component reconciliation summary','workbook_section','summary',array[]::text[],'excluded','Component-level totals such as MEams New Sales, QDCs, One-Time Fees, Expansion Override and Government Affairs. Reference/checksum only; never import as separate payable earnings.'),
  ('Different New MEams Scenarios','workbook_tab','scenario',array[]::text[],'excluded','Alternative MEams rate scenarios. Analysis only; never import as payable, approved or paid compensation.')
)
insert into public.historical_source_catalog(employee_id,document_name,source_label,source_type,evidence_role,authoritative_for,import_status,notes)
select sharon.id,'2024-2025-2026 Sharon Wells Variable Compensation',s.source_label,s.source_type,s.evidence_role,s.authoritative_for,s.import_status,s.notes
from sharon cross join sources s
where not exists (
  select 1 from public.historical_source_catalog h
  where h.employee_id=sharon.id
    and h.document_name='2024-2025-2026 Sharon Wells Variable Compensation'
    and h.source_label=s.source_label
);
