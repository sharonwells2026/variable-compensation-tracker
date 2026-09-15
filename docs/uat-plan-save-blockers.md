# UAT plan save blocker fixes

This batch addresses issues found during the first live admin UAT pass on September 14, 2026.

## Fixed

- Earned-condition editor now calls the deployed `save_simple_comp_qualification` RPC instead of the nonexistent `save_simple_comp_earned_conditions` RPC.
- Raw schema-cache errors are replaced with a user-safe save message while preserving unsaved edits on the page.
- Draft plan details now track unsaved changes and prompt to save before navigating to Earning Types, People, Approvals, Agreements, readiness, or back to the plan.
- Approval-sequence edits now track unsaved changes and prompt to save before returning to Plan Setup.
- Browser/tab close protection remains in place for unsaved plan and approval changes.
- Regression tests assert the correct RPC and navigation protection.

## UAT expectation

After deployment, rebuild the same test plan path and verify:

1. Plan setup details cannot be silently lost when opening Approvals or another setup area.
2. Earned conditions save successfully.
3. A failed save leaves edits visible and gives a human-readable message.
4. Approval edits cannot be silently lost when returning to Plan Setup.
