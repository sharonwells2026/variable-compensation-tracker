"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { createClient } from "@supabase/supabase-js";
import {
  ArrowLeft,
  CalendarDays,
  ChevronRight,
  FileCheck2,
  Plus,
  Save,
  ShieldCheck,
  Users,
} from "lucide-react";

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL || "https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || "sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Component = {
  component_id: string;
  name: string;
  component_code: string;
  calculation_type: string | null;
  measurement_source: string | null;
  measurement_period: string | null;
  maximum_payout: number | null;
  rule_configuration: any;
};

type Assignment = { employee_id: string; employee_name: string };

type Version = {
  version_id: string;
  version_number: number;
  status: string;
  effective_start_date: string;
  effective_end_date: string | null;
  currency_code: string;
  notes?: string | null;
  components: Component[];
  assignments: Assignment[];
  draft_assignments: Assignment[];
};

type Plan = {
  plan_id: string;
  name: string;
  plan_code: string;
  description: string | null;
  versions: Version[];
};

function title(value: string | null | undefined) {
  return String(value || "—")
    .replaceAll("_", " ")
    .replace(/\b\w/g, (x) => x.toUpperCase());
}

function pct(value: any) {
  return `${Number(value) * 100}%`;
}

function paySummary(component: Component) {
  const cfg = component.rule_configuration || {};
  if (component.calculation_type === "percentage" && cfg.rate != null) {
    return `${pct(cfg.rate)} of ${title(component.measurement_source)}`;
  }
  if (component.calculation_type === "tiered_percentage" && Array.isArray(cfg.tiers)) {
    return cfg.tiers
      .map(
        (tier: any) =>
          `${tier.minimum_contract_years || 0}${
            tier.maximum_contract_years ? `–${tier.maximum_contract_years}` : "+"
          } yr: ${pct(tier.rate)}`
      )
      .join(" · ");
  }
  if (component.calculation_type === "threshold_bonus") {
    return `${Number(cfg.threshold_amount || 0).toLocaleString("en-US", {
      style: "currency",
      currency: "USD",
      maximumFractionDigits: 0,
    })} threshold → ${Number(cfg.bonus_amount || 0).toLocaleString("en-US", {
      style: "currency",
      currency: "USD",
      maximumFractionDigits: 0,
    })} bonus`;
  }
  if (component.calculation_type === "fixed_amount" && cfg.amount != null) {
    return Number(cfg.amount).toLocaleString("en-US", {
      style: "currency",
      currency: "USD",
    });
  }
  return title(component.calculation_type);
}

export default function ManageDraftPlan() {
  const params = useParams<{ versionId: string }>();
  const router = useRouter();

  const [plans, setPlans] = useState<Plan[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [currency, setCurrency] = useState("USD");
  const [notes, setNotes] = useState("");

  useEffect(() => {
    (async () => {
      setLoading(true);
      const { data, error: loadError } = await supabase.rpc("get_compensation_plan_admin_data");
      if (loadError) {
        setError(loadError.message);
        setLoading(false);
        return;
      }
      const loadedPlans = (data?.plans || []) as Plan[];
      setPlans(loadedPlans);
      for (const plan of loadedPlans) {
        const version = plan.versions.find((item) => item.version_id === params.versionId);
        if (version) {
          setStartDate(version.effective_start_date || "");
          setEndDate(version.effective_end_date || "");
          setCurrency(version.currency_code || "USD");
          setNotes(version.notes || "");
          break;
        }
      }
      setLoading(false);
    })();
  }, [params.versionId]);

  const plan = useMemo(
    () => plans.find((item) => item.versions.some((version) => version.version_id === params.versionId)) || null,
    [plans, params.versionId]
  );
  const version = plan?.versions.find((item) => item.version_id === params.versionId) || null;
  const people = version?.status === "draft" ? version.draft_assignments : version?.assignments || [];

  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (!version || version.status !== "draft") return;
    if (endDate && startDate && endDate < startDate) {
      setError("Effective end date cannot be before the effective start date.");
      return;
    }

    setSaving(true);
    setError("");
    setMessage("");
    const { error: saveError } = await supabase.rpc("update_compensation_plan_draft_version", {
      selected_plan_version_id: version.version_id,
      selected_effective_start_date: startDate,
      selected_effective_end_date: endDate || null,
      selected_currency_code: currency,
      selected_notes: notes || null,
    });
    setSaving(false);
    if (saveError) {
      setError(saveError.message);
      return;
    }
    setMessage("Plan dates and details saved.");
  };

  if (loading) {
    return (
      <main className="plan-workspace">
        <div className="plan-page-shell"><div className="plan-empty">Loading plan…</div></div>
      </main>
    );
  }

  if (!plan || !version) {
    return (
      <main className="plan-workspace">
        <div className="plan-page-shell"><div className="plan-alert error">Plan version not found.</div></div>
      </main>
    );
  }

  if (version.status !== "draft") {
    return (
      <main className="plan-workspace">
        <div className="plan-page-shell">
          <div className="plan-alert warning">Only draft versions can be managed here.</div>
          <Link className="plan-button secondary" href={`/plans?version=${version.version_id}`}>Back to plan</Link>
        </div>
      </main>
    );
  }

  return (
    <main className="plan-workspace">
      <div className="plan-page-shell" style={{ paddingBottom: 80 }}>
        <div className="plan-breadcrumb">
          <Link href={`/plans?version=${version.version_id}`}><ArrowLeft size={15} />Plan</Link>
          <span>/</span><span>Manage draft</span>
        </div>

        <header className="plan-page-header">
          <div>
            <span className="plan-kicker">DRAFT PLAN</span>
            <h1>Manage {plan.name}</h1>
            <p>Draft v{version.version_number}. Configure the plan here, then use readiness to approve and activate it.</p>
          </div>
          <span className="plan-status draft">Draft v{version.version_number}</span>
        </header>

        {error && <div className="plan-alert error">{error}</div>}
        {message && <div className="plan-info-row">{message}</div>}

        <form className="plan-editor-card" onSubmit={save}>
          <section>
            <div className="plan-editor-heading">
              <div>
                <CalendarDays size={20} />
                <div>
                  <h2>Effective dates</h2>
                  <p>These dates determine when this version governs earnings. They do not change the active plan until this draft is approved and activated.</p>
                </div>
              </div>
            </div>
            <div className="plan-form-grid two">
              <label>Effective start date *<input type="date" required value={startDate} onChange={(e) => setStartDate(e.target.value)} /></label>
              <label>Effective end date<input type="date" min={startDate || undefined} value={endDate} onChange={(e) => setEndDate(e.target.value)} /><small>Leave blank when the plan has no planned end date.</small></label>
              <label>Currency<select value={currency} onChange={(e) => setCurrency(e.target.value)}><option value="USD">USD</option></select></label>
              <label>Version notes<textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="What changed in this version?" /></label>
            </div>
            <div style={{ display: "flex", justifyContent: "flex-end", marginTop: 14 }}>
              <button className="plan-button brand" disabled={saving}><Save size={14} />{saving ? "Saving…" : "Save plan details"}</button>
            </div>
          </section>
        </form>

        <section className="plan-section">
          <div className="plan-section-title">
            <div><h3>Earning Types & conditions</h3><p>Each earning type contains its payout logic, Earned conditions, and Eligible-for-payment conditions in one editor.</p></div>
            <Link className="plan-button brand" href={`/plans/component/new?version=${version.version_id}`}><Plus size={14} />Add Earning Type</Link>
          </div>
          {version.components.map((component) => (
            <Link
              key={component.component_id}
              href={`/plans/component/${component.component_id}?version=${version.version_id}`}
              style={{ textDecoration: "none", color: "inherit", display: "grid", gridTemplateColumns: "minmax(220px,1.2fr) minmax(260px,1.8fr) 28px", gap: 16, alignItems: "center", border: "1px solid #e3e8ef", borderRadius: 10, padding: "14px 16px", marginTop: 10, background: "white" }}
            >
              <div><b>{component.name}</b><div style={{ fontSize: 11, color: "#667085", fontFamily: "monospace", marginTop: 3 }}>{component.component_code}</div></div>
              <div>
                <small style={{ color: "#667085" }}>PAYOUT</small>
                <div style={{ fontSize: 12, fontWeight: 700, marginTop: 3 }}>{paySummary(component)}</div>
                <div style={{ fontSize: 11, color: "#667085", marginTop: 4 }}>
                  {title(component.measurement_period)} · based on {title(component.measurement_source)}
                  {component.maximum_payout != null ? ` · max ${Number(component.maximum_payout).toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 })}` : ""}
                </div>
              </div>
              <ChevronRight size={18} />
            </Link>
          ))}
          {!version.components.length && <div className="plan-empty">No Earning Types yet.</div>}
        </section>

        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(260px,1fr))", gap: 16, marginTop: 16 }}>
          <section className="plan-section" style={{ margin: 0 }}>
            <div className="plan-section-title">
              <div><h3>People</h3><p>{people.length} employee{people.length === 1 ? "" : "s"} currently included in this draft.</p></div>
              <Link className="plan-button secondary" href={`/plans/applicability/${version.version_id}`}><Users size={14} />Manage people</Link>
            </div>
            {people.map((person) => <div key={person.employee_id} style={{ fontSize: 13, padding: "8px 0", borderTop: "1px solid #eef1f4" }}>{person.employee_name}</div>)}
          </section>

          <section className="plan-section" style={{ margin: 0 }}>
            <div className="plan-section-title">
              <div><h3>Approvals</h3><p>Define who must approve earnings generated under this plan.</p></div>
              <Link className="plan-button secondary" href={`/plans/manage/${version.version_id}/approvals`}><ShieldCheck size={14} />Manage approvals</Link>
            </div>
            <p style={{ fontSize: 12, color: "#667085", lineHeight: 1.6 }}>At least one required approval step is needed before the plan can be approved.</p>
          </section>

          <section className="plan-section" style={{ margin: 0 }}>
            <div className="plan-section-title">
              <div><h3>Agreements</h3><p>Attach signed compensation agreements for employees assigned to this plan.</p></div>
              <Link className="plan-button secondary" href={`/plans/agreements/${version.version_id}`}><FileCheck2 size={14} />Manage agreements</Link>
            </div>
            <p style={{ fontSize: 12, color: "#667085", lineHeight: 1.6 }}>Readiness will identify anyone assigned to the plan who is still missing an agreement.</p>
          </section>

          <section className="plan-section" style={{ margin: 0 }}>
            <h3 style={{ marginTop: 0 }}>Ready to review?</h3>
            <p style={{ fontSize: 12, color: "#667085", lineHeight: 1.6 }}>Readiness checks earning types, Earned conditions, payment conditions, effective dates, people, agreements, and plan approvals before approval is allowed.</p>
            <button type="button" className="plan-button brand" onClick={() => router.push(`/plans?version=${version.version_id}`)}>Review readiness</button>
          </section>
        </div>
      </div>
    </main>
  );
}
