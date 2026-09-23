import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917191500_metric_qualification_rule_purpose.sql','utf8');

test('rule-set purpose constraint permits metric qualification rules',()=>{
  assert.match(migration,/metric_qualification/);
  assert.match(migration,/comp_rule_sets_purpose_check/);
  assert.match(migration,/drop constraint if exists/);
  assert.match(migration,/add constraint comp_rule_sets_purpose_check/);
});
