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
const card={background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18,textDecoration:"none",color:"#051b34",display:"block"} as const;

export default function SettingsPage(){
 const[access,setAccess]=useState<Access|null>(null),[loading,setLoading]=useState(true);
 useEffect(()=>{(async()=>{const{data}=await supabase.rpc("get_current_user_access");setAccess((data||null) as Access|null);setLoading(false)})()},[]);
 const perms=access?.permissions||[],roles=access?.roles||[];
 const admin=roles.includes("system_administrator");
 const has=(p:string)=>admin||perms.includes(p);
 const canMapping=has("settings.manage")||has("settings.hubspot_mapping.view")||has("settings.hubspot_mapping.edit");
 const canManage=has("settings.manage");
 const cards=useMemo(()=>[
  canMapping?{href:"/settings/hubspot-integration",icon:<RefreshCw size={22}/>,title:"HubSpot Integration",text:"Control synchronization, choose which HubSpot objects are brought into the tracker, and review source changes."}:null,
  canMapping?{href:"/settings/hubspot-mapping",icon:<Database size={22}/>,title:"HubSpot Rule Data",text:"Choose which synchronized HubSpot objects, fields, and values plan administrators may use when defining earning and payment conditions."}:null,
  canManage?{href:"/settings/help-content",icon:<CircleHelp size={22}/>,title:"Inline Help",text:"Edit the guidance administrators see while configuring compensation plans without changing application code."}:null,
  canManage?{href:"/users",icon:<ShieldCheck size={22}/>,title:"Users & Access",text:"Manage application users, roles, visibility, and compensation administration access."}:null,
 ].filter(Boolean) as {href:string;icon:React.ReactNode;title:string;text:string}[],[canMapping,canManage]);
 if(loading)return <main style={{padding:28}}>Loading settings…</main>;
 if(!canMapping&&!canManage)return <main style={{padding:28}}><h1>Settings</h1><p>You do not have permission to view configuration settings.</p></main>;
 return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,color:"#051b34"}}><div style={{maxWidth:1180,margin:"0 auto"}}>
  <header style={{marginBottom:22}}><small style={{fontWeight:900,color:"#2095f3",letterSpacing:1}}>CONFIGURATION</small><h1 style={{fontSize:34,margin:"6px 0"}}>Settings</h1><p style={{margin:0,color:"#647184",maxWidth:760}}>Configure the source data and administrative controls that govern how compensation is calculated and managed.</p></header>
  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(300px,1fr))",gap:14}}>{cards.map(c=><Link key={c.href} href={c.href} style={card}><div style={{display:"flex",justifyContent:"space-between",gap:16}}><div><div style={{width:42,height:42,borderRadius:10,background:"#eef7ff",display:"grid",placeItems:"center",color:"#1677c8",marginBottom:12}}>{c.icon}</div><h2 style={{fontSize:19,margin:"0 0 7px"}}>{c.title}</h2><p style={{margin:0,color:"#647184",lineHeight:1.5}}>{c.text}</p></div><ArrowRight size={18} style={{marginTop:4,flex:"0 0 auto"}}/></div></Link>)}</section>
 </div></main>;
}
