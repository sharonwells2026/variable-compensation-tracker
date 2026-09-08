"use client";

import Link from "next/link";
import {BadgeCheck,ChartNoAxesCombined,FileText,History,Users} from "lucide-react";

const cards=[
 {href:"/submissions",title:"Approvals",body:"Review compensation waiting on executive approval and return or reject when needed.",icon:BadgeCheck},
 {href:"/earnings",title:"Compensation overview",body:"Review earned, eligible, approved, unpaid, and paid compensation across your authorized scope.",icon:ChartNoAxesCombined},
 {href:"/employees",title:"Employees",body:"Review employee compensation participation, plans, managers, and workflow readiness.",icon:Users},
 {href:"/plans",title:"Plans",body:"Review compensation plan versions and rules available to your role.",icon:FileText},
 {href:"/audit",title:"Audit history",body:"Review compensation and approval history within your authorized scope.",icon:History},
];

export default function ExecutiveWorkspace(){return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:30,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{maxWidth:1180,margin:"0 auto"}}><header style={{marginBottom:24}}><small style={{fontWeight:900,letterSpacing:1.2,color:"#2095f3"}}>EXECUTIVE COMPENSATION</small><h1 style={{fontSize:38,margin:"8px 0"}}>Executive workspace</h1><p style={{margin:0,color:"#647184",maxWidth:780}}>A concise approval workflow with broader compensation visibility. Approval actions stay simple while oversight, history, employees, and plans remain available according to effective permissions.</p></header><section style={{display:"grid",gridTemplateColumns:"repeat(2,minmax(280px,1fr))",gap:14}}>{cards.map(({href,title,body,icon:Icon})=><Link key={href} href={href} style={{textDecoration:"none",color:"inherit",background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:20,display:"block"}}><Icon size={24} color="#2095f3"/><h2 style={{fontSize:20,margin:"10px 0 5px"}}>{title}</h2><p style={{margin:0,color:"#647184",lineHeight:1.5}}>{body}</p></Link>)}</section></div></main>}
