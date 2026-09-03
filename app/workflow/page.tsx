"use client";

import {useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import {CheckCircle2,ChevronRight,Clock3,RefreshCw,ShieldCheck,WalletCards} from "lucide-react";
import {currentEngagifiiWorkflow} from "../../lib/compensation-workflow";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type Employee={id:string;full_name:string;email:string};
type WorkflowVersion={id:string;employee_id:string;workflow_name:string;status:string;effective_start_date:string;effective_end_date:string|null;notes:string|null};
type ApprovalStep={id:string;workflow_version_id:string;employee_id:string;approval_order:number;step_name:string|null;approval_level:string;approver_employee_id:string|null;is_required:boolean};
type PostStep={id:string;workflow_version_id:string;employee_id:string;stage_order:number;step_name:string;step_type:string;assignee_employee_id:string;is_required_for_payment:boolean;requires_payment_details:boolean};
type PayrollBatch={id:string;batch_name:string;payroll_period_start:string|null;payroll_period_end:string|null;scheduled_payment_date:string|null;actual_payment_date:string|null;status:string;payment_reference:string|null;payment_method:string|null;created_at:string};
type WorkflowPayload={employees:Employee[];workflow_versions:WorkflowVersion[];approval_steps:ApprovalStep[];post_steps:PostStep[];payroll_batches:PayrollBatch[]};

function personName(id:string|null,employees:Map<string,Employee>){return id?employees.get(id)?.full_name||"Unassigned":"Unassigned"}

export default function WorkflowPage(){
  const[employees,setEmployees]=useState<Employee[]>([]),[versions,setVersions]=useState<WorkflowVersion[]>([]),[approvalSteps,setApprovalSteps]=useState<ApprovalStep[]>([]),[postSteps,setPostSteps]=useState<PostStep[]>([]),[batches,setBatches]=useState<PayrollBatch[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState("");
  const employeeMap=useMemo(()=>new Map(employees.map(employee=>[employee.id,employee])),[employees]);
  const load=async()=>{
    if(!supabase){setError("Supabase connection unavailable");setLoading(false);return}
    setLoading(true);setError("");
    const{data,error:rpcError}=await supabase.rpc("get_workflow_management_data");
    if(rpcError){setError(rpcError.message);setLoading(false);return}
    const payload=(data||{}) as Partial<WorkflowPayload>;
    setEmployees(payload.employees||[]);
    setVersions(payload.workflow_versions||[]);
    setApprovalSteps(payload.approval_steps||[]);
    setPostSteps(payload.post_steps||[]);
    setBatches(payload.payroll_batches||[]);
    setLoading(false);
  };
  useEffect(()=>{load()},[]);

  return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:"32px",fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}>
    <div style={{maxWidth:1200,margin:"0 auto"}}>
      <header style={{display:"flex",justifyContent:"space-between",gap:20,alignItems:"flex-start",marginBottom:24}}>
        <div><small style={{fontWeight:800,letterSpacing:1.2,color:"#2095f3"}}>VARIABLE COMPENSATION · ADMINISTRATION</small><h1 style={{fontSize:34,margin:"8px 0"}}>Approval & payment workflow</h1><p style={{margin:0,color:"#5b6778",maxWidth:760}}>Operational workflow is separate from the compensation lifecycle. Approved does not mean paid, and Finance acceptance does not mean paid.</p></div>
        <button onClick={load} disabled={loading} style={{display:"flex",gap:8,alignItems:"center",border:"1px solid #d6dee8",background:"white",borderRadius:9,padding:"10px 14px",fontWeight:700,cursor:"pointer"}}><RefreshCw size={16}/>{loading?"Refreshing…":"Refresh"}</button>
      </header>

      <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:22,marginBottom:22}}>
        <div style={{display:"flex",alignItems:"center",gap:10,marginBottom:18}}><ShieldCheck size={22}/><div><b>Current Engagifii operating model</b><div style={{fontSize:13,color:"#657286",marginTop:3}}>System Administrator retains full application authority. Business workflow still records the responsible business owner for every step.</div></div></div>
        <div style={{display:"flex",alignItems:"stretch",gap:8,flexWrap:"wrap"}}>
          {["Sharon reviews","Namit approves","Scott accepts for payment","Scott confirms payment"].map((label,index)=><div key={label} style={{display:"flex",alignItems:"center",gap:8}}><div style={{background:index===0?"#eaf5ff":"#f7f9fc",border:"1px solid #dbe4ee",borderRadius:10,padding:"12px 15px",minWidth:190}}><small style={{display:"block",color:"#718096",fontWeight:700}}>STEP {index+1}</small><b style={{display:"block",marginTop:4}}>{label}</b></div>{index<3&&<ChevronRight size={18} color="#8a97a8"/>}</div>)}
        </div>
        <div style={{marginTop:14,fontSize:13,color:"#657286"}}>{currentEngagifiiWorkflow.employeeSequence.join(" → ")}</div>
      </section>

      {error&&<section style={{background:"#fff5f5",border:"1px solid #fed7d7",borderRadius:12,padding:16,marginBottom:20}}><b>Workflow data could not load</b><div style={{marginTop:5,fontSize:13}}>{error}</div></section>}

      <div style={{display:"grid",gridTemplateColumns:"minmax(0,1.45fr) minmax(320px,.75fr)",gap:20,alignItems:"start"}}>
        <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:22}}>
          <div style={{marginBottom:16}}><h2 style={{margin:"0 0 5px"}}>Configured employee workflows</h2><p style={{margin:0,color:"#657286",fontSize:14}}>Live workflow versions, approval steps, and post-approval Finance responsibilities.</p></div>
          {loading?<p>Loading workflow configuration…</p>:versions.length===0?<p style={{color:"#657286"}}>No workflow versions found.</p>:versions.map(version=>{
            const employee=employeeMap.get(version.employee_id);
            const approvals=approvalSteps.filter(step=>step.workflow_version_id===version.id);
            const posts=postSteps.filter(step=>step.workflow_version_id===version.id);
            return <article key={version.id} style={{border:"1px solid #e2e8f0",borderRadius:12,padding:18,marginBottom:14}}>
              <div style={{display:"flex",justifyContent:"space-between",gap:16,alignItems:"flex-start"}}><div><small style={{fontWeight:800,color:"#2095f3"}}>{employee?.full_name||"Unknown employee"}</small><h3 style={{margin:"5px 0 4px"}}>{version.workflow_name}</h3><div style={{fontSize:12,color:"#718096"}}>Effective {version.effective_start_date}{version.effective_end_date?` through ${version.effective_end_date}`:""}</div></div><span style={{textTransform:"uppercase",fontSize:11,fontWeight:800,background:version.status==="active"?"#e9f8ef":"#fff8e7",padding:"6px 9px",borderRadius:999}}>{version.status}</span></div>
              <div style={{display:"grid",gap:8,marginTop:15}}>
                {approvals.map(step=><div key={step.id} style={{display:"grid",gridTemplateColumns:"34px 1fr auto",gap:10,alignItems:"center",padding:"10px 12px",background:"#f8fafc",borderRadius:9}}><span style={{width:28,height:28,borderRadius:999,display:"grid",placeItems:"center",background:"#eaf5ff",fontWeight:800}}>{step.approval_order}</span><div><b>{step.step_name||step.approval_level}</b><small style={{display:"block",color:"#718096",marginTop:2}}>Approver: {personName(step.approver_employee_id,employeeMap)}</small></div><span style={{fontSize:12,fontWeight:700}}>{step.is_required?"Required":"Optional"}</span></div>)}
                {posts.map(step=><div key={step.id} style={{display:"grid",gridTemplateColumns:"34px 1fr auto",gap:10,alignItems:"center",padding:"10px 12px",background:"#f8fafc",borderRadius:9}}><span style={{width:28,height:28,borderRadius:999,display:"grid",placeItems:"center",background:"#eef7ee",fontWeight:800}}><WalletCards size={15}/></span><div><b>{step.step_name}</b><small style={{display:"block",color:"#718096",marginTop:2}}>Owner: {personName(step.assignee_employee_id,employeeMap)}</small></div><span style={{fontSize:12,fontWeight:700}}>{step.is_required_for_payment?"Required for payment":"Optional"}</span></div>)}
              </div>
              {version.notes&&<p style={{fontSize:13,color:"#657286",margin:"14px 0 0"}}>{version.notes}</p>}
            </article>
          })}
        </section>

        <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:22}}>
          <div style={{display:"flex",gap:10,alignItems:"center",marginBottom:16}}><Clock3 size={20}/><div><h2 style={{margin:0,fontSize:20}}>Payroll batches</h2><small style={{color:"#718096"}}>Acceptance and payment remain distinct</small></div></div>
          {loading?<p>Loading payroll…</p>:batches.length===0?<div style={{border:"1px dashed #ccd6e2",borderRadius:10,padding:18,textAlign:"center",color:"#657286"}}><WalletCards size={24}/><b style={{display:"block",marginTop:8}}>No payroll batches yet</b><small>The first live batch will appear here after approved earnings are prepared for payment.</small></div>:batches.map(batch=><article key={batch.id} style={{borderTop:"1px solid #edf1f5",padding:"14px 0"}}><div style={{display:"flex",justifyContent:"space-between",gap:10}}><b>{batch.batch_name}</b><span style={{fontSize:11,fontWeight:800,textTransform:"uppercase"}}>{batch.status}</span></div><small style={{display:"block",color:"#718096",marginTop:4}}>{batch.payroll_period_start||"—"} → {batch.payroll_period_end||"—"}</small><div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:8,marginTop:10,fontSize:12}}><span><b>Scheduled</b><br/>{batch.scheduled_payment_date||"Not set"}</span><span><b>Paid</b><br/>{batch.actual_payment_date||"Not confirmed"}</span></div>{batch.actual_payment_date&&<div style={{display:"flex",gap:6,alignItems:"center",marginTop:9,color:"#177245",fontSize:12,fontWeight:700}}><CheckCircle2 size={14}/>Payment confirmed</div>}</article>)}
        </section>
      </div>
    </div>
  </main>
}
