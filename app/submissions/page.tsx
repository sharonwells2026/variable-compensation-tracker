"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {CheckCircle2,ChevronRight,Eye,Home,RefreshCw,RotateCcw,Send,ShieldCheck,WalletCards,XCircle} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type AccessSummary={authenticated:boolean;user_id?:string;email?:string;full_name?:string;employee_id?:string|null;roles:string[];permissions:string[]};
type Batch={id:string;batch_name:string;status:string;created_at:string;submitted_at:string|null;approved_at:string|null;finance_accepted_at:string|null;return_reason:string|null;item_count:number;employee_count:number;proposed_total:number;};
type Item={id:string;review_batch_id:string;comp_earning_id:string;employee_id:string;employee_name:string;proposed_amount:number;included:boolean;review_note:string|null;override_reason?:string|null;item_snapshot:Record<string,unknown>;};
type Payload={batches:Batch[];items:Item[]};

const stageCopy:Record<string,{label:string;owner:string;description:string}>={
  draft:{label:"Ready to submit",owner:"Sharon / System Admin",description:"Review eligible earnings, correct or exclude anything not ready, and submit whenever appropriate."},
  returned:{label:"Returned",owner:"Sharon / System Admin",description:"Returned for correction or clarification. Edit and resubmit when ready."},
  submitted:{label:"With Namit",owner:"Executive approver",description:"Submitted snapshot is frozen while approval is pending."},
  approved:{label:"With Scott",owner:"Finance",description:"Approved and waiting for Finance acceptance."},
  finance_accepted:{label:"Payment pending",owner:"Finance",description:"Finance accepted the obligation. Actual payment is confirmed separately in payroll."},
  closed:{label:"Completed",owner:"Complete",description:"Review workflow completed."},
  cancelled:{label:"Cancelled",owner:"Complete",description:"Submission was cancelled and remains in the audit trail."},
};

function money(value:number){return new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(value||0))}
function dateLabel(value:string|null){return value?new Date(value).toLocaleString():"—"}

export default function SubmissionsPage(){
  const[data,setData]=useState<Payload>({batches:[],items:[]});
  const[access,setAccess]=useState<AccessSummary|null>(null);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState("");
  const[busy,setBusy]=useState<string|null>(null);
  const[comments,setComments]=useState<Record<string,string>>({});
  const[active,setActive]=useState("all");
  const[expanded,setExpanded]=useState<Record<string,boolean>>({});
  const[editing,setEditing]=useState<Record<string,{amount:string;note:string;reason:string}>>({});

  const isAdmin=Boolean(access?.roles?.includes("system_administrator"));
  const canApprove=isAdmin||Boolean(access?.permissions?.includes("earnings.approve"));
  const canFinance=isAdmin||Boolean(access?.permissions?.includes("payments.view"));
  const canPrepare=isAdmin;

  const load=async()=>{
    if(!supabase){setError("Database connection unavailable");setLoading(false);return}
    setLoading(true);setError("");
    const[{data:accessData,error:accessError},{data:result,error:rpcError}]=await Promise.all([
      supabase.rpc("get_current_user_access"),
      supabase.rpc("get_compensation_review_batches")
    ]);
    if(accessError)setError(accessError.message);else setAccess(accessData as AccessSummary);
    if(rpcError)setError(current=>current||rpcError.message);else setData((result||{batches:[],items:[]}) as Payload);
    setLoading(false);
  };
  useEffect(()=>{load()},[]);

  const filtered=useMemo(()=>active==="all"?data.batches:data.batches.filter(batch=>batch.status===active),[data.batches,active]);
  const counts=useMemo(()=>Object.fromEntries(["draft","submitted","approved","finance_accepted","closed","returned"].map(status=>[status,data.batches.filter(batch=>batch.status===status).length])),[data.batches]);

  const prepare=async()=>{
    if(!supabase||!canPrepare)return;
    const name=`Compensation submission · ${new Date().toLocaleDateString("en-US",{month:"short",day:"numeric",year:"numeric"})}`;
    setBusy("prepare");setError("");
    const{error:rpcError}=await supabase.rpc("prepare_compensation_review_batch",{requested_batch_name:name,requested_period_start:null,requested_period_end:null});
    if(rpcError)setError(rpcError.message);else await load();
    setBusy(null);
  };

  const act=async(batch:Batch,action:"submit"|"approve"|"return"|"accept")=>{
    if(!supabase)return;
    if(action==="submit"&&!canPrepare)return setError("System administrator access is required to submit this review batch.");
    if((action==="approve"||action==="return")&&!canApprove)return setError("Approval permission is required for this action.");
    if(action==="accept"&&!canFinance)return setError("Finance permission is required for this action.");
    const note=comments[batch.id]?.trim()||null;
    if(action==="return"&&!note)return setError("A return reason is required.");
    setBusy(batch.id+action);setError("");
    const call=action==="submit"
      ? supabase.rpc("submit_compensation_review_batch",{target_review_batch_id:batch.id})
      : action==="accept"
        ? supabase.rpc("accept_compensation_review_batch_for_payment",{target_review_batch_id:batch.id,action_comments:note})
        : supabase.rpc("act_on_compensation_review_batch",{target_review_batch_id:batch.id,requested_action:action==="approve"?"approved":"returned",action_comments:note});
    const{error:rpcError}=await call;
    if(rpcError)setError(rpcError.message);else{setComments(current=>({...current,[batch.id]:""}));await load()}
    setBusy(null);
  };

  const startEdit=(item:Item)=>setEditing(current=>({...current,[item.id]:{amount:String(item.proposed_amount),note:item.review_note||"",reason:item.override_reason||""}}));
  const saveItem=async(item:Item,included=item.included)=>{
    if(!supabase||!canPrepare)return;
    const draft=editing[item.id]||{amount:String(item.proposed_amount),note:item.review_note||"",reason:item.override_reason||""};
    const amount=Number(draft.amount);
    if(!Number.isFinite(amount)||amount<0)return setError("Enter a valid proposed amount.");
    const original=Number(item.item_snapshot?.eligible_amount??item.proposed_amount);
    if(amount!==original&&!draft.reason.trim())return setError("An override reason is required when the proposed amount differs from the calculated eligible amount.");
    setBusy(item.id);setError("");
    const{error:rpcError}=await supabase.rpc("update_compensation_review_batch_item",{
      target_batch_item_id:item.id,
      requested_included:included,
      requested_proposed_amount:amount,
      requested_review_note:draft.note.trim()||null,
      requested_override_reason:draft.reason.trim()||null
    });
    if(rpcError)setError(rpcError.message);else{setEditing(current=>{const next={...current};delete next[item.id];return next});await load()}
    setBusy(null);
  };

  return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:"28px",fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}>
    <div style={{maxWidth:1250,margin:"0 auto"}}>
      <nav style={{display:"flex",gap:9,alignItems:"center",marginBottom:18,flexWrap:"wrap"}}>
        <Link href="/" style={{display:"inline-flex",alignItems:"center",gap:6,color:"#31465a",textDecoration:"none",fontWeight:700}}><Home size={16}/>Workspace</Link>
        <span style={{color:"#a0adba"}}>/</span><b>Submissions</b>
        <Link href="/workflow" style={{marginLeft:"auto",color:"#2095f3",fontWeight:700,textDecoration:"none"}}>Workflow configuration</Link>
      </nav>

      <header style={{display:"flex",justifyContent:"space-between",gap:18,alignItems:"flex-start",marginBottom:22,flexWrap:"wrap"}}>
        <div><small style={{fontWeight:800,letterSpacing:1.2,color:"#2095f3"}}>COMPENSATION ADMINISTRATION</small><h1 style={{fontSize:34,margin:"7px 0"}}>Compensation submissions</h1><p style={{margin:0,color:"#647184",maxWidth:820}}>No monthly cutoff. Eligible compensation can be prepared and submitted at any point. Reporting periods organize activity; they never block submission.</p><small style={{display:"block",marginTop:8,color:"#718096"}}>{access?.full_name||access?.email||"Signed-in user"}{isAdmin?" · System Administrator":""}</small></div>
        <div style={{display:"flex",gap:8,flexWrap:"wrap"}}>
          {canPrepare&&<button onClick={prepare} disabled={busy==="prepare"} style={{padding:"10px 14px",background:"#2095f3",color:"white",border:0,borderRadius:9,fontWeight:800,cursor:"pointer"}}>{busy==="prepare"?"Preparing…":"Prepare eligible compensation"}</button>}
          <button onClick={load} disabled={loading} style={{display:"flex",alignItems:"center",gap:7,padding:"10px 13px",background:"white",border:"1px solid #d9e2eb",borderRadius:9,fontWeight:700}}><RefreshCw size={16}/>{loading?"Refreshing…":"Refresh"}</button>
        </div>
      </header>

      <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(170px,1fr))",gap:10,marginBottom:20}}>
        {[["draft","Ready to submit","Sharon"],["submitted","With Namit","Namit"],["approved","With Scott","Scott"],["finance_accepted","Payment pending","Scott"],["closed","Completed","—"]].map(([status,label,owner])=><button key={status} onClick={()=>setActive(active===status?"all":status)} style={{textAlign:"left",background:active===status?"#eaf5ff":"white",border:"1px solid #dfe6ee",borderRadius:12,padding:15,cursor:"pointer"}}><small style={{display:"block",fontWeight:800,color:"#718096"}}>{owner}</small><b style={{display:"block",fontSize:16,margin:"4px 0"}}>{label}</b><strong style={{fontSize:24}}>{counts[status]||0}</strong></button>)}
      </section>

      <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18,marginBottom:18}}>
        <div style={{display:"flex",alignItems:"center",gap:8,flexWrap:"wrap"}}>{["Sharon reviews/submits","Namit approves","Scott accepts","Scott confirms paid"].map((label,index)=><div key={label} style={{display:"flex",alignItems:"center",gap:8}}><span style={{padding:"9px 12px",border:"1px solid #dbe4ee",borderRadius:9,background:index===0?"#eaf5ff":"#f8fafc",fontWeight:700}}>{label}</span>{index<3&&<ChevronRight size={16} color="#8b98a8"/>}</div>)}</div>
        <p style={{margin:"12px 0 0",color:"#647184",fontSize:13}}>Finance acceptance is not payment. A compensation item becomes Paid only when the payroll/payment record confirms the actual payment.</p>
      </section>

      {error&&<div style={{background:"#fff3f3",border:"1px solid #f2caca",borderRadius:10,padding:13,marginBottom:15}}>{error}</div>}

      {loading?<p>Loading submissions…</p>:filtered.length===0?<section style={{background:"white",border:"1px dashed #cbd5df",borderRadius:14,padding:34,textAlign:"center"}}><ShieldCheck size={28}/><h2>No submissions in this queue</h2><p style={{color:"#647184"}}>Eligible compensation can be prepared and submitted whenever it is ready.</p>{canPrepare&&<button onClick={prepare} disabled={busy==="prepare"} style={{padding:"10px 14px",background:"#2095f3",color:"white",border:0,borderRadius:8,fontWeight:800}}>Prepare eligible compensation</button>}</section>:filtered.map(batch=>{
        const stage=stageCopy[batch.status]||{label:batch.status,owner:"—",description:""};
        const allItems=data.items.filter(item=>item.review_batch_id===batch.id);
        const items=allItems.filter(item=>item.included);
        const editable=(batch.status==="draft"||batch.status==="returned")&&canPrepare;
        return <article key={batch.id} style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:20,marginBottom:15}}>
          <div style={{display:"flex",justifyContent:"space-between",gap:14,alignItems:"flex-start",flexWrap:"wrap"}}><div><small style={{fontWeight:800,color:"#2095f3"}}>{stage.label.toUpperCase()} · {stage.owner}</small><h2 style={{margin:"5px 0 3px",fontSize:21}}>{batch.batch_name}</h2><p style={{margin:0,color:"#647184",fontSize:13}}>{stage.description}</p><small style={{display:"block",marginTop:6,color:"#8793a1"}}>Created {dateLabel(batch.created_at)}{batch.submitted_at?` · Submitted ${dateLabel(batch.submitted_at)}`:""}</small></div><div style={{textAlign:"right"}}><b style={{fontSize:23}}>{money(batch.proposed_total)}</b><small style={{display:"block",color:"#718096",marginTop:3}}>{batch.item_count} included items · {batch.employee_count} employees</small></div></div>

          <button onClick={()=>setExpanded(current=>({...current,[batch.id]:!current[batch.id]}))} style={{marginTop:14,display:"inline-flex",gap:7,alignItems:"center",padding:"8px 10px",border:"1px solid #d9e2eb",background:"white",borderRadius:8,fontWeight:700}}><Eye size={15}/>{expanded[batch.id]?"Hide items":"Review items"}</button>

          {expanded[batch.id]&&<div style={{display:"grid",gap:8,marginTop:12}}>{allItems.map(item=>{
            const edit=editing[item.id];
            const original=Number(item.item_snapshot?.eligible_amount??item.proposed_amount);
            return <div key={item.id} style={{background:item.included?"#f8fafc":"#fbfbfb",border:"1px solid #e5ebf1",borderRadius:10,padding:12,opacity:item.included?1:.68}}>
              <div style={{display:"grid",gridTemplateColumns:"minmax(150px,1.1fr) minmax(220px,2fr) auto",gap:12,alignItems:"center"}}><b>{item.employee_name}</b><span style={{fontSize:13,color:"#5f6b7a"}}>{String(item.item_snapshot?.earning_name||"Compensation earning")} · calculated eligible {money(original)}</span><strong>{money(item.proposed_amount)}</strong></div>
              {item.override_reason&&<small style={{display:"block",marginTop:6,color:"#9a6415"}}>Override: {item.override_reason}</small>}
              {item.review_note&&<small style={{display:"block",marginTop:4,color:"#647184"}}>Note: {item.review_note}</small>}
              {editable&&<div style={{marginTop:9}}>{edit?<div style={{display:"grid",gridTemplateColumns:"140px 1fr 1fr auto",gap:8,alignItems:"center"}}><input type="number" step="0.01" value={edit.amount} onChange={e=>setEditing(current=>({...current,[item.id]:{...edit,amount:e.target.value}}))} style={{padding:8,border:"1px solid #ccd6e0",borderRadius:7}}/><input value={edit.note} onChange={e=>setEditing(current=>({...current,[item.id]:{...edit,note:e.target.value}}))} placeholder="Review note" style={{padding:8,border:"1px solid #ccd6e0",borderRadius:7}}/><input value={edit.reason} onChange={e=>setEditing(current=>({...current,[item.id]:{...edit,reason:e.target.value}}))} placeholder="Override reason if amount changes" style={{padding:8,border:"1px solid #ccd6e0",borderRadius:7}}/><div style={{display:"flex",gap:6}}><button onClick={()=>saveItem(item)} disabled={busy===item.id} style={{padding:"8px 10px",border:0,borderRadius:7,background:"#0f8a57",color:"white",fontWeight:800}}>Save</button><button onClick={()=>setEditing(current=>{const next={...current};delete next[item.id];return next})} style={{padding:"8px 10px",border:"1px solid #d5dde6",borderRadius:7,background:"white"}}>Cancel</button></div></div>:<div style={{display:"flex",gap:7}}><button onClick={()=>startEdit(item)} style={{padding:"7px 9px",border:"1px solid #d5dde6",background:"white",borderRadius:7,fontWeight:700}}>Edit amount / note</button><button onClick={()=>{startEdit(item);setTimeout(()=>saveItem(item,!item.included),0)}} disabled={busy===item.id} style={{padding:"7px 9px",border:"1px solid #d5dde6",background:"white",borderRadius:7,fontWeight:700}}>{item.included?<><XCircle size={14}/> Exclude</>:"Re-include"}</button></div>}</div>}
            </div>})}</div>}

          {!expanded[batch.id]&&<div style={{display:"grid",gap:7,marginTop:15}}>{items.slice(0,6).map(item=><div key={item.id} style={{display:"grid",gridTemplateColumns:"1.2fr 1.8fr auto",gap:12,alignItems:"center",background:"#f8fafc",borderRadius:9,padding:"10px 12px"}}><b>{item.employee_name}</b><span style={{fontSize:13,color:"#5f6b7a"}}>{String(item.item_snapshot?.earning_name||"Compensation earning")}{item.override_reason?` · Override: ${item.override_reason}`:""}</span><strong>{money(item.proposed_amount)}</strong></div>)}</div>}
          {!expanded[batch.id]&&items.length>6&&<small style={{display:"block",marginTop:8,color:"#718096"}}>+ {items.length-6} additional included items</small>}

          {batch.return_reason&&<div style={{marginTop:13,padding:11,background:"#fff8e7",borderRadius:9}}><b>Return reason:</b> {batch.return_reason}</div>}

          {batch.status!=="closed"&&batch.status!=="cancelled"&&<div style={{display:"flex",gap:9,alignItems:"center",marginTop:16,flexWrap:"wrap"}}>
            {(batch.status==="submitted"&&canApprove||batch.status==="approved"&&canFinance)&&<input value={comments[batch.id]||""} onChange={e=>setComments(current=>({...current,[batch.id]:e.target.value}))} placeholder={batch.status==="submitted"?"Approval comment or required return reason…":"Finance note…"} style={{flex:"1 1 280px",padding:"10px 11px",border:"1px solid #d6dee8",borderRadius:8}}/>}
            {(batch.status==="draft"||batch.status==="returned")&&canPrepare&&<button onClick={()=>act(batch,"submit")} disabled={busy===batch.id+"submit"} style={{display:"flex",gap:7,alignItems:"center",padding:"10px 13px",border:0,borderRadius:8,background:"#2095f3",color:"white",fontWeight:800}}><Send size={16}/>Submit to Namit</button>}
            {batch.status==="submitted"&&canApprove&&<><button onClick={()=>act(batch,"approve")} disabled={busy===batch.id+"approve"} style={{display:"flex",gap:7,alignItems:"center",padding:"10px 13px",border:0,borderRadius:8,background:"#0f8a57",color:"white",fontWeight:800}}><CheckCircle2 size={16}/>Approve</button><button onClick={()=>act(batch,"return")} disabled={busy===batch.id+"return"} style={{display:"flex",gap:7,alignItems:"center",padding:"10px 13px",border:"1px solid #d5dde6",borderRadius:8,background:"white",fontWeight:800}}><RotateCcw size={16}/>Return</button></>}
            {batch.status==="approved"&&canFinance&&<button onClick={()=>act(batch,"accept")} disabled={busy===batch.id+"accept"} style={{display:"flex",gap:7,alignItems:"center",padding:"10px 13px",border:0,borderRadius:8,background:"#051b34",color:"white",fontWeight:800}}><WalletCards size={16}/>Accept for payment</button>}
            {batch.status==="submitted"&&!canApprove&&<small style={{color:"#718096"}}>Waiting for an authorized approver.</small>}
            {batch.status==="approved"&&!canFinance&&<small style={{color:"#718096"}}>Waiting for Finance acceptance.</small>}
          </div>}
        </article>
      })}
    </div>
  </main>
}
