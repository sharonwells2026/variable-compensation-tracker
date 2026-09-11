"use client";

import {FormEvent,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useParams,useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,CalendarDays,ChevronRight,Plus,Save,Users} from "lucide-react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");

type Component={component_id:string;name:string;component_code:string;calculation_type:string|null;measurement_source:string|null;measurement_period:string|null;maximum_payout:number|null;rule_configuration:any};
type Assignment={employee_id:string;employee_name:string};
type Version={version_id:string;version_number:number;status:string;effective_start_date:string;effective_end_date:string|null;currency_code:string;notes?:string|null;components:Component[];assignments:Assignment[];draft_assignments:Assignment[]};
type Plan={plan_id:string;name:string;plan_code:string;description:string|null;versions:Version[]};

function title(v:string|null|undefined){return String(v||"—").replaceAll("_"," ").replace(/\b\w/g,x=>x.toUpperCase())}
function pct(v:any){return `${Number(v)*100}%`}
function paySummary(c:Component){const cfg=c.rule_configuration||{};if(c.calculation_type==="percentage"&&cfg.rate!=null)return `${pct(cfg.rate)} of ${title(c.measurement_source)}`;if(c.calculation_type==="tiered_percentage"&&Array.isArray(cfg.tiers))return cfg.tiers.map((t:any)=>`${t.minimum_contract_years||0}${t.maximum_contract_years?`–${t.maximum_contract_years}`:"+"} yr: ${pct(t.rate)}`).join(" · ");if(c.calculation_type==="threshold_bonus")return `${Number(cfg.threshold_amount||0).toLocaleString("en-US",{style:"currency",currency:"USD",maximumFractionDigits:0})} threshold → ${Number(cfg.bonus_amount||0).toLocaleString("en-US",{style:"currency",currency:"USD",maximumFractionDigits:0})} bonus`;if(c.calculation_type==="fixed_amount"&&cfg.amount!=null)return Number(cfg.amount).toLocaleString("en-US",{style:"currency",currency:"USD"});return title(c.calculation_type)}

export default function ManageDraftPlan(){
 const params=useParams<{versionId:string}>();const router=useRouter();
 const[plans,setPlans]=useState<Plan[]>([]),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 const[startDate,setStartDate]=useState(""),[endDate,setEndDate]=useState(""),[currency,setCurrency]=useState("USD"),[notes,setNotes]=useState("");
 useEffect(()=>{(async()=>{setLoading(true);const{data,error:e}=await supabase.rpc("get_compensation_plan_admin_data");if(e){setError(e.message);setLoading(false);return}const ps=(data?.plans||[]) as Plan[];setPlans(ps);for(const p of ps){const v=p.versions.find(x=>x.version_id===params.versionId);if(v){setStartDate(v.effective_start_date||"");setEndDate(v.effective_end_date||"");setCurrency(v.currency_code||"USD");setNotes(v.notes||"");break}}setLoading(false)})()},[params.versionId]);
 const plan=useMemo(()=>plans.find(p=>p.versions.some(v=>v.version_id===params.versionId))||null,[plans,params.versionId]);
 const version=plan?.versions.find(v=>v.version_id===params.versionId)||null;
 const people=version?.status==="draft"?version.draft_assignments:version?.assignments||[];
 const save=async(e:FormEvent)=>{e.preventDefault();if(!version||version.status!=="draft")return;setSaving(true);setError("");setMessage("");const{error:saveError}=await supabase.rpc("update_compensation_plan_draft_version",{selected_plan_version_id:version.version_id,selected_effective_start_date:startDate,selected_effective_end_date:endDate||null,selected_currency_code:currency,selected_notes:notes||null});setSaving(false);if(saveError){setError(saveError.message);return}setMessage("Plan dates and details saved.")};
 if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Loading plan…</div></div></main>;
 if(!plan||!version)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-alert error">Plan version not found.</div></div></main>;
 if(version.status!=="draft")return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-alert warning">Only draft versions can be managed here.</div><Link className="plan-button secondary" href={`/plans?version=${version.version_id}`}>Back to plan</Link></div></main>;
 return <main className="plan-workspace"><div className="plan-page-shell" style={{paddingBottom:80}}>
  <div className="plan-breadcrumb"><Link href={`/plans?version=${version.version_id}`}><ArrowLeft size={15}/>Plan</Link><span>/</span><span>Manage draft</span></div>
  <header className="plan-page-header"><div><span className="plan-kicker">DRAFT PLAN</span><h1>Manage {plan.name}</h1><p>Draft v{version.version_number}. Set when it applies, review what it pays, and edit its earning rules before approval.</p></div><span className="plan-status draft">Draft v{version.version_number}</span></header>
  {error&&<div className="plan-alert error">{error}</div>}{message&&<div className="plan-info-row">{message}</div>}
  <form className="plan-editor-card" onSubmit={save}><section><div className="plan-editor-heading"><div><CalendarDays size={20}/><div><h2>Effective dates</h2><p>These dates determine when this version governs earnings. They do not change the active plan until this draft is approved and activated.</p></div></div></div><div className="plan-form-grid two">
   <label>Effective start date *<input type="date" required value={startDate} onChange={e=>setStartDate(e.target.value)}/></label>
   <label>Effective end date<input type="date" min={startDate||undefined} value={endDate} onChange={e=>setEndDate(e.target.value)}/><small>Leave blank when the plan has no planned end date.</small></label>
   <label>Currency<select value={currency} onChange={e=>setCurrency(e.target.value)}><option value="USD">USD</option></select></label>
   <label>Version notes<textarea rows={2} value={notes} onChange={e=>setNotes(e.target.value)} placeholder="What changed in this version?"/></label>
  </div><div style={{display:"flex",justifyContent:"flex-end",marginTop:14}}><button className="plan-button brand" disabled={saving}><Save size={14}/>{saving?"Saving…":"Save plan details"}</button></div></section></form>

  <section className="plan-section"><div className="plan-section-title"><div><h3>Earning Types & rules</h3><p>Open any earning type to view or change its payout, Earned conditions, and payment eligibility.</p></div><Link className="plan-button brand" href={`/plans/component/new?version=${version.version_id}`}><Plus size={14}/>Add Earning Type</Link></div>
   {version.components.map(c=><Link key={c.component_id} href={`/plans/component/${c.component_id}?version=${version.version_id}`} style={{textDecoration:"none",color:"inherit",display:"grid",gridTemplateColumns:"minmax(220px,1.2fr) minmax(260px,1.8fr) 28px",gap:16,alignItems:"center",border:"1px solid #e3e8ef",borderRadius:10,padding:"14px 16px",marginTop:10,background:"white"}}><div><b>{c.name}</b><div style={{fontSize:11,color:"#667085",fontFamily:"monospace",marginTop:3}}>{c.component_code}</div></div><div><small style={{color:"#667085"}}>PAYOUT RULE</small><div style={{fontSize:12,fontWeight:700,marginTop:3}}>{paySummary(c)}</div><div style={{fontSize:11,color:"#667085",marginTop:4}}>{title(c.measurement_period)} · based on {title(c.measurement_source)}{c.maximum_payout!=null?` · max ${Number(c.maximum_payout).toLocaleString("en-US",{style:"currency",currency:"USD",maximumFractionDigits:0})}`:""}</div></div><ChevronRight size={18}/></Link>)}
   {!version.components.length&&<div className="plan-empty">No Earning Types yet.</div>}
  </section>

  <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:16,marginTop:16}}><section className="plan-section" style={{margin:0}}><div className="plan-section-title"><div><h3>People</h3><p>{people.length} employee{people.length===1?"":"s"} currently included in this draft.</p></div><Link className="plan-button secondary" href={`/plans/applicability/${version.version_id}`}><Users size={14}/>Manage people</Link></div>{people.map(p=><div key={p.employee_id} style={{fontSize:13,padding:"8px 0",borderTop:"1px solid #eef1f4"}}>{p.employee_name}</div>)}</section><section className="plan-section" style={{margin:0}}><h3 style={{marginTop:0}}>Before activation</h3><p style={{fontSize:12,color:"#667085",lineHeight:1.6}}>Review every earning type, confirm effective dates and people, attach required agreements, resolve readiness blockers, then approve and activate from the plan page.</p><button type="button" className="plan-button secondary" onClick={()=>router.push(`/plans?version=${version.version_id}`)}>Return to readiness</button></section></div>
 </div></main>;
}
