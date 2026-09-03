"use client";

import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {CheckCircle2,ChevronRight,Home,RefreshCw,WalletCards} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type AccessSummary={full_name?:string;email?:string;roles:string[];permissions:string[]};
type Summary={counts:Record<string,number>;amounts:Record<string,number>;employees:Array<{employee_id:string;employee_name:string;eligible_count:number;approved_count:number;ready_for_payroll_count:number;held_count:number;ready_amount:number}>};
type PayrollBatch={id:string;batch_name:string;payroll_period_start:string;payroll_period_end:string;scheduled_payment_date:string|null;actual_payment_date:string|null;status:string;payment_reference:string|null;payment_method:string|null;created_at:string};

type WorkflowPayload={payroll_batches:PayrollBatch[]};
function money(value:number){return new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(value||0))}

export default function PaymentsPage(){
  const[summary,setSummary]=useState<Summary|null>(null);
  const[batches,setBatches]=useState<PayrollBatch[]>([]);
  const[access,setAccess]=useState<AccessSummary|null>(null);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState("");

  const load=async()=>{
    if(!supabase){setError("Database connection unavailable");setLoading(false);return}
    setLoading(true);setError("");
    const[a,b,c]=await Promise.all([
      supabase.rpc("get_current_user_access"),
      supabase.rpc("get_payout_readiness_summary"),
      supabase.rpc("get_workflow_management_data")
    ]);
    if(a.error)setError(a.error.message);else setAccess(a.data as AccessSummary);
    if(b.error)setError(current=>current||b.error.message);else setSummary(b.data as Summary);
    if(c.error)setError(current=>current||c.error.message);else setBatches(((c.data||{}) as WorkflowPayload).payroll_batches||[]);
    setLoading(false);
  };
  useEffect(()=>{load()},[]);

  const isAdmin=Boolean(access?.roles?.includes("system_administrator"));
  const canFinance=isAdmin||Boolean(access?.permissions?.includes("payments.view"));

  return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{maxWidth:1250,margin:"0 auto"}}>
    <nav style={{display:"flex",gap:9,alignItems:"center",marginBottom:18,flexWrap:"wrap"}}><Link href="/" style={{display:"inline-flex",alignItems:"center",gap:6,color:"#31465a",textDecoration:"none",fontWeight:700}}><Home size={16}/>Workspace</Link><ChevronRight size={15} color="#9aa7b4"/><Link href="/submissions" style={{color:"#31465a",fontWeight:700,textDecoration:"none"}}>Submissions</Link><ChevronRight size={15} color="#9aa7b4"/><b>Payments</b></nav>
    <header style={{display:"flex",justifyContent:"space-between",gap:18,alignItems:"flex-start",marginBottom:22,flexWrap:"wrap"}}><div><small style={{fontWeight:800,letterSpacing:1.2,color:"#2095f3"}}>FINANCE & PAYROLL</small><h1 style={{fontSize:34,margin:"7px 0"}}>Payments</h1><p style={{margin:0,color:"#647184",maxWidth:820}}>This workspace begins after compensation is approved and accepted for payment. Finance acceptance does not mark an earning Paid; actual payment confirmation does.</p><small style={{display:"block",marginTop:8,color:"#718096"}}>{access?.full_name||access?.email||"Signed-in user"}{isAdmin?" · System Administrator":""}</small></div><button onClick={load} disabled={loading} style={{display:"flex",alignItems:"center",gap:7,padding:"10px 13px",background:"white",border:"1px solid #d9e2eb",borderRadius:9,fontWeight:700}}><RefreshCw size={16}/>{loading?"Refreshing…":"Refresh"}</button></header>

    {error&&<div style={{background:"#fff3f3",border:"1px solid #f2caca",borderRadius:10,padding:13,marginBottom:15}}>{error}</div>}
    {!canFinance&&!loading&&<div style={{background:"#fff8e7",border:"1px solid #ead8a5",borderRadius:10,padding:13,marginBottom:15}}>You have read-only access to this payment view. Finance actions require payment permissions.</div>}

    <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(180px,1fr))",gap:10,marginBottom:20}}>{[
      ["Approved & eligible",summary?.counts?.approved_and_eligible||0,summary?.amounts?.approved||0],
      ["Ready for payroll",summary?.counts?.ready_for_payroll||0,summary?.amounts?.ready_for_payroll||0],
      ["Scheduled",summary?.counts?.scheduled||0,summary?.amounts?.scheduled||0],
      ["Held",summary?.counts?.held||0,summary?.amounts?.held||0],
      ["Paid",summary?.counts?.paid||0,summary?.amounts?.paid||0]
    ].map(([label,count,amount])=><div key={String(label)} style={{background:"white",border:"1px solid #dfe6ee",borderRadius:12,padding:15}}><small style={{display:"block",fontWeight:800,color:"#718096"}}>{label}</small><b style={{display:"block",fontSize:24,margin:"5px 0"}}>{loading?"—":String(count)}</b><strong style={{color:"#31465a"}}>{loading?"—":money(Number(amount))}</strong></div>)}</section>

    <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18,marginBottom:18}}><div style={{display:"flex",alignItems:"center",gap:8,flexWrap:"wrap"}}>{["Namit approves","Scott accepts","Payroll scheduled","Scott confirms actual payment"].map((label,index)=><div key={label} style={{display:"flex",alignItems:"center",gap:8}}><span style={{padding:"9px 12px",border:"1px solid #dbe4ee",borderRadius:9,background:index>=1?"#f8fafc":"#eaf5ff",fontWeight:700}}>{label}</span>{index<3&&<ChevronRight size={16} color="#8b98a8"/>}</div>)}</div></section>

    <div style={{display:"grid",gridTemplateColumns:"minmax(0,1.25fr) minmax(320px,.75fr)",gap:16,alignItems:"start"}}>
      <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18}}><h2 style={{marginTop:0}}>Employee payout readiness</h2><p style={{color:"#647184",marginTop:-7}}>Live ledger status by employee. This is not a second approval queue.</p><div style={{display:"grid",gap:8,marginTop:14}}>{(summary?.employees||[]).filter(x=>x.eligible_count||x.approved_count||x.ready_for_payroll_count||x.held_count).map(row=><div key={row.employee_id} style={{display:"grid",gridTemplateColumns:"1.4fr repeat(4,minmax(75px,.65fr))",gap:10,alignItems:"center",padding:"11px 12px",background:"#f8fafc",borderRadius:9}}><b>{row.employee_name}</b><span><small style={{display:"block",color:"#7b8794"}}>Eligible</small>{row.eligible_count}</span><span><small style={{display:"block",color:"#7b8794"}}>Approved</small>{row.approved_count}</span><span><small style={{display:"block",color:"#7b8794"}}>Ready</small>{row.ready_for_payroll_count}</span><strong style={{textAlign:"right"}}>{money(row.ready_amount)}</strong></div>)}</div>{!loading&&(summary?.employees||[]).every(x=>!x.eligible_count&&!x.approved_count&&!x.ready_for_payroll_count&&!x.held_count)&&<p style={{color:"#647184"}}>No employee payouts are currently waiting in the payment lifecycle.</p>}</section>

      <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18}}><h2 style={{marginTop:0}}>Payroll batches</h2><p style={{color:"#647184",marginTop:-7}}>Payment execution only. Review submissions remain in <Link href="/submissions">Submissions</Link>.</p><div style={{display:"grid",gap:9,marginTop:14}}>{batches.map(batch=><div key={batch.id} style={{border:"1px solid #e2e8ef",borderRadius:10,padding:12}}><div style={{display:"flex",justifyContent:"space-between",gap:8}}><b>{batch.batch_name}</b><span style={{fontWeight:800,textTransform:"capitalize",color:batch.status==="paid"?"#0f8a57":"#59697a"}}>{batch.status.replaceAll("_"," ")}</span></div><small style={{display:"block",marginTop:5,color:"#718096"}}>Scheduled {batch.scheduled_payment_date||"—"} · Paid {batch.actual_payment_date||"—"}</small>{batch.payment_reference&&<small style={{display:"block",marginTop:3,color:"#718096"}}>Reference {batch.payment_reference}</small>}</div>)}</div>{!loading&&batches.length===0&&<div style={{textAlign:"center",padding:24,color:"#647184"}}><WalletCards size={26}/><p>No payroll batches yet.</p></div>}</section>
    </div>

    <section style={{marginTop:16,background:"#eef7ff",border:"1px solid #cde5f8",borderRadius:12,padding:14,display:"flex",gap:10,alignItems:"flex-start"}}><CheckCircle2 size={19} color="#0f8a57"/><div><b>Audit rule</b><p style={{margin:"3px 0 0",color:"#526477"}}>Paid history is never silently rewritten. Corrections must be recorded as adjustments so the original approved and paid record remains intact.</p></div></section>
  </div></main>
}
