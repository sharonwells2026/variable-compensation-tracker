"use client";

import {FormEvent,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,Copy,FilePlus2,Save,ShieldCheck} from "lucide-react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");
type Version={version_id:string;version_number:number;status:string;effective_start_date:string;effective_end_date:string|null;currency_code:string;components:any[]};
type Plan={plan_id:string;name:string;plan_code:string;versions:Version[]};
type StartMode="copy"|"clean";

export default function NewVersionPage(){
 const router=useRouter();
 const[plans,setPlans]=useState<Plan[]>([]),[planId,setPlanId]=useState(""),[startDate,setStartDate]=useState(new Date().toISOString().slice(0,10)),[endDate,setEndDate]=useState(""),[currency,setCurrency]=useState("USD"),[notes,setNotes]=useState(""),[mode,setMode]=useState<StartMode>("copy"),[saving,setSaving]=useState(false),[error,setError]=useState("");
 useEffect(()=>{(async()=>{const q=new URLSearchParams(window.location.search);const requestedPlan=q.get("plan")||"";const{data,error}=await supabase.rpc("get_compensation_plan_admin_data");if(error){setError(error.message);return}const ps=(data?.plans||[]) as Plan[];setPlans(ps);setPlanId(requestedPlan||ps[0]?.plan_id||"")})()},[]);
 const plan=useMemo(()=>plans.find(p=>p.plan_id===planId),[plans,planId]);
 const existingDraft=plan?.versions.find(v=>v.status==="draft")||null;
 const activeVersion=plan?.versions.find(v=>v.status==="active")||null;
 useEffect(()=>{if(!activeVersion&&mode==="copy")setMode("clean")},[activeVersion?.version_id,mode]);
 const submit=async(e:FormEvent)=>{
  e.preventDefault();
  if(existingDraft){setError(`Version ${existingDraft.version_number} is already the working draft for this plan. Open that draft instead of creating another.`);return}
  if(mode==="copy"&&!activeVersion){setError("This plan does not have an active version to copy. Start with a clean draft instead.");return}
  setError("");setSaving(true);
  const response=mode==="copy"&&activeVersion
   ?await supabase.rpc("create_compensation_plan_version_from_source",{selected_plan_id:planId,source_plan_version_id:activeVersion.version_id,selected_effective_start_date:startDate,selected_effective_end_date:endDate||null,selected_currency_code:currency,selected_notes:notes||null})
   :await supabase.rpc("create_compensation_plan_version",{selected_plan_id:planId,selected_effective_start_date:startDate,selected_effective_end_date:endDate||null,selected_currency_code:currency,selected_notes:notes||null,copy_components_from_version_id:null});
  setSaving(false);
  if(response.error){setError(response.error.code==="23505"?"This plan already has a working draft. Open that draft and continue there.":response.error.message);return}
  router.push(`/plans?version=${response.data?.plan_version_id||""}`)
 };
 return <main className="plan-workspace"><div className="plan-page-shell">
  <div className="plan-breadcrumb"><Link href="/plans"><ArrowLeft size={15}/>Plans</Link><span>/</span><span>Edit plan</span></div>
  <header className="plan-page-header"><div><span className="plan-kicker">PLAN EDITING</span><h1>Edit plan in a new draft</h1><p>The active version keeps running while you prepare, validate, and approve the next version.</p></div></header>
  {error&&<div className="plan-alert error">{error}</div>}
  <form className="plan-editor-card" onSubmit={submit}>
   <div className="plan-editor-heading"><div><span className="plan-step-number"><Copy size={14}/></span><div><h2>How should this draft start?</h2><p>Most edits should begin with the current active version. Start clean only when the new plan is fundamentally different.</p></div></div><span className="plan-status draft">Draft only</span></div>
   <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(280px,1fr))",gap:12,marginBottom:20}}>
    <label style={{display:"block",border:mode==="copy"?"2px solid #2095f3":"1px solid #d7dee8",borderRadius:12,padding:16,cursor:activeVersion?"pointer":"not-allowed",background:mode==="copy"?"#f4faff":"#fff",opacity:activeVersion?1:.55}}>
     <div style={{display:"flex",gap:10,alignItems:"flex-start"}}><input type="radio" name="startMode" checked={mode==="copy"} disabled={!activeVersion} onChange={()=>setMode("copy")} style={{marginTop:3}}/><div><div style={{display:"flex",alignItems:"center",gap:7,fontWeight:700}}><Copy size={15}/>Start from the active version</div><p style={{margin:"6px 0 0",fontSize:12.5,color:"#5b6b7f",lineHeight:1.45}}>{activeVersion?`Copies Active v${activeVersion.version_number} earning types, compensation rules, attribution rules, and current employee applicability into the new draft.`:"No active version is available to copy."}</p></div></div>
    </label>
    <label style={{display:"block",border:mode==="clean"?"2px solid #2095f3":"1px solid #d7dee8",borderRadius:12,padding:16,cursor:"pointer",background:mode==="clean"?"#f4faff":"#fff"}}>
     <div style={{display:"flex",gap:10,alignItems:"flex-start"}}><input type="radio" name="startMode" checked={mode==="clean"} onChange={()=>setMode("clean")} style={{marginTop:3}}/><div><div style={{display:"flex",alignItems:"center",gap:7,fontWeight:700}}><FilePlus2 size={15}/>Start from scratch</div><p style={{margin:"6px 0 0",fontSize:12.5,color:"#5b6b7f",lineHeight:1.45}}>Creates an empty draft. Use this when the new version should be rebuilt rather than edited from the current structure.</p></div></div>
    </label>
   </div>
   <div className="plan-form-grid two"><label>Plan<select value={planId} onChange={e=>setPlanId(e.target.value)} required>{plans.map(p=><option key={p.plan_id} value={p.plan_id}>{p.name}</option>)}</select></label><label>Effective start date<input type="date" value={startDate} onChange={e=>setStartDate(e.target.value)} required/></label><label>Effective end date<input type="date" value={endDate} onChange={e=>setEndDate(e.target.value)}/></label><label>Currency<select value={currency} onChange={e=>setCurrency(e.target.value)}><option>USD</option></select></label></div>
   {existingDraft&&<div className="plan-alert warning">This plan already has draft version {existingDraft.version_number}. Only one working draft is allowed at a time. <Link href={`/plans?version=${existingDraft.version_id}`}>Open the existing draft</Link>.</div>}
   {mode==="copy"&&activeVersion&&<div className="plan-info-row"><ShieldCheck size={15}/>Active v{activeVersion.version_number} and all historical earnings remain unchanged. Rule-preview history and signed agreements are intentionally not copied; the new version must be revalidated and its agreement coverage confirmed before approval.</div>}
   <label className="plan-full-field">Version notes<textarea rows={3} value={notes} onChange={e=>setNotes(e.target.value)} placeholder="What are you changing in this version, and what should be checked before activation?"/></label>
   <div className="plan-info-row">Creating this draft does not retire or modify the active version. Employees move to the new version only after readiness is complete, the draft is approved, and it is explicitly activated.</div>
   <div className="plan-actions"><Link className="plan-button secondary" href="/plans">Cancel</Link><button className="plan-button primary" disabled={saving||Boolean(existingDraft)}><Save size={15}/>{saving?"Creating…":mode==="copy"?"Create editable copy":"Create clean draft"}</button></div>
  </form>
 </div></main>;
}
