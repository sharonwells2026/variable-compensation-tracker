import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const migration=fs.readFileSync('supabase/migrations/20260917162000_plan_effective_date_contract_and_safe_draft_delete.sql','utf8');
const applicability=fs.readFileSync('app/plans/applicability/[versionId]/page.tsx','utf8');

test('plan participation keeps employee start, plan waiting period, and effective date distinct',()=>{
  assert.match(migration,/employee_start_date/);
  assert.match(migration,/plan_waiting_period_days/);
  assert.match(migration,/selected_effective_start_date-employee_start/);
  assert.match(migration,/earning_eligibility_waiting_period_days/);
  assert.match(applicability,/Employee start date/);
  assert.match(applicability,/Days until plan takes effect/);
  assert.match(applicability,/Plan effective date/);
});

test('activation promotes the plan timing contract without reusing it as payout waiting',()=>{
  assert.match(migration,/employee_start_date,plan_waiting_period_days/);
  assert.match(migration,/da\.employee_start_date,da\.plan_waiting_period_days/);
  assert.match(migration,/da\.effective_start_date\+da\.eligibility_waiting_period_days/);
});

test('draft deletion is guarded and preserves historical compensation',()=>{
  assert.match(migration,/preview_comp_plan_draft_delete/);
  assert.match(migration,/Only draft versions can be deleted/);
  assert.match(migration,/active employee assignments/);
  assert.match(migration,/comp_earnings/);
  assert.match(migration,/dependent_version_count/);
  assert.match(migration,/DELETE DRAFT/);
  assert.match(migration,/not exists\(select 1 from public\.comp_plan_agreements a where a\.storage_path=o\.name\)/);
});
