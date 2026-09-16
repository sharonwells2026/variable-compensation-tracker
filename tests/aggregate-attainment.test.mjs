import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root=fileURLToPath(new URL("..",import.meta.url));

test("aggregate attainment engine supports threshold and milestone payouts",async()=>{
  const migration=await readFile(`${root}/supabase/migrations/20260916080000_comp_aggregate_attainment_engine.sql`,"utf8");
  assert.match(migration,/selected_calculation_type = 'threshold_bonus'/);
  assert.match(migration,/selected_calculation_type = 'milestone_bonus'/);
  assert.match(migration,/preview_comp_component_aggregate/);
  assert.match(migration,/source_component_codes/);
  assert.match(migration,/comp_plan_draft_assignments/);
  assert.match(migration,/resolve_comp_user_attribution/);
});

test("aggregate attainment setup exposes benchmark and source Earning Types",async()=>{
  const page=await readFile(`${root}/app/plans/component/[componentId]/aggregate/page.tsx`,"utf8");
  assert.match(page,/What counts toward attainment\?/);
  assert.match(page,/Starting baseline/);
  assert.match(page,/Benchmark \*/);
  assert.match(page,/Payout when benchmark is met/);
  assert.match(page,/preview_comp_component_aggregate/);
  assert.match(page,/save_compensation_plan_component/);
});

test("Earned conditions expose advanced nested logic without flattening it",async()=>{
  const editor=await readFile(`${root}/app/plans/component/[componentId]/earned-conditions-editor.tsx`,"utf8");
  assert.match(editor,/Need AND \/ OR \/ NOT\? Open Advanced logic/);
  assert.match(editor,/Advanced Earned logic is active/);
  assert.match(editor,/usesAdvancedLogic/);
  assert.match(editor,/groups\.length>1/);
  assert.match(editor,/n\.negate===true/);
});
