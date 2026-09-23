# Compensation -> RevOS Identity, Permission and Authorization Mapping — 2026-09-22

## Purpose
Define how Compensation enters the shared RevOS shell without weakening or replacing Compensation's mature authorization controls.

## Current state

### Compensation
The standalone application has its own:
- Supabase Auth linkage through `profiles`
- employee identity linkage
- management/org scope concepts
- access-control administration RPCs
- permission overrides/custom-role behavior
- employee/user preview behavior
- effective-dated employee approval/workflow structures
- audit events

Business-critical authorization functions include:
- `get_current_user_access`
- `get_access_control_admin_data`
- `admin_set_user_role`
- `admin_set_user_permission_override`
- `begin_user_preview`
- `end_user_preview`
- `get_user_preview_targets`

### RevOS Core
RevOS Core already contains:
- `revos_modules`
- `revos_roles`
- `revos_permissions`
- `revos_role_permissions`
- `revos_user_permissions`
- `revos_module_roles`
- `revos_module_role_permissions`
- `revos_user_module_access`
- `revos_user_module_permissions`

The Compensation module is already registered as:
- module key: `compensation`
- label: Variable Compensation
- current route: external Netlify Compensation app
- status: existing external
- architecture locked: true

Important current gap:
- no Compensation-specific `revos_module_roles` are configured yet
- no Compensation-specific `revos_module_role_permissions` are configured yet

## Target model

### Shared RevOS responsibility
RevOS should own:
- primary application identity/session
- whether a user may enter the Compensation module
- module-level role assignment
- shared navigation visibility
- shared global/admin access boundaries
- common audit context for cross-module activity

### Compensation responsibility
Compensation must continue to own/enforce:
- who may view another employee's compensation
- finance/payment actions
- approval actions
- plan creation/edit/approval/activation
- earning correction/dispute actions
- payroll actions
- employee/management scope
- preview-as-user restrictions
- plan/earning historical immutability
- any field/action-level restriction required for compensation privacy or financial control

## Preservation rule
Do not replace Compensation's granular authorization model with broad RevOS roles.

Initial native RevOS Compensation should use layered authorization:
1. RevOS module access answers whether the user can enter Compensation.
2. Compensation authorization answers what the user can see/do inside it.
3. Only after parity is proven may selected controls be consolidated into shared RevOS permission primitives.

## Identity reconciliation
Before moving runtime ownership:
- map each durable Compensation profile to the corresponding RevOS authenticated user
- preserve `employee_id` linkage
- preserve active/deactivated state
- preserve employee hierarchy/manager scope
- preserve HubSpot owner IDs used for attribution
- do not treat employee records as replaceable authentication records

## Permission migration sequence
1. Inventory every Compensation UI/action and the RPC/RLS permission that protects it.
2. Group permissions by business capability rather than by page.
3. Create Compensation module-role candidates in RevOS only after the underlying Compensation controls are known.
4. Map shared RevOS module roles to existing Compensation scopes.
5. Keep Compensation's RPC/RLS checks authoritative during rehearsal and dual run.
6. Verify denied actions as well as allowed actions.
7. Preserve user preview as read-only/controlled behavior.
8. Preserve audit of privilege changes.

## Required permission domains
At minimum, parity must cover:
- self compensation view
- team/manager compensation view
- executive aggregate view
- plan administration
- plan approval/activation
- earnings review
- credit review
- correction/dispute handling
- finance acceptance
- payroll batch management
- payment recording
- reports/export
- HubSpot compensation mapping
- employee administration
- user/role administration
- audit access
- user preview

## UAT rule
Permission testing must include negative-path cases:
- employee cannot view another employee without scope
- manager scope does not leak outside assigned hierarchy
- finance cannot silently gain plan-admin rights
- plan admin cannot record payment unless separately authorized
- preview mode cannot perform privileged writes
- deactivated users cannot retain active access through stale session state
- module access alone does not grant sensitive Compensation actions

## Cutover gate
The external Compensation route must not be switched to native RevOS until:
- identity mapping is complete
- all permission domains have test cases
- negative-path tests pass
- Compensation RLS/RPC authorization remains enforced
- audit records are preserved
- rollback can restore the external route without changing compensation data
