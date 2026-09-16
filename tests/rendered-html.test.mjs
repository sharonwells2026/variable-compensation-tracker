import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));

test("defines the compensation tracker entry experience", async () => {
  const [layout, page] = await Promise.all([
    readFile(`${root}/app/layout.tsx`, "utf8"),
    readFile(`${root}/app/page.tsx`, "utf8"),
  ]);
  assert.match(layout, /title:\s*["']Variable Compensation Tracker["']/);
  assert.match(layout, /Engagifii variable compensation management and employee earnings portal\./i);
  assert.match(page, /ENGAGIFII COMPENSATION/);
  assert.match(page, /roles\.includes\("system_administrator"\).*router\.replace\("\/manage"\)/s);
  assert.match(page, /roles\.includes\("finance_payroll"\).*router\.replace\("\/finance"\)/s);
  assert.match(page, /roles\.includes\("executive_administrator"\).*router\.replace\("\/executive"\)/s);
  assert.match(page, /router\.replace\("\/me"\)/);
  assert.doesNotMatch(layout + page, /codex-preview/i);
});

test("uses the deployed Earned-condition RPC and protects or autosaves draft setup", async () => {
  const [earnedEditor, earningType, managePlan, approvals, newPlan, people] = await Promise.all([
    readFile(`${root}/app/plans/component/[componentId]/earned-conditions-editor.tsx`, "utf8"),
    readFile(`${root}/app/plans/component/[componentId]/page.tsx`, "utf8"),
    readFile(`${root}/app/plans/manage/[versionId]/page.tsx`, "utf8"),
    readFile(`${root}/app/plans/manage/[versionId]/approvals/page.tsx`, "utf8"),
    readFile(`${root}/app/plans/new/page.tsx`, "utf8"),
    readFile(`${root}/app/plans/applicability/[versionId]/page.tsx`, "utf8"),
  ]);
  assert.match(earnedEditor, /save_simple_comp_qualification/);
  assert.doesNotMatch(earnedEditor, /save_simple_comp_earned_conditions/);
  assert.match(earningType, /You have unsaved changes\. Save them before leaving this Earning Type\?/);
  assert.match(earningType, /beforeunload/);
  assert.match(managePlan, /if\(dirty\)\{const ok=await saveDraft\(\)/);
  assert.match(managePlan, /beforeunload/);
  assert.match(newPlan, /Next step/);
  assert.match(newPlan, /router\.push\(versionId\?`\/plans\/applicability\/\$\{versionId\}`/);
  assert.match(people, /saveAndNext/);
  assert.match(approvals, /const next=async\(\)=>\{if\(dirty\)\{const ok=await save\(\)/);
  assert.match(approvals, /beforeunload/);
});

test("full Earning Type editor can configure the payout methods needed for the Wes pilot", async () => {
  const page = await readFile(`${root}/app/plans/component/[componentId]/page.tsx`, "utf8");
  assert.match(page, /value="percentage">Percentage/);
  assert.match(page, /value="tiered_percentage">Different percentages by contract term/);
  assert.match(page, /Contract-term payout tiers/);
  assert.match(page, /minimum_contract_years/);
  assert.match(page, /maximum_contract_years/);
  assert.match(page, /value="threshold_bonus">Bonus when a quota \/ benchmark is reached/);
  assert.match(page, /Quota \/ benchmark/);
  assert.match(page, /Bonus paid when benchmark is exceeded/);
  assert.match(page, /value="fixed_amount">Fixed dollar amount/);
  assert.match(page, /value="average_arr">ARR/);
  assert.match(page, /value="book_of_business">Running total \/ book of business/);
  assert.match(page, /value="annual">Annually/);
  assert.match(page, /The customer has paid/);
  assert.match(page, /Customer has paid/);
  assert.match(page, /aggregateComponentCodes/);
  assert.match(page, /aggregateFixedUplift/);
  assert.match(page, /Advanced AND \/ OR \/ NOT logic|Use advanced logic/);
  assert.match(page, /fixed_amount_per_unit" disabled/);
  assert.match(page, /milestone_bonus" disabled/);
});

test("Plan Builder V2 has dedicated review, cloning, configurable payment mapping, and optional approval runtime", async () => {
  const [progress, review, managePlan, settings, paymentMapping, cloneMigration, approvalMigration, approvals] = await Promise.all([
    readFile(`${root}/app/plans/components/plan-builder-progress.tsx`, "utf8"),
    readFile(`${root}/app/plans/manage/[versionId]/review/page.tsx`, "utf8"),
    readFile(`${root}/app/plans/manage/[versionId]/page.tsx`, "utf8"),
    readFile(`${root}/app/settings/page.tsx`, "utf8"),
    readFile(`${root}/app/settings/payment-condition-mapping/page.tsx`, "utf8"),
    readFile(`${root}/supabase/migrations/20260915205500_clone_compensation_plan_component.sql`, "utf8"),
    readFile(`${root}/supabase/migrations/20260915212500_plan_scoped_optional_approval_workflows.sql`, "utf8"),
    readFile(`${root}/app/plans/manage/[versionId]/approvals/page.tsx`, "utf8"),
  ]);
  assert.match(progress, /\/plans\/manage\/\$\{id\}\/review/);
  assert.match(review, /validate_compensation_plan_version_readiness/);
  assert.match(review, /Approve plan/);
  assert.match(review, /Activate plan/);
  assert.match(managePlan, /clone_compensation_plan_component/);
  assert.match(managePlan, /Clone & edit/);
  assert.match(cloneMigration, /create or replace function public\.clone_compensation_plan_component/);
  assert.match(settings, /Customer Payment Mapping/);
  assert.match(paymentMapping, /save_comp_business_condition_setting/);
  assert.match(paymentMapping, /customer_payment_received/);
  assert.match(approvals, /Optional \/ advisory/);
  assert.match(approvals, /optional reviewer receives an advisory review request/i);
  assert.match(approvalMigration, /install_plan_approval_workflows/);
  assert.match(approvalMigration, /compensation_optional_review/);
  assert.match(approvalMigration, /optional_review_recorded/);
  assert.match(approvalMigration, /plan_version_id/);
});
