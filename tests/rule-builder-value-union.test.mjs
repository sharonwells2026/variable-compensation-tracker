import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917182000_union_rule_builder_values.sql','utf8');

test('rule builder unions discovered and HubSpot-defined values',()=>{
  assert.match(migration,/comp_rule_builder_field_options/);
  assert.match(migration,/comp_hubspot_discovered_values/);
  assert.match(migration,/jsonb_array_elements\(coalesce\(definition_options,'\[\]'::jsonb\)\)/);
  assert.match(migration,/union all/);
  assert.match(migration,/distinct on\(value\)/);
});

test('catalog uses unified option helper',()=>{
  assert.match(migration,/private\.comp_rule_builder_field_options\(p\.internal_object_key,p\.property_name,p\.options\)/);
});
