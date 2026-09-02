# Compensation Tracker UI/UX Audit Backlog

This is the running product-design backlog for the Compensation Tracker. The governing principle is to preserve compensation logic, controls, auditability, permissions, and effective-dated history while making the application feel simple by organizing it around user jobs rather than database concepts.

## Approved information architecture direction

### My Compensation
- Overview
- My Plan
- Earnings
- Submissions & Approvals
- Payments & Statements

### Team
- Overview
- People
- Earnings
- Approvals
- Exceptions

### Administration
- Overview
- People & Access
- Plans & Programs
- Earnings & Credits
- Approval Workflows
- Payroll
- Data & Integrations
- Reconciliation
- Reports & Analytics
- Audit & Activity
- Settings

### Settings secondary navigation
- Organization
- Roles & Permissions
- Employee / Data Scope
- Payroll Configuration
- Notifications
- Calendars & Periods
- Security & Domains
- Data Governance & Retention
- Appearance
- Personal Preferences (when appropriate for the signed-in user)

### Global application utilities
- Global search
- Notification center
- AI/copilot entry point
- Workspace switcher (My / Team / Administration, permission-dependent)
- Account/profile menu
- Help

## User mental models

### Employee
Understand what I can earn, what I have earned, why, what is eligible, what is waiting, what was paid, and what action I need to take.

### Manager / Approver
Understand assigned people and approvals, validate data and amounts, resolve exceptions, and act without receiving unrelated administration privileges.

### Finance / Payroll
Understand approved and payable earnings, acknowledge handoffs, capture payment information, schedule/process payment, correct payment records, and preserve an auditable history.

### Plan Administrator
Design, version, validate, assign, and maintain compensation plans/programs without receiving system/security administration by default.

### Executive Administrator
See broad compensation performance, reporting, approvals/reviews, risk, and company-level information without automatically receiving system/security administration.

### System Administrator
Manage people/access, roles/permissions, scopes, organization configuration, integrations, security, governance, and system configuration.

## Employee vs Application User

An Employee is the business/person record. An Application User is access to the software. They must remain distinct.

Employee records may exist without application access. Application access is invitation-only and can include multiple roles, explicit permission overrides, and data/employee scope. UI should explain this as `Employee record` and `App access`, not expose auth implementation details unnecessarily.

## Provisioning workflow

People & Access should provide one coherent setup experience:
1. Employee identity and employment details
2. Manager/reporting relationship
3. Organization/business unit
4. Compensation participation
5. Application access decision
6. Role(s)
7. Employee/data scope
8. Explicit permission overrides (exception path, not default path)
9. Compensation plan assignment when applicable
10. Approval workflow/readiness when applicable
11. Notification defaults
12. Review readiness and unresolved dependencies
13. Prepare/send invitation
14. Activation status

The invitation remains the boundary between pre-invite configuration and an active application user.

## View-as-user design

View-as-user is a safe preview, never transactional impersonation.
- Persistent banner: `Viewing as <employee>`
- Obvious `Return to my account`
- Preview uses target user's effective navigation/data visibility
- Mutating actions disabled while previewing
- Entry/exit should be auditable
- Do not grant to every manager
- Recommended control: a dedicated `users.preview_as` permission, assigned by default only to System Administrator (and optionally explicit Executive/Admin overrides where justified)

## Audit backlog

### P0 — broken or misleading workflows
- [ ] Add Employee currently routes into the wrong conceptual area; route to People & Access provisioning.
- [ ] User provisioning is buried at the top of Settings; move it to People & Access.
- [ ] Existing standalone Employee Administration, User Administration, and Approval Workflow routes are not integrated into one coherent Administration shell.
- [ ] Some controls navigate to generic `/` rather than the intended object/workflow (for example Manage compensation plan from employee administration).
- [ ] Verify every visible CTA completes its stated workflow; remove no functionality, but eliminate dead-end/misleading navigation.

### P1 — application shell / navigation
- [ ] Add account/profile menu with identity, role/workspace context, preferences, and Log Out.
- [ ] Add permission-controlled safe View-as-user preview.
- [ ] Replace monolithic hard-coded navigation with permission-aware My / Team / Administration information architecture.
- [ ] Move Help to global utility rather than Administration.
- [ ] Add global search.
- [ ] Add notification center.
- [ ] Add AI/copilot entry point and future model selector architecture.
- [ ] Keep workspace switching persistent and understandable.
- [ ] Ensure irrelevant administration destinations are absent, not merely disabled, for users without permission.

### P1 — Settings redesign
- [ ] Replace one long Settings page with secondary navigation and task-focused pages.
- [ ] Separate personal preferences from organization/system administration.
- [ ] Move roles/permissions/scope management into coherent access administration while retaining appropriate Settings entry points.
- [ ] Move HubSpot from a generic sidebar item into Data & Integrations.
- [ ] Organize calendars, periods, deadlines, payroll config, domains/security, audit retention, notification defaults, and appearance under clear settings sections.

### P1 — People & Access
- [ ] Unified employee directory with employee-record status, app-access status, compensation participation, plan readiness, workflow readiness, and invitation status.
- [ ] Employee detail should link to the exact plan, approval workflow, earnings, payments, access configuration, and audit history for that employee.
- [ ] Clearly support employees who never need app access and app users who have operational roles without personal compensation.
- [ ] Manager/reporting and organization hierarchy need first-class editing and history-safe behavior.
- [ ] Invitation workflow needs review/readiness step before send.

### P1 — compensation administration
- [ ] Plans & Programs needs lifecycle/versioning, assignment, effective dating, component rules, eligibility, targets/milestones, validation, and impact visibility.
- [ ] Earnings & Credits needs calculation lineage/explainability, adjustments, holds, eligibility, ownership/credit, exceptions, and audit history.
- [ ] Approval Workflows belongs in Administration and should expose required approvals separately from post-approval finance/executive handoffs.
- [ ] Payroll needs a purpose-built finance work queue, payment acknowledgment/details, schedules, holds/corrections, exports/statements, and payment history.
- [ ] Reconciliation should be exception-oriented rather than a generic data dump.

### P1 — dashboards and meetings
- [ ] Role-specific overview dashboards should answer `what changed`, `what needs attention`, `what is at risk`, and `what action is next`.
- [ ] Executive/company reporting should support employee, business line, plan/program, period, earning type, status, and source dimensions.
- [ ] Meeting mode should support saved views, drill-down, annotations/actions, and AI summaries without modifying source data unless explicitly confirmed.

### P2 — layout and interaction quality
- [ ] Replace very long mixed-purpose pages with task-based pages, tabs, drawers, and progressive disclosure.
- [ ] Normalize page headers, action placement, filters, tables, drawers, empty states, warnings, and readiness states.
- [ ] Reduce excessive whitespace while preserving scanability.
- [ ] Improve responsive/mobile behavior for employee and approval workflows.
- [ ] Establish consistent terminology across Earned / Eligible / Approved / Ready for Payroll / Paid.
- [ ] Add contextual explanations for calculations and status transitions.

## Backend capability / UI gap checks
- [ ] Pre-invite provisioning backend exists; ensure full usable UI path through invitation preparation and activation.
- [ ] Roles, permissions, overrides, and employee/data scope need dedicated usable administration UI rather than informational text only.
- [ ] Effective-dated approval workflow engine exists; integrate it into employee/admin navigation and readiness.
- [ ] Post-approval handoff tasks exist; surface required Finance and optional Executive work queues.
- [ ] Notification types/preferences exist; add notification center and distinguish in-app from queued/delivered email state.
- [ ] Audit capability exists; make object-level history discoverable in addition to global Audit & Activity.
- [ ] HubSpot refresh/reconciliation capabilities exist; reorganize under Data & Integrations and operational exception workflows.

## AI architecture requirement
AI is a cross-application capability, not a single page. It should eventually support:
- explain an earning/calculation in plain language
- summarize employee/team/company compensation performance
- meeting preparation and live drill-down assistance
- identify anomalies and reconciliation candidates
- draft descriptions/administrative notes with human confirmation
- answer questions over authorized compensation data
- recommend next actions without silently executing them
- configurable model/provider selection for authorized users
- task-specific model defaults with governance, audit, cost, and data-access controls

AI must respect the same permissions and employee/data scope as the signed-in user (or safe preview target), and mutating actions require explicit confirmation and normal authorization.
