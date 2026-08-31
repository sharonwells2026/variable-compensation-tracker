"use client";

import {useEffect,useMemo,useState} from "react";
import {ArrowLeft,CalendarDays,ChevronDown,ChevronUp,Eye,Plus,Save,ShieldCheck,Trash2,Users} from "lucide-react";
import {createClient} from "@supabase/supabase-js";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type WorkflowSummary={workflow_version_id:string;workflow_name:string;effective_start_date:string;effective_end_date:string|null;status:string;step_count:number};
type Employee={employee_id:string;full_name:string;email:string;job_title:string|null;is_active:boolean;current_workflow:WorkflowSummary|null};
type Approver={user_id:string;employee_id:string|null;full_name:string;email:string};
type AdminData={employees:Employee[];eligible_approvers:Approver[]};
type WorkflowStep={step_name:string;approval_level:string;approver_user_id:string;backup_approver_user_id:string;is_required:boolean};
type WorkflowHistory={workflow_version_id:string;workflow_name:string;status:string;effective_start_date:string;effective_end_date:string|null;notes:string|null;steps:Array<{id:string;approval_order:number;step_name:string;approval_level:string;is_required:boolean;approver_user_id:string;approver_name:string|null;backup_approver_user_id:string|null;backup_approver_name:string|null}>};

type Preview={status:string;workflow_name?:string;earned_date:string;steps:Array<{approval_order:number;step_name:string;approval_level:string;required:boolean;approver_name:string|null;backup_approver_name:string|null}>};

const blankStep=():WorkflowStep=>({step_name:"Manager Review",approval_level:"manager",approver_user_id:"",backup_approver_user_id:"",is_required:true});

export default function ApprovalWorkflowsPage(){
  const[data,setData]=useState<AdminData>({employees:[],eligible_approvers:[]});
  const[selectedEmployeeId,setSelectedEmployeeId]=useState("");
  const[history,setHistory]=useState<WorkflowHistory[]>([]);
  const[loading,setLoading]=useState(true);
  const[saving,setSaving]=useState(false);
  const[error,setError]=useState("");
  const[notice,setNotice]=useState("");
  const[workflowName,setWorkflowName]=useState("Standard Approval Workflow");
  const[startDate,setStartDate]=useState(new Date().toISOString().slice(0,10));
  const[endDate,setEndDate]=useState("");
  const[notes,setNotes]=useState("");
  const[steps,setSteps]=useState<WorkflowStep[]>([blankStep()]);
  const[previewDate,setPreviewDate]=useState(new Date().toISOString().slice(0,10));
  const[preview,setPreview]=useState<Preview|null>(null);

  const selectedEmployee=useMemo(()=>data.employees.find(e=>e.employee_id===selectedEmployeeId)||null,[data.employees,selectedEmployeeId]);

  const loadAdmin=async()=>{
    if(!supabase){setError("Database connection is unavailable.");setLoading(false);return;}
    setLoading(true);setError("");
    const{data:result,error:rpcError}=await supabase.rpc("get_approval_workflow_admin_data");
    if(rpcError){setError(rpcError.message);setLoading(false);return;}
    const next=(result||{employees:[],eligible_approvers:[]}) as AdminData;
    setData(next);
    setSelectedEmployeeId(current=>current||next.employees?.[0]?.employee_id||"");
    setLoading(false);
  };

  const loadHistory=async(employeeId:string)=>{
    if(!supabase||!employeeId)return;
    const{data:result,error:rpcError}=await supabase.rpc("get_employee_approval_workflows",{selected_employee_id:employeeId});
    if(rpcError){setError(rpcError.message);return;}
    setHistory((result||[]) as WorkflowHistory[]);
  };

  useEffect(()=>{loadAdmin()},[]);
  useEffect(()=>{if(selectedEmployeeId){loadHistory(selectedEmployeeId);setPreview(null)}},[selectedEmployeeId]);

  const updateStep=(index:number,patch:Partial<WorkflowStep>)=>setSteps(current=>current.map((step,i)=>i===index?{...step,...patch}:step));
  const moveStep=(index:number,direction:-1|1)=>{
    const next=[...steps],target=index+direction;if(target<0||target>=next.length)return;
    [next[index],next[target]]=[next[target],next[index]];setSteps(next);
  };
  const removeStep=(index:number)=>setSteps(current=>current.length===1?current:current.filter((_,i)=>i!==index));

  const createWorkflow=async()=>{
    if(!supabase||!selectedEmployeeId)return;
    if(steps.some(step=>!step.step_name.trim()||!step.approver_user_id)){setError("Every step needs a name and primary approver.");return;}
    setSaving(true);setError("");setNotice("");
    const payload=steps.map(step=>({step_name:step.step_name.trim(),approval_level:step.approval_level||"manager",approver_user_id:step.approver_user_id,backup_approver_user_id:step.backup_approver_user_id||null,is_required:step.is_required,conditions:{}}));
    const{error:rpcError}=await supabase.rpc("create_employee_approval_workflow",{
      selected_employee_id:selectedEmployeeId,
      selected_workflow_name:workflowName,
      selected_effective_start_date:startDate,
      selected_effective_end_date:endDate||null,
      selected_steps:payload,
      selected_notes:notes||null
    });
    if(rpcError){setError(rpcError.message);setSaving(false);return;}
    setNotice("Approval workflow created.");
    await loadAdmin();await loadHistory(selectedEmployeeId);
    setSteps([blankStep()]);setNotes("");setSaving(false);
  };

  const runPreview=async()=>{
    if(!supabase||!selectedEmployeeId)return;
    setError("");
    const{data:result,error:rpcError}=await supabase.rpc("preview_employee_approval_workflow",{selected_employee_id:selectedEmployeeId,selected_earned_date:previewDate});
    if(rpcError){setError(rpcError.message);return;}
    setPreview(result as Preview);
  };

  return <main className="min-h-screen bg-[#f6f8fc] text-[#252b35]">
    <div className="border-t-[7px] border-[#a7e3e5] bg-white shadow-sm">
      <div className="mx-auto flex max-w-[1500px] items-center justify-between px-6 py-4">
        <div className="flex items-center gap-4">
          <a href="/" className="grid h-9 w-9 place-items-center rounded-lg border border-[#e1e5ea] text-[#2095f3] hover:bg-[#f2f7ff]"><ArrowLeft size={17}/></a>
          <div><p className="m-0 text-[10px] font-extrabold tracking-[.12em] text-[#8d939c]">ADMINISTRATION</p><h1 className="m-0 text-xl font-bold">Approval Workflows</h1></div>
        </div>
        <div className="flex items-center gap-2 rounded-lg bg-[#edf6ff] px-3 py-2 text-xs font-semibold text-[#0879d5]"><ShieldCheck size={15}/> Effective-dated workflow engine</div>
      </div>
    </div>

    <div className="mx-auto grid max-w-[1500px] gap-5 px-6 py-6 lg:grid-cols-[360px_minmax(0,1fr)]">
      <aside className="rounded-xl border border-[#e1e5ea] bg-white p-4 shadow-sm">
        <div className="mb-4 flex items-start justify-between"><div><h2 className="m-0 text-sm font-bold">Employees</h2><p className="mt-1 text-xs text-[#77808e]">Choose an employee to configure routing.</p></div><Users size={18} className="text-[#2095f3]"/></div>
        {loading&&<p className="text-xs text-[#77808e]">Loading employees...</p>}
        {!loading&&data.employees.map(employee=>{
          const active=employee.employee_id===selectedEmployeeId;
          return <button key={employee.employee_id} onClick={()=>setSelectedEmployeeId(employee.employee_id)} className={`mb-2 w-full rounded-lg border p-3 text-left transition ${active?"border-[#2095f3] bg-[#eef7ff]":"border-[#e7eaee] bg-white hover:bg-[#f8fafc]"}`}>
            <div className="flex items-start justify-between gap-3"><div><div className="text-sm font-semibold">{employee.full_name}</div><div className="mt-1 text-[11px] text-[#77808e]">{employee.job_title||employee.email}</div></div><span className={`rounded-full px-2 py-1 text-[10px] font-bold ${employee.current_workflow?"bg-[#e9f8f2] text-[#17795e]":"bg-[#fff1d3] text-[#946407]"}`}>{employee.current_workflow?`${employee.current_workflow.step_count} step${employee.current_workflow.step_count===1?"":"s"}`:"No workflow"}</span></div>
            {employee.current_workflow&&<div className="mt-2 text-[10px] text-[#66717f]">{employee.current_workflow.workflow_name}</div>}
          </button>
        })}
      </aside>

      <section className="space-y-5">
        {error&&<div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}
        {notice&&<div className="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">{notice}</div>}

        <div className="rounded-xl border border-[#e1e5ea] bg-white p-5 shadow-sm">
          <div className="mb-5 flex flex-wrap items-start justify-between gap-4"><div><p className="m-0 text-[10px] font-extrabold tracking-[.1em] text-[#2095f3]">EMPLOYEE WORKFLOW</p><h2 className="mt-1 text-xl font-bold">{selectedEmployee?.full_name||"Select an employee"}</h2><p className="mt-1 text-xs text-[#77808e]">Create a new effective-dated workflow version. Historical versions are preserved.</p></div>{selectedEmployee?.current_workflow&&<div className="rounded-lg border border-[#d8e9f7] bg-[#f5fbff] px-3 py-2 text-xs"><b>{selectedEmployee.current_workflow.workflow_name}</b><div className="mt-1 text-[#77808e]">Effective {selectedEmployee.current_workflow.effective_start_date}{selectedEmployee.current_workflow.effective_end_date?` to ${selectedEmployee.current_workflow.effective_end_date}`:" onward"}</div></div>}</div>

          <div className="grid gap-4 md:grid-cols-3">
            <label className="text-xs font-semibold">Workflow name<input value={workflowName} onChange={e=>setWorkflowName(e.target.value)} className="mt-1 w-full rounded-lg border border-[#dfe4ea] px-3 py-2.5 text-sm font-normal outline-none focus:border-[#2095f3]"/></label>
            <label className="text-xs font-semibold">Effective start<input type="date" value={startDate} onChange={e=>setStartDate(e.target.value)} className="mt-1 w-full rounded-lg border border-[#dfe4ea] px-3 py-2.5 text-sm font-normal outline-none focus:border-[#2095f3]"/></label>
            <label className="text-xs font-semibold">Effective end <span className="font-normal text-[#8b939e]">(optional)</span><input type="date" value={endDate} onChange={e=>setEndDate(e.target.value)} className="mt-1 w-full rounded-lg border border-[#dfe4ea] px-3 py-2.5 text-sm font-normal outline-none focus:border-[#2095f3]"/></label>
          </div>

          <div className="mt-5"><div className="mb-3 flex items-center justify-between"><div><h3 className="m-0 text-sm font-bold">Approval steps</h3><p className="mt-1 text-xs text-[#77808e]">Steps run sequentially in the order shown.</p></div><button onClick={()=>setSteps(current=>[...current,blankStep()])} className="inline-flex items-center gap-1 rounded-lg border border-[#2095f3] px-3 py-2 text-xs font-bold text-[#2095f3]"><Plus size={14}/> Add step</button></div>
            <div className="space-y-3">{steps.map((step,index)=><div key={index} className="rounded-xl border border-[#e1e5ea] bg-[#fafbfd] p-4">
              <div className="mb-3 flex items-center justify-between"><div className="flex items-center gap-2"><span className="grid h-7 w-7 place-items-center rounded-full bg-[#2095f3] text-xs font-bold text-white">{index+1}</span><b className="text-sm">{step.step_name||`Step ${index+1}`}</b></div><div className="flex gap-1"><button onClick={()=>moveStep(index,-1)} disabled={index===0} className="rounded border border-[#dfe4ea] p-1.5 disabled:opacity-30"><ChevronUp size={14}/></button><button onClick={()=>moveStep(index,1)} disabled={index===steps.length-1} className="rounded border border-[#dfe4ea] p-1.5 disabled:opacity-30"><ChevronDown size={14}/></button><button onClick={()=>removeStep(index)} disabled={steps.length===1} className="rounded border border-[#f0d5d5] p-1.5 text-red-600 disabled:opacity-30"><Trash2 size={14}/></button></div></div>
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                <label className="text-[11px] font-semibold">Step name<input value={step.step_name} onChange={e=>updateStep(index,{step_name:e.target.value})} className="mt-1 w-full rounded-lg border border-[#dfe4ea] bg-white px-3 py-2 text-xs font-normal"/></label>
                <label className="text-[11px] font-semibold">Primary approver<select value={step.approver_user_id} onChange={e=>updateStep(index,{approver_user_id:e.target.value})} className="mt-1 w-full rounded-lg border border-[#dfe4ea] bg-white px-3 py-2 text-xs font-normal"><option value="">Select approver</option>{data.eligible_approvers.filter(a=>a.employee_id!==selectedEmployeeId).map(a=><option key={a.user_id} value={a.user_id}>{a.full_name}</option>)}</select></label>
                <label className="text-[11px] font-semibold">Backup approver<select value={step.backup_approver_user_id} onChange={e=>updateStep(index,{backup_approver_user_id:e.target.value})} className="mt-1 w-full rounded-lg border border-[#dfe4ea] bg-white px-3 py-2 text-xs font-normal"><option value="">None</option>{data.eligible_approvers.filter(a=>a.employee_id!==selectedEmployeeId&&a.user_id!==step.approver_user_id).map(a=><option key={a.user_id} value={a.user_id}>{a.full_name}</option>)}</select></label>
                <label className="text-[11px] font-semibold">Approval type<select value={step.approval_level} onChange={e=>updateStep(index,{approval_level:e.target.value})} className="mt-1 w-full rounded-lg border border-[#dfe4ea] bg-white px-3 py-2 text-xs font-normal"><option value="manager">Manager</option><option value="executive">Executive</option><option value="finance">Finance</option><option value="other">Other</option></select></label>
              </div>
              <label className="mt-3 flex items-center gap-2 text-xs"><input type="checkbox" checked={step.is_required} onChange={e=>updateStep(index,{is_required:e.target.checked})}/> Required approval step</label>
            </div>)}</div>
          </div>

          <label className="mt-4 block text-xs font-semibold">Notes<textarea value={notes} onChange={e=>setNotes(e.target.value)} rows={3} className="mt-1 w-full rounded-lg border border-[#dfe4ea] px-3 py-2 text-sm font-normal" placeholder="Optional notes about why this workflow version exists."/></label>
          <div className="mt-5 flex justify-end"><button onClick={createWorkflow} disabled={saving||!selectedEmployeeId} className="inline-flex items-center gap-2 rounded-lg bg-[#2095f3] px-4 py-2.5 text-xs font-bold text-white disabled:opacity-50"><Save size={15}/>{saving?"Saving...":"Create workflow version"}</button></div>
        </div>

        <div className="grid gap-5 xl:grid-cols-2">
          <div className="rounded-xl border border-[#e1e5ea] bg-white p-5 shadow-sm"><div className="mb-4 flex items-center justify-between"><div><h3 className="m-0 text-sm font-bold">Preview routing</h3><p className="mt-1 text-xs text-[#77808e]">See which workflow applies to an earning date.</p></div><Eye size={18} className="text-[#2095f3]"/></div><div className="flex gap-2"><input type="date" value={previewDate} onChange={e=>setPreviewDate(e.target.value)} className="flex-1 rounded-lg border border-[#dfe4ea] px-3 py-2 text-sm"/><button onClick={runPreview} className="rounded-lg bg-[#051b34] px-4 py-2 text-xs font-bold text-white">Preview</button></div>{preview&&<div className="mt-4 rounded-lg bg-[#f7f9fc] p-4">{preview.status==="no_workflow"?<p className="m-0 text-sm text-[#946407]">No workflow governs {preview.earned_date}.</p>:<><div className="mb-3 text-sm font-bold">{preview.workflow_name}</div><div className="space-y-2">{preview.steps.map(step=><div key={step.approval_order} className="flex items-center gap-3 rounded-lg border border-[#e1e5ea] bg-white p-3"><span className="grid h-7 w-7 place-items-center rounded-full bg-[#e8f4ff] text-xs font-bold text-[#2095f3]">{step.approval_order}</span><div><b className="text-xs">{step.step_name}</b><div className="mt-1 text-[11px] text-[#77808e]">{step.approver_name||"Unresolved approver"}{step.backup_approver_name?` · Backup: ${step.backup_approver_name}`:""}</div></div></div>)}</div></>}</div>}</div>

          <div className="rounded-xl border border-[#e1e5ea] bg-white p-5 shadow-sm"><div className="mb-4 flex items-center justify-between"><div><h3 className="m-0 text-sm font-bold">Workflow history</h3><p className="mt-1 text-xs text-[#77808e]">Historical versions stay visible and unchanged.</p></div><CalendarDays size={18} className="text-[#2095f3]"/></div>{history.length===0?<div className="rounded-lg border border-dashed border-[#d8dde4] p-6 text-center text-xs text-[#77808e]">No approval workflow has been created for this employee.</div>:<div className="space-y-3">{history.map(item=><div key={item.workflow_version_id} className="rounded-lg border border-[#e1e5ea] p-3"><div className="flex items-start justify-between gap-3"><div><b className="text-sm">{item.workflow_name}</b><div className="mt-1 text-[11px] text-[#77808e]">{item.effective_start_date} → {item.effective_end_date||"ongoing"}</div></div><span className="rounded-full bg-[#eef4fb] px-2 py-1 text-[10px] font-bold text-[#47627a]">{item.status}</span></div><div className="mt-3 flex flex-wrap gap-2">{item.steps.map(step=><span key={step.id} className="rounded-md bg-[#f6f8fc] px-2 py-1.5 text-[10px] text-[#53606f]">{step.approval_order}. {step.step_name} · {step.approver_name||"Unknown"}</span>)}</div></div>)}</div>}</div>
        </div>
      </section>
    </div>
  </main>;
}
