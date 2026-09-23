import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917185000_generic_metric_readiness.sql','utf8');

test('readiness accepts mapped numeric metric value fields',()=>{
  assert.match(migration,/validate_compensation_plan_version_readiness_pre_generic_metric_fields/);
  assert.match(migration,/invalid_metric_value_field/);
  assert.match(migration,/is_comp_metric_numeric_value_field/);
  assert.match(migration,/blocker_count/);
  assert.match(migration,/jsonb_array_length\(blockers\)=0/);
});
