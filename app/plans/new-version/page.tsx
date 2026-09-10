"use client";

import {FormEvent,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,Copy,Save} from "lucide-react";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Version={version_id:string;version_number:number;status:string;effective_start_date:string;effective_end_date:string|null;currency_code:string;components:any[]};
type Plan={plan_id:string;name:string;plan_code:string;versions:Version[]};

export default function NewVersionPage(){
 const router=useRouter();
 const[plans,setPlans]=useState<Plan[]>([]),[planId,setPlanId]=useState(""),[copyFrom,setCopyFrom]=useState(""),[startDate,setStartDate]=useState(new Date().toISOString().slice(0,10)),[endDate,setEndDate]=useState(""),[currency,setCurrency]=useState("USD"),[notes,setNotes]=useState(""),[saving,setSaving]=useState(false),[error,setError]=useState("");
 useEffect(()=>{(async()=>{const q=new URLSearchParams(window.location.search);const requestedPlan=q.get("plan")||"";const requestedCopy=q.get("copy")||"";const{data,error}=await supabase.rpc("get_compensation_plan_admin_data");if(error){setError(error.message);return;}const ps=(data?.plans||[]) as Plan[];setPlans(ps);setPlanId(requestedPlan||ps[0]?.plan_id||"");setCopyFrom(requestedCopy);})()},[]);
 const plan=useMemo(()=>plans.find(p=>p.plan_id===planId),[plans,planId]);
 const submit=async(e:FormEvent)=>{e.preventDefault();setError("");setSaving(true);const{data,error:rpcError}=await supabase.rpc("create_compensation_plan_version",{selected_plan_id:planId,selected_effective_start_date:startDate,selected_effective_end_date:endDate||null,selected_currency_code:currency,selected_notes:notes||null,copy_components_from_version_id:copyFrom||null});setSaving(false);if(rpcError){setError(rpcError.message);return;}router.push(`/plans?version=${data?.plan_version_id||""}`)};
 return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-breadcrumb"><Link href="/plans"><ArrowLeft size={15}/>Plans & Rules</Link><span>/</span><span>New draft version</span></div><header className="plan-page-header"><div><span className="plan-kicker">VERSIONING</span><h1>Create a new draft version</h1><p>Existing earnings remain tied to the version that calculated them. This draft can be rebuilt and tested without changing the active version.</p></div></header>{error&&<div className="plan-alert error">{error}</div>}<form className="plan-editor-card" onSubmit={submit}><div className="plan-editor-heading"><div><span className="plan-step-number"><Copy size={14}/></span><div><h2>Draft version</h2><p>Choose whether to start clean or copy the current structure as a reference.</p></div></div><span className="plan-status draft">Draft only</span></div><div className="plan-form-grid two"><label>Plan<select value={planId} onChange={e=>{setPlanId(e.target.value);setCopyFrom("")}} required>{plans.map(p=><option key={p.plan_id} value={p.plan_id}>{p.name}</option>)}</select></label><label>Copy components from<select value={copyFrom} onChange={e=>setCopyFrom(e.target.value)}><option value="">Start with no components</option>{plan?.versions.map(v=><option key={v.version_id} value={v.version_id}>Version {v.version_number} · {v.status} · {v.components.length} components</option>)}</select><small>For our clean-plan rebuilds, starting empty is safest. Copy only when you intentionally want the prior configuration as a starting point.</small></label><label>Effective start date<input type="date" value={startDate} onChange={e=>setStartDate(e.target.value)} required/></label><label>Effective end date<input type="date" value={endDate} onChange={e=>setEndDate(e.target.value)}/></label><label>Currency<select value={currency} onChange={e=>setCurrency(e.target.value)}><option>USD</option></select></label></div><label className="plan-full-field">Version notes<textarea rows={3} value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Why this version is being created, what changed, and what must be validated before activation."/></label><div className="plan-info-row">Creating this version does not retire or modify the active version. Activation remains a separate governed action.</div><div className="plan-actions"><Link className="plan-button secondary" href="/plans">Cancel</Link><button className="plan-button primary" disabled={saving}><Save size={15}/>{saving?"Creating…":"Create draft version"}</button></div></form></div></main>;
}
