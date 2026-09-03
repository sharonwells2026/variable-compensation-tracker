# Approval and payment workflow

Status: product decision locked and live draft workflow configuration aligned in Supabase on 2026-09-03.

## Authority model

Sharon Wells is the System Administrator. System Administrator is unrestricted application authority and may administer, review, correct, override, reopen, approve, and operate compensation and payment workflows. The ordinary business workflow does not constrain System Administrator authority.

## Compensation lifecycle

Keep compensation state separate from operational routing:

Earned -> Eligible -> Approved -> Paid

Eligibility, approval, Finance acceptance, and actual payment are distinct facts.

## Business workflow

### Sharon Wells compensation

Sharon prepares/administers -> Namit Bhatia approves -> Scott Key accepts for payment -> Scott Key confirms actual payment.

### Other employee compensation

Employee verifies/submits -> Sharon/System Admin reviews data and amount -> Namit Bhatia approves -> Scott Key accepts for payment -> Scott Key confirms actual payment.

The System Administrator can intervene at any point.

## Current Supabase implementation

Existing structures are reused rather than introducing a second payout subsystem:

- `employee_approval_workflow_versions`: effective-dated workflow definitions
- `employee_approval_chains`: pre-Finance review/approval steps
- `employee_post_approval_steps`: required Finance acceptance handoff
- `approval_requests` / `approval_actions`: approval execution and history
- `payroll_batches`: payment run, scheduled/actual payment dates, reference and status
- `payroll_payment_items`: earnings included in a payment run

Current live draft workflow configuration:

- Wes Morris: Sharon compensation-administrator review -> Namit executive approval -> Scott Finance acceptance
- Sharon Wells: Namit executive approval -> Scott Finance acceptance
- Actual payment confirmation is represented by the payroll batch/payment record, not by a second approval status.

## Payment confirmation rule

Scott's Finance acceptance does **not** mark compensation Paid. Paid occurs only when actual payment is confirmed on the payroll batch/payment record with the actual payment date. Payment confirmation is also retained in audit history; it is not a second user-facing compensation lifecycle state.

## Submission snapshots

When a payout is submitted for approval, preserve the source facts and calculated amount being approved. Subsequent HubSpot changes must not silently rewrite the approved historical obligation. Corrections to paid history are adjustments, not destructive edits.

## UI contract

Management Approval screens should communicate the actual routing rather than the old generic Manager/Executive/Payroll wording.

Target labels:

- Compensation Admin Review
- Pending Namit Approval / Executive Approval
- Approved
- Pending Finance Acceptance
- Accepted for Payment
- Paid
- Returned

Payments should distinguish:

- Approved & eligible
- Accepted for payment
- Scheduled
- Paid
- Returned/held

The user-facing compensation lifecycle remains Earned -> Eligible -> Approved -> Paid.
