import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const page=fs.readFileSync('app/plans/component/[componentId]/page.tsx','utf8');

test('aggregate editor supports multiple metric sources',()=>{
  assert.match(page,/Metric Sources/);
  assert.match(page,/metricSources/);
  assert.match(page,/Add Metric Source/);
  assert.match(page,/openMetricSourceRule/);
  assert.match(page,/metricSourceIndex/);
});

test('aggregate value selector comes from mapped numeric Deal fields',()=>{
  assert.match(page,/numericDealFields/);
  assert.match(page,/f\.object_type==="deal"&&f\.data_type==="number"/);
  assert.match(page,/Every mapped numeric Deal field is available here/);
  assert.doesNotMatch(page,/<option value="renewal_arr">Renewal ARR<\/option>/);
});

test('aggregate editor exposes combined attainment preview',()=>{
  assert.match(page,/preview_comp_component_aggregate/);
  assert.match(page,/Preview current attainment/);
  assert.match(page,/Overlapping sources fail closed/);
});
