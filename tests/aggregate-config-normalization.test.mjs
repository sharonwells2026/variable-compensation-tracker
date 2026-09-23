import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root=fileURLToPath(new URL("..",import.meta.url));

test("Book-of-Business configuration is normalized at the persistence boundary",async()=>{
  const migration=await readFile(`${root}/supabase/migrations/20260916221500_normalize_aggregate_configuration.sql`,"utf8");
  assert.match(migration,/normalize_comp_aggregate_configuration/);
  assert.match(migration,/before insert or update on public\.comp_plan_components/);
  assert.match(migration,/source_component_codes/);
  assert.match(migration,/aggregate_component_codes/);
  assert.match(migration,/benchmark_amount/);
  assert.match(migration,/threshold_amount/);
  assert.match(migration,/payout_amount/);
  assert.match(migration,/bonus_amount/);
  assert.match(migration,/use_legacy/);
});
