"use client";

import {FormEvent,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useParams,useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,CheckCircle2,ExternalLink,HelpCircle,Save} from "lucide-react";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Component={component_id:string;name:string;component_code:string;description:string|null;calculation_type:string|null;measurement_source:string|null;measurement_period:string|null;calculation_order:number;maximum_payout:number|null;is_active:boolean;payout_timing_method:string;measurement_label:string|null;additional_eligibility_waiting_days:number|null;allow_manager_payout_override:boolean;rule_configuration:any};
type Version={version_id:string;version_number:number;status:string;components:Component[]};
type Plan={plan_id:string;name:string;versions:Version[]};
type RuleSetSummary={id:string;plan_component_id:string;name:string;purpose:string;version:number;is_active:boolean};
type EligibilityMode="immediate"|"customer_payment"|"waiting_period"|"rule";

const slug=(v:string)=>v.toUpperCase().trim().replace(/[^A-Z0-9]+/g,"_").replace(/^_+|_+$/g,"").slice(0,80);
function existingMode(c:Component|null):EligibilityMode{
 const e=c?.rule_configuration?.eligibility;
 if(e?.business_concept==="customer_payment_received")return "customer_payment";
 if(e?.mode==="immediate"||e?.mode==="waiting_period"||e?.mode==="rule")return e.mode;
 const legacy=c?.rule_configuration?.eligibility_condition;
 if(legacy==="customer_payment_received"||legacy==="paid_stage_and_invoice_paid_date")return "customer_payment";
 return "immediate";
}
function Help({children}:{children:React.ReactNode}){return <span title={String(children)} style={{display:"inline-flex",alignItems:"center",gap:4,color:"#667085",fontWeight:500,fontSize:11}}><HelpCircle size={13}/>{children}</span>}

export default function CompensationEarningEditor(){
 const params=useParams<{componentId:string}>();
 const router=useRouter();
 const isNew=params.componentId==="new";
 const[plans,setPlans]=useState<Plan[]>([]),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 const[versionId,setVersionId]=useState("");
 const[name,setName]=useState(""),[code,setCode]=useState(""),[codeTouched,setCodeTouched]=useState(false),[description,setDescription]=useState("");
 const[calculationType,setCalculationType]=useState("percentage"),[measurementSource,setMeasurementSource]=useState("amount"),[customMeasurementSource,setCustomMeasurementSource]=useState(""),[measurementPeriod,setMeasurementPeriod]=useState("per_deal"),[maximumPayout,setMaximumPayout]=useState("");
 const[ratePercent,setRatePercent]=useState("");
 const[eligibilityMode,setEligibilityMode]=useState<EligibilityMode>("immediate"),[waitingDays,setWaitingDays]=useState("0"),[eligibilityDescription,setEligibilityDescription]=useState("");
 const[ruleConfig,setRuleConfig]=useState<any>({});
 const[ruleSets,setRuleSets]=useState<RuleSetSummary[]>([]),[selectedEligibilityRuleSet,setSelectedEligibilityRuleSet]=useState("");
 const[dirty,setDirty]=useState(false),[savedComponentId,setSavedComponentId]=useState(isNew?"":params.componentId);

 useEffect(()=>{(async()=>{
   setLoading(true);setError("");
   const q=new URLSearchParams(window.location.search);const requestedVersion=q.get("version")||"";const returnedRuleSet=q.get("ruleSet")||"";const returnedPurpose=q.get("purpose")||"";const returnedChoice=q.get("eligibilityChoice") as EligibilityMode|null;
   const{data,error:rpcError}=await supabase.rpc("get_compensation_plan_admin_data");
   if(rpcError){setError(rpcError.message);setLoading(false);return;}
   const ps=(data?.plans||[]) as Plan[];setPlans(ps);
   if(isNew){setVersionId(requestedVersion);if(returnedChoice)setEligibilityMode(returnedChoice);setLoading(false);return;}
   for(const p of ps){for(const v of p.versions){const c=v.components.find(x=>x.component_id===params.componentId);if(c){
     const cfg=c.rule_configuration||{};setVersionId(v.version_id);setName(c.name);setCode(c.component_code);setCodeTouched(true);setDescription(c.description||"");setCalculationType(c.calculation_type||"percentage");setMeasurementSource(["amount","average_arr","book_of_business","hubspot_meeting"].includes(c.measurement_source||"")?(c.measurement_source||"amount"):"custom");setCustomMeasurementSource(["amount","average_arr","book_of_business","hubspot_meeting"].includes(c.measurement_source||"")?"":(c.measurement_source||""));setMeasurementPeriod(c.measurement_period||"per_deal");setMaximumPayout(c.maximum_payout==null?"":String(c.maximum_payout));setRatePercent(cfg.rate!=null?String(Number(cfg.rate)*100):"");setRuleConfig(cfg);
     setEligibilityMode(returnedChoice||existingMode(c));const e=cfg.eligibility;setWaitingDays(String(e?.waiting_days??c.additional_eligibility_waiting_days??0));setEligibilityDescription(e?.description||"");setSelectedEligibilityRuleSet(returnedPurpose==="eligibility"&&returnedRuleSet?returnedRuleSet:e?.rule_set_id||"");
   }}}
   setLoading(false);
 })()},[isNew,params.componentId]);

 useEffect(()=>{if(!savedComponentId)return;(async()=>{const{data,error:catalogError}=await supabase.rpc("get_comp_rule_builder_catalog",{target_plan_component_id:savedComponentId});if(catalogError){setError(catalogError.message);return;}setRuleSets((data?.rule_sets||[]) as RuleSetSummary[]);})()},[savedComponentId]);
 useEffect(()=>{const f=(e:BeforeUnloadEvent)=>{if(!dirty)return;e.preventDefault();e.returnValue=""};window.addEventListener("beforeunload",f);return()=>window.removeEventListener("beforeunload",f)},[dirty]);
 const mark=()=>{setDirty(true);setMessage("")};
 const selectedPlan=useMemo(()=>plans.find(p=>p.versions.some(v=>v.version_id===versionId)),[plans,versionId]);
 const selectedVersion=selectedPlan?.versions.find(v=>v.version_id===versionId);const editable=selectedVersion?.status==="draft";
 const eligibilityRuleSets=ruleSets.filter(r=>r.purpose==="eligibility");const qualificationRuleSets=ruleSets.filter(r=>r.purpose==="qualification");
 const actualMeasurementSource=measurementSource==="custom"?customMeasurementSource:measurementSource;
 const ruleBuilderHref=(purpose:string,ruleSetId?:string)=>{const returnTo=`/plans/component/${savedComponentId}?version=${versionId}${purpose==="eligibility"?`&eligibilityChoice=${eligibilityMode}`:""}`;const q=new URLSearchParams();if(ruleSetId)q.set("ruleSet",ruleSetId);else{q.set("component",savedComponentId);q.set("purpose",purpose);}q.set("returnTo",returnTo);return `/plans/rules?${q.toString()}`};

 const save=async(e:FormEvent)=>{
   e.preventDefault();if(!versionId){setError("A draft plan version is required.");return;}if(!editable){setError("Only draft plan versions can be edited.");return;}if(!name.trim()||!code.trim()){setError("Complete all required fields marked with *.");return;}if(calculationType==="percentage"&&(ratePercent===""||Number(ratePercent)<0)){setError("Enter the percentage the employee earns.");return;}if(!actualMeasurementSource){setError("Choose what the calculation is based on.");return;}
   setSaving(true);setError("");setMessage("");
   const nextRuleConfig={...(ruleConfig||{})};if(calculationType==="percentage")nextRuleConfig.rate=Number(ratePercent)/100;else delete nextRuleConfig.rate;
   const{data,error:componentError}=await supabase.rpc("save_compensation_plan_component",{selected_plan_version_id:versionId,selected_component_id:savedComponentId||null,selected_name:name.trim(),selected_component_code:code.trim(),selected_description:description||null,selected_calculation_type:calculationType,selected_measurement_source:actualMeasurementSource,selected_measurement_period:measurementPeriod,selected_calculation_order:1,selected_rule_configuration:nextRuleConfig,selected_maximum_payout:maximumPayout===""?null:Number(maximumPayout),selected_is_active:true,selected_payout_timing_method:"annual",selected_allow_manager_payout_override:true,selected_measurement_label:null});
   if(componentError){setSaving(false);setError(componentError.message);return;}
   const id=String(data?.component_id||savedComponentId);setSavedComponentId(id);setRuleConfig(nextRuleConfig);
   const ruleId=(eligibilityMode==="rule"||eligibilityMode==="customer_payment")?(selectedEligibilityRuleSet||null):null;
   const{error:eligError}=await supabase.rpc("save_compensation_plan_component_eligibility",{selected_component_id:id,selected_mode:eligibilityMode,selected_waiting_days:eligibilityMode==="waiting_period"?Number(waitingDays||0):null,selected_rule_set_id:ruleId,selected_description:eligibilityDescription||null});
   if(eligError){setSaving(false);setError(`The earning was saved, but the Eligible condition could not be saved: ${eligError.message}`);return;}
   setDirty(false);setSaving(false);setMessage(ruleId||eligibilityMode==="immediate"||eligibilityMode==="waiting_period"?"Saved.":"Saved. Your Eligible choice is preserved; finish its rule before activation.");
   if(isNew)router.replace(`/plans/component/${id}?version=${versionId}`);
 };

 if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Loading compensation earning…</div></div></main>;
 return <main className="plan-workspace"><div className="plan-page-shell" style={{paddingBottom:90}}>
   <div className="plan-breadcrumb"><Link href="/plans"><ArrowLeft size={15}/>Plans</Link><span>/</span><span>{selectedPlan?.name||"Plan"}</span><span>/</span><span>{isNew?"Add earning":name||"Earning"}</span></div>
   <header className="plan-page-header"><div><span className="plan-kicker">COMPENSATION EARNING</span><h1>{isNew?"Add an earning to this plan":name||"Compensation earning"}</h1><p>Define what the employee earns, when they earn it, and what must happen before it can be paid.</p><small><b>* Required field</b></small></div>{selectedVersion&&<span className={`plan-status ${selectedVersion.status}`}>{selectedVersion.status} v{selectedVersion.version_number}</span>}</header>
   {dirty&&<div className="plan-alert warning">Unsaved changes</div>}{error&&<div className="plan-alert error">{error}</div>}{message&&<div className="plan-info-row"><CheckCircle2 size={16}/>{message}</div>}
   <form onSubmit={save} className="plan-editor-card">
     <section>
       <div className="plan-editor-heading"><div><span className="plan-step-number">1</span><div><h2>What does the employee earn?</h2><p>Start with the payout. Conditions for earning it come next.</p></div></div></div>
       <div className="plan-form-grid two">
         <label>Earning name *<input value={name} onChange={e=>{const v=e.target.value;setName(v);if(!codeTouched)setCode(slug(v));mark()}} placeholder="Retention commission" required disabled={!editable}/></label>
         <label>Earning code *<input value={code} onChange={e=>{setCodeTouched(true);setCode(slug(e.target.value));mark()}} required disabled={!editable}/><Help>Auto-created from the name. You can change it.</Help></label>
         <label>How is it calculated? *<select value={calculationType} onChange={e=>{setCalculationType(e.target.value);mark()}} disabled={!editable}><option value="percentage">Percentage</option><option value="tiered_percentage">Different percentages by tier</option><option value="fixed_amount">Fixed dollar amount</option><option value="fixed_amount_per_unit">Fixed amount for each qualifying item</option><option value="milestone_bonus">Milestone bonus</option><option value="threshold_bonus">Threshold bonus</option></select></label>
         {calculationType==="percentage"&&<label>Percentage earned *<div style={{display:"flex",alignItems:"center",gap:8}}><input type="number" min="0" step="0.01" value={ratePercent} onChange={e=>{setRatePercent(e.target.value);mark()}} placeholder="2" required disabled={!editable}/><b>%</b></div></label>}
         <label>Percentage or amount is based on *<select value={measurementSource} onChange={e=>{setMeasurementSource(e.target.value);mark()}} disabled={!editable}><option value="amount">Deal amount</option><option value="average_arr">Average annual recurring revenue (ARR)</option><option value="book_of_business">Book of business value</option><option value="hubspot_meeting">Qualifying meeting/activity</option><option value="custom">Something else…</option></select><Help>Choose the number or activity used to calculate this earning.</Help></label>
         {measurementSource==="custom"&&<label>Custom calculation basis *<input value={customMeasurementSource} onChange={e=>{setCustomMeasurementSource(e.target.value);mark()}} required disabled={!editable}/><Help>Use this only when the standard choices do not fit.</Help></label>}
         <label>How often is this calculated? *<select value={measurementPeriod} onChange={e=>{setMeasurementPeriod(e.target.value);mark()}} disabled={!editable}><option value="per_deal">For each qualifying deal/activity</option><option value="monthly">Monthly</option><option value="quarterly">Quarterly</option><option value="annual">Annually</option></select></label>
         <label>Maximum payout<input type="number" step="0.01" value={maximumPayout} onChange={e=>{setMaximumPayout(e.target.value);mark()}} placeholder="No maximum" disabled={!editable}/><Help>Optional. Leave blank if there is no cap.</Help></label>
       </div>
       <label className="plan-full-field">Description<textarea value={description} onChange={e=>{setDescription(e.target.value);mark()}} rows={2} placeholder="Optional plain-language explanation" disabled={!editable}/></label>
     </section>

     <section style={{marginTop:30}}>
       <div className="plan-editor-heading"><div><span className="plan-step-number">2</span><div><h2>When does the employee earn it?</h2><p>Describe which HubSpot records qualify. Example: Renewal deal + any Won stage + Customer Experience Manager is Wes Morris.</p></div></div>{savedComponentId&&<Link className="plan-button secondary" href={qualificationRuleSets[0]?ruleBuilderHref("qualification",qualificationRuleSets[0].id):ruleBuilderHref("qualification")}><ExternalLink size={14}/>{qualificationRuleSets[0]?"Edit earning conditions":"Set earning conditions"}</Link>}</div>
       {!savedComponentId?<div className="plan-alert warning">Save this earning first, then set the conditions that make it Earned.</div>:qualificationRuleSets.length?<div className="plan-info-row"><CheckCircle2 size={16}/>Earning conditions have been created. Open them to review or change them.</div>:<div className="plan-info-row">No earning conditions yet. This earning cannot be activated until you define them.</div>}
     </section>

     <section style={{marginTop:30}}>
       <div className="plan-editor-heading"><div><span className="plan-step-number">3</span><div><h2>What else must happen before it can be paid?</h2><p>This is the difference between Earned and Eligible.</p></div></div></div>
       <div className="eligibility-choice-grid">{([['immediate','Nothing else','It becomes Eligible as soon as it is Earned.'],['customer_payment','Customer payment received','The customer must pay Engagifii before this earning becomes Eligible.'],['waiting_period','Wait a set number of days','It becomes Eligible after a defined waiting period.'],['rule','Another condition','Use another business condition from approved synchronized data.']] as [EligibilityMode,string,string][]).map(([value,title,copy])=><label key={value} className={`eligibility-choice ${eligibilityMode===value?'selected':''}`}><input type="radio" name="eligibility" checked={eligibilityMode===value} onChange={()=>{setEligibilityMode(value);if(value==="immediate"||value==="waiting_period")setSelectedEligibilityRuleSet("");mark()}} disabled={!editable}/><div><b>{title}</b><span>{copy}</span></div></label>)}</div>
       {eligibilityMode==="waiting_period"&&<div className="plan-form-grid two" style={{marginTop:14}}><label>Number of days *<input type="number" min="0" value={waitingDays} onChange={e=>{setWaitingDays(e.target.value);mark()}} required disabled={!editable}/></label></div>}
       {(eligibilityMode==="customer_payment"||eligibilityMode==="rule")&&savedComponentId&&<div className="plan-info-row" style={{marginTop:14,justifyContent:"space-between"}}><span>{selectedEligibilityRuleSet?"Eligibility condition attached.":eligibilityMode==="customer_payment"?"Your Customer payment choice will save now. Next, define what HubSpot evidence proves the customer paid.":"Your choice will save now. Next, define the condition."}</span><Link className="plan-button secondary" href={selectedEligibilityRuleSet?ruleBuilderHref("eligibility",selectedEligibilityRuleSet):ruleBuilderHref("eligibility")}><ExternalLink size={14}/>{selectedEligibilityRuleSet?"Edit condition":"Define condition"}</Link></div>}
       {eligibilityRuleSets.length>0&&!selectedEligibilityRuleSet&&<label className="plan-full-field" style={{marginTop:12}}>Existing eligibility rule<select value={selectedEligibilityRuleSet} onChange={e=>{setSelectedEligibilityRuleSet(e.target.value);mark()}}><option value="">Choose a rule…</option>{eligibilityRuleSets.map(r=><option key={r.id} value={r.id}>{r.name} · v{r.version}</option>)}</select></label>}
       <label className="plan-full-field">Internal note<textarea value={eligibilityDescription} onChange={e=>{setEligibilityDescription(e.target.value);mark()}} rows={2} placeholder="Optional" disabled={!editable}/></label>
     </section>

     <div className="plan-actions" style={{position:"sticky",bottom:12,zIndex:30,background:"white",borderTop:"1px solid #e6e8ec",paddingTop:14,marginTop:28}}><Link href={`/plans?version=${versionId}`} className="plan-button secondary">Back to plan</Link><button disabled={saving||!editable} className="plan-button primary" type="submit"><Save size={16}/>{saving?"Saving…":dirty?"Save changes":"Save"}</button></div>
   </form>
 </div></main>;
}
