"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {History,RefreshCw,Search} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type Event={event_id:string;event_type:string;event_reason:string|null;occurred_at:string;actor_name:string|null;target_name:string|null;employee_name:string|null;previous_state:Record<string,unknown>|null;new_state:Record<string,unknown>|null};
type Payload={events:Event[]};
function label(v:string){return v.replaceAll("_"," ").replace(/\b\w/g,x=>x.toUpperCase())}

export default function AuditPage(){
 const[data,setData]=useState<Payload>({events:[]}),[loading,setLoading]=useState(true),[error,setError]=useState(""),[query,setQuery]=useState("");
 const load=async()=>{if(!supabase){setError("Audit history is temporarily unavailable.");setLoading(false);return}setLoading(true);setError("");const{data:result,error:rpcError}=await supabase.rpc("get_admin_audit_activity",{selected_limit:200});if(rpcError)setError("We couldn't load the audit history. Refresh and try again.");else setData((result||{events:[]}) as Payload);setLoading(false)};
 useEffect(()=>{load()},[]);
 const rows=useMemo(()=>{const q=query.trim().toLowerCase();return !q?data.events:data.events.filter(e=>`${e.event_type} ${e.event_reason||""} ${e.actor_name||""} ${e.target_name||""} ${e.employee_name||""}`.toLowerCase().includes(q))},[data.events,query]);
 const actors=useMemo(()=>new Set(data.events.map(e=>e.actor_name||"System")).size,[data.events]);
 const types=useMemo(()=>new Set(data.events.map(e=>e.event_type)).size,[data.events]);
 return <main className="eng-page"><div className="eng-page__shell">
  <nav className="eng-breadcrumb" aria-label="Breadcrumb"><Link href="/manage">Control Center</Link><span className="eng-breadcrumb__sep">/</span><span className="eng-breadcrumb__current">Audit Log</span></nav>
  <header className="eng-page-header"><div className="eng-page-header__main"><span className="eng-page-header__eyebrow">AUDIT & HISTORY</span><h1>Audit Log</h1><p className="eng-page-header__lede">Immutable operational history for compensation, approvals, access, workflow, reconciliation, and payment actions.</p></div><div className="eng-page-header__actions"><button className="eng-btn" onClick={load} disabled={loading}><RefreshCw size={16}/>{loading?"Refreshing…":"Refresh"}</button></div></header>
  {error&&<div className="eng-callout eng-callout--danger"><div className="eng-callout__body"><b>Audit history unavailable</b>{error}</div></div>}
  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(180px,1fr))",gap:10,marginBottom:16}}><div className="eng-card"><div className="eng-card__body"><small>Events returned</small><b className="eng-figure eng-figure--strong" style={{display:"block",fontSize:26,marginTop:4}}>{loading?"—":data.events.length}</b></div></div><div className="eng-card"><div className="eng-card__body"><small>Distinct actors</small><b className="eng-figure eng-figure--strong" style={{display:"block",fontSize:26,marginTop:4}}>{loading?"—":actors}</b></div></div><div className="eng-card"><div className="eng-card__body"><small>Event types</small><b className="eng-figure eng-figure--strong" style={{display:"block",fontSize:26,marginTop:4}}>{loading?"—":types}</b></div></div></section>
  <section className="eng-card"><div className="eng-card__head"><div><h2>Recent events</h2><p>Search the most recent 200 audit events.</p></div><div className="eng-card__head-actions" style={{minWidth:300}}><div style={{position:"relative",width:"100%"}}><Search size={15} style={{position:"absolute",left:10,top:10,color:"var(--eng-ink-faint)"}}/><input className="eng-input" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search actor, employee, event or reason" style={{width:"100%",paddingLeft:32}}/></div></div></div><div className="eng-card__body">{loading?<div className="eng-skel-rows">{[0,1,2,3].map(i=><div className="eng-skel-row" key={i}><div className="eng-skel" style={{height:14,width:"100%"}}/></div>)}</div>:rows.length===0?<div className="eng-empty eng-empty--inline"><div className="eng-empty__icon"><History size={22}/></div><h2>{query?"No matching audit events":"No audit events returned"}</h2><p>{query?"Try a broader search term.":"Operational events will appear here as activity is recorded."}</p></div>:<div style={{display:"grid"}}>{rows.map(e=><article key={e.event_id} style={{display:"grid",gridTemplateColumns:"170px 1.15fr 1fr 1.8fr",gap:12,alignItems:"start",padding:"12px 0",borderBottom:"1px solid var(--eng-border-soft)",fontSize:13}}><span className="eng-figure eng-figure--muted">{new Date(e.occurred_at).toLocaleString()}</span><div><b>{label(e.event_type)}</b><small style={{display:"block",color:"var(--eng-ink-meta)"}}>{e.actor_name||"System"}{e.employee_name?` · ${e.employee_name}`:""}</small></div><span>{e.target_name||"—"}</span><div><span>{e.event_reason||"No reason recorded"}</span>{(e.previous_state||e.new_state)&&<details style={{marginTop:5}}><summary style={{cursor:"pointer",color:"var(--eng-blue-strong)",fontWeight:600}}>State details</summary><pre style={{whiteSpace:"pre-wrap",fontSize:11,background:"var(--eng-surface-alt)",padding:8,borderRadius:7,overflow:"auto",border:"1px solid var(--eng-border-soft)"}}>{JSON.stringify({previous:e.previous_state,new:e.new_state},null,2)}</pre></details>}</div></article>)}</div>}</div></section>
 </div></main>
}
