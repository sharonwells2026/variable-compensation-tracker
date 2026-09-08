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
  assert.match(
    layout,
    /Engagifii variable compensation management and employee earnings portal\./i,
  );
  assert.match(page, /ENGAGIFII COMPENSATION/);
  assert.match(page, /roles\.includes\("system_administrator"\).*router\.replace\("\/manage"\)/s);
  assert.match(page, /roles\.includes\("finance_payroll"\).*router\.replace\("\/finance"\)/s);
  assert.match(page, /roles\.includes\("executive_administrator"\).*router\.replace\("\/executive"\)/s);
  assert.match(page, /router\.replace\("\/me"\)/);
  assert.doesNotMatch(layout + page, /codex-preview/i);
});
