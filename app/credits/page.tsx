"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { createClient } from "@supabase/supabase-js";
import {
  AlertTriangle,
  ArrowLeft,
  CheckCircle2,
  Clock3,
  Database,
  GitBranch,
  Users,
} from "lucide-react";

const supabaseUrl =
  process.env.NEXT_PUBLIC_SUPABASE_URL ||
  "https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  "sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase = createClient(supabaseUrl, supabaseKey);

type Summary = {
  candidate_count?: number;
  eligible_candidate_count?: number;
  pending_condition_count?: number;
  generated_earning_count?: number;
  open_review_count?: number;
};

type Row = {
  candidate_key: string;
  hubspot_deal_id: string;
  deal_name: string;
  company_name: string;
  employee_name: string;
  plan_name: string;
  component_name: string;
  credit_percentage: number;
  source_amount: number;
  calculated_earning_amount: number;
  calculation_status: string;
  eligibility_status: string;
  earned_date?: string;
  earning_id?: string;
  earning_amount?: number;
  earning_eligibility_status?: string;
  payment_status?: string;
  review_status?: string;
  review_type?: string;
  review_question?: string;
  hubspot_record_url?: string;
};

type Review = {
  id: string;
  employee_name: string;
  hubspot_deal_id: string;
  review_type: string;
  review_question: string;
  review_status: string;
  decision_notes?: string;
};

type Payload = {
  summary?: Summary;
  lineage?: Row[];
  reviews?: Review[];
};

const money = (value?: number) =>
  new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(Number(value || 0));

const statusLabel = (value?: string) => {
  const labels: Record<string, string> = {
    eligible: "Eligible",
    pending_condition: "Waiting on eligibility",
    ready_for_payroll: "Accepted / Unpaid",
    not_payable: "Unpaid",
    paid: "Paid",
    ready: "Calculated",
  };
  return labels[value || ""] || String(value || "—").replaceAll("_", " ");
};

export default function CreditsPage() {
  const [data, setData] = useState<Payload>({});
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState("all");

  useEffect(() => {
    void (async () => {
      const { data: result, error: rpcError } = await supabase.rpc(
        "get_compensation_credits_workspace_data",
      );
      if (rpcError) setError(rpcError.message);
      else setData((result || {}) as Payload);
      setLoading(false);
    })();
  }, []);

  const rows = data.lineage || [];
  const visible = useMemo(
    () =>
      rows.filter(
        (row) =>
          filter === "all" ||
          (filter === "eligible" && row.eligibility_status === "eligible") ||
          (filter === "waiting" &&
            row.eligibility_status === "pending_condition") ||
          (filter === "review" && Boolean(row.review_status)),
      ),
    [rows, filter],
  );
  const summary = data.summary || {};

  const metrics = [
    {
      icon: <Database size={20} />,
      title: "Source candidates",
      value: summary.candidate_count || 0,
      copy: "Transactions evaluated against active compensation rules",
    },
    {
      icon: <CheckCircle2 size={20} />,
      title: "Eligible",
      value: summary.eligible_candidate_count || 0,
      copy: "Calculated and currently eligible",
    },
    {
      icon: <Clock3 size={20} />,
      title: "Waiting",
      value: summary.pending_condition_count || 0,
      copy: "Earned but waiting on an eligibility condition",
    },
    {
      icon: <GitBranch size={20} />,
      title: "Generated earnings",
      value: summary.generated_earning_count || 0,
      copy: "Current earning ledger records",
    },
    {
      icon: <AlertTriangle size={20} />,
      title: "Open reviews",
      value: summary.open_review_count || 0,
      copy: "Attribution decisions still requiring resolution",
    },
  ];

  const filters = [
    ["all", "All"],
    ["eligible", "Eligible"],
    ["waiting", "Waiting"],
    ["review", "Reviewed attribution"],
  ];

  return (
    <main
      style={{
        minHeight: "100vh",
        background: "#f5f7fa",
        padding: "clamp(16px,3vw,28px)",
        fontFamily: "Inter,Arial,sans-serif",
        color: "#051b34",
      }}
    >
      <div style={{ maxWidth: 1280, margin: "0 auto" }}>
        <header style={{ marginBottom: 22 }}>
          <Link
            href="/manage"
            style={{
              display: "inline-flex",
              gap: 6,
              alignItems: "center",
              textDecoration: "none",
              color: "#647184",
              fontWeight: 700,
              fontSize: 13,
            }}
          >
            <ArrowLeft size={15} />
            Control Center
          </Link>
          <small
            style={{
              display: "block",
              fontWeight: 800,
              letterSpacing: 1.1,
              color: "#2095f3",
              marginTop: 12,
            }}
          >
            COMPENSATION ADMINISTRATION
          </small>
          <h1 style={{ fontSize: "clamp(28px,5vw,36px)", margin: "6px 0" }}>
            Earnings & Credits
          </h1>
          <p
            style={{
              margin: 0,
              color: "#647184",
              maxWidth: 900,
              lineHeight: 1.5,
            }}
          >
            Live traceability from source transaction to compensation attribution
            to generated earning. Calculation, eligibility, approval, and payment
            remain distinct.
          </p>
        </header>

        {error && (
          <div
            style={{
              padding: 14,
              borderRadius: 10,
              background: "#fff5f5",
              border: "1px solid #fed7d7",
              marginBottom: 16,
            }}
          >
            <b>Unable to load lineage.</b> {error}
          </div>
        )}

        <section
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit,minmax(180px,1fr))",
            gap: 10,
            marginBottom: 18,
          }}
        >
          {metrics.map((metric) => (
            <div
              key={metric.title}
              style={{
                background: "white",
                border: "1px solid #dfe6ee",
                borderRadius: 14,
                padding: 16,
              }}
            >
              <span style={{ color: "#2095f3" }}>{metric.icon}</span>
              <div style={{ fontSize: 28, fontWeight: 900, marginTop: 8 }}>
                {loading ? "…" : metric.value}
              </div>
              <b>{metric.title}</b>
              <p
                style={{
                  fontSize: 12,
                  color: "#718096",
                  lineHeight: 1.4,
                  margin: "5px 0 0",
                }}
              >
                {metric.copy}
              </p>
            </div>
          ))}
        </section>

        <section
          style={{
            background: "white",
            border: "1px solid #dfe6ee",
            borderRadius: 14,
            overflow: "hidden",
            marginBottom: 18,
          }}
        >
          <div
            style={{
              padding: 18,
              borderBottom: "1px solid #edf1f5",
              display: "flex",
              gap: 12,
              justifyContent: "space-between",
              alignItems: "center",
              flexWrap: "wrap",
            }}
          >
            <div>
              <h2 style={{ margin: 0, fontSize: 20 }}>
                Transaction → credit → earning
              </h2>
              <p style={{ margin: "4px 0 0", color: "#647184", fontSize: 13 }}>
                Each row preserves the source deal, attributed employee, plan
                component, calculated obligation, and ledger state.
              </p>
            </div>
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {filters.map(([key, label]) => (
                <button
                  key={key}
                  onClick={() => setFilter(key)}
                  style={{
                    border: "1px solid #ccd8e4",
                    borderRadius: 20,
                    padding: "7px 10px",
                    background: filter === key ? "#051b34" : "white",
                    color: filter === key ? "white" : "#42566a",
                    fontWeight: 750,
                  }}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>

          <div style={{ overflowX: "auto" }}>
            <table
              style={{ width: "100%", borderCollapse: "collapse", minWidth: 1000 }}
            >
              <thead>
                <tr>
                  {[
                    "Source transaction",
                    "Employee / credit",
                    "Plan component",
                    "Basis",
                    "Calculated earning",
                    "Eligibility",
                    "Ledger",
                  ].map((heading) => (
                    <th
                      key={heading}
                      style={{
                        textAlign: "left",
                        fontSize: 11,
                        textTransform: "uppercase",
                        letterSpacing: 0.6,
                        color: "#718096",
                        padding: "11px 14px",
                        background: "#f8fafc",
                        borderBottom: "1px solid #e6edf3",
                      }}
                    >
                      {heading}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {visible.map((row) => (
                  <tr key={row.candidate_key}>
                    <td
                      style={{
                        padding: 14,
                        borderBottom: "1px solid #edf1f5",
                        maxWidth: 280,
                      }}
                    >
                      <b>{row.company_name || row.deal_name}</b>
                      <div style={{ fontSize: 12, color: "#647184", marginTop: 3 }}>
                        {row.deal_name}
                      </div>
                      <div style={{ fontSize: 11, color: "#9aabb9", marginTop: 3 }}>
                        HubSpot #{row.hubspot_deal_id}
                      </div>
                    </td>
                    <td style={{ padding: 14, borderBottom: "1px solid #edf1f5" }}>
                      <b>{row.employee_name}</b>
                      <div style={{ fontSize: 12, color: "#647184" }}>
                        {Number(row.credit_percentage || 0)}% credit
                      </div>
                      {row.review_status && (
                        <div style={{ fontSize: 11, color: "#8a5b00", marginTop: 4 }}>
                          Attribution review: {statusLabel(row.review_status)}
                        </div>
                      )}
                    </td>
                    <td style={{ padding: 14, borderBottom: "1px solid #edf1f5" }}>
                      {row.component_name}
                      <div style={{ fontSize: 11, color: "#718096" }}>
                        {row.plan_name}
                      </div>
                    </td>
                    <td style={{ padding: 14, borderBottom: "1px solid #edf1f5" }}>
                      {money(row.source_amount)}
                    </td>
                    <td
                      style={{
                        padding: 14,
                        borderBottom: "1px solid #edf1f5",
                        fontWeight: 850,
                      }}
                    >
                      {money(row.calculated_earning_amount)}
                    </td>
                    <td style={{ padding: 14, borderBottom: "1px solid #edf1f5" }}>
                      {statusLabel(row.eligibility_status)}
                    </td>
                    <td style={{ padding: 14, borderBottom: "1px solid #edf1f5" }}>
                      {row.earning_id ? (
                        <>
                          <b>{money(row.earning_amount)}</b>
                          <div style={{ fontSize: 12, color: "#647184" }}>
                            {statusLabel(row.payment_status)}
                          </div>
                        </>
                      ) : (
                        <span style={{ color: "#8a5b00", fontWeight: 750 }}>
                          Candidate only
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
                {!loading && visible.length === 0 && (
                  <tr>
                    <td
                      colSpan={7}
                      style={{ padding: 28, textAlign: "center", color: "#718096" }}
                    >
                      No records match this view.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </section>

        <section
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit,minmax(320px,1fr))",
            gap: 14,
          }}
        >
          <div
            style={{
              background: "white",
              border: "1px solid #dfe6ee",
              borderRadius: 14,
              padding: 18,
            }}
          >
            <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
              <AlertTriangle color="#b7791f" />
              <h2 style={{ margin: 0, fontSize: 19 }}>Attribution reviews</h2>
            </div>
            <p style={{ color: "#647184", fontSize: 13, lineHeight: 1.45 }}>
              Conflicts are preserved as explicit decisions rather than silently
              guessed.
            </p>
            {(data.reviews || []).map((review) => (
              <div
                key={review.id}
                style={{ padding: "11px 0", borderTop: "1px solid #edf1f5" }}
              >
                <b>
                  {review.employee_name} · {statusLabel(review.review_status)}
                </b>
                <div style={{ fontSize: 13, marginTop: 3 }}>
                  {review.review_question}
                </div>
                {review.decision_notes && (
                  <div style={{ fontSize: 12, color: "#647184", marginTop: 4 }}>
                    {review.decision_notes}
                  </div>
                )}
              </div>
            ))}
            {!loading && (data.reviews || []).length === 0 && (
              <div style={{ color: "#718096" }}>No attribution reviews.</div>
            )}
          </div>

          <div
            style={{
              background: "white",
              border: "1px solid #dfe6ee",
              borderRadius: 14,
              padding: 18,
            }}
          >
            <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
              <Users color="#2095f3" />
              <h2 style={{ margin: 0, fontSize: 19 }}>Control rules</h2>
            </div>
            <p style={{ color: "#647184", fontSize: 13, lineHeight: 1.45 }}>
              Deal Owner defaults to 100% applicable credit unless a configured rule
              says otherwise. Multiple plan components do not imply split credit.
              Historical ownership is snapshotted. Approved and Paid history is
              corrected through controlled adjustments, never silent mutation.
            </p>
            <div
              style={{
                padding: 12,
                borderRadius: 10,
                background: "#eef7ff",
                fontSize: 12,
                lineHeight: 1.45,
              }}
            >
              <b>Next control layer:</b> manual reassignment will require a reason,
              audit event, and recalculation before approval. Approved/Paid items
              will route through return or adjustment workflows instead.
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}
