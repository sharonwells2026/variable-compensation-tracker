# Compensation Feature Parity Matrix — Phase 1

Legend:
- PROD = present in deployed production main/runtime
- BRANCH = newer work on plan-builder-v2
- TARGET = required in native RevOS Compensation
- VERIFY = behavior must be compared before cutover

| Capability | Current production | plan-builder-v2 | RevOS target | Status |
|---|---|---|---|---|
| Dashboard / personal plan | PROD | retained | Native RevOS | VERIFY |
| Plans list/create | PROD | enhanced | Native RevOS | VERIFY |
| Plan versions | PROD | enhanced | Native RevOS | VERIFY |
| Components | PROD | enhanced | Native RevOS | VERIFY |
| Deal qualification/rules | PROD | enhanced | Native RevOS | VERIFY |
| Aggregate attainment | backend partly live | UI + newer migrations | Native RevOS | HIGH PRIORITY VERIFY |
| Plan applicability | PROD | enhanced | Native RevOS | VERIFY |
| Plan approval config | PROD | enhanced | Native RevOS | VERIFY |
| Plan agreements | PROD | enhanced | Native RevOS | VERIFY |
| Earnings | PROD | retained | Native RevOS | VERIFY |
| Credits/reviews | PROD | retained | Native RevOS | VERIFY |
| Corrections | PROD | retained | Native RevOS | VERIFY |
| Approval workflow | PROD | retained | Native RevOS | VERIFY |
| Finance/payments | PROD | retained | Native RevOS | VERIFY |
| Payroll | backend exists | dedicated page added | Native RevOS | HIGH PRIORITY VERIFY |
| Reconciliation | PROD | enhanced | Native RevOS | VERIFY |
| Reports | limited/other views | dedicated reports page | Native RevOS | BRANCH REVIEW |
| Payment-condition mapping | component page exists | settings page added | Native RevOS | BRANCH REVIEW |
| Employee administration | PROD | retained | Native RevOS | VERIFY |
| User administration | PROD | retained | Shared RevOS + comp scopes | VERIFY |
| HubSpot integration admin | PROD | branch still references local sync | Shared RevOS integration | REDESIGN TRANSPORT, PRESERVE SEMANTICS |
| Audit | PROD | retained | Shared + module audit | VERIFY |

## Production route baseline
Production main exposes:
- /attention
- /audit
- /corrections
- /credits
- /earnings
- /employees
- /executive
- /finance
- /hubspot
- /manage
- /me
- /payments
- /plans and nested plan-builder routes
- /reconciliation
- /settings and HubSpot/settings routes
- /submissions
- /users
- /workflow

## New route surfaces on plan-builder-v2
- /payroll
- /plans/component/[componentId]/aggregate
- /plans/manage/[versionId]/review
- /reports
- /settings/payment-condition-mapping

These are not automatically approved for production merely because they are newer. They require dependency and regression review.

## Exit criteria for Phase 1
Every matrix row receives:
- source commit(s);
- database dependencies;
- test coverage;
- production behavior reference;
- target RevOS disposition;
- parity result;
- rollback note.
