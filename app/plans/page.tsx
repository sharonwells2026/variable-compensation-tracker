"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {ChevronRight,Plus,RefreshCw,SlidersHorizontal} from "lucide-react";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Component={component_id:string;name:string;component_code:string;description:string|null;calculation_type:string|null;measurement_source:string|null;measurement_period:string|null;calculation_order:number;maximum_payout:number|null;is_active:boolean;payout_timing_method:string;measurement_label:string|null;additional_eligibility_waiting_days:number|null;rule_configuration:any};
type Assignment={assignment_id:string;employee_id:string;employee_name:string;allocation_percent:number;effective_start_date:string;effective_end_date:string|null;earnings_eligibility_date:string|null};
type Version={version_id:string;version_number:number;status:string;effective_start_date:string;effective_end_date:string|null;currency_code:string;notes:string|null;approved_at:string|null;components:Component[];assignments:Assignment[]};
type Plan={plan_id:string;name:string;plan_code:string;description:string|null;plan_type:string;is_active:boolean;versions:Version[]};
type Payload={plans:Plan[]};

function label(v:string|null|undefined){return String(v||"—").replaceAll("_"," ").replace(/\b\w/g,x=>x.toUpperCase())}
function money(v:number|null){return v==null?"No cap":new Intl.NumberFormat("en-US",{style:"currency",currency:"USD",maximumFractionDigits:0}).format(v)}
function rateText(c:Component){
 const cfg=c.rule_configuration||{};
 if(cfg.rate!=null)return `${Number(cfg.rate)*100}% of ${c.measurement_label||label(c.measurement_source)}`;
 if(cfg.amount_per_completed_qdc!=null)return `${money(cfg.amount_per_completed_qdc)} per qualifying activity`;
 if(cfg.bonus_amount!=null)return `${money(cfg.bonus_amount)} bonus`;
 if(Array.isArray(cfg.tiers))return `${cfg.tiers.length} tier${cfg.tiers.length===1?"":"s"} based on contract term`;
 if(Array.isArray(cfg.milestones))return `${cfg.milestones.length} milestone bonuses`;
 return label(c.calculation_type);
}
function earnedText(c:Component){
 const cfg=c.rule_configuration||{};
 if(cfg.earned_condition==="qualifying_stage")return "When the configured activity reaches its qualifying stage";
 if(cfg.earned_condition==="closed_won")return "When the qualifying deal closes won";
 if(cfg.earned_condition==="customer_signature_and_payment")return "Legacy: customer signature and payment";
 if(c.measurement_source==="hubspot_meeting")return "When a qualifying meeting is completed";
 if(c.measurement_source==="book_of_business")return "When the year-end book threshold is met";
 if(c.measurement_source==="new_logo_arr")return "When the annual ARR milestone is reached";
 return "Defined by the component qualification rule";
}
function eligibleText(c:Component){
 const cfg=c.rule_configuration||{};
 const eligibility=cfg.eligibility;
 if(eligibility?.mode==="immediate")return "Immediately — no extra condition";
 if(eligibility?.mode==="waiting_period")return `After ${eligibility.waiting_days||0} day${eligibility.waiting_days===1?"":"s"}`;
 if(eligibility?.mode==="rule")return eligibility.description||"When the custom eligibility rule passes";
 if(cfg.eligibility_condition==="customer_payment_received"||cfg.eligibility_condition==="paid_stage_and_invoice_paid_date")return "Legacy: when customer payment is recorded";
 if(c.additional_eligibility_waiting_days!=null)return c.additional_eligibility_waiting_days===0?"Immediately — no extra condition":`After ${c.additional_eligibility_waiting_days} days`;
 return "Not yet configured";
}

export default function PlansPage(){
 const[data,setData]=useState<Payload>({plans:[]});
 const[loading,setLoading]=useState(true),[error,setError]=useState("");
 const[selectedPlanId,setSelectedPlanId]=useState("");
 const[selectedVersionId,setSelectedVersionId]=useState("");
 const load=async()=>{setLoading(true);setError("");const{data:result,error:rpcError}=await supabase.rpc("get_compensation_plan_admin_data");if(rpcError)setError(rpcError.message);else{const next=(result||{plans:[]}) as Payload;setData(next);setSelectedPlanId(current=>current&&next.plans.some(p=>p.plan_id===current)?current:next.plans[0]?.plan_id||"");}setLoading(false)};
 useEffect(()=>{load()},[]);
 const selectedPlan=useMemo(()=>data.plans.find(p=>p.plan_id===selectedPlanId)||data.plans[0], [data.plans,selectedPlanId]);
 useEffect(()=>{if(selectedPlan)setSelectedVersionId(current=>current&&selectedPlan.versions.some(v=>v.version_id===current)?current:selectedPlan.versions[0]?.version_id||"")},[selectedPlan]);
 const selectedVersion=selectedPlan?.versions.find(v=>v.version_id===selectedVersionId)||selectedPlan?.versions[0];

 return <main className="plan-workspace"><div className="plan-page-shell">
   <div className="plan-toolbar"><div><span className="plan-kicker">PLAN CONFIGURATION</span><h1 style={{margin:"5px 0 6px",fontSize:32}}>Plans & Rules</h1><p style={{margin:0,color:"#667085",fontSize:12}}>Configure what each component pays, when it becomes Earned, what makes it Eligible, and who it applies to.</p></div><div className="plan-toolbar-actions"><button className="plan-button secondary" onClick={load} disabled={loading}><RefreshCw size={15}/>{loading?"Refreshing…":"Refresh"}</button><Link className="plan-button secondary" href="/plans/rules"><SlidersHorizontal size={15}/>Rule Builder</Link><Link className="plan-button brand" href="/plans/new"><Plus size={15}/>New plan</Link></div></div>
   <div className="plan-lifecycle-strip"><div><span>1</span><b>Qualifying activity</b><small>HubSpot or other source</small></div><div><span>2</span><b>Earned</b><small>Plan rules are met</small></div><div><span>3</span><b>Eligible</b><small>Extra condition is met</small></div><div><span>4</span><b>Approved</b><small>Required review is complete</small></div><div><span>5</span><b>Paid</b><small>Finance/payroll paid employee</small></div></div>
   {error&&<div className="plan-alert error">{error}</div>}
   <div className="plan-overview-grid">
     <aside className="plan-list-panel"><div className="plan-list-header"><h2>Compensation plans</h2><p>{data.plans.length} plan{data.plans.length===1?"":"s"} · select one to review</p></div><div className="plan-list">{data.plans.map(p=>{const active=p.versions.find(v=>v.status==="active"),draft=p.versions.find(v=>v.status==="draft");return <button key={p.plan_id} onClick={()=>setSelectedPlanId(p.plan_id)} className={selectedPlan?.plan_id===p.plan_id?"selected":""}><b>{p.name}</b><span>{p.plan_code}</span><span>{draft?`Draft v${draft.version_number}`:active?`Active v${active.version_number}`:"No current version"}</span></button>})}{!loading&&data.plans.length===0&&<div className="plan-empty" style={{margin:12}}>No plans yet.</div>}</div></aside>
     <section className="plan-detail-panel">{selectedPlan&&selectedVersion?<>
       <div className="plan-detail-header"><div><h2>{selectedPlan.name}</h2><p>{selectedPlan.plan_code} · {label(selectedPlan.plan_type)}{selectedPlan.description?` · ${selectedPlan.description}`:""}</p></div><span className={`plan-status ${selectedVersion.status}`}>{label(selectedVersion.status)} v{selectedVersion.version_number}</span></div>
       <div className="plan-version-tabs">{selectedPlan.versions.map(v=><button key={v.version_id} className={`plan-version-tab ${selectedVersion.version_id===v.version_id?"selected":""}`} onClick={()=>setSelectedVersionId(v.version_id)}>v{v.version_number} · {label(v.status)}</button>)}</div>
       <div className="plan-section"><div className="plan-section-title"><div><h3>Effective period & version</h3><p>Earnings keep the plan version they were calculated under.</p></div></div><div style={{display:"flex",gap:20,flexWrap:"wrap",fontSize:11,color:"#475467"}}><span><b>Starts:</b> {selectedVersion.effective_start_date}</span><span><b>Ends:</b> {selectedVersion.effective_end_date||"Open ended"}</span><span><b>Currency:</b> {selectedVersion.currency_code}</span></div></div>
       <div className="plan-section"><div className="plan-section-title"><div><h3>Compensation components</h3><p>Each component should make the Earned and Eligible distinction explicit.</p></div>{selectedVersion.status==="draft"&&<Link className="plan-button secondary" href={`/plans/component/new?version=${selectedVersion.version_id}`}><Plus size={14}/>Add component</Link>}</div>
         {selectedVersion.components.map(c=><div className="plan-component-row" key={c.component_id}><div className="plan-component-cell"><small>COMPONENT / PAYS</small><b>{c.name}</b><span>{rateText(c)} · {money(c.maximum_payout)}</span></div><div className="plan-component-cell earned"><small>EARNED WHEN</small><b>{earnedText(c)}</b><span>{c.component_code}</span></div><div className="plan-component-cell eligible"><small>ELIGIBLE WHEN</small><b>{eligibleText(c)}</b><span>{eligibleText(c).startsWith("Legacy")?"Rebuild this condition in the new configuration model.":""}</span></div><div className="plan-component-cell"><small>APPROVAL</small><b>Inherited employee workflow</b><span>Resolved at submission time</span></div><div className="plan-component-cell"><Link href={`/plans/component/${c.component_id}?version=${selectedVersion.version_id}`} className="plan-edit-link" aria-label={`Edit ${c.name}`}><ChevronRight size={18}/></Link></div></div>)}
         {selectedVersion.components.length===0&&<div className="plan-empty">This draft has no components yet. Add the first component to define what the plan pays.</div>}
       </div>
       <div className="plan-section"><div className="plan-section-title"><div><h3>Who it applies to</h3><p>Assignments are effective-dated. Prior activity is not silently backdated into a new assignment.</p></div></div>{selectedVersion.assignments.length>0?<div>{selectedVersion.assignments.map(a=><span className="plan-assignment-pill" key={a.assignment_id}><b>{a.employee_name}</b> · {a.allocation_percent}% · {a.effective_start_date}{a.effective_end_date?` → ${a.effective_end_date}`:""}</span>)}</div>:<div className="plan-empty">No employee assignments on this version.</div>}</div>
     </>:<div className="plan-empty" style={{margin:18}}>Select a plan to review.</div>}</section>
   </div>
 </div></main>;
}
