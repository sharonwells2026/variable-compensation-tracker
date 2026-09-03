-- DRAFT ONLY. Do not apply to production until the current schema is validated.
-- Engagifii Variable Compensation Tracker
-- Monthly payout workflow: Sharon review/submission -> Namit approval -> Scott acceptance -> Scott payment confirmation.
-- Product decision: System Administrator is unrestricted application authority. Business workflow steps do not limit System Admin authority.

begin;

-- Keep operational workflow separate from the compensation lifecycle.
-- Compensation lifecycle remains Earned -> Eligible -> Approved -> Paid.
do $$ begin
  create type public.payout_batch_status as enum (
    'draft',
    'submitted',
    'approved',
    'accepted_for_payment',
    'paid',
    'returned',
    'cancelled'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.payout_action_type as enum (
    'created',
    'submitted',
    'approved',
    'returned',
    'accepted_for_payment',
    'payment_confirmed',
    'reopened',
    'cancelled',
    'admin_override'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.payout_batches (
  id uuid primary key default gen_random_uuid(),
  period_start date not null,
  period_end date not null,
  label text not null,
  status public.payout_batch_status not null default 'draft',
  prepared_by uuid references auth.users(id),
  submitted_by uuid references auth.users(id),
  submitted_at timestamptz,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  finance_accepted_by uuid references auth.users(id),
  finance_accepted_at timestamptz,
  paid_confirmed_by uuid references auth.users(id),
  paid_confirmed_at timestamptz,
  payment_date date,
  payment_reference text,
  returned_at timestamptz,
  return_reason text,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payout_batch_period_valid check (period_end >= period_start)
);

create table if not exists public.payout_batch_items (
  id uuid primary key default gen_random_uuid(),
  payout_batch_id uuid not null references public.payout_batches(id) on delete cascade,
  employee_id uuid,
  earning_id uuid,
  amount numeric(14,2) not null,
  earning_status text,
  eligibility_status text,
  approval_status text,
  payment_status text,
  source_snapshot jsonb not null default '{}'::jsonb,
  included boolean not null default true,
  exclusion_reason text,
  created_at timestamptz not null default now(),
  unique (payout_batch_id, earning_id)
);

create table if not exists public.payout_batch_activity (
  id uuid primary key default gen_random_uuid(),
  payout_batch_id uuid not null references public.payout_batches(id) on delete cascade,
  action public.payout_action_type not null,
  actor_user_id uuid references auth.users(id),
  from_status public.payout_batch_status,
  to_status public.payout_batch_status,
  comment text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists payout_batches_status_idx on public.payout_batches(status);
create index if not exists payout_batches_period_idx on public.payout_batches(period_start, period_end);
create index if not exists payout_batch_items_batch_idx on public.payout_batch_items(payout_batch_id);
create index if not exists payout_batch_activity_batch_idx on public.payout_batch_activity(payout_batch_id, created_at);

-- Application-level workflow contract.
comment on table public.payout_batches is
'Monthly compensation payout batches. Operational workflow is Sharon/admin review -> Namit approval -> Scott Finance acceptance -> Scott payment confirmation. System administrators retain unrestricted authority.';
comment on column public.payout_batches.snapshot is
'Immutable-at-submission representation of the proposed payout so later HubSpot changes cannot silently alter what was approved.';
comment on column public.payout_batch_items.source_snapshot is
'Source facts, plan/rule version, formula inputs, calculated amount, eligibility evidence and other lineage captured for audit.';

-- This migration intentionally does not guess the existing roles/permissions table names.
-- When activated, the access migration must map system_administrator to every application permission,
-- including compensation review, approval, return, adjustment, payout acceptance, payment confirmation,
-- reopening, reconciliation, configuration, integration, and audit actions.
-- Namit and Scott receive only their business-role permissions; Sharon's System Admin authority supersedes workflow restrictions.

-- Transition contract for the UI/RPC layer:
-- draft -> submitted: compensation administrator/System Admin
-- submitted -> approved: executive approver (currently Namit) OR System Admin
-- submitted/approved -> returned: current business owner OR System Admin, reason required
-- approved -> accepted_for_payment: Finance (currently Scott) OR System Admin
-- accepted_for_payment -> paid: Finance (currently Scott) OR System Admin; payment_date required
-- any non-paid state -> reopened/corrected as permitted; paid history is never silently mutated
-- paid corrections create adjustments and preserve the original payment/activity record.

rollback;
-- DRAFT ONLY: rollback keeps this file safe to inspect in SQL tooling without applying schema changes.
