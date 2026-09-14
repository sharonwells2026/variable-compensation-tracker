"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {ArrowRight,CircleHelp,Database,RefreshCw,ShieldCheck} from "lucide-react";

const supabase=createClient(
 process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);
type Access={roles?:string[];permissions?:string[]};

export default function SettingsPage(){
 const[access,setAccess]=useState<Access|null>(null),[loading,setLoading]=useState(true);
 useEffect(()=>{(async()=>{const{data}=await supabase.rpc("get_current_user_access");setAccess((data||null) as Access|null);setLoading(false)})()},[]);
 const perms=access?.permissions||[],roles=access?.roles||[];
 const admin=roles.includes("system_administrator");
 const has=(p:string)=>admin||perms.includes(p);
 const canMapping=has("settings.manage")||has("settings.hubspot_mapping.view")||has("settings.hubspot_mapping.edit");
 const canManage=has("settings.manage");
 const cards=useMemo(()=>[
  canMapping?{href:"/settings/hubspot-integration",icon:<RefreshCw size={21}/>,eyebrow:"DATA FLOW",title:"HubSpot Integration",text:"Manage synchronization and confirm that the HubSpot objects compensation depends on are flowing into RevOS."}:null,
  canMapping?{href:"/settings/hubspot-mapping",icon:<Database size={21}/>,eyebrow:"RULE INPUTS",title:"HubSpot Rule Data",text:"Choose which synchronized HubSpot objects, fields, and values plan administrators may use in earning and payment conditions."}:null,
  canManage?{href:"/settings/help-content",icon:<CircleHelp size={21}/>,eyebrow:"ADMIN GUIDANCE",title:"Inline Help",text:"Edit the guidance administrators see while configuring plans without changing application code."}:null,
  canManage?{href:"/users",icon:<ShieldCheck size={21}/>,eyebrow:"ACCESS CONTROL",title:"Users & Access",text:"Manage roles, effective permissions, visibility, and compensation administration access."}:null,
 ].filter(Boolean) as {href:string;icon:React.ReactNode;eyebrow:string;title:string;text:string}[],[canMapping,canManage]);
 if(loading)return <main className="eng-page"><div className="eng-page__shell"><div className="eng-card"><div className="eng-card__body">Loading settings…</div></div></div></main>;
 if(!canMapping&&!canManage)return <main className="eng-page"><div className="eng-page__shell"><header className="eng-page-header"><div className="eng-page-header__main"><span className="eng-page-header__eyebrow">CONFIGURATION</span><h1>Settings</h1></div></header><div className="eng-callout eng-callout--warn"><div className="eng-callout__body"><b>Access restricted</b>You do not have permission to view configuration settings.</div></div></div></main>;
 return <main className="eng-page"><div className="eng-page__shell">
  <nav className="eng-breadcrumb"><Link href="/manage">Control Center</Link><span className="eng-breadcrumb__sep">/</span><span className="eng-breadcrumb__current">Settings</span></nav>
  <header className="eng-page-header"><div className="eng-page-header__main"><span className="eng-page-header__eyebrow">CONFIGURATION</span><h1>Settings</h1><p className="eng-page-header__lede">Configure source data, rule inputs, administrator guidance, and access controls that govern how compensation is calculated and managed.</p></div></header>
  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(300px,1fr))",gap:14}}>{cards.map(c=><Link key={c.href} href={c.href} className="eng-card" style={{textDecoration:"none",color:"inherit",display:"block"}}><div className="eng-card__body" style={{height:"100%",boxSizing:"border-box"}}><div style={{display:"flex",justifyContent:"space-between",gap:16,height:"100%"}}><div><div style={{width:40,height:40,borderRadius:10,background:"var(--eng-blue-tint)",display:"grid",placeItems:"center",color:"var(--eng-blue-strong)",marginBottom:12}}>{c.icon}</div><small className="eng-page-header__eyebrow">{c.eyebrow}</small><h2 style={{fontSize:18,margin:"0 0 7px"}}>{c.title}</h2><p style={{margin:0,color:"var(--eng-ink-meta)",lineHeight:1.5}}>{c.text}</p></div><ArrowRight size={18} style={{marginTop:4,flex:"0 0 auto",color:"var(--eng-ink-faint)"}}/></div></div></Link>)}</section>
 </div></main>;
}
