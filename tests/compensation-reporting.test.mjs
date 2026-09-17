import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const report=await readFile(new URL('../app/reports/page.tsx',import.meta.url),'utf8');
const migration=await readFile(new URL('../supabase/migrations/20260917202000_enrich_compensation_reporting.sql',import.meta.url),'utf8');

test('ledger exposes source and calculation audit detail',()=>{
  for(const field of ['earning_description','source_snapshot','eligibility_condition_description','eligibility_evidence','source_url']){
    assert.match(migration,new RegExp(`'${field}'`));
  }
  assert.match(report,/Deal \/ Source/);
  assert.match(report,/Source Amount/);
  assert.match(report,/Eligibility Evidence/);
  assert.match(report,/component_rate/);
});

test('payroll export describes payment-ready state rather than assuming finance timestamp',()=>{
  assert.match(report,/Payment-ready payroll report/);
  assert.match(report,/all payment-required approvals and handoffs are complete/);
  assert.doesNotMatch(report,/Finance-accepted compensation that is ready for payroll/);
});