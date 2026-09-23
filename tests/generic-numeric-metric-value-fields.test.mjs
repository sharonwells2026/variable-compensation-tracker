import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917184500_generic_numeric_metric_value_fields.sql','utf8');

test('metric aggregate accepts any mapped numeric deal field',()=>{
  assert.match(migration,/comp_rule_field_catalog/);
  assert.match(migration,/comp_hubspot_object_mappings/);
  assert.match(migration,/f\.object_type='deal'/);
  assert.match(migration,/f\.data_type='number'/);
  assert.match(migration,/comp_rule_deal_property\(d\.id,selected_value_field\)/);
  assert.doesNotMatch(migration,/selected_value_field not in \('/);
});

test('numeric metric value fields fail closed when unavailable or nonnumeric',()=>{
  assert.match(migration,/Aggregate value field % is not an available mapped numeric Deal field/);
  assert.match(migration,/non-numeric value % for aggregate field %/);
  assert.match(migration,/is_comp_metric_numeric_value_field/);
});
