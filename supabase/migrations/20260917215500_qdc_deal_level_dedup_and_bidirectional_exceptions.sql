-- QDC payout unit is the deal. Meeting and deal-field evidence are alternative/corroborating
-- qualification paths and must collapse to one candidate per employee/component/deal.
-- Also flag both directions of QDC stage/date inconsistency.

-- NOTE: live definition is maintained in comp_qdc_deal_candidates_v3 and
-- comp_qdc_data_quality_exceptions_v2. This migration documents the business invariants
-- and adds assertions that can be used by release verification.
create or replace view public.comp_qdc_release_assertions_v1
with (security_invoker=true)
as
select
  (select count(*) from (
     select candidate_key from public.comp_qdc_deal_candidates_v3
     group by candidate_key having count(*)>1
   ) d)=0 as no_duplicate_deal_candidates,
  (select count(*) from public.comp_qdc_data_quality_exceptions_v2
    where exception_type='completion_date_without_completed_stage') as date_without_completed_stage_count,
  (select count(*) from public.comp_qdc_data_quality_exceptions_v2
    where exception_type='completed_stage_without_completion_date') as completed_stage_without_date_count;

comment on view public.comp_qdc_release_assertions_v1 is
'Release assertions for deal-level QDC deduplication and bidirectional QDC stage/date data-quality exceptions.';

grant select on public.comp_qdc_release_assertions_v1 to authenticated;
