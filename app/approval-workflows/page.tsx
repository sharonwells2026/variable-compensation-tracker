"use client";

import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { AlertTriangle, ArrowLeft, CheckCircle2, ChevronDown, ChevronUp, Eye, History, Plus, Save, ShieldCheck, Trash2, Users } from "lucide-react";
import { createClient } from "@supabase/supabase-js";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type WorkflowSummary={workflow_version_id:string;workflow_name:string;effective_start_date:string;effective_end_date:string|null;status:string;step_count:number;unresolved_approver_count?:number};
type Employee={employee_id:string;full_name:string;email:string;job_title:string|null;is_active:boolean;current_workflow:WorkflowSummary|null;planned_workflow?:WorkflowSummary|null};
type Approver={employee_id:string;user_id:string|null;full_name:string;email:string;provisioning_status:"active"|"preinvite"|"unavailable"};
type Step={step_name:string;approver_employee_id:string;backup_approver_employee_id:string};
type HistoryRow={workflow_version_id:string;workflow_name:string;status:string;effective_start_date:string;effective_end_date:string|null;steps:any[]};

const blank=():Step=>({step_name:"",approver_employee_id:"",backup_approver_employee_id:""});
const today=()=>new Date().toISOString().slice(0,10);
const yearOf=(d:string)=>d?.slice(0,4)||new Date().getFullYear().toString();

export default function ApprovalWorkflowsPage(){
  const searchParams=useSearchParams();
  const requestedEmployee=searchParams.get("employee")||"";
  const [data,setData]=useState<{employees:Employee[];eligible_approvers:Approver[]}>({employees:[],eligible_approvers:[]});
  const [employeeId,setEmployeeId]=useState("");
  const [history,setHistory]=useState<HistoryRow[]>([]);
  const [start,setStart]=useState(today());
  const [notes,setNotes]=useState("");
  const [steps,setSteps]=useState<Step[]>([blank()]);
  const [previewDate,setPreviewDate]=useState(today());
  const [preview,setPreview]=useState<any>(null);
  const [error,setError]=useState("");
  const [notice,setNotice]=useState("");
  const [saving,setSaving]=useState(false);

  const employee=useMemo(()=>data.employees.find(x=>x.employee_id===employeeId)||null,[data,employeeId]);
  const approvers=useMemo(()=>data.eligible_approvers.filter(x=>x.employee_id!==employeeId),[data,employeeId]);
  const activeApprovers=approvers.filter(x=>x.provisioning_status==="active");
  const plannedApprovers=approvers.filter(x=>x.provisioning_status==="preinvite");
  const workflowName=employee?`${employee.full_name} Approval Workflow — ${yearOf(start)}`:"Approval Workflow";
  const replacementValid=!employee?.current_workflow||start>employee.current_workflow.effective_start_date;
  const valid=!!start&&replacementValid&&steps.every(x=>x.step_name.trim()&&x.approver_employee_id);
  const containsPreinvite=steps.some(s=>approvers.find(a=>a.employee_id===s.approver_employee_id)?.provisioning_status==="preinvite" || (s.backup_approver_employee_id&&approvers.find(a=>a.employee_id===s.backup_approver_employee_id)?.provisioning_status==="preinvite"));

  const load=async()=>{
    setError("");
    const {data:r,error:e}=await supabase.rpc("get_approval_workflow_admin_data");
    if(e){setError(e.message);return}
    const d=r||{employees:[],eligible_approvers:[]};
    setData(d);
    setEmployeeId(current=>{
      if(current&&d.employees?.some((x:Employee)=>x.employee_id===current)) return current;
      if(requestedEmployee&&d.employees?.some((x:Employee)=>x.employee_id===requestedEmployee)) return requestedEmployee;
      return d.employees?.[0]?.employee_id||"";
    });
  };

  const loadHistory=async(id:string)=>{
    const {data:r,error:e}=await supabase.rpc("get_employee_approval_workflows",{selected_employee_id:id});
    if(e)setError(e.message);else setHistory(r||[]);
  };

  useEffect(()=>{load()},[]);
  useEffect(()=>{
    if(employeeId){
      loadHistory(employeeId);
      setStart(today());setNotes("");setSteps([blank()]);setPreview(null);setError("");setNotice("");
    }
  },[employeeId]);

  const updateStep=(i:number,patch:Partial<Step>)=>setSteps(xs=>xs.map((s,n)=>n===i?{...s,...patch}:s));
  const move=(i:number,d:number)=>setSteps(xs=>{const next=[...xs],j=i+d;if(j<0||j>=next.length)return xs;[next[i],next[j]]=[next[j],next[i]];return next});
  const payload=()=>steps.map(s=>({step_name:s.step_name.trim(),approval_level:"other",approver_employee_id:s.approver_employee_id,backup_approver_employee_id:s.backup_approver_employee_id||null,is_required:true,conditions:{}}));

  const save=async()=>{
    if(!employee||!valid)return;
    setSaving(true);setError("");setNotice("");
    const args={selected_workflow_name:workflowName,selected_effective_start_date:start,selected_effective_end_date:null,selected_steps:payload(),selected_notes:notes||null};
    const result=employee.current_workflow
      ? await supabase.rpc("replace_employee_approval_workflow",{selected_current_workflow_version_id:employee.current_workflow.workflow_version_id,...args})
      : await supabase.rpc("create_employee_approval_workflow",{selected_employee_id:employeeId,...args});
    if(result.error){setError(result.error.message);setSaving(false);return}
    const status=result.data?.status;
    if(status==="draft_pending_approvers"||status==="replacement_pending_approvers") setNotice("Planned workflow saved. It cannot route earnings until every approver has an active app account.");
    else setNotice(employee.current_workflow?"Workflow replacement saved and activated.":"Approval workflow saved and activated.");
    await load();await loadHistory(employeeId);setSteps([blank()]);setNotes("");setSaving(false);
  };

  const activatePlanned=async()=>{
    if(!employee?.planned_workflow)return;
    setSaving(true);setError("");setNotice("");
    const {data:r,error:e}=await supabase.rpc("activate_ready_employee_approval_workflow",{selected_workflow_version_id:employee.planned_workflow.workflow_version_id});
    if(e)setError(e.message);
    else if(r?.status==="not_ready")setNotice(`Workflow is still waiting on ${r.unresolved_approver_count} approver account${r.unresolved_approver_count===1?"":"s"}.`);
    else setNotice("Planned workflow is now active.");
    await load();await loadHistory(employeeId);setSaving(false);
  };

  const testRouting=async()=>{
    const {data:r,error:e}=await supabase.rpc("preview_employee_approval_workflow",{selected_employee_id:employeeId,selected_earned_date:previewDate});
    if(e)setError(e.message);else setPreview(r);
  };

  return <main className="min-h-screen bg-[#f6f8fc] text-[#252b35]">
    <header className="border-t-[7px] border-[#a7e3e5] bg-white shadow-sm"><div className="mx-auto flex max-w-[1500px] items-center justify-between px-6 py-4"><div className="flex items-center gap-4"><a href="/employee-administration" className="grid h-9 w-9 place-items-center rounded-lg border text-[#2095f3]"><ArrowLeft size={17}/></a><div><p className="text-[10px] font-extrabold tracking-[.12em] text-[#8d939c]">ADMINISTRATION</p><h1 className="text-xl font-bold">Approval Workflows</h1></div></div><div className="flex items-center gap-2 rounded-lg bg-[#edf6ff] px-3 py-2 text-xs font-semibold text-[#0879d5]"><ShieldCheck size={15}/> Effective-dated & history-safe</div></div></header>

    <div className="mx-auto grid max-w-[1500px] gap-5 px-6 py-6 lg:grid-cols-[360px_minmax(0,1fr)]">
      <aside className="self-start rounded-xl border bg-white p-4 shadow-sm"><div className="mb-4 flex justify-between"><div><h2 className="text-sm font-bold">Employees</h2><p className="mt-1 text-xs text-[#77808e]">Select an employee to manage routing.</p></div><Users size={18} className="text-[#2095f3]"/></div>{data.employees.map(x=><button key={x.employee_id} onClick={()=>setEmployeeId(x.employee_id)} className={`mb-2 w-full rounded-lg border p-3 text-left ${x.employee_id===employeeId?"border-[#2095f3] bg-[#eef7ff]":"bg-white"}`}><div className="flex justify-between gap-2"><div><b className="text-sm">{x.full_name}</b><div className="mt-1 text-[11px] text-[#77808e]">{x.job_title||x.email}</div></div><span className={`h-fit rounded-full px-2 py-1 text-[10px] font-bold ${x.current_workflow?"bg-[#e9f8f2] text-[#17795e]":x.planned_workflow?"bg-[#edf6ff] text-[#0879d5]":"bg-[#fff1d3] text-[#946407]"}`}>{x.current_workflow?"Active":x.planned_workflow?"Planned":"Missing workflow"}</span></div>{x.planned_workflow&&<div className="mt-2 text-[10px] text-[#66717f]">Waiting on {x.planned_workflow.unresolved_approver_count||0} approver account{x.planned_workflow.unresolved_approver_count===1?"":"s"}</div>}</button>)}</aside>

      <section className="space-y-5">
        {error&&<div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
        {notice&&<div className="rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</div>}

        <div className="rounded-xl border bg-white p-4 shadow-sm"><div className="flex flex-wrap items-center justify-between gap-3"><div><b className="text-sm">Available approvers</b><p className="mt-1 text-xs text-[#77808e]">Active accounts can route immediately. Pre-invite approvers can be used to plan a workflow, but the workflow stays inactive until they activate their account.</p></div><div className="flex gap-2"><span className="rounded-full bg-[#e9f8f2] px-3 py-1 text-[10px] font-bold text-[#17795e]">{activeApprovers.length} active</span><span className="rounded-full bg-[#edf6ff] px-3 py-1 text-[10px] font-bold text-[#0879d5]">{plannedApprovers.length} pre-invite</span></div></div></div>

        {employee?.planned_workflow&&<div className="rounded-xl border border-blue-200 bg-blue-50 p-4"><div className="flex items-start justify-between gap-4"><div><div className="flex items-center gap-2 text-sm font-bold text-blue-900"><AlertTriangle size={16}/> Planned workflow is not live</div><p className="mt-1 text-xs text-blue-800">{employee.planned_workflow.workflow_name} is saved, but {employee.planned_workflow.unresolved_approver_count||0} approver account{employee.planned_workflow.unresolved_approver_count===1?" is":"s are"} still unresolved. Draft workflows cannot receive approval requests.</p></div><button onClick={activatePlanned} disabled={saving} className="rounded-lg border border-blue-300 bg-white px-3 py-2 text-xs font-bold text-blue-800">Check & activate</button></div></div>}

        <div className="rounded-xl border bg-white p-5 shadow-sm">
          <div className="mb-5 flex justify-between gap-4"><div><p className="text-[10px] font-extrabold tracking-[.1em] text-[#2095f3]">EMPLOYEE WORKFLOW</p><h2 className="mt-1 text-xl font-bold">{employee?.full_name||"Select employee"}</h2><p className="mt-1 text-xs text-[#77808e]">{employee?.job_title||employee?.email}</p></div>{employee?.current_workflow?<div className="h-fit min-w-[260px] rounded-lg border border-emerald-100 bg-[#f3fbf7] px-3 py-2 text-xs"><b className="text-[#17795e]">Current workflow</b><div className="mt-1 font-semibold">{employee.current_workflow.step_count} approval step{employee.current_workflow.step_count===1?"":"s"}</div><div className="mt-1 text-[#66717f]">Effective {employee.current_workflow.effective_start_date} until replaced</div></div>:<span className="h-fit rounded-lg bg-[#fff6df] px-3 py-2 text-xs font-semibold text-[#946407]">Workflow required</span>}</div>

          <div className="grid gap-4 rounded-lg border bg-[#fafbfd] p-4 md:grid-cols-2"><div><div className="text-xs font-semibold">Workflow</div><div className="mt-1 rounded-lg border bg-white px-3 py-2.5 text-sm">{workflowName}</div><span className="mt-1 block text-[10px] text-[#77808e]">Named automatically from the employee and effective year.</span></div><label className="text-xs font-semibold">Effective start *<input type="date" value={start} onChange={e=>setStart(e.target.value)} className="mt-1 w-full rounded-lg border bg-white px-3 py-2.5 text-sm font-normal"/><span className={`mt-1 block text-[10px] font-normal ${replacementValid?"text-[#77808e]":"text-red-600"}`}>{employee?.current_workflow?(replacementValid?`Current workflow remains live until the replacement can activate. If ready, it will end automatically the day before ${start}.`:`Choose a date after ${employee.current_workflow.effective_start_date}.`):"Remains effective until replaced."}</span></label></div>

          <div className="mt-5"><div className="mb-3 flex justify-between"><div><h3 className="text-sm font-bold">Approval steps</h3><p className="mt-1 text-xs text-[#77808e]">All steps are required and run sequentially.</p></div><button onClick={()=>setSteps(xs=>[...xs,blank()])} className="h-fit rounded-lg border border-[#2095f3] px-3 py-2 text-xs font-bold text-[#2095f3]"><Plus size={14} className="inline"/> Add step</button></div>
            {steps.map((s,i)=><div key={i} className="mb-3 rounded-xl border bg-[#fafbfd] p-4"><div className="mb-3 flex justify-between"><div className="flex items-center gap-2"><span className="grid h-7 w-7 place-items-center rounded-full bg-[#2095f3] text-xs font-bold text-white">{i+1}</span><b className="text-sm">{s.step_name||`Approval step ${i+1}`}</b></div><div><button onClick={()=>move(i,-1)} disabled={!i} className="p-1 disabled:opacity-30"><ChevronUp size={14}/></button><button onClick={()=>move(i,1)} disabled={i===steps.length-1} className="p-1 disabled:opacity-30"><ChevronDown size={14}/></button><button onClick={()=>setSteps(xs=>xs.length===1?xs:xs.filter((_,n)=>n!==i))} disabled={steps.length===1} className="p-1 text-red-600 disabled:opacity-30"><Trash2 size={14}/></button></div></div><div className="grid gap-3 md:grid-cols-2"><label className="text-[11px] font-semibold">Step name *<input value={s.step_name} onChange={e=>updateStep(i,{step_name:e.target.value})} placeholder="e.g. Manager Review, CFO Approval" className="mt-1 w-full rounded-lg border bg-white px-3 py-2 text-xs font-normal"/></label><label className="text-[11px] font-semibold">Primary approver *<select value={s.approver_employee_id} onChange={e=>updateStep(i,{approver_employee_id:e.target.value})} className="mt-1 w-full rounded-lg border bg-white px-3 py-2 text-xs font-normal"><option value="">Select approver</option>{approvers.map(a=><option key={a.employee_id} value={a.employee_id}>{a.full_name} {a.provisioning_status==="preinvite"?"— pre-invite":"— active"}</option>)}</select></label></div><label className="mt-3 block text-[11px] font-semibold">Backup approver <span className="font-normal text-[#77808e]">(optional)</span><select value={s.backup_approver_employee_id} onChange={e=>updateStep(i,{backup_approver_employee_id:e.target.value})} className="ml-2 rounded-lg border bg-white px-3 py-2 text-xs font-normal"><option value="">No backup</option>{approvers.filter(a=>a.employee_id!==s.approver_employee_id).map(a=><option key={a.employee_id} value={a.employee_id}>{a.full_name} {a.provisioning_status==="preinvite"?"— pre-invite":"— active"}</option>)}</select></label></div>)}
          </div>

          {containsPreinvite&&<div className="mb-4 flex gap-3 rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900"><AlertTriangle size={16}/><div><b>This will be saved as a planned workflow.</b><div className="mt-1">At least one selected approver is pre-invite. The workflow will be stored safely but will not route earnings until every selected approver has an active account with approval permission.</div></div></div>}

          <label className="block text-xs font-semibold">Administrative notes <span className="font-normal text-[#77808e]">(optional)</span><textarea value={notes} onChange={e=>setNotes(e.target.value)} rows={2} className="mt-1 w-full rounded-lg border px-3 py-2 text-sm font-normal" placeholder="Why this workflow exists or what changed."/></label>
          <div className="mt-4 flex items-center justify-between border-t pt-4"><span className="text-xs text-[#77808e]">{valid?(containsPreinvite?"Ready to save as planned workflow.":"Ready to save and activate."):!replacementValid?"Choose a valid replacement effective date.":"Complete the date, step names and approvers."}</span><button onClick={save} disabled={!valid||saving||!!employee?.planned_workflow} className="rounded-lg bg-[#2095f3] px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-40"><Save size={15} className="mr-2 inline"/>{saving?"Saving...":employee?.current_workflow?"Schedule workflow change":containsPreinvite?"Save planned workflow":"Save approval workflow"}</button></div>
        </div>

        <div className="grid gap-5 xl:grid-cols-2">
          <div className="rounded-xl border bg-white p-5 shadow-sm"><h3 className="flex items-center gap-2 text-sm font-bold"><Eye size={16} className="text-[#2095f3]"/> Test live routing</h3><p className="mt-1 text-xs text-[#77808e]">Tests only active or historical live workflows. Planned drafts are intentionally excluded.</p><div className="mt-3 flex gap-2"><input type="date" value={previewDate} onChange={e=>setPreviewDate(e.target.value)} className="flex-1 rounded-lg border px-3 py-2 text-sm"/><button onClick={testRouting} className="rounded-lg bg-[#051b34] px-4 text-xs font-bold text-white">Test routing</button></div>{preview&&<div className="mt-3 rounded-lg bg-[#f7f9fc] p-3 text-xs">{preview.status==="no_workflow"?`No live workflow applies on ${previewDate}.`:<><b>{preview.workflow_name}</b>{preview.steps?.map((s:any)=><div key={s.approval_order} className="mt-1">{s.approval_order}. {s.step_name} — {s.approver_name||"Unassigned"}</div>)}</>}</div>}</div>
          <div className="rounded-xl border bg-white p-5 shadow-sm"><h3 className="flex items-center gap-2 text-sm font-bold"><History size={16} className="text-[#2095f3]"/> Workflow history</h3><p className="mt-1 text-xs text-[#77808e]">Includes planned, active, and historical versions.</p>{history.length===0?<div className="mt-3 rounded-lg border border-dashed p-5 text-center text-xs text-[#77808e]">No saved workflow for this employee.</div>:<div className="mt-3 space-y-2">{history.map(h=><div key={h.workflow_version_id} className="rounded-lg border p-3 text-xs"><div className="flex justify-between"><b>{h.workflow_name}</b><span className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${h.status==="active"?"bg-emerald-50 text-emerald-700":h.status==="draft"?"bg-blue-50 text-blue-700":"bg-slate-100 text-slate-600"}`}>{h.status==="draft"?"planned":h.status}</span></div><div className="mt-1 text-[#77808e]">{h.effective_start_date} → {h.effective_end_date||"ongoing"}</div>{h.steps.map((s:any)=><div key={s.id} className="mt-2 flex items-center gap-2"><span>{s.approval_order}. {s.step_name} — {s.approver_name||"Unassigned"}</span>{s.approver_provisioning_status==="active"?<CheckCircle2 size={12} className="text-emerald-600"/>:<span className="rounded-full bg-blue-50 px-2 py-0.5 text-[9px] font-bold text-blue-700">pre-invite</span>}</div>)}</div>)}</div>}</div>
        </div>
      </section>
    </div>
  </main>;
}
