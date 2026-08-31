"use client";

import { useEffect, useMemo, useState } from "react";
import { createClient } from "@supabase/supabase-js";
import { AlertTriangle, ChevronRight, RefreshCw, Search, ShieldCheck, UserPlus, Users } from "lucide-react";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || "";
const supabase = supabaseKey ? createClient(supabaseUrl, supabaseKey) : null;

type EmployeeAdminRecord = {
  employee_id: string;
  full_name: string;
  email?: string | null;
  title?: string | null;
  department?: string | null;
  manager_name?: string | null;
  is_active?: boolean;
  profile_status?: string | null;
  has_app_access?: boolean;
  plan_name?: string | null;
  plan_status?: string | null;
  plan_effective_start_date?: string | null;
  plan_effective_end_date?: string | null;
  earnings_eligibility_date?: string | null;
  workflow_name?: string | null;
  workflow_status?: string | null;
  readiness?: string | null;
  readiness_reasons?: string[] | null;
};

function badge(label:string, tone:"good"|"warn"|"muted"="muted") {
  return <span className={`employee-admin-badge ${tone}`}>{label}</span>;
}

function initials(name:string){return name.split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]?.toUpperCase()).join("")||"—"}

export default function EmployeeAdministration({go}:{go?:(screen:any)=>void}) {
  const [employees,setEmployees]=useState<EmployeeAdminRecord[]>([]);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [query,setQuery]=useState("");
  const [selected,setSelected]=useState<EmployeeAdminRecord|null>(null);

  const load=async()=>{
    if(!supabase){setError("Database connection is unavailable.");setLoading(false);return}
    setLoading(true);setError("");
    const {data,error}=await supabase.rpc("get_employee_administration_data");
    if(error){
      // 103B is deploy-safe before its richer admin RPC exists: fall back to the
      // workflow admin employee directory rather than rendering hard-coded people.
      const fallback=await supabase.rpc("get_approval_workflow_admin_data");
      if(fallback.error){setError(error.message);setEmployees([])}
      else {
        const raw:any=fallback.data||{};
        const list=Array.isArray(raw)?raw:(raw.employees||[]);
        setEmployees(list.map((x:any)=>({
          employee_id:x.employee_id||x.id,
          full_name:x.full_name||x.employee_name||"Unnamed employee",
          email:x.email,
          title:x.title,
          department:x.department,
          manager_name:x.manager_name,
          is_active:x.is_active!==false,
          profile_status:x.profile_status,
          has_app_access:Boolean(x.has_app_access||x.profile_id),
          plan_name:x.plan_name,
          plan_status:x.plan_status,
          earnings_eligibility_date:x.earnings_eligibility_date,
          workflow_name:x.workflow_name||x.current_workflow_name,
          workflow_status:x.workflow_status||x.current_workflow_status,
          readiness:x.readiness,
          readiness_reasons:x.readiness_reasons||[]
        })));
      }
    } else {
      const raw:any=data||{};
      setEmployees(Array.isArray(raw)?raw:(raw.employees||[]));
    }
    setLoading(false);
  };

  useEffect(()=>{load()},[]);
  useEffect(()=>{if(selected){const fresh=employees.find(x=>x.employee_id===selected.employee_id);if(fresh)setSelected(fresh)}},[employees]);

  const filtered=useMemo(()=>{
    const q=query.trim().toLowerCase();
    if(!q)return employees;
    return employees.filter(x=>[x.full_name,x.email,x.title,x.department,x.manager_name,x.plan_name].some(v=>String(v||"").toLowerCase().includes(q)));
  },[employees,query]);

  const counts=useMemo(()=>({
    total:employees.length,
    access:employees.filter(x=>x.has_app_access).length,
    plans:employees.filter(x=>x.plan_name).length,
    workflows:employees.filter(x=>x.workflow_name).length
  }),[employees]);

  return <div className="employee-admin">
    <div className="title employee-admin-title"><div><h1>Employees</h1><p>Manage employee records, application access, compensation plans, eligibility, and approval readiness.</p></div><div className="employee-admin-actions"><button className="secondary" onClick={load} disabled={loading}><RefreshCw/>Refresh</button><button className="primary" onClick={()=>go?.("settings")}><UserPlus/>Add employee / user</button></div></div>

    <div className="employee-admin-stats">
      <article><small>EMPLOYEES</small><b>{counts.total}</b><span>Active compensation records</span></article>
      <article><small>APP ACCESS</small><b>{counts.access}</b><span>Provisioned application users</span></article>
      <article><small>PLAN ASSIGNED</small><b>{counts.plans}</b><span>Employees with a plan assignment</span></article>
      <article><small>WORKFLOW READY</small><b>{counts.workflows}</b><span>Employees with approval routing</span></article>
    </div>

    <section className="card employee-admin-card">
      <div className="employee-admin-toolbar"><div><Users/><span><b>Employee directory</b><small>Operational readiness across compensation administration</small></span></div><label><Search/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search employees, roles, plans..."/></label></div>
      {error&&<div className="employee-admin-warning"><AlertTriangle/><div><b>Unable to load employee administration data</b><small>{error}</small></div></div>}
      {loading?<div className="employee-admin-empty">Loading employees…</div>:filtered.length===0?<div className="employee-admin-empty">No employees match this search.</div>:<div className="employee-admin-table">
        <div className="employee-admin-head"><span>Employee</span><span>App access</span><span>Compensation plan</span><span>Approval workflow</span><span>Readiness</span><span/></div>
        {filtered.map(employee=>{
          const ready=employee.readiness==="ready"||Boolean(employee.has_app_access&&employee.plan_name&&employee.workflow_name);
          return <button className="employee-admin-row" key={employee.employee_id} onClick={()=>setSelected(employee)}>
            <span className="employee-admin-person"><i>{initials(employee.full_name)}</i><span><b>{employee.full_name}</b><small>{[employee.title,employee.department].filter(Boolean).join(" · ")||employee.email||"Employee"}</small></span></span>
            <span>{employee.has_app_access?badge("Provisioned","good"):badge("Not provisioned","warn")}</span>
            <span>{employee.plan_name?<><b>{employee.plan_name}</b><small>{employee.plan_status||"Assigned"}{employee.earnings_eligibility_date?` · Eligible ${employee.earnings_eligibility_date}`:""}</small></>:badge("Missing plan","warn")}</span>
            <span>{employee.workflow_name?<><b>{employee.workflow_name}</b><small>{employee.workflow_status||"Configured"}</small></>:badge("Missing workflow","warn")}</span>
            <span>{ready?badge("Ready","good"):badge("Needs setup","warn")}</span>
            <ChevronRight/>
          </button>
        })}
      </div>}
    </section>

    {selected&&<div className="employee-admin-backdrop" onMouseDown={()=>setSelected(null)}><section className="employee-admin-drawer" onMouseDown={e=>e.stopPropagation()}><button className="employee-admin-close" onClick={()=>setSelected(null)}>×</button><div className="employee-admin-profile"><i>{initials(selected.full_name)}</i><div><small>EMPLOYEE</small><h2>{selected.full_name}</h2><p>{[selected.title,selected.department].filter(Boolean).join(" · ")||selected.email||""}</p></div></div>
      <div className="employee-admin-detail-grid"><article><small>MANAGER</small><b>{selected.manager_name||"Not assigned"}</b></article><article><small>APP ACCESS</small><b>{selected.has_app_access?"Provisioned":"Not provisioned"}</b></article><article><small>COMPENSATION PLAN</small><b>{selected.plan_name||"No plan assigned"}</b><span>{selected.earnings_eligibility_date?`Eligibility ${selected.earnings_eligibility_date}`:"Eligibility date not available"}</span></article><article><small>APPROVAL WORKFLOW</small><b>{selected.workflow_name||"No workflow configured"}</b></article></div>
      {selected.readiness_reasons?.length?<div className="employee-admin-readiness"><AlertTriangle/><div><b>Setup required</b>{selected.readiness_reasons.map(reason=><small key={reason}>{reason}</small>)}</div></div>:<div className="employee-admin-readiness good"><ShieldCheck/><div><b>Compensation setup is ready</b><small>No readiness issues are currently reported.</small></div></div>}
      <div className="employee-admin-drawer-actions"><button className="secondary" onClick={()=>go?.("plans")}>Manage compensation plan</button><a className="primary" href={`/approval-workflows?employee=${encodeURIComponent(selected.employee_id)}`}>Manage approval workflow</a></div>
    </section></div>}
  </div>
}
