# Compensation -> RevOS UAT, Dual-Run and Rollback Plan — 2026-09-22

## Objective
Move Compensation into RevOS without changing production compensation outcomes until parity is proven.

## Current production anchors
- GitHub repo: `sharonwells2026/variable-compensation-tracker`
- standalone Supabase: `bwdtbsqojtxfbeyfkang`
- RevOS Core Supabase: `lkoigekescagsdjqgrtq`
- current RevOS Compensation route points to the standalone Netlify app
- production Compensation data remains authoritative for compensation-specific financial state until cutover

## Preservation baseline captured 2026-09-22
Structure:
- plans: 6
- plan versions: 7
- components: 23
- rule sets: 16
- employees: 6
- employee plan assignments: 2
- calculations: 8
- earnings rows: 29
- approval requests: 2
- plan agreements: 2
- payroll batches: 1
- payroll payment items: 0
- historical compensation records: 9

Current earning aggregates:
- earned: 3027.30
- eligible: 2074.40
- approved: 92.50
- paid: 0.00

These values are a point-in-time baseline only and must be refreshed before each rehearsal/cutover.

## Environment strategy
Use production HubSpot as the authoritative source for current business facts only where read-only comparison is required.

For destructive/writeback/UAT behavior:
- use the HubSpot UAT sandbox
- use a non-production RevOS/Supabase rehearsal environment or isolated schema/branch
- never point UAT write paths at production HubSpot
- never run payroll/payment mutations against production compensation data for rehearsal

## Rehearsal sequence

### Stage 1 — schema/runtime rehearsal
- create source-controlled target migrations
- apply only to UAT/staging
- verify RLS, grants, functions, triggers and views
- run Supabase advisors
- verify no duplicate HubSpot sync subsystem is introduced

### Stage 2 — data-copy rehearsal
Copy or reconstruct Compensation-owned state with stable source identifiers:
- plans/versions/components
- rules
- employees/assignments/books
- approvals/agreements
- credits/calculations/earnings
- payroll structures
- disputes/corrections
- historical/audit records

Do not rewrite historical IDs or lifecycle relationships without a documented mapping.

### Stage 3 — HubSpot fact binding
Bind target Compensation logic to RevOS Core HubSpot read models.
Validate active field dependencies, attribution fields, pipelines, stages, deal types and meeting/QDC evidence.

### Stage 4 — behavioral parity
For the same controlled fixture set compare source vs target:
- deal candidate qualification
- QDC candidate qualification
- attribution/credit ownership
- amount basis
- rule evaluation
- aggregate attainment
- earned amount
- eligibility
- approval readiness
- agreement requirements
- payroll readiness
- correction/reversal behavior
- reports/reconciliation

Every mismatch receives a disposition:
- expected intentional change
- source bug
- target bug
- data-shape mismatch
- unresolved/no-go

### Stage 5 — permission parity
Run both allow and deny scenarios for every sensitive action.

### Stage 6 — dual run
Run standalone Compensation and RevOS Compensation in parallel against equivalent HubSpot facts.

Rules:
- only one side may be authoritative for financial writes
- do not double-create earnings
- do not double-approve
- do not double-schedule payroll
- do not double-record payment
- target results remain comparison-only until go-live approval

## Cutover prerequisites
All must be true:
- migration/schema parity complete
- function/trigger behavior covered
- row/key parity complete
- financial aggregate parity complete
- per-employee/per-component restricted parity complete
- historical chains preserved
- HubSpot field dependencies satisfied through Core
- permissions/negative-path tests pass
- UAT signoff complete
- final production baseline captured
- backup/export captured
- rollback steps tested
- explicit go/no-go approval

## Rollback model
Rollback must be route/runtime based, not data deletion based.

If cutover fails:
1. disable native Compensation writes
2. restore RevOS Compensation route to the standalone app
3. keep standalone Compensation Supabase intact
4. reconcile any writes made during the cutover window
5. do not delete target data until reconciliation concludes
6. retain audit evidence from the failed cutover
7. correct and rehearse again

## No-retirement rule
The standalone Compensation app/database must remain available through the rollback window.

Do not:
- delete the standalone database
- archive the repo
- remove production migration history
- purge historical compensation data
- disable old read access
until final reconciliation and rollback-window signoff.

## Next implementation gate
After the dependency maps are complete, the next safe code change is a source-controlled UAT-only target migration design for the Compensation namespace/domain inside RevOS Core. No production apply is authorized by this document.
