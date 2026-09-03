"use client";

import {useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import {CheckCircle2,ChevronRight,RefreshCw,RotateCcw,Send,ShieldCheck,WalletCards} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type Batch={id:string;batch_name:string;status:string;created_at:string;submitted_at:string|null;approved_at:string|null;finance_accepted_at:string|null;return_reason:string|null;item_count:number;employee_count:number;proposed_total:number;};
type Item={id:string;review_batch_id:string;comp_earning_id:string;employee_id:string;employee_name:string;proposed_amount:number;included:boolean;review_note:string|null;override_reason?:string|null;item_snapshot:Record<string,unknown>;};
type Payload={batches:Batch[];items:Item[]};

const stageCopy:Record<string,{label:string;owner:string;description:string}>={
  draft:{label:"Ready to submit",owner:"Sharon",description:"Review eligible earnings, exclude anything not ready, and submit whenever appropriate."},
  returned:{label:"Returned",owner:"Sharon",description:"Returned for correction or clarification. Edit and resubmit when ready."},
  submitted:{label:"With Namit",owner:"Namit",description:"Submitted snapshot is frozen while executive approval is pending."},
  approved:{label:"With Scott",owner:"Scott",description:"Approved and waiting for Finance acceptance."},
  finance_accepted:{label:"Payment pending",owner:"Scott",description:"Finance accepted the obligation. Actual payment is confirmed separately in payroll."},
  closed:{label:"Completed",owner:"Complete",description:"Review workflow completed."},
  cancelled:{label:"Cancelled",owner:"Complete",description:"Submission was cancelled and remains in the audit trail."},
};

function money(value:number){return new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(value||0))}

export default function SubmissionsPage(){
  const[data,setData]=useState<Payload>({batches:[],items:[]});
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState("");
  const[busy,setBusy]=useState<string|null>(null);
  const[comments,setComments]=useState<Record<string,string>>({});
  const[active,setActive]=useState("all");

  const load=async()=>{
    if(!supabase){setError("Database connection unavailable");setLoading(false);return}
    setLoading(true);setError("");
    const{data:result,error:rpcError}=await supabase.rpc("get_compensation_review_batches");
    if(rpcError)setError(rpcError.message);else setData((result||{batches:[],items:[]}) as Payload);
    setLoading(false);
  };
  useEffect(()=>{load()},[]);

  const filtered=useMemo(()=>active==="all"?data.batches:data.batches.filter(batch=>batch.status===active),[data.batches,active]);
  const counts=useMemo(()=>Object.fromEntries(["draft","submitted","approved","finance_accepted","closed","returned"].map(status=>[status,data.batches.filter(batch=>batch.status===status).length])),[data.batches]);

  const act=async(batch:Batch,action:"submit"|"approve"|"return"|"accept")=>{
    if(!supabase)return;
    setBusy(batch.id+action);setError("");
    const note=comments[batch.id]||null;
    const call=action==="submit"
      ? supabase.rpc("submit_compensation_review_batch",{target_review_batch_id:batch.id})
      : action==="accept"
        ? supabase.rpc("accept_compensation_review_batch_for_payment",{target_review_batch_id:batch.id,action_comments:note})
        : supabase.rpc("act_on_compensation_review_batch",{target_review_batch_id:batch.id,requested_action:action==="approve"?"approved":"returned",action_comments:note});
    const{error:rpcError}=await call;
    if(rpcError)setError(rpcError.message);else{setComments(current=>({...current,[batch.id]:""}));await load()}
    setBusy(null);
  };

  return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:"28px",fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}>
    <div style={{maxWidth:1250,margin:"0 auto"}}>
      <header style={{display:"flex",justifyContent:"space-between",gap:18,alignItems:"flex-start",marginBottom:22}}>
        <div><small style={{fontWeight:800,letterSpacing:1.2,color:"#2095f3"}}>COMPENSATION ADMINISTRATION</small><h1 style={{fontSize:34,margin:"7px 0"}}>Compensation submissions</h1><p style={{margin:0,color:"#647184",maxWidth:800}}>No monthly cutoff. Submit eligible compensation whenever it is ready. Reporting periods organize activity; they do not control when a submission is allowed.</p></div>
        <button onClick={load} disabled={loading} style={{display:"flex",alignItems:"center",gap:7,padding:"10px 13px",background:"white",border:"1px solid #d9e2eb",borderRadius:9,fontWeight:700}}><RefreshCw size={16}/>{loading?"Refreshing…":"Refresh"}</button>
      </header>

      <section style={{display:"grid",gridTemplateColumns:"repeat(5,minmax(0,1fr))",gap:10,marginBottom:20}}>
        {[["draft","Ready to submit","Sharon"],["submitted","With Namit","Namit"],["approved","With Scott","Scott"],["finance_accepted","Payment pending","Scott"],["closed","Completed","—"]].map(([status,label,owner])=><button key={status} onClick={()=>setActive(active===status?"all":status)} style={{textAlign:"left",background:active===status?"#eaf5ff":"white",border:"1px solid #dfe6ee",borderRadius:12,padding:15,cursor:"pointer"}}><small style={{display:"block",fontWeight:800,color:"#718096"}}>{owner}</small><b style={{display:"block",fontSize:16,margin:"4px 0"}}>{label}</b><strong style={{fontSize:24}}>{counts[status]||0}</strong></button>)}
      </section>

      <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18,marginBottom:18}}>
        <div style={{display:"flex",alignItems:"center",gap:8,flexWrap:"wrap"}}>{["Sharon reviews","Namit approves","Scott accepts","Scott confirms paid"].map((label,index)=><div key={label} style={{display:"flex",alignItems:"center",gap:8}}><span style={{padding:"9px 12px",border:"1px solid #dbe4ee",borderRadius:9,background:index===0?"#eaf5ff":"#f8fafc",fontWeight:700}}>{label}</span>{index<3&&<ChevronRight size={16} color="#8b98a8"/>}</div>)}</div>
      </section>

      {error&&<div style={{background:"#fff3f3",border:"1px solid #f2caca",borderRadius:10,padding:13,marginBottom:15}}>{error}</div>}

      {loading?<p>Loading submissions…</p>:filtered.length===0?<section style={{background:"white",border:"1px dashed #cbd5df",borderRadius:14,padding:34,textAlign:"center"}}><ShieldCheck size={28}/><h2>No submissions in this queue</h2><p style={{color:"#647184"}}>Eligible compensation can be submitted whenever it is ready.</p></section>:filtered.map(batch=>{
        const stage=stageCopy[batch.status]||{label:batch.status,owner:"—",description:""};
        const items=data.items.filter(item=>item.review_batch_id===batch.id&&item.included);
        return <article key={batch.id} style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:20,marginBottom:15}}>
          <div style={{display:"flex",justifyContent:"space-between",gap:14,alignItems:"flex-start"}}><div><small style={{fontWeight:800,color:"#2095f3"}}>{stage.label.toUpperCase()}</small><h2 style={{margin:"5px 0 3px",fontSize:21}}>{batch.batch_name}</h2><p style={{margin:0,color:"#647184",fontSize:13}}>{stage.description}</p></div><div style={{textAlign:"right"}}><b style={{fontSize:23}}>{money(batch.proposed_total)}</b><small style={{display:"block",color:"#718096",marginTop:3}}>{batch.item_count} items · {batch.employee_count} employees</small></div></div>

          <div style={{display:"grid",gap:7,marginTop:15}}>{items.slice(0,8).map(item=><div key={item.id} style={{display:"grid",gridTemplateColumns:"1.2fr 1.8fr auto",gap:12,alignItems:"center",background:"#f8fafc",borderRadius:9,padding:"10px 12px"}}><b>{item.employee_name}</b><span style={{fontSize:13,color:"#5f6b7a"}}>{String(item.item_snapshot?.earning_name||"Compensation earning")}{item.override_reason?` · Override: ${item.override_reason}`:""}</span><strong>{money(item.proposed_amount)}</strong></div>)}</div>
          {items.length>8&&<small style={{display:"block",marginTop:8,color:"#718096"}}>+ {items.length-8} additional items</small>}

          {batch.return_reason&&<div style={{marginTop:13,padding:11,background:"#fff8e7",borderRadius:9}}><b>Return reason:</b> {batch.return_reason}</div>}

          {batch.status!=="closed"&&batch.status!=="cancelled"&&<div style={{display:"flex",gap:9,alignItems:"center",marginTop:16,flexWrap:"wrap"}}>
            {(batch.status==="submitted"||batch.status==="approved")&&<input value={comments[batch.id]||""} onChange={e=>setComments(current=>({...current,[batch.id]:e.target.value}))} placeholder={batch.status==="submitted"?"Comment or return reason…":"Finance note…"} style={{flex:"1 1 280px",padding:"10px 11px",border:"1px solid #d6dee8",borderRadius:8}}/>}
            {(batch.status==="draft"||batch.status==="returned")&&<button onClick={()=>act(batch,"submit")} disabled={busy===batch.id+"submit"} style={{display:"flex",gap:7,alignItems:"center",padding:"10px 13px",border:0,borderRadius:8,background:"#2095f3",color:"white",fontWeight:800}}><Send size={16}/>Submit to Namit</button>}
            {batch.status==="submitted"&&<><button onClick={()=>act(batch,"approve")} disabled={busy===batch.id+"approve"} style={{display:"flex",gap:7,alignItems:"center",padding:"10px 13px",border:0,borderRadius:8,background:"#0f8a57",color:"white",fontWeight:800}}><CheckCircle2 size={16}/>Approve</button><button onClick={()=>act(batch,"return")} disabled={busy===batch.id+"return"} style={{display:"flex",gap:7,alignItems:"center",padding:"10px 13px",border:"1px solid #d5dde6",borderRadius:8,background:"white",fontWeight:800}}><RotateCcw size={16}/>Return</button></>}
            {batch.status==="approved"&&<button onClick={()=>act(batch,"accept")} disabled={busy===batch.id+"accept"} style={{display:"flex",gap:7,alignItems:"center",padding:"10px 13px",border:0,borderRadius:8,background:"#051b34",color:"white",fontWeight:800}}><WalletCards size={16}/>Accept for payment</button>}
          </div>}
        </article>
      })}
    </div>
  </main>
}
