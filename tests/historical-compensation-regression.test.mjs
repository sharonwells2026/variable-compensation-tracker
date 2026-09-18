import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import {fileURLToPath} from "node:url";

const root=fileURLToPath(new URL("..",import.meta.url));

test("historical reconciliation is review-first and preserves prior settlement on ignore",async()=>{
  const boundary=await readFile(`${root}/supabase/migrations/20260917195500_reconciliation_boundary_review.sql`,"utf8");
  const resolution=await readFile(`${root}/supabase/migrations/20260917200500_reconciliation_review_resolution.sql`,"utf8");
  assert.match(boundary,/reconciliation_review_options.*underpayment.*overpayment.*ignore/s);
  assert.match(boundary,/payment_status := 'held'/);
  assert.match(boundary,/eligible_amount := 0/);
  assert.match(resolution,/requested_decision.*underpayment.*overpayment.*ignore/s);
  assert.match(resolution,/accepted the prior settlement amount without financial change/);
  assert.match(resolution,/negative_adjustment_recorded_no_automatic_clawback/);
  assert.match(resolution,/positive_adjustment_pending_approval/);
});

test("unadopted renewal proposal is disabled rather than treated as payable compensation",async()=>{
  const guard=await readFile(`${root}/supabase/migrations/20260917202500_effective_date_and_unadopted_component_guards.sql`,"utf8");
  assert.match(guard,/SHARON_RENEWAL_OVERRIDE_REVIEW/);
  assert.match(guard,/is_active=false/);
  assert.match(guard,/Review-only historical proposal; not an adopted compensation term/);
  assert.match(guard,/comp_component_deal_rules/);
  assert.match(guard,/comp_user_attribution_rules/);
});

test("component effective-date helper rejects dates before start and after end",async()=>{
  const guard=await readFile(`${root}/supabase/migrations/20260917202500_effective_date_and_unadopted_component_guards.sql`,"utf8");
  assert.match(guard,/comp_rule_is_effective/);
  assert.match(guard,/effective_start_date/);
  assert.match(guard,/effective_end_date/);
});
