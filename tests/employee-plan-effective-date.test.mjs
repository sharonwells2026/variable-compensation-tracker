import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const page=fs.readFileSync('app/plans/applicability/[versionId]/page.tsx','utf8');
const migration=fs.readFileSync('supabase/migrations/20260917143000_employee_start_waiting_effective_date.sql','utf8');

test('applicability shows employee start, waiting days, and calculated effective date',()=>{
  assert.match(page,/Employee start date/);
  assert.match(page,/Days until plan takes effect/);
  assert.match(page,/Plan effective date/);
  assert.match(page,/addDays\(employee\?\.hire_date/);
  assert.match(page,/readOnly/);
});

test('admin plan payload exposes authoritative employee hire date',()=>{
  assert.match(migration,/'hire_date',e\.hire_date/);
  assert.match(migration,/get_compensation_plan_admin_data/);
});
