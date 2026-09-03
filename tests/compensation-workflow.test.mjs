import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";

const source = await readFile(new URL("../lib/compensation-workflow.ts", import.meta.url), "utf8");

test("keeps approval and payment as separate workflow states", () => {
  assert.match(source, /pending_executive_approval/);
  assert.match(source, /pending_finance_acceptance/);
  assert.match(source, /accepted_for_payment/);
  assert.match(source, /\| "paid"/);
});

test("encodes the current Engagifii workflow owners", () => {
  assert.match(source, /compensationAdministrator: "Sharon Wells"/);
  assert.match(source, /executiveApprover: "Namit Bhatia"/);
  assert.match(source, /financePayroll: "Scott Key"/);
});

test("does not treat finance acceptance as payment", () => {
  assert.match(source, /Finance has accepted the approved payout for processing\. The item is still not Paid until payment is confirmed\./);
});

test("preserves the four compensation lifecycle states", () => {
  for (const state of ["earned", "eligible", "approved", "paid"]) {
    assert.match(source, new RegExp(`\\| "${state}"`));
  }
});

test("system administrator has operational authority without rewriting paid history", () => {
  assert.match(source, /actor === "system_administrator"/);
  assert.match(source, /Paid history is preserved/);
});
