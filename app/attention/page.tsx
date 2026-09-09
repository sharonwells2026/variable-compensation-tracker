"use client";

import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,ArrowLeft,ArrowRight,RefreshCw,ShieldAlert,WalletCards,Wrench} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=createClient(supabaseUrl,supabaseKey);
const money=(v?:number)=>new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(v||0));

type Data={metrics?:Record<string,number>;missing_plan_assignments?:any[];waiting_eligibility?:any[];returned_or_correction?:any[];ready_for_payroll?:any[];open_corrections?:any[]};

export default function AttentionPage(){
 const[data,setData]=useState<Data>({}),[loading,setLoading]=useState(true),[error,setError]=useState("");
 const load=async()=>{setLoading(true);setError("");const{data:d,error:e}=await supabase.rpc("get_comp_attention_workspace_data");if(e)setError(e.message);else setData((d||{}) as Data);setLoading(false)};
 useEffect(()=>{void load()},[]);
 const m=data.metrics||{};
 const cards=[
  {label:"Missing plan assignment",value:m.missing_plan_assignment||0,copy:"Active employees without a current compensation plan",href:"/plans",icon:<ShieldAlert size={18}/>},
  {label:"Waiting on eligibility",value:m.waiting_eligibility||0,copy:"Earned items not yet eligible for payment",href:"/credits",icon:<AlertTriangle size={18}/>},
  {label:"Returned / correction",value:m.returned_or_correction||0,copy:"Items requiring correction or workflow restart",href:"/corrections",icon:<Wrench size={18}/>},
  {label:"Ready for payroll",value:m.ready_for_payroll||0,copy:"Approved earnings waiting on Finance",href:"/payments",icon:<WalletCards size={18}/>},
 ];
 return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:"clamp(16px,3vw,28px)",fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{maxWidth:1200,margin:"0 auto"}}>
  <header style={{display:"flex",justifyContent:"space-between",gap:16,alignItems:"flex-start",flexWrap:"wrap",marginBottom:20}}><div><Link href="/manage" style={{display:"inline-flex",gap:6,alignItems:"center",textDecoration:"none",color:"#647184",fontWeight:700,fontSize:13}}><ArrowLeft size={15}/>Control Center</Link><small style={{display:"block",fontWeight:800,letterSpacing:1.1,color:"#2095f3",marginTop:12}}>OPERATIONS QUEUE</small><h1 style={{fontSize:"clamp(28px,5vw,36px)",margin:"6px 0"}}>Needs Attention</h1><p style={{margin:0,color:"#647184",maxWidth:800,lineHeight:1.5}}>One operational queue for compensation records that are blocked, incomplete, returned, or waiting on the next owner.</p></div><button onClick={load} style={{display:"inline-flex",alignItems:"center",gap:6,padding:"9px 12px",border:"1px solid #d6e0e9",background:"white",borderRadius:8,fontWeight:800}}><RefreshCw size={15}/>Refresh</button></header>
  {error&&<div style={{padding:13,borderRadius:10,background:"#fff5f5",border:"1px solid #fed7d7",marginBottom:14}}><b>Unable to load attention queue.</b> {error}</div>}
  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(220px,1fr))",gap:12,marginBottom:18}}>{cards.map(c=><Link key={c.label} href={c.href} style={{textDecoration:"none",color:"inherit",background:"white",border:"1px solid #dfe6ee",borderRadius:13,padding:16,display:"block"}}><div style={{display:"flex",justifyContent:"space-between",gap:10}}><div>{c.icon}<div style={{fontSize:28,fontWeight:900,marginTop:8}}>{loading?"—":c.value}</div><div style={{fontWeight:850,marginTop:3}}>{c.label}</div><div style={{fontSize:12,color:"#718096",marginTop:3,lineHeight:1.4}}>{c.copy}</div></div><ArrowRight size={17}/></div></Link>)}</section>
  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(320px,1fr))",gap:14}}>
   <div style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,overflow:"hidden"}}><div style={{padding:16,borderBottom:"1px solid #edf1f5"}}><h2 style={{margin:0,fontSize:18}}>Plan setup required</h2></div>{(data.missing_plan_assignments||[]).length===0?<div style={{padding:18,color:"#718096"}}>No active employees are missing a current plan.</div>:(data.missing_plan_assignments||[]).map(x=><div key={x.employee_id} style={{padding:14,borderBottom:"1px solid #edf1f5"}}><b>{x.employee_name}</b><div style={{fontSize:12,color:"#718096",marginTop:2}}>{x.email}</div><Link href="/plans" style={{fontSize:12,fontWeight:800,color:"#0c6fb8",textDecoration:"none"}}>Resolve plan assignment →</Link></div>)}</div>
   <div style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,overflow:"hidden"}}><div style={{padding:16,borderBottom:"1px solid #edf1f5"}}><h2 style={{margin:0,fontSize:18}}>Waiting on eligibility</h2></div>{(data.waiting_eligibility||[]).length===0?<div style={{padding:18,color:"#718096"}}>Nothing is waiting on an eligibility condition.</div>:(data.waiting_eligibility||[]).slice(0,8).map(x=><div key={x.earning_id} style={{padding:14,borderBottom:"1px solid #edf1f5"}}><b>{x.employee_name} · {x.earning_name}</b><div style={{fontSize:13,marginTop:3}}>{money(x.earned_amount)}</div><div style={{fontSize:12,color:"#718096",marginTop:3,lineHeight:1.4}}>{x.condition||"Eligibility condition pending"}</div></div>)}</div>
   <div style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,overflow:"hidden"}}><div style={{padding:16,borderBottom:"1px solid #edf1f5"}}><h2 style={{margin:0,fontSize:18}}>Ready for Finance</h2></div>{(data.ready_for_payroll||[]).length===0?<div style={{padding:18,color:"#718096"}}>Nothing is waiting for payroll.</div>:(data.ready_for_payroll||[]).map(x=><div key={x.earning_id} style={{padding:14,borderBottom:"1px solid #edf1f5"}}><b>{x.employee_name} · {x.earning_name}</b><div style={{fontSize:13,marginTop:3}}>{money(x.approved_amount)}</div><div style={{fontSize:12,color:"#718096",marginTop:3}}>{x.expected_pay_period_label||"Payroll period not assigned"}</div><Link href="/payments" style={{fontSize:12,fontWeight:800,color:"#0c6fb8",textDecoration:"none"}}>Open Payments →</Link></div>)}</div>
  </section>
  <section style={{marginTop:18,padding:14,borderRadius:10,background:"#eef7ff",border:"1px solid #cfe8fb",fontSize:13,lineHeight:1.5}}><b>Queue rule:</b> normal lifecycle states are separated from true blockers. Waiting on a documented eligibility condition is visible here for awareness, but only setup gaps, returns, corrections, holds, or owner actions should be treated as exceptions.</section>
 </div></main>;
}
