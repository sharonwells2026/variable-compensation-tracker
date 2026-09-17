import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917190500_multi_metric_sources.sql','utf8');

test('aggregate metrics support multiple independently qualified numeric sources',()=>{
  assert.match(migration,/compute_comp_metric_sources_summary/);
  assert.match(migration,/metric_sources/);
  assert.match(migration,/rule_set_id/);
  assert.match(migration,/value_field/);
  assert.match(migration,/source_mode','metric_sources'/);
});

test('metric sources fail closed on overlaps to prevent double counting',()=>{
  assert.match(migration,/Metric sources overlap on one or more HubSpot deals/);
  assert.match(migration,/seen_ids && source_ids/);
});

test('aggregate normalization preserves metric rules and multi-source configuration',()=>{
  assert.match(migration,/qualification_rule_set_id/);
  assert.match(migration,/metric_sources/);
  assert.match(migration,/normalize_comp_aggregate_configuration/);
});

test('readiness validates every metric source and requires fresh previews',()=>{
  assert.match(migration,/invalid_metric_source_rule/);
  assert.match(migration,/invalid_metric_source_value_field/);
  assert.match(migration,/metric_source_needs_preview/);
  assert.match(migration,/comp_rule_set_preview_runs/);
});
