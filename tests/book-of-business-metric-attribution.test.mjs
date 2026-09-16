import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root=fileURLToPath(new URL("..",import.meta.url));

test("book of business aggregate uses metric attribution before earning attribution",async()=>{
  const migration=await readFile(`${root}/supabase/migrations/20260916233000_book_of_business_metric_attribution.sql`,"utf8");
  assert.match(migration,/attribution_purpose='metric'/);
  assert.match(migration,/metric_key='book_of_business'/);
  assert.match(migration,/resolve_comp_user_attribution\([^)]*'metric','book_of_business'/s);
  assert.match(migration,/resolve_comp_user_attribution\([^)]*'earning',null/s);
  assert.match(migration,/resolved_credit_percentage/);
  assert.match(migration,/employee_plan_assignments/);
  assert.match(migration,/comp_plan_draft_assignments/);
  assert.match(migration,/source_component_codes/);
  assert.match(migration,/preview_comp_component_aggregate/);
  assert.match(migration,/compute_comp_component_attainment/);
});
