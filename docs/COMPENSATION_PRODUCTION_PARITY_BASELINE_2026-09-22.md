# Compensation Production Parity Baseline — 2026-09-22

This is an aggregate preservation baseline for migration validation. It intentionally avoids per-person detail.

## Structure counts
- Plans: 6
- Plan versions: 7
- Components: 23
- Rule sets: 16
- Employees: 6
- Employee plan assignments: 2
- Calculations: 8
- Earnings rows: 29
- Approval requests: 2
- Plan agreements: 2
- Payroll batches: 1
- Payroll payment items: 0
- Historical compensation records: 9

## Current earning aggregates
For `comp_earnings where is_current = true`:
- Earned amount: 3027.30
- Eligible amount: 2074.40
- Approved amount: 92.50
- Paid amount: 0.00

Payroll payment-item total:
- Paid amount: 0.00

## Use
Before RevOS cutover, target data must reconcile to the source at:
1. primary-key/record level;
2. lifecycle-state level;
3. financial total level;
4. per-employee/per-component detail in a restricted validation process;
5. historical supersession/correction chains.

These values are a point-in-time baseline only and will change while production Compensation remains active. A fresh frozen baseline must be captured immediately before migration rehearsal and again before production cutover.
