alter table public.comp_plan_agreements
  drop constraint if exists comp_plan_agreements_signed_at_required;

alter table public.comp_plan_agreements
  add constraint comp_plan_agreements_signed_at_required
  check (signed_at is not null);

-- A row in comp_plan_agreements represents an executed agreement.
-- Unsigned drafts/templates may exist outside this table, but must not satisfy plan readiness.