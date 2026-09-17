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

test("legacy aggregate route redirects to the authoritative Earning Type editor",async()=>{
  const legacyPage=await readFile(`${root}/app/plans/component/[componentId]/aggregate/page.tsx`,"utf8");
  assert.match(legacyPage,/LegacyAggregateRedirect/);
  assert.match(legacyPage,/router\.replace\(`\/plans\/component\/\$\{params\.componentId\}/);
  assert.doesNotMatch(legacyPage,/Choose at least one Earning Type that counts toward this benchmark/);
});

test("authoritative aggregate editor exposes configurable Metric Sources and preserves component metadata",async()=>{
  const page=await readFile(`${root}/app/plans/component/[componentId]/page.tsx`,"utf8");
  assert.match(page,/Metric Sources/);
  assert.match(page,/Add Metric Source/);
  assert.match(page,/Value to sum \*/);
  assert.match(page,/metricSources/);
  assert.match(page,/openMetricSourceRule/);
  assert.match(page,/selected_calculation_order:1/);
  assert.match(page,/selected_is_active:true/);
  assert.match(page,/selected_payout_timing_method:"annual"/);
  assert.match(page,/selected_allow_manager_payout_override:true/);
  assert.match(page,/selected_measurement_label:null/);
});

test("aggregate normalization is insert-safe and never backfills active plans",async()=>{
  const migration=await readFile(`${root}/supabase/migrations/20260916221500_normalize_aggregate_configuration.sql`,"utf8");
  assert.match(migration,/old_cfg jsonb:='\{\}'::jsonb/);
  assert.match(migration,/if tg_op='UPDATE' then\s+old_cfg:=coalesce\(old\.rule_configuration,'\{\}'::jsonb\)/);
  assert.match(migration,/from public\.comp_plan_versions pv/);
  assert.match(migration,/pv\.status='draft'/);
  assert.doesNotMatch(migration,/where measurement_source='book_of_business'\s+and calculation_type='threshold_bonus';/);
});

test("Earned conditions expose advanced nested logic without flattening it",async()=>{
  const editor=await readFile(`${root}/app/plans/component/[componentId]/earned-conditions-editor.tsx`,"utf8");
  assert.match(editor,/Need AND \/ OR \/ NOT\? Open Advanced logic/);
  assert.match(editor,/Advanced Earned logic is active/);
  assert.match(editor,/usesAdvancedLogic/);
  assert.match(editor,/groups\.length>1/);
  assert.match(editor,/n\.negate===true/);
});
