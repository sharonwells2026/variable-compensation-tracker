import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917171500_new_mapped_object_field_backfill.sql','utf8');

test('newly mapped objects backfill already-synced fields',()=>{
  assert.match(migration,/backfill_comp_rule_fields_for_mapped_object/);
  assert.match(migration,/comp_hubspot_object_mappings/);
  assert.match(migration,/hubspot_property_definitions/);
  assert.match(migration,/after insert or update of object_type,hubspot_object_type,is_eligible/);
  assert.match(migration,/new\.is_eligible=true/);
});
