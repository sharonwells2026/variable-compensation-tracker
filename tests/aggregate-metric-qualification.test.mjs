import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import {fileURLToPath} from "node:url";

const root=fileURLToPath(new URL("..",import.meta.url));

test("book-of-business editor exposes a configurable metric qualification rule",async()=>{
  const page=await readFile(`${root}/app/plans/component/[componentId]/page.tsx`,"utf8");
  assert.match(page,/Metric Qualification rule/);
  assert.match(page,/metric_qualification/);
  assert.match(page,/Value to sum/);
  assert.match(page,/aggregateQualificationRuleSetId/);
  assert.match(page,/qualification_rule_set_id/);
  assert.match(page,/value_field/);
  assert.match(page,/Legacy source-Earning-Type compatibility/);
});

test("aggregate engine evaluates metric rules while preserving legacy fallback",async()=>{
  const migration=await readFile(`${root}/supabase/migrations/20260917154500_aggregate_metric_qualification_rules.sql`,"utf8");
  assert.match(migration,/compute_comp_metric_rule_summary/);
  assert.match(migration,/comp_rule_evaluate_deal_node/);
  assert.match(migration,/qualification_rule_set_id/);
  assert.match(migration,/value_field/);
  assert.match(migration,/source_mode/);
  assert.match(migration,/legacy_components/);
  assert.match(migration,/metric_rule_needs_preview/);
  assert.match(migration,/purpose='metric_qualification'/);
});
