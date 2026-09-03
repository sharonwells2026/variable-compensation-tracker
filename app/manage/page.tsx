"use client";

import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,BarChart3,CheckCircle2,ClipboardCheck,History,RefreshCw,Settings,ShieldCheck,Users,WalletCards} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type Access={full_name?:string;email?:string;roles:string[];permissions:string[]};
type Summary={counts:Record<string,number>;amounts:Record<string,number>};
type ReviewBatch={status:string;proposed_total:number;};
type ReviewPayload={batches:ReviewBatch[]};
type EarningsSummary={summary:{current_earnings:number;payment_exceptions:number;awaiting_approval:number}};
function money(value:number){return new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(value||0))}

export default function ManagePage(){
  const[access,setAccess]=useState<Access|null>(null);
  const[summary,setSummary]=useState<Summary|null>(null);
  const[reviews,setReviews]=useState<ReviewPayload>({batches:[]});
  const[earnings,setEarnings]=useState<EarningsSummary|null>(null);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState("");
  const load=async()=>{
    if(!supabase){setError("Database connection unavailable");setLoading(false);return}
    setLoading(true);setError("");
    const[a,b,c,d]=await Promise.all([supabase.rpc("get_current_user_access"),supabase.rpc("get_payout_readiness_summary"),supabase.rpc("get_compensation_review_batches"),supabase.rpc("get_admin_earnings_data")]);
    if(a.error)setError(a.error.message);else setAccess(a.data as Access);
    if(b.error)setError(current=>current||b.error.message);else setSummary(b.data as Summary);
    if(c.error)setError(current=>current||c.error.message);else setReviews((c.data||{batches:[]}) as ReviewPayload);
    if(d.error)setError(current=>current||d.error.message);else setEarnings(d.data as EarningsSummary);
    setLoading(false);
  };
  useEffect(()=>{load()},[]);

  const isAdmin=Boolean(access?.roles?.includes("system_administrator"));
  const withNamit=reviews.batches.filter(x=>x.status==="submitted");
  const withScott=reviews.batches.filter(x=>x.status==="approved");
  const paymentPending=reviews.batches.filter(x=>x.status==="finance_accepted");

  const cards=[
    {href:"/earnings",icon:<BarChart3/>,title:"Earnings",copy:"Authoritative ledger for earned, eligible, approved, and paid compensation across employees.",metric:`${earnings?.summary?.current_earnings||0} current earnings`},
    {href:"/attention",icon:<AlertTriangle/>,title:"Needs Attention",copy:"Human-action queue for holds, mismatches, returned approvals, reconciliation issues, and other exceptions.",metric:`${earnings?.summary?.payment_exceptions||0} payment exceptions · ${earnings?.summary?.awaiting_approval||0} awaiting approval`},
    {href:"/submissions",icon:<ClipboardCheck/>,title:"Submissions",copy:"Review eligible compensation, submit whenever ready, and manage Namit/Scott handoffs.",metric:`${withNamit.length} with Namit · ${withScott.length} with Scott`},
    {href:"/payments",icon:<WalletCards/>,title:"Payments",copy:"Track Finance acceptance, payroll readiness, scheduled pay runs, and confirmed payments.",metric:`${summary?.counts?.ready_for_payroll||0} ready · ${money(summary?.amounts?.ready_for_payroll||0)}`},
    {href:"/workflow",icon:<ShieldCheck/>,title:"Workflow",copy:"Review effective approval chains and Finance handoff configuration without hardcoding people into product logic.",metric:"Sharon admin · Namit approval · Scott Finance"},
  ];

  return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{maxWidth:1250,margin:"0 auto"}}>
    <header style={{display:"flex",justifyContent:"space-between",gap:18,alignItems:"flex-start",marginBottom:24,flexWrap:"wrap"}}><div><small style={{fontWeight:800,letterSpacing:1.2,color:"#2095f3"}}>ENGAGIFII COMPENSATION</small><h1 style={{fontSize:36,margin:"7px 0"}}>Management workspace</h1><p style={{margin:0,color:"#647184",maxWidth:820}}>One operating model for compensation review, approval, Finance acceptance, payroll, and audit. Eligible compensation can be submitted at any point in the month.</p><small style={{display:"block",marginTop:8,color:"#718096"}}>{access?.full_name||access?.email||"Signed-in user"}{isAdmin?" · System Administrator":""}</small></div><button onClick={load} disabled={loading} style={{display:"flex",alignItems:"center",gap:7,padding:"10px 13px",background:"white",border:"1px solid #d9e2eb",borderRadius:9,fontWeight:700}}><RefreshCw size={16}/>{loading?"Refreshing…":"Refresh"}</button></header>

    {error&&<div style={{background:"#fff3f3",border:"1px solid #f2caca",borderRadius:10,padding:13,marginBottom:15}}>{error}</div>}

    <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(190px,1fr))",gap:10,marginBottom:22}}>{[
      ["Eligible",summary?.counts?.eligible||0,summary?.amounts?.eligible||0],
      ["With Namit",withNamit.length,withNamit.reduce((a,b)=>a+Number(b.proposed_total||0),0)],
      ["With Scott",withScott.length,withScott.reduce((a,b)=>a+Number(b.proposed_total||0),0)],
      ["Payment pending",paymentPending.length,paymentPending.reduce((a,b)=>a+Number(b.proposed_total||0),0)],
      ["Paid",summary?.counts?.paid||0,summary?.amounts?.paid||0]
    ].map(([label,count,amount])=><div key={String(label)} style={{background:"white",border:"1px solid #dfe6ee",borderRadius:12,padding:15}}><small style={{fontWeight:800,color:"#718096"}}>{label}</small><b style={{display:"block",fontSize:25,margin:"5px 0"}}>{loading?"—":String(count)}</b><strong>{loading?"—":money(Number(amount))}</strong></div>)}</section>

    <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(280px,1fr))",gap:14,marginBottom:22}}>{cards.map(card=><Link href={card.href} key={card.href} style={{display:"block",background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:20,textDecoration:"none",color:"inherit"}}><div style={{display:"flex",justifyContent:"space-between",gap:12}}><span style={{width:42,height:42,borderRadius:10,display:"grid",placeItems:"center",background:"#eaf5ff",color:"#2095f3"}}>{card.icon}</span><CheckCircle2 size={18} color="#9aabb9"/></div><h2 style={{margin:"14px 0 6px"}}>{card.title}</h2><p style={{color:"#647184",lineHeight:1.45,minHeight:58}}>{card.copy}</p><b style={{fontSize:13,color:"#31465a"}}>{card.metric}</b></Link>)}</section>

    <section style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:14,marginBottom:22}}><div style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18}}><h2 style={{marginTop:0}}>Canonical workflow</h2>{["Sharon reviews and submits eligible compensation whenever it is ready.","Namit approves or returns the frozen submission snapshot.","Scott accepts the approved obligation for payment.","Payroll execution confirms the actual payment; acceptance alone is never Paid."].map((x,i)=><div key={x} style={{display:"flex",gap:10,margin:"11px 0"}}><b style={{width:25,height:25,borderRadius:20,display:"grid",placeItems:"center",background:"#eaf5ff",color:"#2095f3",flex:"0 0 auto"}}>{i+1}</b><span>{x}</span></div>)}</div><div style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18}}><h2 style={{marginTop:0}}>System controls</h2><div style={{display:"grid",gap:9}}><div><Users size={17}/> <b>System Admin</b><p style={{margin:"3px 0",color:"#647184"}}>Sharon retains unrestricted administrative authority, with overrides recorded in audit history.</p></div><div><History size={17}/> <b>Historical integrity</b><p style={{margin:"3px 0",color:"#647184"}}>Paid records are not silently rewritten; corrections become traceable adjustments.</p></div><div><Settings size={17}/> <b>Configuration over hardcoding</b><p style={{margin:"3px 0",color:"#647184"}}>Approval and Finance roles remain configurable for future personnel changes.</p></div></div></div></section>

    <section style={{background:"#fff8e7",border:"1px solid #ead8a5",borderRadius:12,padding:14,display:"flex",gap:10,alignItems:"flex-start"}}><AlertTriangle size={19}/><div><b>Prototype cleanup in progress</b><p style={{margin:"3px 0 0",color:"#66593b"}}>The original single-page prototype still exists at the root URL while its remaining employee, plan, reconciliation, HubSpot, and settings features are moved into this consolidated route structure. Earnings, Needs Attention, Submissions, Payments, and Workflow are now authoritative management screens.</p></div></section>
  </div></main>
}
