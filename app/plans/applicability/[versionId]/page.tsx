"use client";

import {FormEvent,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useParams,useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,ArrowRight,Plus,Trash2} from "lucide-react";
import PlanBuilderProgress from "../../components/plan-builder-progress";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");
type Employee={employee_id:string;employee_name:string;email:string;job_title:string|null;department:string|null};
type Assignment={assignment_id?:string;draft_assignment_id?:string;employee_id:string;employee_name:string;allocation_percent:number;effective_start_date:string;effective_end_date:string|null;earnings_eligibility_date:string|null;eligibility_waiting_period_days?:number;assignment_notes?:string|null};
type Version={version_id:string;version_number:number;status:string;effective_start_date:string;effective_end_date:string|null;assignments:Assignment[];draft_assignments:Assignment[]};
type Plan={plan_id:string;name:string;versions:Version[]};
type Payload={plans:Plan[];employees:Employee[]};

export default function ApplicabilityPage(){
 const params=useParams<{versionId:string}>();const router=useRouter();
 const[data,setData]=useState<Payload>({plans:[],employees:[]});const[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 const[employeeId,setEmployeeId]=useState(""),[start,setStart]=useState(""),[end,setEnd]=useState(""),[allocation,setAllocation]=useState("100"),[waiting,setWaiting]=useState("0"),[notes,setNotes]=useState("");
 const load=async()=>{setLoading(true);setError("");const{data:result,error:e}=await supabase.rpc("get_compensation_plan_admin_data");if(e)setError(e.message);else{const next=(result||{plans:[],employees:[]}) as Payload;setData(next);if(!employeeId&&next.employees[0])setEmployeeId(next.employees[0].employee_id)}setLoading(false)};
 useEffect(()=>{void load()},[]);
 const match=useMemo(()=>{for(const p of data.plans){const v=p.versions.find(x=>x.version_id===params.versionId);if(v)return{plan:p,version:v}}return null},[data.plans,params.versionId]);
 useEffect(()=>{if(match?.version.effective_start_date&&!start)setStart(match.version.effective_start_date)},[match?.version.effective_start_date,start]);
 const editable=match?.version.status==="draft";const rows=editable?(match?.version.draft_assignments||[]):(match?.version.assignments||[]);
 const saveAssignment=async()=>{if(!editable||!employeeId||!start)return false;setError("");setMessage("");const allocationNumber=Number(allocation||0),waitingNumber=Number(waiting||0);if(!Number.isFinite(allocationNumber)||allocationNumber<=0||allocationNumber>100){setError("Allocation percent must be greater than 0 and no more than 100.");return false}if(!Number.isFinite(waitingNumber)||waitingNumber<0){setError("Waiting days cannot be negative.");return false}if(end&&end<start){setError("Effective end date must be on or after the effective start date.");return false}if(match?.version.effective_start_date&&start<match.version.effective_start_date){setError(`Employee participation cannot start before the plan starts on ${match.version.effective_start_date}.`);return false}if(match?.version.effective_end_date&&end&&end>match.version.effective_end_date){setError(`Employee participation cannot end after the plan ends on ${match.version.effective_end_date}.`);return false}setSaving(true);const{error:rpcError}=await supabase.rpc("save_comp_plan_draft_assignment",{selected_plan_version_id:params.versionId,selected_employee_id:employeeId,selected_effective_start_date:start,selected_effective_end_date:end||null,selected_allocation_percent:allocationNumber,selected_eligibility_waiting_period_days:waitingNumber,selected_assignment_notes:notes||null});setSaving(false);if(rpcError){setError("We couldn't save who this plan applies to. Please try again.");return false}setMessage("Saved.");setNotes("");await load();return true};
 const submit=async(e:FormEvent)=>{e.preventDefault();await saveAssignment()};
 const saveAndNext=async()=>{if(rows.length){router.push(`/plans/manage/${params.versionId}#earning-types`);return}const ok=await saveAssignment();if(ok)router.push(`/plans/manage/${params.versionId}#earning-types`)};
 const remove=async(id:string)=>{setError("");const{error:e}=await supabase.rpc("delete_comp_plan_draft_assignment",{selected_draft_assignment_id:id});if(e)setError("We couldn't remove that person from the draft.");else await load()};
 if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Loading plan…</div></div></main>;
 if(!match)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-alert error">Plan version not found.</div></div></main>;
 return <main className="plan-workspace"><div className="plan-page-shell">
   <div className="plan-breadcrumb"><Link href="/plans"><ArrowLeft size={15}/>Plans</Link><span>/</span><span>{match.plan.name}</span></div>
   <PlanBuilderProgress versionId={params.versionId} current="people" completed={{basics:true,people:rows.length>0}}/>
   <header className="plan-page-header"><div><span className="plan-kicker">STEP 2 OF 6</span><h1>Who does this plan apply to?</h1><p>Add the employee or employees covered by this plan. This is saved as part of the draft and becomes visible to employees only after activation.</p></div><span className={`plan-status ${match.version.status}`}>{match.version.status} v{match.version.version_number}</span></header>
   {error&&<div className="plan-alert error">{error}</div>}{message&&<div className="plan-info-row" style={{marginBottom:14}}>{message}</div>}
   <section className="plan-editor-card">
     {rows.length>0&&<div className="plan-step-card" style={{marginTop:0}}><div className="plan-step-card__head"><div><h3>People already included</h3><p>You can add more people or remove someone before activation.</p></div></div>{rows.map(a=><div key={a.draft_assignment_id||a.assignment_id} style={{display:"flex",justifyContent:"space-between",gap:12,alignItems:"center",borderTop:"1px solid #eef1f4",padding:"10px 0"}}><div><b style={{display:"block",fontSize:13}}>{a.employee_name}</b><small style={{color:"#667085"}}>{a.allocation_percent}% allocation · starts {a.earnings_eligibility_date||a.effective_start_date}</small></div>{editable&&a.draft_assignment_id?<button type="button" onClick={()=>void remove(a.draft_assignment_id!)} className="plan-button secondary" aria-label={`Remove ${a.employee_name}`}><Trash2 size={14}/>Remove</button>:null}</div>)}</div>}
     {editable&&<form onSubmit={submit}><div className="plan-editor-heading"><div><span className="plan-step-number">2</span><div><h2>{rows.length?"Add another person":"Add a person"}</h2><p>For most individual plans, choose the employee and leave allocation at 100%.</p></div></div></div>
       <div className="plan-form-grid two">
         <label>Employee<select value={employeeId} onChange={e=>setEmployeeId(e.target.value)} required><option value="">Choose employee…</option>{data.employees.map(e=><option key={e.employee_id} value={e.employee_id}>{e.employee_name}{e.job_title?` · ${e.job_title}`:""}</option>)}</select></label>
         <label>Allocation percent<input type="number" min="0.01" max="100" step="0.01" value={allocation} onChange={e=>setAllocation(e.target.value)} required/><small>Usually 100%.</small></label>
         <label>Effective start date<input type="date" min={match.version.effective_start_date||undefined} max={match.version.effective_end_date||undefined} value={start} onChange={e=>setStart(e.target.value)} required/></label>
         <label>Effective end date<input type="date" min={start||match.version.effective_start_date||undefined} max={match.version.effective_end_date||undefined} value={end} onChange={e=>setEnd(e.target.value)}/><small>Leave blank unless participation ends before the plan does.</small></label>
         <label>Additional waiting days<input type="number" min="0" value={waiting} onChange={e=>setWaiting(e.target.value)}/><small>Usually 0. Payment eligibility is configured later on each Earning Type.</small></label>
         <label>Internal note<input value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Optional"/></label>
       </div>
       <div className="plan-actions"><button type="submit" className="plan-button secondary" disabled={saving}><Plus size={15}/>{saving?"Saving…":"Save & add another"}</button></div>
     </form>}
   </section>
   <div className="plan-wizard-actions"><Link className="plan-button secondary" href={`/plans/manage/${params.versionId}`}><ArrowLeft size={15}/>Back</Link><div className="plan-wizard-actions__right"><button type="button" className="plan-button brand" disabled={saving||(!rows.length&&!employeeId)} onClick={()=>void saveAndNext()}>{saving?"Saving…":"Next step"}<ArrowRight size={15}/></button></div></div>
 </div></main>;
}
