"use client";

import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,History,RefreshCw} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type Event={event_id:string;event_type:string;event_reason:string|null;occurred_at:string;actor_name:string|null;target_name:string|null;employee_name:string|null;previous_state:Record<string,unknown>|null;new_state:Record<string,unknown>|null};
type Payload={events:Event[]};
function label(v:string){return v.replaceAll("_"," ").replace(/\b\w/g,x=>x.toUpperCase())}

export default function AuditPage(){
 const[data,setData]=useState<Payload>({events:[]}),[loading,setLoading]=useState(true),[error,setError]=useState("");
 const load=async()=>{if(!supabase){setError("Database connection unavailable");setLoading(false);return}setLoading(true);setError("");const{data:result,error:rpcError}=await supabase.rpc("get_admin_audit_activity",{selected_limit:200});if(rpcError)setError(rpcError.message);else setData((result||{events:[]}) as Payload);setLoading(false)};useEffect(()=>{load()},[]);
 return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{maxWidth:1320,margin:"0 auto"}}><header style={{display:"flex",justifyContent:"space-between",gap:18,alignItems:"flex-start",marginBottom:22,flexWrap:"wrap"}}><div><Link href="/manage" style={{display:"inline-flex",gap:6,alignItems:"center",textDecoration:"none",color:"#647184",fontWeight:700,fontSize:13}}><ArrowLeft size={15}/>Management</Link><small style={{display:"block",fontWeight:800,letterSpacing:1.1,color:"#2095f3",marginTop:12}}>AUDIT & HISTORY</small><h1 style={{fontSize:34,margin:"6px 0"}}>Activity log</h1><p style={{margin:0,color:"#647184"}}>Immutable operational history for compensation, approvals, access, workflow, reconciliation, and payment actions.</p></div><button onClick={load} disabled={loading} style={{display:"flex",gap:7,alignItems:"center",padding:"10px 13px",background:"white",border:"1px solid #d9e2eb",borderRadius:9,fontWeight:700}}><RefreshCw size={16}/>{loading?"Refreshing…":"Refresh"}</button></header>{error&&<div style={{background:"#fff3f3",border:"1px solid #f2caca",borderRadius:10,padding:13,marginBottom:15}}>{error}</div>}
 <section style={{background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18}}><div style={{display:"flex",justifyContent:"space-between",gap:10,marginBottom:12}}><div><h2 style={{margin:"0 0 4px"}}>Recent events</h2><small style={{color:"#718096"}}>{data.events.length} events returned</small></div><History size={20} color="#2095f3"/></div>{data.events.length===0?<p style={{color:"#647184"}}>No audit events returned.</p>:<div style={{display:"grid",gap:8}}>{data.events.map(e=><article key={e.event_id} style={{display:"grid",gridTemplateColumns:"170px 1.15fr 1fr 1.8fr",gap:12,alignItems:"start",padding:"11px 0",borderBottom:"1px solid #edf1f5",fontSize:13}}><span>{new Date(e.occurred_at).toLocaleString()}</span><div><b>{label(e.event_type)}</b><small style={{display:"block",color:"#718096"}}>{e.actor_name||"System"}{e.employee_name?` · ${e.employee_name}`:""}</small></div><span>{e.target_name||"—"}</span><div><span>{e.event_reason||"No reason recorded"}</span>{(e.previous_state||e.new_state)&&<details style={{marginTop:5}}><summary style={{cursor:"pointer",color:"#4f6274"}}>State details</summary><pre style={{whiteSpace:"pre-wrap",fontSize:11,background:"#f7f9fb",padding:8,borderRadius:7,overflow:"auto"}}>{JSON.stringify({previous:e.previous_state,new:e.new_state},null,2)}</pre></details>}</div></article>)}</div>}</section></div></main>
}
