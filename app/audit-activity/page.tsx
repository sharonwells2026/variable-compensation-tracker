"use client";

import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, History, RefreshCw } from "lucide-react";
import { createClient } from "@supabase/supabase-js";
import AdminShell from "../components/admin-shell";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"");

type Event={event_id:string;event_type:string;event_reason:string|null;occurred_at:string;actor_user_id:string|null;actor_name:string|null;target_user_id:string|null;target_name:string|null;related_employee_id:string|null;employee_name:string|null;related_plan_id:string|null;previous_state:any;new_state:any};

export default function AuditActivityPage(){
 const[events,setEvents]=useState<Event[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState(""),[query,setQuery]=useState("");
 const load=async()=>{setLoading(true);setError("");const{data,error:e}=await supabase.rpc("get_admin_audit_activity",{selected_limit:200});if(e)setError(e.message);else setEvents(data?.events||[]);setLoading(false)};
 useEffect(()=>{load()},[]);
 const filtered=useMemo(()=>{const q=query.trim().toLowerCase();if(!q)return events;return events.filter(e=>[e.event_type,e.event_reason,e.actor_name,e.target_name,e.employee_name].some(v=>String(v||"").toLowerCase().includes(q)))},[events,query]);
 return <AdminShell section="audit" title="Audit & Activity" description="Permission-scoped historical activity across access, compensation, approvals, finance, payroll, and configuration."><div className="space-y-5">
  <div className="flex flex-wrap items-center justify-between gap-3"><div><h1 className="text-xl font-bold">Audit trail</h1><p className="mt-1 text-xs text-[#77808e]">Read-only operational history. Visibility follows audit permissions and assigned employee scope.</p></div><button onClick={load} disabled={loading} className="flex items-center gap-1 rounded-lg border bg-white px-3 py-2 text-xs font-bold"><RefreshCw size={14}/>Refresh</button></div>
  {error&&<div className="flex gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700"><AlertTriangle size={17}/><div><b>Unable to load audit activity</b><div className="text-xs">{error}</div></div></div>}
  <section className="rounded-xl border bg-white p-4 shadow-sm"><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search event type, employee, actor, target or reason" className="w-full rounded-lg border px-3 py-2 text-sm"/></section>
  {loading?<div className="rounded-xl border bg-white p-8 text-center text-sm text-[#77808e]">Loading activity…</div>:filtered.length===0?<div className="rounded-xl border bg-white p-8 text-center"><History className="mx-auto text-[#2095f3]"/><b className="mt-3 block text-sm">No audit events match this view</b></div>:<div className="space-y-3">{filtered.map(e=><section key={e.event_id} className="rounded-xl border bg-white p-4 shadow-sm"><div className="flex flex-wrap items-start justify-between gap-3"><div><div className="flex flex-wrap items-center gap-2"><b className="text-sm">{e.event_type.replaceAll("_"," ")}</b>{e.employee_name&&<span className="rounded-full bg-[#eef7ff] px-2 py-1 text-[10px] font-bold text-[#0879d5]">{e.employee_name}</span>}</div><p className="mt-1 text-xs text-[#66717f]">{e.event_reason||"No reason recorded"}</p></div><time className="text-[11px] text-[#77808e]">{new Date(e.occurred_at).toLocaleString()}</time></div><div className="mt-3 grid gap-3 rounded-lg bg-[#fafbfd] p-3 text-xs md:grid-cols-3"><div><small className="text-[9px] font-bold text-[#77808e]">ACTOR</small><b className="block">{e.actor_name||e.actor_user_id||"System"}</b></div><div><small className="text-[9px] font-bold text-[#77808e]">TARGET</small><b className="block">{e.target_name||e.employee_name||e.target_user_id||"—"}</b></div><div><small className="text-[9px] font-bold text-[#77808e]">CHANGE SNAPSHOT</small><b className="block">{e.new_state?"Recorded":"No structured state"}</b></div></div>{e.new_state&&<details className="mt-3 rounded-lg border bg-white p-3 text-xs"><summary className="cursor-pointer font-bold">View recorded state</summary><pre className="mt-3 overflow-auto whitespace-pre-wrap text-[11px]">{JSON.stringify({previous_state:e.previous_state,new_state:e.new_state},null,2)}</pre></details>}</section>)}</div>}
 </div></AdminShell>;
}
