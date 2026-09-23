import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917174500_metric_aggregate_preview_readiness.sql','utf8');

test('aggregate preview prefers Metric Qualification rules',()=>{
  assert.match(migration,/qualification_rule_set_id/);
  assert.match(migration,/compute_comp_metric_rule_summary/);
  assert.match(migration,/source_mode','metric_rule'/);
  assert.match(migration,/value_field/);
});

test('readiness accepts Metric Qualification or legacy aggregate sources',()=>{
  assert.match(migration,/purpose='metric_qualification'/);
  assert.match(migration,/missing_metric_qualification/);
  assert.match(migration,/legacy_aggregate_sources/);
  assert.match(migration,/invalid_metric_value_field/);
});
