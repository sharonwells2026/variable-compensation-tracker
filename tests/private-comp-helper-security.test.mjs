import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root=fileURLToPath(new URL("..",import.meta.url));

test("private compensation helpers are not directly executable by client roles",async()=>{
  const aggregate=await readFile(`${root}/supabase/migrations/20260916221500_normalize_aggregate_configuration.sql`,"utf8");
  const hardening=await readFile(`${root}/supabase/migrations/20260916222500_harden_private_comp_helpers.sql`,"utf8");
  assert.match(aggregate,/revoke all on function private\.normalize_comp_aggregate_configuration\(\) from public, anon, authenticated;/);
  assert.match(hardening,/private\.compute_comp_component_attainment\(uuid,uuid,integer\)/);
  assert.match(hardening,/private\.install_plan_approval_workflows\(uuid,uuid\)/);
  assert.match(hardening,/from public, anon, authenticated/);
});
