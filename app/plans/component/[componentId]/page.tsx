"use client";

import {FormEvent,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useParams,useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,ExternalLink,Save} from "lucide-react";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Component={component_id:string;name:string;component_code:string;description:string|null;calculation_type:string|null;measurement_source:string|null;measurement_period:string|null;calculation_order:number;maximum_payout:number|null;is_active:boolean;payout_timing_method:string;measurement_label:string|null;additional_eligibility_waiting_days:number|null;allow_manager_payout_override:boolean;rule_configuration:any};
type Version={version_id:string;version_number:number;status:string;components:Component[]};
type Plan={plan_id:string;name:string;versions:Version[]};

type EligibilityMode="immediate"|"customer_payment"|"waiting_period"|"rule";

function existingMode(c:Component|null):EligibilityMode{
 const e=c?.rule_configuration?.eligibility;
 if(e?.mode==="immediate"||e?.mode==="waiting_period"||e?.mode==="rule")return e.mode;
 const legacy=c?.rule_configuration?.eligibility_condition;
 if(legacy==="customer_payment_received"||legacy==="paid_stage_and_invoice_paid_date")return "customer_payment";
 return "immediate";
}

export default function ComponentEditor(){
 const params=useParams<{componentId:string}>();
 const router=useRouter();
 const isNew=params.componentId==="new";
 const[plans,setPlans]=useState<Plan[]>([]),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 const[versionId,setVersionId]=useState("");
 const[name,setName]=useState(""),[code,setCode]=useState(""),[description,setDescription]=useState("");
 const[calculationType,setCalculationType]=useState("percentage"),[measurementSource,setMeasurementSource]=useState("amount"),[measurementLabel,setMeasurementLabel]=useState(""),[measurementPeriod,setMeasurementPeriod]=useState("per_deal"),[maximumPayout,setMaximumPayout]=useState("");
 const[payoutTiming,setPayoutTiming]=useState("annual"),[managerOverride,setManagerOverride]=useState(true),[order,setOrder]=useState(1);
 const[eligibilityMode,setEligibilityMode]=useState<EligibilityMode>("immediate"),[waitingDays,setWaitingDays]=useState("0"),[eligibilityDescription,setEligibilityDescription]=useState("");
 const[ruleConfig,setRuleConfig]=useState<any>({});
 const[dirty,setDirty]=useState(false),[savedComponentId,setSavedComponentId]=useState(isNew?"":params.componentId);

 useEffect(()=>{(async()=>{setLoading(true);setError("");const q=typeof window!=="undefined"?new URLSearchParams(window.location.search):null;const requestedVersion=q?.get("version")||"";const{data,error:rpcError}=await supabase.rpc("get_compensation_plan_admin_data");if(rpcError){setError(rpcError.message);setLoading(false);return;}const ps=(data?.plans||[]) as Plan[];setPlans(ps);if(isNew){setVersionId(requestedVersion);setLoading(false);return;}for(const p of ps){for(const v of p.versions){const c=v.components.find(x=>x.component_id===params.componentId);if(c){setVersionId(v.version_id);setName(c.name);setCode(c.component_code);setDescription(c.description||"");setCalculationType(c.calculation_type||"percentage");setMeasurementSource(c.measurement_source||"amount");setMeasurementLabel(c.measurement_label||"");setMeasurementPeriod(c.measurement_period||"per_deal");setMaximumPayout(c.maximum_payout==null?"":String(c.maximum_payout));setPayoutTiming(c.payout_timing_method||"annual");setManagerOverride(c.allow_manager_payout_override!==false);setOrder(c.calculation_order||1);setRuleConfig(c.rule_configuration||{});setEligibilityMode(existingMode(c));const e=c.rule_configuration?.eligibility;setWaitingDays(String(e?.waiting_days??c.additional_eligibility_waiting_days??0));setEligibilityDescription(e?.description||"");}}}setLoading(false);})()},[isNew,params.componentId]);

 useEffect(()=>{const f=(e:BeforeUnloadEvent)=>{if(!dirty)return;e.preventDefault();e.returnValue=""};window.addEventListener("beforeunload",f);return()=>window.removeEventListener("beforeunload",f)},[dirty]);
 const mark=()=>{setDirty(true);setMessage("")};
 const selectedPlan=useMemo(()=>plans.find(p=>p.versions.some(v=>v.version_id===versionId)),[plans,versionId]);
 const selectedVersion=selectedPlan?.versions.find(v=>v.version_id===versionId);
 const editable=selectedVersion?.status==="draft";

 const save=async(e:FormEvent)=>{
   e.preventDefault();if(!versionId){setError("A draft plan version is required.");return;}if(!editable){setError("Only draft plan versions can be edited.");return;}
   setSaving(true);setError("");setMessage("");
   const{data,error:componentError}=await supabase.rpc("save_compensation_plan_component",{
     selected_plan_version_id:versionId,selected_component_id:savedComponentId||null,selected_name:name,selected_component_code:code,
     selected_description:description||null,selected_calculation_type:calculationType,selected_measurement_source:measurementSource||null,
     selected_measurement_period:measurementPeriod,selected_calculation_order:order,selected_rule_configuration:ruleConfig||{},
     selected_maximum_payout:maximumPayout===""?null:Number(maximumPayout),selected_is_active:true,
     selected_payout_timing_method:payoutTiming,selected_allow_manager_payout_override:managerOverride,selected_measurement_label:measurementLabel||null
   });
   if(componentError){setSaving(false);setError(componentError.message);return;}
   const id=String(data?.component_id||savedComponentId);
   setSavedComponentId(id);
   if(eligibilityMode==="immediate"||eligibilityMode==="waiting_period"){
     const{error:eligError}=await supabase.rpc("save_compensation_plan_component_eligibility",{
       selected_component_id:id,selected_mode:eligibilityMode,selected_waiting_days:eligibilityMode==="waiting_period"?Number(waitingDays||0):null,selected_rule_set_id:null,selected_description:eligibilityDescription||null
     });
     if(eligError){setSaving(false);setError(`Component saved, but eligibility could not be saved: ${eligError.message}`);return;}
   }
   setDirty(false);setSaving(false);setMessage("Draft component saved. Nothing has been activated.");
   if(isNew)router.replace(`/plans/component/${id}?version=${versionId}`);
 };

 if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Loading component configuration…</div></div></main>;
 return <main className="plan-workspace"><div className="plan-page-shell">
   <div className="plan-breadcrumb"><Link href="/plans"><ArrowLeft size={15}/>Plans & Rules</Link><span>/</span><span>{selectedPlan?.name||"Plan"}</span><span>/</span><span>{isNew?"New component":name||"Component"}</span></div>
   <header className="plan-page-header"><div><span className="plan-kicker">COMPONENT CONFIGURATION</span><h1>{isNew?"Add compensation component":name||"Compensation component"}</h1><p>Configure each part of the lifecycle separately so Earned and Eligible never mean the same thing by accident.</p></div>{selectedVersion&&<span className={`plan-status ${selectedVersion.status}`}>{selectedVersion.status} v{selectedVersion.version_number}</span>}</header>
   <div className="plan-lifecycle-strip"><div><span>1</span><b>What it pays</b><small>Calculation</small></div><div><span>2</span><b>Earned</b><small>Qualification rule</small></div><div><span>3</span><b>Eligible</b><small>Additional condition</small></div><div><span>4</span><b>Approved</b><small>Employee workflow</small></div><div><span>5</span><b>When it applies</b><small>Plan effective dates</small></div></div>
   {dirty&&<div className="plan-alert warning" style={{position:"sticky",top:12,zIndex:20}}>You have unsaved changes to this component.</div>}
   {error&&<div className="plan-alert error">{error}</div>}{message&&<div className="plan-info-row" style={{marginBottom:14}}>{message}</div>}
   <form onSubmit={save} className="plan-editor-card">
     <div className="plan-editor-heading"><div><span className="plan-step-number">1</span><div><h2>What it pays</h2><p>Define the calculation. Qualification belongs in the Earned rule, not in these fields.</p></div></div></div>
     <div className="plan-form-grid two">
       <label>Component name<input value={name} onChange={e=>{setName(e.target.value);mark()}} required disabled={!editable}/></label>
       <label>Component code<input value={code} onChange={e=>{setCode(e.target.value.toUpperCase().replace(/[^A-Z0-9_]/g,"_"));mark()}} required disabled={!editable}/></label>
       <label>Calculation type<select value={calculationType} onChange={e=>{setCalculationType(e.target.value);mark()}} disabled={!editable}><option value="percentage">Percentage</option><option value="tiered_percentage">Tiered percentage</option><option value="fixed_amount">Fixed amount</option><option value="fixed_amount_per_unit">Fixed amount per unit</option><option value="milestone_bonus">Milestone bonus</option><option value="threshold_bonus">Threshold bonus</option></select></label>
       <label>Measurement source<input value={measurementSource} onChange={e=>{setMeasurementSource(e.target.value);mark()}} placeholder="e.g. average_arr, amount, hubspot_meeting" disabled={!editable}/><small>This remains configurable rather than tied to one hardcoded HubSpot property.</small></label>
       <label>Display label<input value={measurementLabel} onChange={e=>{setMeasurementLabel(e.target.value);mark()}} placeholder="e.g. Average ARR" disabled={!editable}/></label>
       <label>Measurement period<input value={measurementPeriod} onChange={e=>{setMeasurementPeriod(e.target.value);mark()}} placeholder="per_deal, monthly, annual" disabled={!editable}/></label>
       <label>Maximum payout<input type="number" step="0.01" value={maximumPayout} onChange={e=>{setMaximumPayout(e.target.value);mark()}} placeholder="No cap" disabled={!editable}/></label>
       <label>Calculation order<input type="number" min={1} value={order} onChange={e=>{setOrder(Number(e.target.value));mark()}} disabled={!editable}/></label>
     </div>
     <label className="plan-full-field">Description<textarea value={description} onChange={e=>{setDescription(e.target.value);mark()}} rows={2} disabled={!editable}/></label>

     <div className="plan-editor-heading" style={{marginTop:28}}><div><span className="plan-step-number">2</span><div><h2>What makes it Earned</h2><p>The qualifying activity and business conditions are authored in Rule Builder.</p></div></div>{savedComponentId?<Link className="plan-button secondary" href={`/plans/rules?component=${savedComponentId}&purpose=qualification`}><ExternalLink size={14}/>Open Rule Builder</Link>:null}</div>
     {!savedComponentId?<div className="plan-alert warning">Save this component first. Then Rule Builder can attach the Earned qualification rule to it.</div>:<div className="plan-info-row">A qualifying source record makes compensation <b>Earned</b>. Payment or another later condition belongs under Eligible.</div>}

     <div className="plan-editor-heading" style={{marginTop:28}}><div><span className="plan-step-number">3</span><div><h2>What makes it Eligible</h2><p>Choose the additional condition, if any, that must be satisfied before the earning may move toward payment.</p></div></div></div>
     <div className="eligibility-choice-grid">
       {([
         ["immediate","Nothing else","Earned and Eligible on the same day."],
         ["customer_payment","Customer payment received","Use synchronized payment evidence. The underlying HubSpot field/value is configured, not hardcoded."],
         ["waiting_period","A waiting period","Wait a defined number of days after the earning date."],
         ["rule","A custom condition","Build an eligibility rule using approved synchronized data."]
       ] as [EligibilityMode,string,string][]).map(([value,title,copy])=><label key={value} className={`eligibility-choice ${eligibilityMode===value?"selected":""}`}><input type="radio" name="eligibility" checked={eligibilityMode===value} onChange={()=>{setEligibilityMode(value);mark()}} disabled={!editable}/><div><b>{title}</b><span>{copy}</span></div></label>)}
     </div>
     {eligibilityMode==="waiting_period"&&<div className="plan-form-grid two" style={{marginTop:14}}><label>Waiting days<input type="number" min={0} value={waitingDays} onChange={e=>{setWaitingDays(e.target.value);mark()}} disabled={!editable}/></label><label>Explanation shown to employee<input value={eligibilityDescription} onChange={e=>{setEligibilityDescription(e.target.value);mark()}} placeholder="e.g. Eligible 30 days after earning date" disabled={!editable}/></label></div>}
     {(eligibilityMode==="customer_payment"||eligibilityMode==="rule")&&<div className="plan-alert warning" style={{marginTop:14}}>{savedComponentId?<>This selection requires an <b>eligibility</b> rule set. Build and preview it in Rule Builder, then return here to attach it. The UI will not silently hardcode a HubSpot stage or property. <Link href={`/plans/rules?component=${savedComponentId}&purpose=eligibility`}>Build eligibility rule</Link>.</>:"Save the component first, then build the eligibility rule."}</div>}

     <div className="plan-editor-heading" style={{marginTop:28}}><div><span className="plan-step-number">4</span><div><h2>Who approves it</h2><p>Approval is inherited from the employee's effective-dated workflow in v1.</p></div></div></div>
     <div className="plan-info-row">The resolved approval chain will be shown when compensation is submitted. Components do not own separate approval chains in v1.</div>

     <div className="plan-editor-heading" style={{marginTop:28}}><div><span className="plan-step-number">5</span><div><h2>When it applies</h2><p>This component inherits the effective period of {selectedPlan?.name||"its plan version"}.</p></div></div></div>
     <div style={{display:"flex",gap:18,flexWrap:"wrap",fontSize:12,color:"#475467"}}><span><b>Version:</b> v{selectedVersion?.version_number||"—"}</span><span><b>Status:</b> {selectedVersion?.status||"—"}</span></div>
     <div className="plan-actions"><Link href="/plans" className="plan-button secondary">Back to plan</Link><button type="submit" className="plan-button primary" disabled={saving||!editable}><Save size={15}/>{saving?"Saving…":"Save draft component"}</button></div>
   </form>
 </div></main>;
}
