"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useParams} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,ArrowLeft,ArrowRight,CheckCircle2,FileText,ShieldCheck,Users} from "lucide-react";
import PlanBuilderProgress from "../../../components/plan-builder-progress";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");

type Component={component_id:string;name:string};
type Assignment={employee_id:string;employee_name:string};
type Version={version_id:string;version_number:number;status:string;effective_start_date:string;effective_end_date:string|null;approved_at?:string|null;components:Component[];assignments:Assignment[];draft_assignments:Assignment[]};
type Plan={plan_id:string;name:string;plan_code:string;versions:Version[]};
type ReadinessItem={code:string;section:string;message:string;component_id?:string;rule_set_id?:string};
type Readiness={ready:boolean;blocker_count:number;warning_count?:number;blockers:ReadinessItem[];warnings?:ReadinessItem[]};
type Access={roles?:string[];permissions?:string[]};

function localToday(){const d=new Date();const y=d.getFullYear(),m=String(d.getMonth()+1).padStart(2,"0"),day=String(d.getDate()).padStart(2,"0");return `${y}-${m}-${day}`}
function blockerHref(item:ReadinessItem,versionId:string){
 if(item.section==="approvals")return `/plans/manage/${versionId}/approvals`;
 if(item.section==="agreements")return `/plans/agreements/${versionId}`;
 if(item.section==="people"||item.section==="applicability")return `/plans/applicability/${versionId}`;
 if(item.component_id&&["missing_aggregate_sources","missing_quota","missing_threshold_bonus"].includes(item.code))return `/plans/component/${item.component_id}/aggregate?version=${versionId}`;
 if(item.component_id&&item.section==="payment")return `/plans/component/${item.component_id}/payment-condition?version=${versionId}`;
 if(item.component_id)return `/plans/component/${item.component_id}?version=${versionId}`;
 if(item.section==="earning_types"||item.section==="earned")return `/plans/manage/${versionId}`;
 return `/plans/manage/${versionId}`;
}

export default function PlanReviewPage(){
 const params=useParams<{versionId:string}>();
 const[plans,setPlans]=useState<Plan[]>([]),[access,setAccess]=useState<Access>({}),[readiness,setReadiness]=useState<Readiness|null>(null);
 const[loading,setLoading]=useState(true),[error,setError]=useState(""),[message,setMessage]=useState(""),[acting,setActing]=useState<"approve"|"activate"|"">("");
 const load=async()=>{setLoading(true);setError("");const[p,a,r]=await Promise.all([supabase.rpc("get_compensation_plan_admin_data"),supabase.rpc("get_current_user_access"),supabase.rpc("validate_compensation_plan_version_readiness",{selected_plan_version_id:params.versionId})]);if(p.error){setError("We couldn't load this plan.");setLoading(false);return}setPlans((p.data?.plans||[]) as Plan[]);if(a.data)setAccess(a.data as Access);if(r.error)setError("We couldn't run readiness checks.");else setReadiness(r.data as Readiness);setLoading(false)};
 useEffect(()=>{void load()},[params.versionId]);
 const plan=useMemo(()=>plans.find(p=>p.versions.some(v=>v.version_id===params.versionId))||null,[plans,params.versionId]);
 const version=plan?.versions.find(v=>v.version_id===params.versionId)||null;
 const people=version?.status==="draft"?version.draft_assignments:version?.assignments||[];
 const roles=access.roles||[],perms=access.permissions||[],admin=roles.includes("system_administrator"),canApprove=admin||perms.includes("plans.approve"),canActivate=admin||perms.includes("plans.activate");
 const approved=Boolean(version?.approved_at),futureDated=Boolean(version?.effective_start_date&&version.effective_start_date>localToday());
 const blockers=readiness?.blockers||[],warnings=readiness?.warnings||[];
 const approvalsMissing=blockers.some(b=>b.section==="approvals");
 const agreementMissing=blockers.some(b=>b.section==="agreements");
 const act=async(kind:"approve"|"activate")=>{if(!version)return;setActing(kind);setError("");setMessage("");const result=kind==="approve"?await supabase.rpc("approve_compensation_plan_version",{selected_plan_version_id:version.version_id,approval_notes:null}):await supabase.rpc("activate_compensation_plan_version",{selected_plan_version_id:version.version_id});setActing("");if(result.error){setError(result.error.message);return}setMessage(kind==="approve"?"Plan approved. Review remains available until activation.":"Plan activated. Employee assignments and earning rules are now live.");await load()};
 if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Running readiness checks…</div></div></main>;
 if(!plan||!version)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-alert error">Plan version not found.</div></div></main>;
 return <main className="plan-workspace"><div className="plan-page-shell" style={{paddingBottom:90}}>
  <div className="plan-breadcrumb"><Link href="/plans"><ArrowLeft size={15}/>Plans</Link><span>/</span><span>{plan.name}</span></div>
  <PlanBuilderProgress versionId={version.version_id} current="review" completed={{basics:true,people:people.length>0,earnings:version.components.length>0,agreements:!agreementMissing,approvals:!approvalsMissing,review:Boolean(readiness?.ready)}}/>
  <header className="plan-page-header"><div><span className="plan-kicker">STEP 6 OF 6</span><h1>Review & activate</h1><p>Confirm the complete plan before approval. Readiness checks the plan structure, people, agreements, Earning Types, Earned rules, payment conditions, and approval workflow.</p></div><span className={`plan-status ${version.status}`}>{version.status} v{version.version_number}</span></header>
  {error&&<div className="plan-alert error">{error}</div>}{message&&<div className="plan-info-row"><CheckCircle2 size={16}/>{message}</div>}

  <section className="plan-step-card">
   <div className="plan-step-card__head"><div><h2>{version.status==="active"?"Plan is active":approved?futureDated?"Approved and scheduled":"Approved and ready to activate":readiness?.ready?"Ready for approval":"Finish these items first"}</h2><p>{version.status==="active"?"This version is currently governing compensation.":approved&&futureDated?`Activation is available on or after ${version.effective_start_date}.`:approved?"Approval is recorded. Activation makes the draft employee assignments live.":readiness?.ready?"All required readiness checks passed.":"Nothing will activate until every blocker is resolved."}</p></div><button type="button" className="plan-button secondary" onClick={()=>void load()}>Run checks again</button></div>
   <div className="plan-review-summary">
    <div><Users size={17}/><b>{people.length}</b><span>person{people.length===1?"":"s"}</span></div>
    <div><FileText size={17}/><b>{version.components.length}</b><span>Earning Type{version.components.length===1?"":"s"}</span></div>
    <div><ShieldCheck size={17}/><b>{readiness?.blocker_count||0}</b><span>blocker{readiness?.blocker_count===1?"":"s"}</span></div>
   </div>
   {blockers.length>0&&<div style={{display:"grid",gap:8,marginTop:18}}>{blockers.map((b,i)=><div key={`${b.code}-${i}`} className="plan-alert warning" style={{margin:0,justifyContent:"space-between",alignItems:"center",gap:12}}><span style={{display:"flex",alignItems:"center",gap:8,minWidth:0}}><AlertTriangle size={15}/><span>{b.message}</span></span><Link href={blockerHref(b,version.version_id)} className="plan-button secondary" style={{flexShrink:0}}>Fix this<ArrowRight size={14}/></Link></div>)}</div>}
   {warnings.length>0&&<div style={{display:"grid",gap:8,marginTop:18}}>{warnings.map((w,i)=><div key={`${w.code}-${i}`} className="plan-info-row" style={{margin:0}}><AlertTriangle size={15}/><span>{w.message}</span></div>)}</div>}
   {readiness?.ready&&<div className="plan-info-row"><CheckCircle2 size={16}/><span>All required readiness checks passed. Approval does not activate the plan; activation is a separate action.</span></div>}
  </section>

  <div className="plan-wizard-actions"><Link className="plan-button secondary" href={`/plans/manage/${version.version_id}/approvals`}><ArrowLeft size={15}/>Back</Link><div className="plan-wizard-actions__right">
   {version.status==="draft"&&!approved&&readiness?.ready&&(canApprove?<button type="button" className="plan-button brand" disabled={Boolean(acting)} onClick={()=>void act("approve")}><ShieldCheck size={15}/>{acting==="approve"?"Approving…":"Approve plan"}</button>:<span className="plan-review-note">Ready for approval. A user with plan-approval permission must act next.</span>)}
   {version.status==="draft"&&approved&&!futureDated&&(canActivate?<button type="button" className="plan-button brand" disabled={Boolean(acting)} onClick={()=>void act("activate")}><CheckCircle2 size={15}/>{acting==="activate"?"Activating…":"Activate plan"}</button>:<span className="plan-review-note">Approved. A user with plan-activation permission must activate it.</span>)}
   {version.status==="draft"&&approved&&futureDated&&<span className="plan-review-note">Approved. Activation becomes available on {version.effective_start_date}.</span>}
   {version.status==="active"&&<Link className="plan-button brand" href="/plans">Done</Link>}
  </div></div>
 </div></main>;
}
