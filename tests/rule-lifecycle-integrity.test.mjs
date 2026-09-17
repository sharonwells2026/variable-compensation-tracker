import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917193000_rule_lifecycle_integrity.sql','utf8');

test('rule activation validation follows mapped-object field contract',()=>{
  assert.match(migration,/comp_rule_field_catalog/);
  assert.match(migration,/comp_hubspot_object_mappings/);
  assert.match(migration,/mapped_object_contract/);
  assert.doesNotMatch(migration,/left join public\.comp_hubspot_field_mappings fm/);
});

test('active-state changes do not invalidate content previews',()=>{
  const activeFn=migration.slice(migration.indexOf('create or replace function public.set_comp_rule_set_active'),migration.indexOf('create or replace function private.freeze_comp_plan_referenced_rule_sets'));
  assert.match(activeFn,/set is_active=target_active,updated_by=auth\.uid\(\)/);
  assert.doesNotMatch(activeFn,/set is_active=target_active,updated_at=/);
});

test('plan approval freezes only referenced current rule versions',()=>{
  assert.match(migration,/freeze_comp_plan_referenced_rule_sets/);
  assert.match(migration,/purpose='qualification'/);
  assert.match(migration,/eligibility/);
  assert.match(migration,/qualification_rule_set_id/);
  assert.match(migration,/metric_sources/);
  assert.match(migration,/approve_compensation_plan_version_pre_rule_freeze/);
  assert.match(migration,/frozen_rule_count/);
});

test('pre-freeze approval endpoint is not left client-callable',()=>{
  assert.match(migration,/revoke all on function public\.approve_compensation_plan_version_pre_rule_freeze\(uuid,text\) from public,anon,authenticated/);
});
