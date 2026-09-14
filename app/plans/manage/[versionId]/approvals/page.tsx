"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useParams} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,Plus,Save,Trash2} from "lucide-react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");

type Approver={employee_id:string;full_name:string;email:string|null;user_id:string|null;provisioning_status:string};
type Step={id?:string;approval_order:number;step_name:string;approval_level:string;approver_employee_id:string;approver_name?:string|null;backup_approver_employee_id?:string|null;backup_approver_name?:string|null;is_required:boolean;conditions?:any};

type Plan={plan_id:string;name:string;versions:{version_id:string;version_number:number;status:string}[]};

const blank=(order:number):Step=>({approval_order:order,step_name:`Approval ${order}`,approval_level:"manager",approver_employee_id:"",backup_approver_employee_id:null,is_required:true,conditions:{}});

export default function PlanApprovalsPage(){
  const params=useParams<{versionId:string}>();
  const[steps,setSteps]=useState<Step[]>([]),[approvers,setApprovers]=useState<Approver[]>([]),[plans,setPlans]=useState<Plan[]>([]);
  const[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");

  async function load(){
    setLoading(true);setError("");
    const [cfg,admin,planData]=await Promise.all([
      supabase.rpc("get_comp_plan_approval_configuration",{selected_plan_version_id:params.versionId}),
      supabase.rpc("get_approval_workflow_admin_data"),
      supabase.rpc("get_compensation_plan_admin_data")
    ]);
    if(cfg.error){setError(cfg.error.message);setLoading(false);return}
    if(admin.error){setError(admin.error.message);setLoading(false);return}
    if(planData.error){setError(planData.error.message);setLoading(false);return}
    const existing=(cfg.data?.steps||[]) as Step[];
    setSteps(existing.length?existing.map((s,i)=>({...s,approval_order:i+1})):[]);
    setApprovers((admin.data?.eligible_approvers||[]) as Approver[]);
    setPlans((planData.data?.plans||[]) as Plan[]);
    setLoading(false);
  }
  useEffect(()=>{void load()},[params.versionId]);

  const plan=useMemo(()=>plans.find(p=>p.versions.some(v=>v.version_id===params.versionId))||null,[plans,params.versionId]);
  const version=plan?.versions.find(v=>v.version_id===params.versionId)||null;
  const editable=version?.status==="draft";

  const change=(index:number,patch:Partial<Step>)=>setSteps(v=>v.map((s,i)=>i===index?{...s,...patch}:s));
  const remove=(index:number)=>setSteps(v=>v.filter((_,i)=>i!==index).map((s,i)=>({...s,approval_order:i+1,step_name:s.step_name||`Approval ${i+1}`})));
  const add=()=>setSteps(v=>[...v,blank(v.length+1)]);

  const save=async()=>{
    if(!editable){setError("Only draft plan versions can have approval requirements edited.");return}
    if(steps.some(s=>!s.approver_employee_id)){setError("Choose an approver for every approval step.");return}
    setSaving(true);setError("");setMessage("");
    const payload=steps.map((s,i)=>({
      approval_order:i+1,
      step_name:s.step_name.trim()||`Approval ${i+1}`,
      approval_level:s.approval_level||"manager",
      approver_employee_id:s.approver_employee_id,
      backup_approver_employee_id:s.backup_approver_employee_id||null,
      is_required:s.is_required,
      conditions:s.conditions||{}
    }));
    const{error:e}=await supabase.rpc("save_comp_plan_approval_configuration",{selected_plan_version_id:params.versionId,selected_steps:payload});
    setSaving(false);
    if(e){setError(e.message);return}
    setMessage(payload.length?"Plan approval requirements saved.":"This plan has no approval steps configured.");
    await load();
  };

  if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Loading approval requirements…</div></div></main>;
  return <main className="plan-workspace"><div className="plan-page-shell" style={{paddingBottom:90}}>
    <div className="plan-breadcrumb"><Link href={`/plans/manage/${params.versionId}`}><ArrowLeft size={15}/>Plan setup</Link><span>/</span><span>Approvals</span></div>
    <header className="plan-page-header"><div><span className="plan-kicker">PLAN APPROVALS</span><h1>{plan?.name||"Compensation plan"}</h1><p>Define who must approve compensation submitted under this plan. Approval requirements belong to the plan, while each employee's submissions retain their own status and history.</p></div>{version&&<span className={`plan-status ${version.status}`}>{version.status} v{version.version_number}</span>}</header>
    {error&&<div className="plan-alert error">{error}</div>}{message&&<div className="plan-info-row">{message}</div>}
    <section className="plan-section">
      <div className="plan-section-title"><div><h3>Approval sequence</h3><p>Steps run in order. A backup approver is optional. You can leave the list empty only if this plan truly requires no approval.</p></div>{editable&&<button type="button" className="plan-button secondary" onClick={add}><Plus size={14}/>Add approval step</button>}</div>
      {!steps.length&&<div className="plan-empty">No approval steps configured for this plan yet.</div>}
      {steps.map((s,i)=><div key={s.id||i} style={{display:"grid",gridTemplateColumns:"48px minmax(180px,1fr) minmax(220px,1fr) minmax(220px,1fr) auto",gap:12,alignItems:"end",borderTop:"1px solid #eef1f4",padding:"14px 0"}}>
        <div style={{fontWeight:800,fontSize:18,textAlign:"center",paddingBottom:10}}>{i+1}</div>
        <label>Step name<input value={s.step_name} disabled={!editable} onChange={e=>change(i,{step_name:e.target.value})}/></label>
        <label>Approver *<select value={s.approver_employee_id||""} disabled={!editable} onChange={e=>change(i,{approver_employee_id:e.target.value})}><option value="">Choose approver</option>{approvers.map(a=><option key={a.employee_id} value={a.employee_id}>{a.full_name}{a.provisioning_status!=="active"?" (pre-invite)":""}</option>)}</select></label>
        <label>Backup approver<select value={s.backup_approver_employee_id||""} disabled={!editable} onChange={e=>change(i,{backup_approver_employee_id:e.target.value||null})}><option value="">None</option>{approvers.filter(a=>a.employee_id!==s.approver_employee_id).map(a=><option key={a.employee_id} value={a.employee_id}>{a.full_name}</option>)}</select></label>
        {editable&&<button type="button" className="plan-button secondary" onClick={()=>remove(i)} aria-label={`Remove approval step ${i+1}`}><Trash2 size={14}/></button>}
      </div>)}
      {editable&&<div style={{display:"flex",justifyContent:"flex-end",marginTop:18}}><button type="button" className="plan-button brand" disabled={saving} onClick={()=>void save()}><Save size={14}/>{saving?"Saving…":"Save approvals"}</button></div>}
    </section>
    <div className="plan-info-row"><b>Plan-centered workflow:</b>&nbsp;employees are assigned to this plan; their individual submissions then move through this approval sequence and keep their own dates, status, comments, and action history.</div>
  </div></main>;
}
