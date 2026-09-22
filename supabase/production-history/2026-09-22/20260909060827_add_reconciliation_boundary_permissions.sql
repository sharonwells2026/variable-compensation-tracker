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
