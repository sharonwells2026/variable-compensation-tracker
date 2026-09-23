import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root=fileURLToPath(new URL("..",import.meta.url));

test("readiness accepts valid legacy earned and payment rules without weakening real blockers",async()=>{
  const migration=await readFile(`${root}/supabase/migrations/20260916230000_legacy_plan_readiness_compatibility.sql`,"utf8");
  assert.match(migration,/legacy_earned_rules/);
  assert.match(migration,/legacy_payment_eligibility/);
  assert.match(migration,/comp_component_deal_rules/);
  assert.match(migration,/marks_earned=true/);
  assert.match(migration,/requires_invoice_paid_date/);
  assert.match(migration,/paid_stage_and_invoice_paid_date/);
  assert.match(migration,/missing_approval_steps/);
  assert.match(migration,/missing_aggregate_sources/);
  assert.match(migration,/missing_credit_attribution/);
  assert.match(migration,/measurement_source='book_of_business'/);
  assert.match(migration,/calculation_type='threshold_bonus'/);
});
