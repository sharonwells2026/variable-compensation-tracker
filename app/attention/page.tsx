"use client";

import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,ArrowRight,RefreshCw,ShieldAlert,WalletCards,Wrench} from "lucide-react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");
const money=(v?:number)=>new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(v||0));
type Data={metrics?:Record<string,number>;missing_plan_assignments?:any[];waiting_eligibility?:any[];returned_or_correction?:any[];ready_for_payroll?:any[];open_corrections?:any[]};

export default function AttentionPage(){
 const[data,setData]=useState<Data>({}),[loading,setLoading]=useState(true),[error,setError]=useState("");
 const load=async()=>{setLoading(true);setError("");const{data:d,error:e}=await supabase.rpc("get_comp_attention_workspace_data");if(e)setError("We couldn't load the attention queue. Try again in a moment.");else setData((d||{}) as Data);setLoading(false)};
 useEffect(()=>{void load()},[]);
 const m=data.metrics||{};
 const cards=[
  {label:"Missing plan assignment",value:m.missing_plan_assignment||0,copy:"Active employees without a current compensation plan",href:"/plans",icon:<ShieldAlert size={17}/>,tone:"warn"},
  {label:"Waiting on eligibility",value:m.waiting_eligibility||0,copy:"Earned items waiting on a documented payment condition",href:"/credits",icon:<AlertTriangle size={17}/>,tone:"info"},
  {label:"Returned / correction",value:m.returned_or_correction||0,copy:"Items requiring correction or workflow restart",href:"/corrections",icon:<Wrench size={17}/>,tone:"warn"},
  {label:"Ready for payroll",value:m.ready_for_payroll||0,copy:"Approved earnings waiting on Finance",href:"/payments",icon:<WalletCards size={17}/>,tone:"ok"},
 ];
 const panel=(title:string,rows:any[],empty:string,render:(x:any)=>React.ReactNode)=><section className="eng-panel"><div className="eng-panel__head"><div><h2 style={{margin:0,fontSize:15}}>{title}</h2></div></div>{rows.length===0?<div className="eng-state eng-state--inline"><strong>{empty}</strong></div>:<div>{rows.map(render)}</div>}</section>;
 return <main className="eng-page"><div className="eng-page__shell">
  <nav className="eng-crumbs"><Link href="/manage">Control Center</Link><span className="eng-crumbs__sep">/</span><span className="eng-crumbs__here">Needs Attention</span></nav>
  <header className="eng-head"><div className="eng-head__main"><span className="eng-head__eyebrow">OPERATIONS QUEUE</span><h1>Needs Attention</h1><p>Focus on compensation records that are blocked, incomplete, returned, or waiting on the next owner.</p></div><div className="eng-head__actions"><button className="eng-button eng-button--secondary" onClick={load} disabled={loading}><RefreshCw size={15}/>{loading?"Refreshing…":"Refresh"}</button></div></header>
  {error&&<div className="eng-msg eng-msg--bad"><AlertTriangle size={16}/><div className="eng-msg__body"><b>Unable to load the queue</b>{error}</div></div>}
  <section className="eng-tiles">{cards.map(c=><Link key={c.label} href={c.href} className={`eng-tile ${c.value&&c.tone==="warn"?"eng-tile--warn":""}`} style={{textDecoration:"none",color:"inherit"}}><div style={{display:"flex",justifyContent:"space-between",alignItems:"center"}}><span style={{color:c.value?"var(--eng-orange)":"var(--eng-blue)"}}>{c.icon}</span><ArrowRight size={15}/></div><span className="eng-tile__v">{loading?"—":c.value}</span><strong style={{display:"block",fontSize:13,marginTop:3}}>{c.label}</strong><span className="eng-tile__sub">{c.copy}</span></Link>)}</section>
  <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(320px,1fr))",gap:14}}>
   {panel("Plan setup required",data.missing_plan_assignments||[],"No active employees are missing a current plan.",x=><div key={x.employee_id} className="eng-panel__body" style={{borderBottom:"1px solid var(--eng-border-soft)"}}><b>{x.employee_name}</b><div style={{fontSize:12,color:"var(--eng-ink-meta)",marginTop:2}}>{x.email}</div><Link href="/plans" style={{fontSize:12,fontWeight:700,color:"var(--eng-blue-strong)",textDecoration:"none"}}>Resolve plan assignment →</Link></div>)}
   {panel("Waiting on eligibility",(data.waiting_eligibility||[]).slice(0,8),"Nothing is waiting on an eligibility condition.",x=><div key={x.earning_id} className="eng-panel__body" style={{borderBottom:"1px solid var(--eng-border-soft)"}}><b>{x.employee_name} · {x.earning_name}</b><div className="eng-num" style={{fontSize:13,marginTop:3}}>{money(x.earned_amount)}</div><div style={{fontSize:12,color:"var(--eng-ink-meta)",marginTop:3}}>{x.condition||"Eligibility condition pending"}</div></div>)}
   {panel("Ready for Finance",data.ready_for_payroll||[],"Nothing is waiting for payroll.",x=><div key={x.earning_id} className="eng-panel__body" style={{borderBottom:"1px solid var(--eng-border-soft)"}}><b>{x.employee_name} · {x.earning_name}</b><div className="eng-num" style={{fontSize:13,marginTop:3}}>{money(x.approved_amount)}</div><div style={{fontSize:12,color:"var(--eng-ink-meta)",marginTop:3}}>{x.expected_pay_period_label||"Payroll period not assigned"}</div><Link href="/payments" style={{fontSize:12,fontWeight:700,color:"var(--eng-blue-strong)",textDecoration:"none"}}>Open Payments →</Link></div>)}
  </div>
  <div className="eng-msg eng-msg--info" style={{marginTop:18}}><div className="eng-msg__body"><b>How to read this queue</b>Normal lifecycle states are separated from true blockers. Waiting on a documented eligibility condition is visible for awareness, while setup gaps, returns, corrections, holds, or owner actions are the real exceptions.</div></div>
 </div></main>;
}