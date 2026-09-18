import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917170000_all_mapped_hubspot_fields_available.sql','utf8');

test('mapped HubSpot objects expose all synced properties and values',()=>{
  assert.match(migration,/hubspot_property_definitions/);
  assert.match(migration,/comp_hubspot_object_mappings/);
  assert.match(migration,/mapping_value_policy','all'/);
  assert.match(migration,/comp_hubspot_discovered_values/);
  assert.match(migration,/jsonb_array_elements\(coalesce\(p\.options,'\[\]'::jsonb\)\)/);
});

test('synced properties automatically populate the rule field catalog',()=>{
  assert.match(migration,/sync_comp_rule_field_from_hubspot_property/);
  assert.match(migration,/hubspot_sync_auto/);
  assert.match(migration,/after insert or update/);
  assert.match(migration,/on conflict\(object_type,property_name\)/);
});

test('curated rule metadata remains authoritative',()=>{
  assert.match(migration,/hubspot_curated/);
  assert.match(migration,/public\.comp_rule_field_catalog\.data_type/);
  assert.match(migration,/public\.comp_rule_field_catalog\.display_name/);
});
