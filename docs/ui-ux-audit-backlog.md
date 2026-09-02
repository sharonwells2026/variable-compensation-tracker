# Variable Compensation Tracker — UI/UX Audit Backlog

This backlog tracks structural, workflow, navigation, and usability findings while the application is migrated to the unified My Compensation / Team / Administration experience.

## P0 — Structural / workflow blockers

- [ ] **Retire duplicate application shells.** The legacy root application still owns a parallel sidebar, header, workspace switcher, and screen navigation while newer Administration routes use `AdminShell`.
- [ ] **Make root navigation URL-aware.** Legacy root screens do not yet reliably hydrate `workspace` and `screen` from query parameters, so Administration links that target root pseudo-screens can land in the wrong state.
- [x] **Dedicated Administration Overview route.** Overview now opens `/admin-overview` instead of routing through the legacy root Administration pseudo-screen.
- [x] **Dedicated Plans & Programs route.** Administration plan navigation now opens `/plans`.
- [x] **Dedicated Earnings & Credits route.** Administration earnings navigation now opens `/earnings`, backed by a permission- and employee-scope-aware read RPC.
- [x] **Dedicated Data & Integrations route.** Administration integration navigation now opens `/data-integrations`.
- [x] **Dedicated Reconciliation route.** Administration reconciliation navigation now opens `/reconciliation`.
- [x] **Dedicated Audit & Activity route.** Administration audit navigation now opens `/audit-activity`, backed by a permission- and employee-scope-aware audit feed RPC.
- [x] **Fix Approval Workflow finance requirement field.** UI now reads backend `is_required_for_payment` rather than the obsolete `is_required` field.
- [x] **Fix Approval Workflow activation readiness count.** UI now reads backend `unresolved_assignee_count` after readiness checks.
- [x] **Fix Approval Workflow history ordering field.** UI now displays `approval_order` returned by the backend.
- [x] **Route Payroll to real finance queue.** Administration Payroll now opens `/payroll`, backed by `get_my_comp_earning_handoff_tasks` and `act_on_comp_earning_handoff`.
- [ ] **Complete Approval Workflows shell migration.** Remove its route-local header/back navigation and render it fully inside the shared Administration shell.

## P1 — Core administration UX

- [x] Visible account menu and Log Out in shared Administration shell.
- [x] People & Access promoted to first-class Administration destination.
- [x] Add Employee routes to the draft-first employee/user provisioning flow.
- [x] Settings split from operational administration and given secondary navigation.
- [x] Employee and Application User remain distinct concepts in People & Access / provisioning.
- [x] Administration navigation filtered by effective permissions.
- [x] Safe View-as-User permission (`users.preview_as`) established in backend.
- [x] Harden new secure read RPCs and View-as-User RPCs against anonymous execution; authenticated callers remain permission-checked inside the functions.
- [ ] Implement persistent read-only View-as-User UI with banner and Return to my account.
- [ ] Add explicit permission-denied state for direct navigation to restricted Administration routes.
- [ ] Normalize loading, empty, warning, error, and success states across all Administration pages.
- [ ] Replace technical provisioning language where a business-friendly label can communicate the same state without hiding the underlying controls.

## P1 — Finance / payroll

- [x] Assigned finance handoff queue exists and records acknowledgement/payment information separately from payment.
- [ ] Add finance queue filters: pending/completed, employee, pay period, aging, and exception state.
- [ ] Add payroll-ready earnings view distinct from assigned handoff tasks.
- [ ] Add payroll batch creation UI using `create_comp_payroll_batch`.
- [ ] Add eligible earning selection and batch assignment using `add_comp_earning_to_payroll_batch`.
- [ ] Add schedule/lock workflow using `schedule_comp_payroll_batch`.
- [ ] Add mark-paid workflow using `mark_comp_payroll_batch_paid`, including actual date/reference/method.
- [ ] Show partial-payment and remaining approved balance clearly.
- [ ] Provide batch history and audit trail.

## P1 — Employee / manager mental models

- [ ] **My Compensation:** Dashboard, plan, earnings, submissions, payment/status history, statements, disputes/corrections.
- [ ] **Team:** scoped dashboard, employee list, approvals, exceptions, attainment, upcoming liabilities.
- [ ] **Administration:** People & Access, Plans & Programs, Earnings & Credits, Approval Workflows, Payroll, Data & Integrations, Reconciliation, Reports & Analytics, Audit & Activity, Settings.
- [ ] Ensure employees never see irrelevant admin navigation.
- [ ] Ensure managers see only scoped employees/data unless explicitly granted broader permissions.
- [ ] Ensure Finance sees finance/payroll work without requiring a personal compensation plan.
- [ ] Ensure Executive Admin can view company-wide reporting and optional review work without inheriting System Admin automatically.
- [ ] Ensure Auditor/Read-only has complete historical visibility but no transactional controls.

## P2 — Global product experience

- [ ] Global search across employees, earnings, plans, deals, batches, and audit events.
- [ ] Notification center with unread state, deep links, and configurable delivery.
- [ ] AI assistant with model selection, permission-aware context, meeting use, and auditable write proposals.
- [ ] Help/knowledge experience appropriate to current role and screen.
- [ ] Responsive/mobile QA for all primary workflows.
- [ ] Accessibility audit: keyboard navigation, focus management, semantic labels, contrast, tables/drawers, validation announcements.
- [ ] Consistent status vocabulary and badge semantics across Employee, Manager, Finance, and Admin views.

## Visual QA findings currently tracked

- [x] Legacy global `aside` styling leaked into People & Access and distorted the layout; shared Admin shell now isolates its sidebar/content.
- [x] Reports descriptive content was overly compressed; reporting model/readiness/library now use clearer grouped structures.
- [x] Settings secondary navigation was vulnerable to legacy fixed-aside behavior; scoped sticky/static behavior added.
- [ ] Recheck People & Access directory width, table overflow, drawer behavior, and responsive states in branch deploy.
- [ ] Recheck Settings density and section hierarchy in branch deploy.
- [ ] Recheck Reports spacing and report-library cards in branch deploy.
- [ ] Recheck Administration Overview summary density and route cards in branch deploy.
- [ ] Recheck Earnings & Credits table density, horizontal overflow, filters, and mobile strategy in branch deploy.
- [ ] Recheck Audit & Activity event density, details disclosure, long JSON snapshots, and mobile behavior in branch deploy.
- [ ] Recheck Approval Workflows after shell migration, especially employee selector, workflow editor density, and mobile stacking.
- [ ] Recheck Netlify toolbar overlap separately from application layout; do not treat Netlify overlay as product UI.

## Security / platform findings

- [ ] Review Supabase advisor warning set before launch. Many operational tables intentionally use RLS with no direct client policies because access is mediated through permission-checked SECURITY DEFINER RPCs; document this architecture rather than adding broad policies blindly.
- [ ] Review remaining SECURITY DEFINER execute grants before launch. Signed-in execution is intentional only where the function itself validates permissions/scope; anonymous execution should remain revoked for privileged RPCs.
- [ ] Enable Supabase leaked-password protection before production launch unless Engagifii security policy explicitly chooses another control.
- [ ] Address mutable search path warning on `public.set_updated_at` before production launch.

## Launch-readiness checks

- [ ] Role-by-role UAT: Employee, Management Approver, Finance/Payroll, Plan Administrator, Executive Administrator, Auditor/Read-only, System Administrator.
- [ ] End-to-end workflow UAT: provision employee → assign plan → configure workflow → calculate/earn → submit → approve → finance acknowledge → payroll schedule → paid → report/audit.
- [ ] Authentication/invitation/password-reset redirect verification on production hostname.
- [ ] Permission and scope negative tests (users cannot see or mutate data outside scope).
- [ ] Compensation calculation reconciliation against known manual examples.
- [ ] Payment/partial-payment/duplicate-payment prevention tests.
- [ ] Audit-event coverage for configuration, access, approvals, finance, payroll, overrides, and AI-assisted changes.
- [ ] Production backup/recovery and rollback plan.
- [ ] Final responsive and accessibility QA.
