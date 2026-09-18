-- Reconciliation boundaries are review boundaries, not automatic exclusions.
-- Historical system-calculated earnings remain visible with their calculated earned amount,
-- but are held and non-payable until finance/admin classifies the difference.

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
    new.is_current := true;
    new.reconciliation_status := 'needs_information'::public.reconciliation_status;
    new.payment_status := 'held'::public.payment_status;
    new.eligibility_status := 'pending_condition'::public.eligibility_status;
    new.eligible_date := null;
    new.eligible_amount := 0;
    new.approved_amount := 0;
    new.paid_amount := 0;
    new.hold_reason := 'Historical earning falls within a confirmed reconciliation boundary. Review as underpayment, overpayment, or covered by prior settlement / ignore.';
    new.historical_reference := boundary_row.settlement_reference;
    new.reconciliation_notes := concat_ws(' ',
      'Historical earning detected inside a confirmed reconciliation boundary and held for review.',
      'Settled through ' || boundary_row.settled_through_date::text || '.',
      'Settlement amount ' || to_char(boundary_row.settlement_amount,'FM9999999990.00') || '.',
      'Do not pay until reconciled as underpayment, overpayment, or covered/ignore.'
    );
    new.source_snapshot := coalesce(new.source_snapshot,'{}'::jsonb) || jsonb_build_object(
      'reconciliation_boundary_id', boundary_row.id,
      'reconciliation_boundary_date', boundary_row.settled_through_date,
      'reconciliation_boundary_amount', boundary_row.settlement_amount,
      'reconciliation_boundary_reference', boundary_row.settlement_reference,
      'reconciliation_boundary_applied', true,
      'reconciliation_review_required', true,
      'reconciliation_review_options', jsonb_build_array('underpayment','overpayment','ignore')
    );
  end if;

  return new;
end;
$$;

comment on function private.apply_reconciliation_boundary_to_new_earning() is
'Flags system-calculated earnings inside a confirmed historical settlement boundary for reconciliation review. The earning remains visible but held and non-payable until classified as underpayment, overpayment, or ignore.';

comment on table public.reconciliation_boundaries is
'Confirmed historical settlement cutoffs. System-calculated earnings inside a boundary are flagged for underpayment, overpayment, or covered/ignore review before any additional payment is allowed.';
