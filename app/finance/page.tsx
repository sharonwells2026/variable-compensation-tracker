"use client";

import Link from "next/link";
import {BadgeDollarSign,FileClock,History,Scale,ShieldCheck} from "lucide-react";

const cards=[
 {href:"/payments",title:"Payments",body:"Accept approved compensation, assign payroll periods, and record actual payment.",icon:BadgeDollarSign},
 {href:"/reconciliation",title:"Reconciliation",body:"Compare approved compensation, payroll readiness, and actual payments.",icon:Scale},
 {href:"/earnings",title:"Compensation ledger",body:"Review compensation source records and lifecycle status.",icon:FileClock},
 {href:"/audit",title:"Audit history",body:"Review payment and compensation changes within your authorized scope.",icon:History},
];

export default function FinanceWorkspace(){return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:30,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{maxWidth:1180,margin:"0 auto"}}><header style={{marginBottom:24}}><small style={{fontWeight:900,letterSpacing:1.2,color:"#2095f3"}}>FINANCE & PAYROLL</small><h1 style={{fontSize:38,margin:"8px 0"}}>Finance workspace</h1><p style={{margin:0,color:"#647184",maxWidth:760}}>A focused workspace for Finance oversight. Your primary workflow is accepting approved compensation into a pay period, then returning later to record the actual payment.</p></header><section style={{background:"#eef7ff",border:"1px solid #cfe5f7",borderRadius:14,padding:16,marginBottom:20,display:"flex",gap:10}}><ShieldCheck size={20}/><div><b>Role-based access</b><p style={{margin:"3px 0 0",color:"#526579"}}>Only Finance permissions assigned to your role or user are available. Additional management visibility can be granted independently.</p></div></section><section style={{display:"grid",gridTemplateColumns:"repeat(2,minmax(280px,1fr))",gap:14}}>{cards.map(({href,title,body,icon:Icon})=><Link key={href} href={href} style={{textDecoration:"none",color:"inherit",background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:20,display:"block"}}><Icon size={24} color="#2095f3"/><h2 style={{fontSize:20,margin:"10px 0 5px"}}>{title}</h2><p style={{margin:0,color:"#647184",lineHeight:1.5}}>{body}</p></Link>)}</section></div></main>}
