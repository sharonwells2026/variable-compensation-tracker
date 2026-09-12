create table if not exists public.historical_source_catalog (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  document_name text not null,
  source_label text not null,
  source_type text not null default 'workbook_tab',
  page_start integer,
  page_end integer,
  evidence_role text not null default 'reference' check (evidence_role in ('earning_detail','eligibility_detail','approval_detail','payment_detail','summary','scenario','reference')),
  authoritative_for text[] not null default '{}',
  import_status text not null default 'mapped' check (import_status in ('mapped','staged','reviewed','imported','excluded')),
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(employee_id, document_name, source_label)
);

alter table public.historical_comp_records
  add column if not exists source_catalog_id uuid references public.historical_source_catalog(id),
  add column if not exists source_tab_name text,
  add column if not exists source_page_number integer,
  add column if not exists evidence_role text,
  add column if not exists evidence_key text,
  add column if not exists import_disposition text not null default 'staged';

do $$ begin
  alter table public.historical_comp_records add constraint historical_comp_records_evidence_role_check
    check (evidence_role is null or evidence_role in ('earning_detail','eligibility_detail','approval_detail','payment_detail','summary','scenario','reference'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.historical_comp_records add constraint historical_comp_records_import_disposition_check
    check (import_disposition in ('staged','candidate','matched','excluded_duplicate','excluded_summary','needs_review','verified'));
exception when duplicate_object then null; end $$;

create index if not exists idx_historical_source_catalog_employee on public.historical_source_catalog(employee_id, import_status);
create index if not exists idx_historical_comp_records_source_catalog on public.historical_comp_records(source_catalog_id);
create index if not exists idx_historical_comp_records_evidence_key on public.historical_comp_records(employee_id, evidence_key) where evidence_key is not null;

comment on table public.historical_source_catalog is 'Maps workbook tabs/report sections before historical compensation rows are imported. Summary, scenario, payment, and earning-detail sources are classified separately to prevent double counting.';
comment on column public.historical_comp_records.import_disposition is 'Controls whether a historical source row may participate in reconciliation. Summary/scenario rows should be excluded rather than counted as earnings.';

alter table public.historical_source_catalog enable row level security;
revoke all on public.historical_source_catalog from anon, authenticated;
grant all on public.historical_source_catalog to service_role;
