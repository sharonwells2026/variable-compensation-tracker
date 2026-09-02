"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, BarChart3, Database, FileBarChart, RefreshCw } from "lucide-react";
import { createClient } from "@supabase/supabase-js";
import AdminShell from "../components/admin-shell";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY||"";
const supabase=supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type Summary={deals:number;companies:number;associations:number;unlinkedDeals:number;unreviewedChanges:number;lastSync:string|null};
const empty:Summary={deals:0,companies:0,associations:0,unlinkedDeals:0,unreviewedChanges:0,lastSync:null};

export default function ReportsPage(){
 const[data,setData]=useState<Summary>(empty),[loading,setLoading]=useState(true),[error,setError]=useState("");
 const load=async()=>{if(!supabase){setError("Database connection is unavailable.");setLoading(false);return}setLoading(true);const{data:r,error:e}=await supabase.rpc("get_compensation_dashboard_data");if(e)setError(e.message);else{setError("");setData({...empty,...(r||{})})}setLoading(false)};
 useEffect(()=>{load()},[]);
 return <AdminShell section="reports" title="Reports & Analytics" description="Compensation performance, operational health, and export-ready analysis.">
   <div className="title"><div><h1>Reports & Analytics</h1><p>One reporting workspace for compensation, payroll, plan performance, employee attainment, exceptions, and source-data health.</p></div><button className="secondary" onClick={load} disabled={loading}><RefreshCw size={15}/>{loading?"Refreshing…":"Refresh"}</button></div>
   {error&&<div className="warning"><AlertTriangle/><div><b>Reporting data could not load</b><small>{error}</small></div></div>}
   <div className="stats">
     <article className="stat"><small>SOURCE DEALS</small><b>{loading?"—":data.deals.toLocaleString()}</b><span>HubSpot compensation source records</span></article>
     <article className="stat"><small>COMPANIES</small><b>{loading?"—":data.companies.toLocaleString()}</b><span>Associated company records</span></article>
     <article className="stat"><small>UNLINKED DEALS</small><b>{loading?"—":data.unlinkedDeals.toLocaleString()}</b><span>Potential reconciliation exceptions</span></article>
     <article className="stat"><small>CHANGES TO REVIEW</small><b>{loading?"—":data.unreviewedChanges.toLocaleString()}</b><span>{data.lastSync?`Last source refresh ${new Date(data.lastSync).toLocaleString()}`:"Source refresh history will appear here"}</span></article>
   </div>
   <div className="two">
     <section className="card panel"><div className="panel-head"><div><h2>Compensation reporting model</h2><p>Reports use the same effective-dated earning, eligibility, approval, and payment records as operational screens.</p></div><FileBarChart size={20}/></div><div className="admin-report-list"><div><b>Employee & team performance</b><span>Earned, eligible, approved, paid, attainment, targets, components, and trends.</span></div><div><b>Company compensation cost</b><span>Accrued liability, payable amounts, payment timing, plan/program cost, and forecast.</span></div><div><b>Plan effectiveness</b><span>Performance by plan, component, role, business unit, source, period, and employee.</span></div><div><b>Exceptions & controls</b><span>Missing source data, ownership conflicts, reconciliation gaps, overrides, holds, and unresolved approvals.</span></div></div></section>
     <section className="card panel"><div className="panel-head"><div><h2>Current data readiness</h2><p>Only measures backed by synchronized or calculated records appear as authoritative.</p></div><Database size={20}/></div><div className="admin-report-list"><div><b>HubSpot source health</b><span>{data.deals?`${data.deals.toLocaleString()} deals and ${data.companies.toLocaleString()} companies are available for analysis.`:"Source counts are not currently available."}</span></div><div><b>Variable compensation calculations</b><span>Compensation earnings, eligibility, approvals, payroll liability, and attainment populate here only after the calculation and reconciliation layers are validated.</span></div><div><b>Historical payroll</b><span>Prior payments remain distinguishable from current calculated liability so reports cannot accidentally overstate amounts owed.</span></div></div></section>
   </div>
   <section className="card panel"><div className="panel-head"><div><h2>Report library</h2><p>The reporting IA is established now; each report becomes interactive as its underlying operational data is activated.</p></div><BarChart3 size={20}/></div><div className="admin-report-library"><article><b>Compensation Summary</b><small>Earned → eligible → approved → scheduled → paid by period and employee.</small></article><article><b>Attainment & Targets</b><small>Quota, book, milestone, component, and goal attainment over time.</small></article><article><b>Payroll Liability</b><small>Approved/eligible liability, holds, upcoming payments, and aging.</small></article><article><b>Plan Performance</b><small>Cost and outcomes by plan, version, component, employee, and business unit.</small></article><article><b>Exception Analysis</b><small>Unmatched records, calculation flags, source changes, disputes, and overrides.</small></article><article><b>Audit & Change Report</b><small>Plan, calculation, approval, access, AI-assisted, and payment changes.</small></article></div></section>
 </AdminShell>
}
