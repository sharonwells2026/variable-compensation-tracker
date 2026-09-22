# Compensation → RevOS Migration Master Plan

## Objective
Move Variable Compensation into RevOS as a native module while preserving all mature business logic, history and financial controls.

HubSpot remains authoritative for CRM/business facts. RevOS Core becomes the shared runtime/integration platform. Compensation remains the owner of compensation configuration, calculation, earning, approval, settlement and historical logic.

## Phase 0 — Preservation (IN PROGRESS)
- Preserve all live migration SQL.
- Inventory production schema, functions, triggers and views.
- Record production GitHub/Netlify/Supabase versions.
- Preserve branch-only work.
- Make no destructive changes.

Exit criteria:
- every one of the 180 live migrations represented in source-control history;
- production application commit recorded;
- schema inventory recorded.

## Phase 1 — Source reconciliation
Reconcile:
- production DB;
- GitHub `main`;
- `plan-builder-v2`;
- other active/divergent branches;
- current Netlify runtime.

Deliverable: feature/behavior ledger with production status and target disposition.

## Phase 2 — Target architecture mapping
For every Compensation domain classify:
- HubSpot-authoritative fact;
- HubSpot synchronized read model;
- RevOS/Compensation configuration;
- derived/live analytics;
- historical snapshot/audit;
- Compensation financial ledger/business outcome;
- technical/integration state;
- legacy/duplicate/unclear.

Key rule: Compensation's separate HubSpot ingestion tables are transitional. Target state consumes the shared RevOS Core HubSpot integration/read models, while retaining Compensation-specific mapping/rule semantics where required.

## Phase 3 — Native RevOS module shell
Move UX into the shared RevOS shell:
- shared auth;
- shared module navigation;
- shared granular permissions;
- Compensation-specific screens/workflows preserved;
- no data cutover yet.

## Phase 4 — Backend rehearsal
Create source-controlled target migrations for RevOS Core.
Run in UAT/staging only.
Migrate or reconstruct:
- plans and versions;
- components/rules;
- employees/assignments/books;
- credits/calculations;
- earnings;
- approvals;
- agreements;
- payroll;
- disputes/corrections;
- history/audit.

No production cutover.

## Phase 5 — Behavioral parity
For a controlled historical fixture set, compare old vs target:
- candidate qualification;
- QDC attribution;
- deal attribution;
- rule evaluation;
- credits;
- aggregate attainment;
- earnings;
- approval readiness;
- payroll eligibility;
- agreements;
- corrections;
- reports/reconciliation.

Every mismatch is explained and dispositioned.

## Phase 6 — Dual run
Run current Compensation and RevOS Compensation in parallel against equivalent HubSpot facts.
Do not allow double writeback or double settlement.

## Phase 7 — Controlled cutover
Prerequisites:
- row-count/key parity;
- financial amount parity;
- behavioral parity;
- UAT approval;
- backup;
- rollback;
- production migration rehearsal;
- explicit go/no-go.

Only then:
- switch RevOS module route from external to native;
- move runtime ownership to RevOS Core;
- retain old system read-only for rollback period.

## Phase 8 — Retirement
Archive only after the rollback window and reconciliation signoff.
Never delete historical Compensation data as a cleanup shortcut.

## Required parity domains
- Plans
- Versions
- Components
- Rules and nested conditions
- Books of business
- QDC attribution
- Deal/new-logo attribution
- Credits
- Calculations
- Earnings
- Earning lifecycle
- Approvals
- Agreements
- Payroll
- Disputes
- Corrections
- Reconciliation
- Reporting
- Historical records
- Permissions
- Audit
