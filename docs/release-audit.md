# Beta Release Audit

## Release gate

Before internal beta deployment:

- Production build passes in GitHub Actions.
- Unit tests pass.
- Root route sends management users to `/manage` and employees to `/me`.
- Employee self-service is scoped to the signed-in employee.
- Employee plan acknowledgment and earning submission are self-service only.
- Sharon retains System Administrator authority, with audit history for administrative actions.
- Compensation lifecycle remains distinct from operational workflow: Earned -> Eligible -> Approved -> Paid.
- Operational workflow remains Sharon review/submission -> Namit approval -> Scott Finance acceptance -> actual payroll payment confirmation.
- Finance acceptance must never be treated as Paid.
- Paid history is preserved; corrections use traceable adjustments rather than silent mutation.
- Anonymous execution is revoked from browser-facing SECURITY DEFINER RPCs.
- Direct compensation tables remain protected by RLS/RPC access rather than broad browser table policies.

## Known non-blocking items

- Supabase reports informational `RLS enabled no policy` notices because protected tables are intentionally accessed through permission-aware RPCs.
- Performance advisor reports several low-traffic or new indexes as unused and additional foreign keys without covering indexes. These are post-beta performance cleanup unless query evidence shows a bottleneck.
- Supabase Auth leaked-password protection should be enabled before broad employee rollout.
