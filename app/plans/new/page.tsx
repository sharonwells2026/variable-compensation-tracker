"use client";

import {FormEvent,useState} from "react";
import Link from "next/link";
import {useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,ArrowRight,Check,RotateCcw} from "lucide-react";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

function makePlanCode(value:string){return value.trim().toUpperCase().replace(/[^A-Z0-9]+/g,"-").replace(/^-+|-+$/g,"").replace(/-+/g,"-").slice(0,80)}

export default function NewPlanPage(){
 const router=useRouter();
 const[name,setName]=useState("");const[code,setCode]=useState("");const[codeEdited,setCodeEdited]=useState(false);const[description,setDescription]=useState("");
 const[startDate,setStartDate]=useState(new Date().toISOString().slice(0,10));const[endDate,setEndDate]=useState("");const[currency,setCurrency]=useState("USD");const[notes,setNotes]=useState("");
 const[saving,setSaving]=useState(false);const[error,setError]=useState("");
 const onNameChange=(value:string)=>{setName(value);if(!codeEdited)setCode(makePlanCode(value))};
 const resetCode=()=>{setCodeEdited(false);setCode(makePlanCode(name))};
 const submit=async(e:FormEvent)=>{e.preventDefault();setError("");if(endDate&&endDate<startDate){setError("Effective end date must be on or after the effective start date.");return}setSaving(true);
   const{data,error:rpcError}=await supabase.rpc("create_compensation_plan",{selected_name:name,selected_plan_code:code,selected_description:description||null,selected_plan_type:"variable_compensation",selected_effective_start_date:startDate,selected_currency_code:currency,selected_notes:notes||null});
   if(rpcError){setSaving(false);setError(rpcError.message);return}const versionId=data?.plan_version_id;
   if(versionId){const{error:updateError}=await supabase.rpc("update_compensation_plan_draft_version",{selected_plan_version_id:versionId,selected_effective_start_date:startDate,selected_effective_end_date:endDate||null,selected_currency_code:currency,selected_notes:notes||null});if(updateError){setSaving(false);setError("The plan was created, but the plan details could not be fully saved. Please reopen the draft and try again.");return}}
   setSaving(false);router.push(versionId?`/plans/applicability/${versionId}`:"/plans");
 };
 return <main className="plan-workspace"><div className="plan-page-shell">
   <div className="plan-breadcrumb"><Link href="/plans"><ArrowLeft size={15}/>Plans</Link><span>/</span><span>New plan</span></div>
   <header className="plan-page-header"><div><span className="plan-kicker">PLAN BUILDER · STEP 1 OF 6</span><h1>Plan basics</h1><p>Start with the plan name, dates and purpose. Clicking Next step saves this draft automatically and takes you to who the plan applies to.</p><small><b>* Required</b></small></div><span className="plan-status draft">Draft</span></header>
   <form onSubmit={submit} className="plan-editor-card">
     <div className="plan-editor-heading"><div><span className="plan-step-number">1</span><div><h2>Name and effective period</h2><p>You can leave at any later step and return to the same draft. Nothing affects an employee until the completed plan is approved and activated.</p></div></div></div>
     {error&&<div className="plan-alert error">{error}</div>}
     <div className="plan-form-grid two">
       <label>Plan name <span aria-hidden="true" style={{color:"#b42318"}}>*</span><input value={name} onChange={e=>onNameChange(e.target.value)} placeholder="e.g. Wes Morris 2026 Variable Compensation" required/><small>Use the name employees and Finance will recognize.</small></label>
       <label>Plan code <span aria-hidden="true" style={{color:"#b42318"}}>*</span><div style={{display:"flex",gap:8,alignItems:"center"}}><input value={code} onChange={e=>{setCodeEdited(true);setCode(makePlanCode(e.target.value))}} placeholder="Auto-generated from plan name" required/><span className="plan-status" style={{whiteSpace:"nowrap"}}>{codeEdited?"Edited":"Auto"}</span></div><small>{codeEdited?<button type="button" onClick={resetCode} style={{border:0,background:"transparent",padding:0,color:"#0879d5",fontWeight:700,cursor:"pointer",display:"inline-flex",gap:4,alignItems:"center"}}><RotateCcw size={12}/>Reset to auto</button>:"Usually leave this as generated."}</small></label>
       <label>Effective start date <span aria-hidden="true" style={{color:"#b42318"}}>*</span><input type="date" value={startDate} onChange={e=>setStartDate(e.target.value)} required/><small>The first date this plan may create earnings.</small></label>
       <label>Effective end date <span style={{fontWeight:400,color:"#667085"}}>(optional)</span><input type="date" min={startDate} value={endDate} onChange={e=>setEndDate(e.target.value)}/><small>Leave blank for an open-ended plan.</small></label>
       <label>Currency <span aria-hidden="true" style={{color:"#b42318"}}>*</span><select value={currency} onChange={e=>setCurrency(e.target.value)} required><option value="USD">USD — U.S. Dollar</option></select></label>
     </div>
     <label className="plan-full-field">Description<textarea value={description} onChange={e=>setDescription(e.target.value)} rows={3} placeholder="Who this plan is for and what it covers."/><small>Shown to administrators reviewing the plan.</small></label>
     <label className="plan-full-field">Internal notes<textarea value={notes} onChange={e=>setNotes(e.target.value)} rows={3} placeholder="Optional implementation or review notes."/></label>
     <div className="plan-info-row"><Check size={16}/><span><b>Autosave flow:</b> Next step creates the draft and saves these details. Every later step will save before it advances.</span></div>
     <div className="plan-actions"><Link href="/plans" className="plan-button secondary">Cancel</Link><button disabled={saving} className="plan-button brand" type="submit">{saving?"Saving…":"Next step"}<ArrowRight size={16}/></button></div>
   </form>
 </div></main>;
}
