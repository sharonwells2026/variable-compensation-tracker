import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917195500_fix_readiness_record_shadow.sql','utf8');

test('readiness core avoids record/table alias shadowing',()=>{
  assert.match(migration,/comp_plan_components pc where pc\.plan_version_id=selected_plan_version_id and pc\.is_active=true/);
  assert.doesNotMatch(migration,/comp_plan_components c where c\.plan_version_id=selected_plan_version_id and c\.is_active=true/);
});

test('readiness still checks assignments, agreements, earned rules, eligibility and effective start',()=>{
  assert.match(migration,/comp_plan_draft_assignments/);
  assert.match(migration,/comp_plan_agreements/);
  assert.match(migration,/purpose='qualification'/);
  assert.match(migration,/eligibility/);
  assert.match(migration,/missing_effective_start/);
});
