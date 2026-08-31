-- 102A Employee Approval Workflow Configuration Engine
-- Installed and verified in production on 2026-08-31.
-- Canonical migration record for effective-dated named employee approval workflows.

create table if not exists public.employee_approval_workflow_versions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  workflow_name text not null,
  effective_start_date date not null,
  effective_end_date date,
  status text not null default 'active',
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_approval_workflow_versions_name_check check (nullif(trim(workflow_name), '') is not null),
  constraint employee_approval_workflow_versions_date_check check (effective_end_date is null or effective_end_date >= effective_start_date),
  constraint employee_approval_workflow_versions_status_check check (status in ('draft','active','ended','cancelled'))
);

create index if not exists employee_approval_workflow_versions_employee_dates_idx
on public.employee_approval_workflow_versions (employee_id,effective_start_date,effective_end_date);

alter table public.employee_approval_chains
  add column if not exists workflow_version_id uuid,
  add column if not exists step_name text,
  add column if not exists conditions jsonb not null default '{}'::jsonb;

create index if not exists employee_approval_chains_workflow_order_idx
on public.employee_approval_chains (workflow_version_id,approval_order);

-- Production canonical functions installed by 102A:
-- private.validate_employee_approval_workflow_version()
-- private.user_has_permission(uuid,text)
-- private.validate_employee_approval_chain()
-- public.create_employee_approval_workflow(uuid,text,date,date,jsonb,text)
-- public.end_employee_approval_workflow(uuid,date)
-- public.get_employee_approval_workflows(uuid)
-- public.preview_employee_approval_workflow(uuid,date)
--
-- V1 intentionally rejects non-empty conditions JSON until conditional
-- routing is implemented by the runtime engine.
