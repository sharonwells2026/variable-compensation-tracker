-- 101E Provisioning Contract Reconciliation
-- Production installed and validated manually 2026-08-31.

alter table public.app_user_drafts add column if not exists earnings_eligibility_date date;

-- Required production provisioning contract:
-- public.prepare_app_user_draft_invitation(uuid)
--   validates employee effective start, manager/org unit, active plan version and explicit eligibility date.
-- public.handle_new_user()
--   invitation-gated activation; materializes employee/profile/org/plan assignment and draft access configuration.
-- public.set_app_user_draft_earnings_eligibility(uuid,date)
--   authenticated users.manage setter for the explicit eligibility date.
--
-- The canonical function bodies are intentionally maintained from the verified production definitions;
-- schema-diff against production before replaying this reconciliation migration on an existing environment.

comment on column public.app_user_drafts.earnings_eligibility_date is
'Authoritative earning eligibility date to use when the draft creates a compensation plan assignment. Separate from employee_effective_start_date because onboarding/waiting periods may delay earning eligibility.';
