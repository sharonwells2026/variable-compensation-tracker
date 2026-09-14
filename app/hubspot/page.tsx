"use client";

import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,CheckCircle2,RefreshCw} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;
type Change={detected_at:string;deal_name:string;field_name:string;old_value:string|null;new_value:string|null;review_status:string};
type Data={deals:number;companies:number;associations:number;unlinkedDeals:number;unreviewedChanges:number;lastSync:string|null;recentChanges:Change[]};
const empty:Data={deals:0,companies:0,associations:0,unlinkedDeals:0,unreviewedChanges:0,lastSync:null,recentChanges:[]};
const card={background:"white",border:"1px solid var(--eng-border, #dfe6ee)",borderRadius:14,padding:18} as const;

export default function HubSpotPage(){
 const[data,setData]=useState<Data>(empty),[loading,setLoading]=useState(true),[syncing,setSyncing]=useState(false),[error,setError]=useState("");
 const load=async()=>{if(!supabase){setError("HubSpot source data is temporarily unavailable.");setLoading(false);return}setLoading(true);setError("");const{data:result,error:rpcError}=await supabase.rpc("get_compensation_dashboard_data");if(rpcError)setError("We couldn't load HubSpot source data. Try again, or check the integration if the problem continues.");else setData((result||empty) as Data);setLoading(false)};
 useEffect(()=>{load()},[]);
 const refresh=async()=>{if(!supabase)return;setSyncing(true);setError("");const{error:rpcError}=await supabase.rpc("refresh_compensation_management_data",{force_refresh:true});if(rpcError)setError("HubSpot refresh could not be completed. No compensation settings were changed.");else await load();setSyncing(false)};
 return <main className="eng-page"><div className="eng-page__shell">
  <nav className="eng-page__crumbs" aria-label="Breadcrumb"><Link href="/manage">Control Center</Link><span>/</span><span>HubSpot Source Data</span></nav>
  <header className="eng-page__header"><div><div className="eng-page__eyebrow">SOURCE DATA</div><h1>HubSpot Source Data</h1><p className="eng-page__lede">The synchronized HubSpot records that compensation calculations use. Configuration lives separately so source records and rule availability are never confused.</p></div><div className="eng-page__actions"><Link className="eng-page__button" href="/settings/hubspot-integration">Integration settings</Link><Link className="eng-page__button" href="/settings/hubspot-mapping">Rule data</Link><button className="eng-page__button eng-page__button--primary" onClick={refresh} disabled={syncing||loading}><RefreshCw size={16}/>{syncing?"Refreshing…":"Refresh HubSpot"}</button></div></header>
  {error&&<div className="eng-page__alert eng-page__alert--danger">{error}</div>}
  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(185px,1fr))",gap:10,marginBottom:18}}>{[["Deals",data.deals],["Companies",data.companies],["Associations",data.associations],["Unlinked deals",data.unlinkedDeals],["Changes to review",data.unreviewedChanges]].map(([a,b])=><div key={String(a)} style={card}><small>{a}</small><b style={{display:"block",fontSize:26,marginTop:4}}>{loading?"—":Number(b).toLocaleString()}</b></div>)}</section>
  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(320px,1fr))",gap:14,marginBottom:18}}><div style={card}><h2 style={{marginTop:0}}>What is synchronized</h2>{["Deals: pipeline, type, stage, owner, ARR, term and payment fields","Companies and account ownership","Deal/company associations","HubSpot change history for audit and recalculation"].map(x=><div key={x} style={{display:"flex",gap:8,margin:"10px 0"}}><CheckCircle2 size={17}/><span>{x}</span></div>)}</div><div style={card}><h2 style={{marginTop:0}}>Items that need review</h2>{["Paid stage and invoice-paid date disagree","Deal has no company association","Compensation-sensitive field changes after calculation","Ownership or attribution is unclear"].map(x=><div key={x} style={{display:"flex",gap:8,margin:"10px 0"}}><AlertTriangle size={17}/><span>{x}</span></div>)}</div></section>
  <section style={card}><div><h2 style={{margin:"0 0 4px"}}>Recent compensation-relevant changes</h2><small>Last completed sync: {data.lastSync?new Date(data.lastSync).toLocaleString():"Not available"}</small></div>{data.recentChanges.length===0?<div className="eng-page__empty"><strong>No recent changes</strong><span>Changes that may affect compensation will appear here after synchronization.</span></div>:<div style={{overflowX:"auto",marginTop:14}}><div style={{minWidth:760}}>{data.recentChanges.map((x,i)=><div key={`${x.detected_at}-${i}`} style={{display:"grid",gridTemplateColumns:"150px 1.2fr 1fr 1.4fr auto",gap:10,alignItems:"center",padding:"10px 0",borderBottom:"1px solid var(--eng-border, #edf1f5)",fontSize:13}}><span>{new Date(x.detected_at).toLocaleString()}</span><b>{x.deal_name}</b><span>{x.field_name}</span><span>{x.old_value||"—"} → {x.new_value||"—"}</span><em>{x.review_status}</em></div>)}</div></div>}</section>
 </div></main>;
}