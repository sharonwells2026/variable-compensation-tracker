"use client";

import Link from "next/link";
import {ArrowLeft,Database,GitBranch,ShieldCheck,AlertTriangle,History,Users} from "lucide-react";

const cards=[
 {icon:<Database/>,title:"Source transactions",copy:"The originating CRM or operational transaction. Source facts remain separate from compensation interpretation."},
 {icon:<Users/>,title:"Compensation credits",copy:"Who receives compensation credit, for which role or component, at what percentage or credited basis, and why."},
 {icon:<GitBranch/>,title:"Generated earnings",copy:"Plan rules turn valid credits into employee earnings while preserving the transaction and credit lineage."}
];
const controls=[
 ["Default attribution","Deal Owner receives 100% of applicable sales credit unless a configured rule says otherwise."],
 ["Multiple components","One transaction may generate multiple earnings without implying that employee credit was split."],
 ["True split credit","A split exists only when the same component or compensation basis is shared across people."],
 ["Historical snapshot","Owner changes after the earning event never silently move previously established compensation credit."],
 ["Before approval","Authorized administrators may reassign credit with a required reason, audit event, and recalculation."],
 ["After approval","Corrections use a controlled return, reopen, or adjustment workflow rather than silent mutation."],
 ["After Paid","Paid history is immutable. Corrections create an auditable reversal/adjustment and replacement."],
];
const exceptions=["No attributable owner","Inactive employee","No active plan/component","Multiple conflicting owners","Invalid credit split","Ownership changed since snapshot","Missing eligibility source data"];

export default function CreditsPage(){return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{maxWidth:1200,margin:"0 auto"}}>
 <header style={{marginBottom:24}}><Link href="/manage" style={{display:"inline-flex",gap:6,alignItems:"center",textDecoration:"none",color:"#647184",fontWeight:700,fontSize:13}}><ArrowLeft size={15}/>Control Center</Link><small style={{display:"block",fontWeight:800,letterSpacing:1.1,color:"#2095f3",marginTop:12}}>COMPENSATION ADMINISTRATION</small><h1 style={{fontSize:34,margin:"6px 0"}}>Earnings & Credits</h1><p style={{margin:0,color:"#647184",maxWidth:850,lineHeight:1.5}}>Trace every compensation obligation from the source transaction to employee credit to the generated earning. Attribution, calculation, approval, and payment remain distinct.</p></header>
 <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(250px,1fr))",gap:12,marginBottom:20}}>{cards.map((c,i)=><div key={c.title} style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18}}><div style={{display:"flex",justifyContent:"space-between"}}><span style={{width:42,height:42,borderRadius:10,display:"grid",placeItems:"center",background:"#eaf5ff",color:"#2095f3"}}>{c.icon}</span><b style={{color:"#9aabb9"}}>0{i+1}</b></div><h2 style={{fontSize:18,margin:"13px 0 6px"}}>{c.title}</h2><p style={{margin:0,color:"#647184",lineHeight:1.45}}>{c.copy}</p></div>)}</section>
 <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:20,marginBottom:18}}><div style={{display:"flex",gap:9,alignItems:"center"}}><ShieldCheck color="#2095f3"/><h2 style={{margin:0}}>Attribution controls</h2></div><div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(330px,1fr))",gap:0,marginTop:12}}>{controls.map(([name,copy])=><div key={name} style={{padding:"13px 14px 13px 0",borderBottom:"1px solid #edf1f5"}}><b>{name}</b><p style={{margin:"4px 0 0",color:"#647184",lineHeight:1.45}}>{copy}</p></div>)}</div></section>
 <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(320px,1fr))",gap:14}}><div style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:20}}><div style={{display:"flex",gap:9,alignItems:"center"}}><AlertTriangle color="#b7791f"/><h2 style={{margin:0}}>Attribution exceptions</h2></div><p style={{color:"#647184"}}>These conditions should stop automatic compensation processing and require resolution rather than a guess.</p>{exceptions.map(x=><div key={x} style={{padding:"8px 0",borderBottom:"1px solid #edf1f5",fontWeight:700}}>{x}</div>)}</div><div style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:20}}><div style={{display:"flex",gap:9,alignItems:"center"}}><History color="#2095f3"/><h2 style={{margin:0}}>Required credit record</h2></div><p style={{color:"#647184"}}>Every compensation credit should retain enough information to reproduce why an employee received the earning.</p>{["Employee","Credit role / type","Credit percentage or credited basis","Source and effective date","Plan and component","Automatic or manual source","Assigned by and assigned at","Manual assignment reason, when applicable"].map(x=><div key={x} style={{padding:"8px 0",borderBottom:"1px solid #edf1f5"}}>{x}</div>)}</div></section>
 <section style={{marginTop:18,padding:16,borderRadius:12,background:"#eef7ff",border:"1px solid #cfe8fb"}}><b>Build state</b><p style={{margin:"5px 0 0",color:"#42566a"}}>This workspace establishes the operating model without inventing attribution data. The next backend step is to expose source transaction → credit → earning lineage from the existing credit and earning tables, then add controlled reassignment actions with audit history.</p></section>
 </div></main>}
