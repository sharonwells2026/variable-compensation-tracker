-- DRAFT ONLY. Do not apply until validated against the active database and RLS/access model.
-- Engagifii Variable Compensation Tracker
-- Monthly operational workflow: Sharon/admin review -> Namit approval -> Scott acceptance -> Scott payment confirmation.
-- Product decision: System Administrator has unrestricted application authority. Business workflow assignments do not restrict System Admin.
-- Compensation lifecycle remains distinct: Earned -> Eligible -> Approved -> Paid.

begin;

-- The active schema already contains payroll_batches and payroll_payment_items.
-- Extend those structures rather than creating a duplicate payout subsystem.

alter table public.payroll_batches
  add column if not exists submitted_by uuid references auth.users(id),
  add column if not exists submitted_at timestamptz,
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz,
  add column if not exists finance_accepted_by uuid references auth.users(id),
  add column if not exists finance_accepted_at timestamptz,
  add column if not exists paid_confirmed_by uuid references auth.users(id),
  add column if not exists paid_confirmed_at timestamptz,
  add column if not exists returned_at timestamptz,
  add column if not exists return_reason text,
  add column if not exists submission_snapshot jsonb not null default '{}'::jsonb;

alter table public.payroll_payment_items
  add column if not exists source_snapshot jsonb not null default '{}'::jsonb,
  add column if not exists included boolean not null default true,
  add column if not exists exclusion_reason text;

create table if not exists public.payroll_batch_activity (
  id uuid primary key default gen_random_uuid(),
  payroll_batch_id uuid not null references public.payroll_batches(id) on delete cascade,
  action text not null,
  actor_user_id uuid references auth.users(id),
  from_status text,
  to_status text,
  comment text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint payroll_batch_activity_action_check check (
    action in (
      'created',
      'submitted',
      'approved',
      'returned',
      'accepted_for_payment',
      'payment_confirmed',
      'reopened',
      'cancelled',
      'admin_override'
    )
  )
);

create index if not exists payroll_batch_activity_batch_idx
  on public.payroll_batch_activity(payroll_batch_id, created_at);

comment on table public.payroll_batch_activity is
'Immutable operational history for monthly payout batches. Business flow is administrator submission, executive approval, Finance acceptance, then Finance payment confirmation. System Administrators may perform any action.';

comment on column public.payroll_batches.submission_snapshot is
'Snapshot of the payout batch at submission so later CRM/source changes cannot silently alter what was approved.';

comment on column public.payroll_payment_items.source_snapshot is
'Source facts, plan/rule version, calculation inputs, calculated amount and eligibility evidence captured for audit.';

-- Status contract for payroll_batches.status (text column already exists):
-- draft
-- submitted
-- approved
-- accepted_for_payment
-- paid
-- returned
-- cancelled
--
-- Do not collapse operational status into compensation lifecycle status.
-- An earning becomes Approved only when required authorization is complete.
-- It becomes Paid only after payment is actually confirmed.

-- Current configured business roles:
-- Sharon / System Administrator: may review, submit, approve, return, accept, confirm payment,
--   reopen, correct, configure, reconcile and administer all records.
-- Namit / Executive Approver: approves or returns submitted compensation.
-- Scott / Finance-Payroll: accepts approved compensation for payment and confirms actual payment.
-- These are configuration values, not hardcoded permanent personnel rules.

-- Existing workflow tables should remain authoritative for routing:
-- employee_approval_workflow_versions
-- employee_approval_chains
-- employee_post_approval_steps
-- approval_requests
-- approval_actions
--
-- Recommended configuration:
--   Approval chain: Namit, step type/level = executive approval.
--   Post-approval step 1: Scott, step_type = finance_acceptance, required_for_payment = true.
--   Post-approval step 2: Scott, step_type = payment_confirmation, required_for_payment = true,
--                         requires_payment_details = true.
-- Sharon's System Administrator authority supersedes ordinary routing restrictions.

-- Security requirements before activation:
-- 1. Enable RLS on payroll_batch_activity if exposed through the Data API.
-- 2. Add explicit authenticated grants if the project has automatic Data API exposure disabled.
-- 3. Policies must use effective application permissions/roles, not user-editable user_metadata.
-- 4. UPDATE policies need SELECT + USING + WITH CHECK.
-- 5. Paid history is never silently mutated; corrections create adjustments/activity records.

rollback;
-- DRAFT ONLY: rollback intentionally prevents this repository draft from changing schema when inspected manually.
