import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import {fileURLToPath} from "node:url";

const root=fileURLToPath(new URL("..",import.meta.url));

test("comp plan agreements cannot satisfy readiness without a signed date",async()=>{
  const migration=await readFile(`${root}/supabase/migrations/20260916234500_require_signed_comp_plan_agreements.sql`,`utf8`);
  assert.match(migration,/comp_plan_agreements_signed_at_required/);
  assert.match(migration,/check \(signed_at is not null\)/i);
});
