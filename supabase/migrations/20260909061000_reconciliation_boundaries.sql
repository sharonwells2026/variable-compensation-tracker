create table if not exists public.reconciliation_boundaries (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  settled_through_date date not null,
  settlement_amount numeric not null check (settlement_amount >= 0),
  settlement_reference text not null,
  settlement_notes text,
  evidence jsonb not null default '{}'::jsonb,
  status text not null default 'confirmed' check (status in ('draft','confirmed','void')),
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(employee_id, settled_through_date, settlement_reference)
);

alter table public.reconciliation_boundaries enable row level security;
revoke all on public.reconciliation_boundaries from anon;
revoke all on public.reconciliation_boundaries from authenticated;
grant select on public.reconciliation_boundaries to authenticated;

drop policy if exists reconciliation_boundaries_select on public.reconciliation_boundaries;
create policy reconciliation_boundaries_select on public.reconciliation_boundaries
for select to authenticated
using (private.has_permission('reconciliation.view') or private.has_app_role('system_administrator'));

insert into private.app_permissions(permission_key,category,display_name,description)
values
 ('reconciliation.view','Reconciliation','View reconciliation','View historical reconciliation records, boundaries, and evidence.'),
 ('reconciliation.manage','Reconciliation','Manage reconciliation','Create, update, confirm, or void historical reconciliation boundaries and actions.')
on conflict (permission_key) do update
set category=excluded.category,display_name=excluded.display_name,description=excluded.description;

insert into private.role_permissions(role_key,permission_key,allowed)
values
 ('system_administrator','reconciliation.view',true),
 ('system_administrator','reconciliation.manage',true),
 ('finance_payroll','reconciliation.view',true),
 ('auditor_read_only','reconciliation.view',true)
on conflict (role_key,permission_key) do update set allowed=excluded.allowed,updated_at=now();

create or replace function private.apply_reconciliation_boundary_to_new_earning()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
declare
  boundary_row public.reconciliation_boundaries%rowtype;
begin
  if new.earning_origin <> 'system_calculated'::public.earning_origin then
    return new;
  end if;

  select b.* into boundary_row
  from public.reconciliation_boundaries b
  where b.employee_id = new.employee_id
    and b.status = 'confirmed'
    and new.earned_date <= b.settled_through_date
  order by b.settled_through_date desc
  limit 1;

  if found then
    new.is_current := false;
    new.reconciliation_status := 'excluded'::public.reconciliation_status;
    new.payment_status := 'not_payable'::public.payment_status;
    new.eligible_amount := 0;
    new.approved_amount := 0;
    new.paid_amount := 0;
    new.historical_reference := boundary_row.settlement_reference;
    new.reconciliation_notes := concat_ws(' ',
      'Automatically excluded from current payable compensation because the earning date is within a confirmed reconciliation boundary.',
      'Settled through ' || boundary_row.settled_through_date::text || '.',
      'Boundary amount ' || to_char(boundary_row.settlement_amount,'FM9999999990.00') || '.'
    );
    new.source_snapshot := coalesce(new.source_snapshot,'{}'::jsonb) || jsonb_build_object(
      'reconciliation_boundary_id', boundary_row.id,
      'reconciliation_boundary_date', boundary_row.settled_through_date,
      'reconciliation_boundary_amount', boundary_row.settlement_amount,
      'reconciliation_boundary_reference', boundary_row.settlement_reference,
      'reconciliation_boundary_applied', true
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_apply_reconciliation_boundary_to_new_earning on public.comp_earnings;
create trigger trg_apply_reconciliation_boundary_to_new_earning
before insert on public.comp_earnings
for each row execute function private.apply_reconciliation_boundary_to_new_earning();

insert into public.reconciliation_boundaries(
 employee_id,settled_through_date,settlement_amount,settlement_reference,settlement_notes,evidence,status
)
select e.id,date '2025-10-29',32964.96,
 'Oct 29, 2025 commission reconciliation true-up',
 'Confirmed reconciliation boundary: the $32,964.96 payment trues up commissions owed through this date; later payments apply to future earnings only.',
 jsonb_build_object(
   'source','Commission Reconciliation Summary and Compensation Plan Review',
   'confirmed_by','Namit Bhatia',
   'confirmation_date','2025-10-29',
   'amount',32964.96,
   'scope','all commissions owed through confirmation date',
   'treatment','boundary only; do not infer transaction-level paid matching without separate evidence'
 ),
 'confirmed'
from public.employees e
where lower(e.email)=lower('sharonwells@engagifii.com')
on conflict (employee_id,settled_through_date,settlement_reference) do nothing;

comment on table public.reconciliation_boundaries is 'Confirmed historical settlement cutoffs used to prevent reconstructed earnings from becoming payable a second time.';
