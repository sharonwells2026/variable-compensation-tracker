"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createClient } from "@supabase/supabase-js";
import { Download, RefreshCw } from "lucide-react";

const supabaseUrl =
  process.env.NEXT_PUBLIC_SUPABASE_URL ||
  "https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  "sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase =
  supabaseUrl && supabaseKey ? createClient(supabaseUrl, supabaseKey) : null;

type SourceSnapshot = {
  deal_name?: string;
  company_name?: string;
  pipeline_name?: string;
  stage_name?: string;
  deal_type?: string;
  amount_label?: string;
  amount_source?: string;
  source_amount?: number;
  component_rate?: number;
  credit_method?: string;
  credit_percentage?: number;
};

type Earning = {
  earning_id: string;
  employee_name: string;
  earning_name: string;
  earning_description?: string | null;
  source_type: string | null;
  source_external_id: string | null;
  source_url: string | null;
  source_snapshot?: SourceSnapshot | null;
  earned_date: string | null;
  earned_amount: number;
  eligibility_status: string;
  eligibility_condition_description?: string | null;
  eligibility_evidence?: Record<string, unknown> | null;
  eligible_date?: string | null;
  eligible_amount: number;
  employee_verification_status: string;
  manager_approval_status: string;
  executive_approval_status: string;
  approved_amount: number;
  payment_status: string;
  paid_amount: number;
  hold_reason: string | null;
  expected_payment_date: string | null;
  expected_pay_period_label: string | null;
  expected_pay_period_start?: string | null;
  expected_pay_period_end?: string | null;
  finance_accepted_at?: string | null;
  reconciliation_status: string | null;
  source_match_status: string | null;
};

type EarningsPayload = {
  summary: Record<string, number>;
  earnings: Earning[];
};

type Payment = {
  earning_id: string;
  employee_name: string;
  earning_name: string;
  earned_date: string;
  approved_amount: number;
  paid_amount: number;
  remaining_amount?: number;
  payment_status: string;
  pay_period_start: string | null;
  pay_period_end: string | null;
  pay_period_label: string | null;
  finance_accepted_at?: string | null;
  actual_payment_date?: string | null;
  payment_reference?: string | null;
  payment_method?: string | null;
};

type FinancePayload = {
  accepted_unpaid: Payment[];
  paid: Payment[];
};

function money(value: number) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(Number(value || 0));
}

function percent(value: number | undefined) {
  if (value == null) return "";
  return `${Number(value) * 100}%`;
}

function csvCell(value: unknown) {
  const text =
    typeof value === "object" && value !== null
      ? JSON.stringify(value)
      : String(value ?? "");
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function downloadCsv(name: string, headers: string[], rows: unknown[][]) {
  const body = [headers, ...rows]
    .map((row) => row.map(csvCell).join(","))
    .join("\n");
  const blob = new Blob([body], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = name;
  anchor.click();
  URL.revokeObjectURL(url);
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

export default function ReportsPage() {
  const [earnings, setEarnings] = useState<EarningsPayload>({
    summary: {},
    earnings: [],
  });
  const [finance, setFinance] = useState<FinancePayload>({
    accepted_unpaid: [],
    paid: [],
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [employee, setEmployee] = useState("all");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const load = async () => {
    if (!supabase) {
      setError("Reporting is temporarily unavailable.");
      setLoading(false);
      return;
    }

    setLoading(true);
    setError("");
    const [earningsResult, financeResult] = await Promise.all([
      supabase.rpc("get_admin_earnings_data"),
      supabase.rpc("get_finance_payment_workspace_data"),
    ]);

    if (earningsResult.error) {
      setError("We couldn't load the earnings ledger.");
    } else {
      setEarnings(
        (earningsResult.data || { summary: {}, earnings: [] }) as EarningsPayload,
      );
    }

    if (!financeResult.error) {
      setFinance(
        (financeResult.data || { accepted_unpaid: [], paid: [] }) as FinancePayload,
      );
    }

    setLoading(false);
  };

  useEffect(() => {
    void load();
  }, []);

  const employees = useMemo(
    () =>
      Array.from(new Set(earnings.earnings.map((item) => item.employee_name))).sort(),
    [earnings.earnings],
  );

  const rows = useMemo(
    () =>
      earnings.earnings.filter(
        (item) =>
          (employee === "all" || item.employee_name === employee) &&
          (!from || !item.earned_date || item.earned_date >= from) &&
          (!to || !item.earned_date || item.earned_date <= to),
      ),
    [earnings.earnings, employee, from, to],
  );

  const payable = useMemo(
    () =>
      finance.accepted_unpaid.filter(
        (item) =>
          (employee === "all" || item.employee_name === employee) &&
          (!from || item.earned_date >= from) &&
          (!to || item.earned_date <= to),
      ),
    [finance.accepted_unpaid, employee, from, to],
  );

  const totals = useMemo(
    () =>
      rows.reduce(
        (totalsSoFar, item) => ({
          earned: totalsSoFar.earned + Number(item.earned_amount || 0),
          eligible: totalsSoFar.eligible + Number(item.eligible_amount || 0),
          approved: totalsSoFar.approved + Number(item.approved_amount || 0),
          paid: totalsSoFar.paid + Number(item.paid_amount || 0),
        }),
        { earned: 0, eligible: 0, approved: 0, paid: 0 },
      ),
    [rows],
  );

  const exportLedger = () => {
    const headers = [
      "Employee",
      "Earning Type",
      "Description",
      "Deal / Source",
      "Company",
      "Deal Type",
      "Pipeline",
      "Stage",
      "Source Type",
      "Source ID",
      "Amount Basis",
      "Source Amount",
      "Rate",
      "Credit Method",
      "Credit %",
      "Earned Date",
      "Earned Amount",
      "Eligibility",
      "Eligibility Rule",
      "Eligibility Evidence",
      "Eligible Date",
      "Eligible Amount",
      "Employee Verification",
      "Manager Approval",
      "Executive Approval",
      "Approved Amount",
      "Payment Status",
      "Paid Amount",
      "Expected Pay Period",
      "Finance Accepted At",
      "Hold Reason",
      "Reconciliation",
      "Source Match",
      "Source URL",
    ];

    const csvRows = rows.map((item) => {
      const source = item.source_snapshot || {};
      return [
        item.employee_name,
        item.earning_name,
        item.earning_description,
        source.deal_name,
        source.company_name,
        source.deal_type,
        source.pipeline_name,
        source.stage_name,
        item.source_type,
        item.source_external_id,
        source.amount_label || source.amount_source,
        source.source_amount,
        percent(source.component_rate),
        source.credit_method,
        source.credit_percentage,
        item.earned_date,
        item.earned_amount,
        item.eligibility_status,
        item.eligibility_condition_description,
        item.eligibility_evidence,
        item.eligible_date,
        item.eligible_amount,
        item.employee_verification_status,
        item.manager_approval_status,
        item.executive_approval_status,
        item.approved_amount,
        item.payment_status,
        item.paid_amount,
        item.expected_pay_period_label,
        item.finance_accepted_at,
        item.hold_reason,
        item.reconciliation_status,
        item.source_match_status,
        item.source_url,
      ];
    });

    downloadCsv(`compensation-ledger-${today()}.csv`, headers, csvRows);
  };

  const exportPayroll = () => {
    const headers = [
      "Employee",
      "Earning Type",
      "Earned Date",
      "Approved Amount",
      "Remaining To Pay",
      "Pay Period Start",
      "Pay Period End",
      "Pay Period",
      "Finance Accepted At",
      "Payment Status",
    ];
    const csvRows = payable.map((item) => [
      item.employee_name,
      item.earning_name,
      item.earned_date,
      item.approved_amount,
      item.remaining_amount ??
        Math.max(Number(item.approved_amount || 0) - Number(item.paid_amount || 0), 0),
      item.pay_period_start,
      item.pay_period_end,
      item.pay_period_label,
      item.finance_accepted_at,
      item.payment_status,
    ]);

    downloadCsv(`compensation-payroll-ready-${today()}.csv`, headers, csvRows);
  };

  return (
    <main className="eng-page">
      <div className="eng-page__shell">
        <nav className="eng-breadcrumb">
          <Link href="/manage">Control Center</Link>
          <span className="eng-breadcrumb__sep">/</span>
          <span>Reports</span>
        </nav>

        <header className="eng-page-header">
          <div className="eng-page-header__main">
            <span className="eng-page-header__eyebrow">COMPENSATION REPORTING</span>
            <h1>Reports</h1>
            <p className="eng-page-header__lede">
              Review the authoritative compensation ledger and produce payment-ready
              payroll exports without changing earning or payment state.
            </p>
          </div>
          <div className="eng-page-header__actions">
            <button className="eng-btn" onClick={load} disabled={loading}>
              <RefreshCw size={16} />
              {loading ? "Refreshing…" : "Refresh"}
            </button>
          </div>
        </header>

        {error && (
          <div className="eng-callout eng-callout--danger">
            <div className="eng-callout__body">{error}</div>
          </div>
        )}

        <section className="eng-card" style={{ margin: "16px 0" }}>
          <div
            className="eng-card__body"
            style={{
              display: "grid",
              gridTemplateColumns: "minmax(220px,1fr) repeat(2,minmax(150px,.55fr))",
              gap: 10,
            }}
          >
            <label>
              <small>Employee</small>
              <select
                className="eng-input"
                style={{ width: "100%" }}
                value={employee}
                onChange={(event) => setEmployee(event.target.value)}
              >
                <option value="all">All employees</option>
                {employees.map((name) => (
                  <option key={name} value={name}>
                    {name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              <small>Earned from</small>
              <input
                className="eng-input"
                style={{ width: "100%" }}
                type="date"
                value={from}
                onChange={(event) => setFrom(event.target.value)}
              />
            </label>
            <label>
              <small>Earned through</small>
              <input
                className="eng-input"
                style={{ width: "100%" }}
                type="date"
                value={to}
                onChange={(event) => setTo(event.target.value)}
              />
            </label>
          </div>
        </section>

        <section
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit,minmax(170px,1fr))",
            gap: 10,
            marginBottom: 18,
          }}
        >
          {[
            ["Earned", totals.earned],
            ["Eligible", totals.eligible],
            ["Approved", totals.approved],
            ["Paid", totals.paid],
          ].map(([label, value]) => (
            <div className="eng-card" key={String(label)}>
              <div className="eng-card__body">
                <small>{label}</small>
                <b
                  className="eng-figure"
                  style={{ display: "block", fontSize: 24, marginTop: 5 }}
                >
                  {loading ? "—" : money(Number(value))}
                </b>
              </div>
            </div>
          ))}
        </section>

        <section className="eng-card" style={{ marginBottom: 18 }}>
          <div className="eng-card__head">
            <div>
              <h2>Compensation ledger</h2>
              <p>
                {rows.length} current earning record{rows.length === 1 ? "" : "s"} in
                this view. Export includes the source deal, calculation basis, rate and
                eligibility evidence when recorded.
              </p>
            </div>
            <button
              className="eng-btn eng-btn--primary"
              onClick={exportLedger}
              disabled={!rows.length}
            >
              <Download size={16} />
              Export ledger CSV
            </button>
          </div>
          <div className="eng-card__body" style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", minWidth: 980 }}>
              <thead>
                <tr>
                  {[
                    "Employee",
                    "Earning",
                    "Source",
                    "Earned date",
                    "Basis",
                    "Earned",
                    "Eligible",
                    "Approved",
                    "Payment",
                  ].map((heading) => (
                    <th
                      key={heading}
                      style={{
                        textAlign: "left",
                        padding: 8,
                        borderBottom: "1px solid var(--eng-border,#e6e8ec)",
                      }}
                    >
                      {heading}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.slice(0, 100).map((item) => {
                  const source = item.source_snapshot || {};
                  return (
                    <tr key={item.earning_id}>
                      <td style={{ padding: 8 }}>{item.employee_name}</td>
                      <td style={{ padding: 8 }}>{item.earning_name}</td>
                      <td style={{ padding: 8 }}>
                        {source.deal_name || item.source_external_id || "—"}
                      </td>
                      <td style={{ padding: 8 }}>{item.earned_date || "—"}</td>
                      <td style={{ padding: 8 }}>
                        {source.source_amount != null
                          ? `${money(source.source_amount)}${
                              source.component_rate != null
                                ? ` × ${percent(source.component_rate)}`
                                : ""
                            }`
                          : "—"}
                      </td>
                      <td style={{ padding: 8 }}>{money(item.earned_amount)}</td>
                      <td style={{ padding: 8 }}>{money(item.eligible_amount)}</td>
                      <td style={{ padding: 8 }}>{money(item.approved_amount)}</td>
                      <td style={{ padding: 8 }}>
                        {item.payment_status.replaceAll("_", " ")}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {rows.length > 100 && (
              <small>Showing first 100 rows. CSV export includes all {rows.length}.</small>
            )}
          </div>
        </section>

        <section className="eng-card">
          <div className="eng-card__head">
            <div>
              <h2>Payment-ready payroll report</h2>
              <p>
                Approved compensation currently eligible to be scheduled for payroll. A
                completed Finance handoff may be represented by the payment-ready status
                even on legacy records where Finance Accepted At was not populated.
              </p>
            </div>
            <button
              className="eng-btn eng-btn--primary"
              onClick={exportPayroll}
              disabled={!payable.length}
            >
              <Download size={16} />
              Export payroll CSV
            </button>
          </div>
          <div className="eng-card__body">
            {payable.length === 0 ? (
              <div className="eng-empty eng-empty--inline">
                <h2>No payment-ready compensation in this view</h2>
                <p>
                  Approved earnings appear here after all payment-required approvals and
                  handoffs are complete.
                </p>
              </div>
            ) : (
              <div style={{ overflowX: "auto" }}>
                <table
                  style={{ width: "100%", borderCollapse: "collapse", minWidth: 760 }}
                >
                  <thead>
                    <tr>
                      {["Employee", "Earning", "Pay period", "Approved", "Remaining"].map(
                        (heading) => (
                          <th
                            key={heading}
                            style={{
                              textAlign: "left",
                              padding: 8,
                              borderBottom: "1px solid var(--eng-border,#e6e8ec)",
                            }}
                          >
                            {heading}
                          </th>
                        ),
                      )}
                    </tr>
                  </thead>
                  <tbody>
                    {payable.map((item) => (
                      <tr key={item.earning_id}>
                        <td style={{ padding: 8 }}>{item.employee_name}</td>
                        <td style={{ padding: 8 }}>{item.earning_name}</td>
                        <td style={{ padding: 8 }}>{item.pay_period_label || "—"}</td>
                        <td style={{ padding: 8 }}>{money(item.approved_amount)}</td>
                        <td style={{ padding: 8 }}>{money(item.remaining_amount ?? 0)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </section>
      </div>
    </main>
  );
}
