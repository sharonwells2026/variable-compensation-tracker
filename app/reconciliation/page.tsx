"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, CheckCircle2, RefreshCw, Scale } from "lucide-react";
import { createClient } from "@supabase/supabase-js";
import AdminShell from "../components/admin-shell";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"");

type DashboardData={unlinkedDeals:number;unreviewedChanges:number;recentChanges:Array<{detected_at:string;deal_name:string;field_name:string;old_value:string|null;new_value:string|null;review_status:string}>};
const empty:DashboardData={unlinkedDeals:0,unreviewedChanges:0,recentChanges:[]};

export default function ReconciliationPage(){
 const[data,setData]=useState<DashboardData>(empty),[loading,setLoading]=useState(true),[error,setError]=useState("");
 const load=async()=>{setLoading(true);setError("");const{data:r,error:e}=await supabase.rpc("get_compensation_dashboard_data");if(e)setError(e.message);else setData({...empty,...(r||{})});setLoading(false)};
 useEffect(()=>{load()},[]);
 const openIssues=(data.unlinkedDeals||0)+(data.unreviewedChanges||0);
 return <AdminShell section="reconciliation" title="Reconciliation" description="Identify source-data exceptions before they affect compensation calculations or payment."><div className="space-y-5">
  <div className="flex flex-wrap items-center justify-between gap-3"><div><h1 className="text-xl font-bold">Reconciliation workbench</h1><p className="mt-1 text-xs text-[#77808e]">Separate data exceptions from compensation approvals so problems are resolved at the right layer.</p></div><button onClick={load} disabled={loading} className="flex items-center gap-1 rounded-lg border bg-white px-3 py-2 text-xs font-bold"><RefreshCw size={14}/>Refresh</button></div>
  {error&&<div className="flex gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700"><AlertTriangle size={17}/><div><b>Reconciliation data could not load</b><div className="text-xs">{error}</div></div></div>}
  <div className="grid gap-3 md:grid-cols-3"><article className="rounded-xl border bg-white p-4 shadow-sm"><small className="text-[10px] font-bold text-[#77808e]">OPEN EXCEPTIONS</small><b className="mt-1 block text-2xl">{loading?"—":openIssues}</b><span className="text-[11px] text-[#77808e]">Source issues requiring review</span></article><article className="rounded-xl border bg-white p-4 shadow-sm"><small className="text-[10px] font-bold text-[#77808e]">UNLINKED DEALS</small><b className="mt-1 block text-2xl">{loading?"—":data.unlinkedDeals}</b><span className="text-[11px] text-[#77808e]">Deals without company association</span></article><article className="rounded-xl border bg-white p-4 shadow-sm"><small className="text-[10px] font-bold text-[#77808e]">CHANGES TO REVIEW</small><b className="mt-1 block text-2xl">{loading?"—":data.unreviewedChanges}</b><span className="text-[11px] text-[#77808e]">Detected changes marked for review</span></article></div>
  {openIssues===0&&!loading?<div className="rounded-xl border bg-white p-8 text-center shadow-sm"><CheckCircle2 className="mx-auto text-[#17795e]"/><b className="mt-3 block text-sm">No source exceptions are currently reported</b><p className="mt-1 text-xs text-[#77808e]">New issues will appear here when synchronized data requires reconciliation.</p></div>:<section className="rounded-xl border bg-white p-5 shadow-sm"><div className="flex items-center gap-2"><Scale size={17} className="text-[#2095f3]"/><h2 className="text-sm font-bold">Recent change review queue</h2></div><p className="mt-1 text-xs text-[#77808e]">This route now owns the exception workspace. Action-level reconciliation controls will be connected to the existing reconciliation records next rather than living inside the legacy root page.</p><div className="mt-4 overflow-x-auto"><div className="min-w-[760px]">{data.recentChanges.filter(x=>x.review_status==="unreviewed").length===0?<div className="rounded-lg bg-[#fafbfd] p-6 text-center text-xs text-[#77808e]">No recent unreviewed change records are available in the dashboard feed.</div>:data.recentChanges.filter(x=>x.review_status==="unreviewed").map((row,i)=><div key={`${row.detected_at}-${i}`} className="grid grid-cols-[160px_1.3fr_1fr_1.2fr_auto] gap-3 border-b py-3 text-xs"><span className="text-[#77808e]">{new Date(row.detected_at).toLocaleString()}</span><b>{row.deal_name}</b><span>{row.field_name}</span><span className="text-[#77808e]">{row.old_value??"—"} → {row.new_value??"—"}</span><span className="rounded-full bg-amber-50 px-2 py-1 text-[10px] font-bold text-amber-800">Needs review</span></div>)}</div></div></section>}
 </div></AdminShell>;
}
