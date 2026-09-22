# Compensation Branch Reconciliation — 2026-09-22

## Production baseline
Production Netlify and deployed application are based on GitHub `main` at:
`c2acc474d7e4b790e4379d28c508625a6f6ba3c3`

Production Supabase has 180 applied migrations.

## plan-builder-v2
`plan-builder-v2` is 113 commits ahead of production `main` and is not deployed production.

Compared with `main`, it adds/modifies application surfaces for:
- plan creation and management;
- component rules and earned conditions;
- aggregate attainment;
- approvals;
- agreements;
- payroll;
- reports;
- reconciliation;
- settings/payment condition mapping;
- QDC evidence and reconciliation;
- new-logo attribution safeguards.

It also adds 39 migration files.

### Live-deployed vs branch-only migrations
Of those 39 migration files:
- 27 have equivalent migration names already present in the live production migration ledger.
- 12 are branch-only and are not present in the production migration ledger.

Branch-only migrations requiring explicit review before any deployment:
- reconciliation_boundary_review
- reconciliation_review_resolution
- enrich_compensation_reporting
- effective_date_and_unadopted_component_guards
- qdc_meeting_event_source_mapping
- qdc_meeting_candidates_v2
- qdc_deal_evidence_source
- qdc_data_mismatch_review_queue
- qdc_deal_level_dedup_and_bidirectional_exceptions
- persist_qdc_deal_evidence_model
- milestone_historical_reconciliation_guard
- new_logo_attribution_exclusivity

## Critical implication
`plan-builder-v2` cannot simply be merged to production or copied into RevOS.

Some of its backend concepts are already live through separately applied production migrations, while later branch work is not live. Application code and database state therefore need feature-by-feature reconciliation.

## Reconciliation method
For each changed feature:
1. identify application files;
2. identify required database objects/functions;
3. determine whether the backend behavior is already live;
4. determine whether production UI exposes it;
5. run existing/new regression tests;
6. classify as:
   - production-equivalent;
   - valid newer feature;
   - incomplete/prototype;
   - superseded;
   - duplicate;
   - unresolved;
7. only then promote into the RevOS Compensation target.

## No-cutover rule
The separate Compensation Netlify site and Supabase project remain operational until RevOS Compensation passes full parity and rollback tests.
