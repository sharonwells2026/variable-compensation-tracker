"use client";

import {FormEvent,useState} from "react";
import Link from "next/link";
import {useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,Check,Save} from "lucide-react";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

function makePlanCode(value:string){
  return value
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g,"_")
    .replace(/^_+|_+$/g,"")
    .replace(/_+/g,"_")
    .slice(0,80);
}

export default function NewPlanPage(){
 const router=useRouter();
 const[name,setName]=useState("");
 const[code,setCode]=useState("");
 const[codeEdited,setCodeEdited]=useState(false);
 const[description,setDescription]=useState("");
 const[startDate,setStartDate]=useState(new Date().toISOString().slice(0,10));
 const[currency,setCurrency]=useState("USD");
 const[notes,setNotes]=useState("");
 const[saving,setSaving]=useState(false);
 const[error,setError]=useState("");
 const onNameChange=(value:string)=>{
   setName(value);
   if(!codeEdited)setCode(makePlanCode(value));
 };
 const submit=async(e:FormEvent)=>{
   e.preventDefault();setError("");setSaving(true);
   const{data,error:rpcError}=await supabase.rpc("create_compensation_plan",{
     selected_name:name,selected_plan_code:code,selected_description:description||null,
     selected_plan_type:"variable_compensation",selected_effective_start_date:startDate,
     selected_currency_code:currency,selected_notes:notes||null
   });
   setSaving(false);
   if(rpcError){setError(rpcError.message);return;}
   const versionId=data?.plan_version_id;
   router.push(versionId?`/plans/component/new?version=${versionId}`:"/plans");
 };
 return <main className="plan-workspace"><div className="plan-page-shell">
   <div className="plan-breadcrumb"><Link href="/plans"><ArrowLeft size={15}/>Plans & Rules</Link><span>/</span><span>New plan</span></div>
   <header className="plan-page-header"><div><span className="plan-kicker">PLAN SETUP</span><h1>Create compensation plan</h1><p>Create the plan first. After you save it, we will take you directly to the first compensation earning to configure.</p></div></header>
   <div className="plan-lifecycle-strip"><div><span>1</span><b>Plan basics</b><small>Name and dates</small></div><div><span>2</span><b>Compensation earnings</b><small>What the plan pays</small></div><div><span>3</span><b>Earned rules</b><small>What must happen to earn it</small></div><div><span>4</span><b>Eligible rules</b><small>What must happen before payment</small></div><div><span>5</span><b>People & review</b><small>Who it applies to and readiness</small></div></div>
   <form onSubmit={submit} className="plan-editor-card">
     <div className="plan-editor-heading"><div><span className="plan-step-number">1</span><div><h2>Plan basics</h2><p>Create a draft first. Nothing becomes active until it is reviewed and activated.</p></div></div><span className="plan-status draft">Draft</span></div>
     {error&&<div className="plan-alert error">{error}</div>}
     <p style={{fontSize:12,color:"#667085",marginTop:0}}><b>* Required field</b></p>
     <div className="plan-form-grid two">
       <label>Plan name <span aria-hidden="true">*</span><input value={name} onChange={e=>onNameChange(e.target.value)} placeholder="e.g. Wes Morris 2027 Variable Compensation Plan" required/></label>
       <label>Plan code <span aria-hidden="true">*</span><input value={code} onChange={e=>{setCodeEdited(true);setCode(makePlanCode(e.target.value))}} placeholder="Auto-generated from plan name" required/><small>Generated automatically from the plan name. You can edit it before saving.</small></label>
       <label>Effective start date <span aria-hidden="true">*</span><input type="date" value={startDate} onChange={e=>setStartDate(e.target.value)} required/></label>
       <label>Currency <span aria-hidden="true">*</span><select value={currency} onChange={e=>setCurrency(e.target.value)} required><option value="USD">USD</option></select></label>
     </div>
     <label className="plan-full-field">Description<textarea value={description} onChange={e=>setDescription(e.target.value)} rows={3} placeholder="Plain-language description of who this plan is for and what it covers."/></label>
     <label className="plan-full-field">Internal notes<textarea value={notes} onChange={e=>setNotes(e.target.value)} rows={3} placeholder="Optional implementation or review notes."/></label>
     <div className="plan-info-row"><Check size={16}/><span>After you create the draft, the next screen will be <b>Add compensation earning</b>. You will not have to figure out where to go next.</span></div>
     <div className="plan-actions"><Link href="/plans" className="plan-button secondary">Cancel</Link><button disabled={saving} className="plan-button primary" type="submit"><Save size={16}/>{saving?"Creating…":"Create plan & continue"}</button></div>
   </form>
 </div></main>;
}
