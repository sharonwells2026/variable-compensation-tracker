"use client";

import {FormEvent,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useParams} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,Plus,Trash2} from "lucide-react";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Employee={employee_id:string;employee_name:string;email:string;job_title:string|null;department:string|null};
type Assignment={assignment_id?:string;draft_assignment_id?:string;employee_id:string;employee_name:string;allocation_percent:number;effective_start_date:string;effective_end_date:string|null;earnings_eligibility_date:string|null;eligibility_waiting_period_days?:number;assignment_notes?:string|null};
type Version={version_id:string;version_number:number;status:string;effective_start_date:string;effective_end_date:string|null;assignments:Assignment[];draft_assignments:Assignment[]};
type Plan={plan_id:string;name:string;versions:Version[]};
type Payload={plans:Plan[];employees:Employee[]};

export default function ApplicabilityPage(){
 const params=useParams<{versionId:string}>();
 const[data,setData]=useState<Payload>({plans:[],employees:[]});
 const[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 const[employeeId,setEmployeeId]=useState(""),[start,setStart]=useState(""),[end,setEnd]=useState(""),[allocation,setAllocation]=useState("100"),[waiting,setWaiting]=useState("0"),[notes,setNotes]=useState("");

 const load=async()=>{setLoading(true);setError("");const{data:result,error:e}=await supabase.rpc("get_compensation_plan_admin_data");if(e)setError(e.message);else{const next=(result||{plans:[],employees:[]}) as Payload;setData(next);if(!employeeId&&next.employees[0])setEmployeeId(next.employees[0].employee_id);}setLoading(false)};
 useEffect(()=>{load()},[]);
 const match=useMemo(()=>{for(const p of data.plans){const v=p.versions.find(x=>x.version_id===params.versionId);if(v)return{plan:p,version:v};}return null},[data.plans,params.versionId]);
 useEffect(()=>{if(match?.version.effective_start_date&&!start)setStart(match.version.effective_start_date)},[match?.version.effective_start_date,start]);
 const editable=match?.version.status==="draft";
 const rows=editable?(match?.version.draft_assignments||[]):(match?.version.assignments||[]);

 const save=async(e:FormEvent)=>{e.preventDefault();if(!editable||!employeeId||!start)return;setSaving(true);setError("");setMessage("");const{error:rpcError}=await supabase.rpc("save_comp_plan_draft_assignment",{selected_plan_version_id:params.versionId,selected_employee_id:employeeId,selected_effective_start_date:start,selected_effective_end_date:end||null,selected_allocation_percent:Number(allocation||100),selected_eligibility_waiting_period_days:Number(waiting||0),selected_assignment_notes:notes||null});if(rpcError)setError(rpcError.message);else{setMessage("Draft applicability saved. This does not affect the employee until the plan version is activated.");setNotes("");await load();}setSaving(false)};
 const remove=async(id:string)=>{setError("");setMessage("");const{error:e}=await supabase.rpc("delete_comp_plan_draft_assignment",{selected_draft_assignment_id:id});if(e)setError(e.message);else{setMessage("Draft applicability removed.");await load();}};

 if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Loading plan applicability…</div></div></main>;
 if(!match)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-alert error">Plan version not found.</div></div></main>;
 return <main className="plan-workspace"><div className="plan-page-shell">
   <div className="plan-breadcrumb"><Link href={`/plans?version=${params.versionId}`}><ArrowLeft size={15}/>Plans & Rules</Link><span>/</span><span>{match.plan.name}</span><span>/</span><span>Who it applies to</span></div>
   <header className="plan-page-header"><div><span className="plan-kicker">PLAN APPLICABILITY</span><h1>Who this plan applies to</h1><p>Configure employee applicability before activation without exposing a draft plan to employees or creating live earnings.</p></div><span className={`plan-status ${match.version.status}`}>{match.version.status} v{match.version.version_number}</span></header>
   {error&&<div className="plan-alert error">{error}</div>}{message&&<div className="plan-info-row" style={{marginBottom:14}}>{message}</div>}
   <section className="plan-editor-card">
     <div className="plan-editor-heading"><div><span className="plan-step-number">1</span><div><h2>{editable?"Draft applicability":"Current assignments"}</h2><p>{editable?"These assignments become live only when this approved version is activated.":"This version is not editable. These are the live employee assignments for it."}</p></div></div></div>
     {rows.length?<div style={{display:"grid",gap:8}}>{rows.map(a=><div key={a.draft_assignment_id||a.assignment_id} style={{display:"grid",gridTemplateColumns:"minmax(220px,1fr) 100px 150px 150px 44px",gap:10,alignItems:"center",border:"1px solid #e6e8ec",borderRadius:10,padding:"10px 12px"}}><div><b style={{display:"block",fontSize:12}}>{a.employee_name}</b><small style={{color:"#667085"}}>Eligible from {a.earnings_eligibility_date||a.effective_start_date}</small></div><span style={{fontSize:12}}>{a.allocation_percent}%</span><span style={{fontSize:11}}>{a.effective_start_date}</span><span style={{fontSize:11}}>{a.effective_end_date||"Open ended"}</span>{editable&&a.draft_assignment_id?<button type="button" onClick={()=>remove(a.draft_assignment_id!)} className="plan-button secondary" style={{padding:8}} aria-label={`Remove ${a.employee_name}`}><Trash2 size={14}/></button>:<span/>}</div>)}</div>:<div className="plan-empty">No employees are configured for this version yet.</div>}

     {editable&&<><div className="plan-editor-heading" style={{marginTop:28}}><div><span className="plan-step-number">2</span><div><h2>Add or update employee</h2><p>Saving here is safe: the employee will not see this draft plan and no earnings are created.</p></div></div></div>
     <form onSubmit={save}>
       <div className="plan-form-grid two">
         <label>Employee<select value={employeeId} onChange={e=>setEmployeeId(e.target.value)} required>{data.employees.map(e=><option key={e.employee_id} value={e.employee_id}>{e.employee_name}{e.job_title?` · ${e.job_title}`:""}</option>)}</select></label>
         <label>Allocation percent<input type="number" min="0" max="100" step="0.01" value={allocation} onChange={e=>setAllocation(e.target.value)} required/></label>
         <label>Effective start date<input type="date" value={start} onChange={e=>setStart(e.target.value)} required/></label>
         <label>Effective end date<input type="date" value={end} onChange={e=>setEnd(e.target.value)}/></label>
         <label>Employee-level eligibility waiting days<input type="number" min="0" value={waiting} onChange={e=>setWaiting(e.target.value)}/><small>Use only when the employee assignment itself has an additional waiting period. Component eligibility is configured separately.</small></label>
         <label>Assignment notes<input value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Optional internal note"/></label>
       </div>
       <div className="plan-info-row">Draft applicability is intentionally stored separately from live employee plan assignments. Activation promotes these records atomically.</div>
       <div className="plan-actions"><Link href={`/plans?version=${params.versionId}`} className="plan-button secondary">Back to plan</Link><button type="submit" className="plan-button primary" disabled={saving}><Plus size={15}/>{saving?"Saving…":"Save draft applicability"}</button></div>
     </form></>}
   </section>
 </div></main>;
}
