"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,ArrowLeft,CheckCircle2,Database,RefreshCw,Search,ShieldCheck} from "lucide-react";

const supabase=createClient(
 process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Access={roles?:string[];permissions?:string[]};
type SyncObject={hubspot_object_type:string;internal_object_key:string;object_category:string;description?:string|null;read_access:string;record_sync_enabled:boolean;sync_reason?:string|null;updated_at?:string|null};
type LatestRun={id:string;status:string;started_at:string;completed_at?:string|null;schema_summary?:Record<string,any>;data_summary?:Record<string,any>;change_summary?:Record<string,any>;warnings?:any[];error_message?:string|null};
type StatusData={objects:SyncObject[];latest_run:LatestRun|null;summary:{registered_objects:number;readable_objects:number;record_sync_objects:number;properties:number;open_configuration_changes:number}};

const card={background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18} as const;
const btn={border:"1px solid #c7d3de",borderRadius:9,padding:"10px 13px",background:"white",fontWeight:800,color:"#051b34",cursor:"pointer"} as const;
const label=(s:string)=>s.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());
const coreObjects=new Set(["DEAL","COMPANY","MEETING_EVENT"]);

export default function HubSpotIntegrationPage(){
 const[access,setAccess]=useState<Access|null>(null),[data,setData]=useState<StatusData|null>(null),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false);
 const[error,setError]=useState(""),[message,setMessage]=useState(""),[search,setSearch]=useState("");
 const perms=access?.permissions||[],roles=access?.roles||[];
 const admin=roles.includes("system_administrator");
 const canView=admin||perms.includes("settings.manage")||perms.includes("settings.hubspot_mapping.view")||perms.includes("settings.hubspot_mapping.edit");
 const canEdit=admin||perms.includes("settings.manage")||perms.includes("settings.hubspot_mapping.edit");

 const load=async()=>{
  setLoading(true);setError("");
  const[a,s]=await Promise.all([supabase.rpc("get_current_user_access"),supabase.rpc("get_hubspot_integration_status")]);
  if(a.data)setAccess(a.data as Access);
  if(s.error)setError(s.error.message); else setData(s.data as StatusData);
  setLoading(false);
 };
 useEffect(()=>{load()},[]);

 const filtered=useMemo(()=>{
  const q=search.trim().toLowerCase();
  const rows=data?.objects||[];
  return q?rows.filter(o=>`${o.hubspot_object_type} ${o.internal_object_key} ${o.description||""}`.toLowerCase().includes(q)):rows;
 },[data,search]);
 const synced=filtered.filter(o=>o.record_sync_enabled);
 const available=filtered.filter(o=>!o.record_sync_enabled&&o.read_access==="AVAILABLE");
 const restricted=filtered.filter(o=>o.read_access!=="AVAILABLE");

 const toggle=async(o:SyncObject,next:boolean)=>{
  if(!canEdit)return;
  setBusy(true);setError("");setMessage("");
  const{error:e}=await supabase.rpc("set_hubspot_object_record_sync",{target_hubspot_object_type:o.hubspot_object_type,enabled:next});
  if(e)setError(e.message);else{setMessage(`${o.hubspot_object_type} ${next?"will now":"will no longer"} sync records during HubSpot re-sync.`);await load()}
  setBusy(false);
 };

 const resync=async()=>{
  if(!canEdit)return;
  setBusy(true);setError("");setMessage("Re-syncing HubSpot. This may take a few minutes because schema, pipelines, stages, and enabled records are being refreshed.");
  const{data:r,error:e}=await supabase.rpc("resync_hubspot_integration");
  if(e){setError(e.message);setMessage("");}
  else{
   const changes=r?.changes||{};
   const warningCount=Array.isArray(r?.warnings)?r.warnings.length:0;
   setMessage(`HubSpot re-sync finished${warningCount?" with warnings":""}. ${changes.added||0} new, ${changes.changed||0} updated, and ${changes.removed||0} removed configuration items detected.`);
   await load();
  }
  setBusy(false);
 };

 if(loading)return <main style={{padding:28,fontFamily:"Inter,Arial,sans-serif"}}>Loading HubSpot integration…</main>;
 if(!canView)return <main style={{padding:28,fontFamily:"Inter,Arial,sans-serif"}}><h1>HubSpot Integration</h1><p>You do not have permission to view this configuration.</p></main>;

 const last=data?.latest_run;
 const scopeWarning=Array.isArray(last?.warnings)?last!.warnings!.some((w:any)=>w?.status==="schema_scope_missing"):false;
 return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{maxWidth:1240,margin:"0 auto"}}>
  <Link href="/settings" style={{display:"inline-flex",gap:6,alignItems:"center",textDecoration:"none",color:"#647184",fontWeight:800,fontSize:13}}><ArrowLeft size={15}/> Settings</Link>
  <header style={{display:"flex",justifyContent:"space-between",gap:18,alignItems:"flex-start",margin:"12px 0 18px",flexWrap:"wrap"}}><div><small style={{fontWeight:900,color:"#2095f3",letterSpacing:1}}>DATA INTEGRATION</small><h1 style={{fontSize:34,margin:"5px 0"}}>HubSpot Integration</h1><p style={{margin:0,color:"#647184",maxWidth:820}}>Control which HubSpot objects synchronize records into the Compensation Tracker. This v1 integration is read-only: HubSpot → Compensation Tracker only.</p></div><button onClick={resync} disabled={!canEdit||busy} style={{...btn,background:"#2095f3",borderColor:"#2095f3",color:"white"}}><RefreshCw size={16}/> {busy?"Re-syncing…":"Re-sync HubSpot"}</button></header>
  {error&&<div style={{...card,background:"#fff1f1",borderColor:"#efc7c7",marginBottom:12}}>{error}</div>}
  {message&&<div style={{...card,background:"#edf9f2",borderColor:"#cce8d7",marginBottom:12}}>{message}</div>}
  {scopeWarning&&<div style={{...card,background:"#fff9e9",borderColor:"#eadcae",marginBottom:12,display:"flex",gap:10}}><AlertTriangle size={20}/><div><b>HubSpot schema permission is incomplete</b><p style={{margin:"4px 0 0",color:"#647184"}}>The current HubSpot credential can refresh registered objects, fields, pipelines, stages, and values, but cannot automatically enumerate a brand-new object type. We can fix that later by adding the required HubSpot schema scope.</p></div></div>}

  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(190px,1fr))",gap:10,marginBottom:14}}>
   <div style={card}><small>Registered objects</small><b style={{display:"block",fontSize:25,marginTop:4}}>{data?.summary.registered_objects||0}</b></div>
   <div style={card}><small>Readable objects</small><b style={{display:"block",fontSize:25,marginTop:4}}>{data?.summary.readable_objects||0}</b></div>
   <div style={card}><small>Record-sync objects</small><b style={{display:"block",fontSize:25,marginTop:4}}>{data?.summary.record_sync_objects||0}</b></div>
   <div style={card}><small>Available HubSpot fields</small><b style={{display:"block",fontSize:25,marginTop:4}}>{data?.summary.properties||0}</b></div>
   <div style={{...card,borderColor:(data?.summary.open_configuration_changes||0)>0?"#e4c776":"#dfe6ee"}}><small>Changes to review</small><b style={{display:"block",fontSize:25,marginTop:4}}>{data?.summary.open_configuration_changes||0}</b></div>
  </section>

  <section style={{...card,marginBottom:14}}><div style={{display:"flex",justifyContent:"space-between",gap:14,alignItems:"center",flexWrap:"wrap"}}><div><h2 style={{fontSize:19,margin:"0 0 4px"}}>v1 required record sync</h2><p style={{margin:0,color:"#647184"}}>These objects stay synchronized whether or not every field is used for compensation.</p></div><ShieldCheck size={22}/></div><div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(230px,1fr))",gap:9,marginTop:12}}>{["DEAL","COMPANY","MEETING_EVENT"].map(k=>{const o=data?.objects.find(x=>x.hubspot_object_type===k);return <div key={k} style={{border:"1px solid #dfe6ee",borderRadius:10,padding:11}}><b>{k==="MEETING_EVENT"?"Meetings":label(k)}</b><code style={{display:"block",fontSize:11,color:"#647184",marginTop:3}}>{k}</code><span style={{display:"inline-flex",gap:5,alignItems:"center",fontSize:12,fontWeight:900,color:o?.record_sync_enabled?"#0f7a50":"#b42318",marginTop:8}}>{o?.record_sync_enabled?<CheckCircle2 size={14}/>:<AlertTriangle size={14}/>} {o?.record_sync_enabled?"Record sync on":"Record sync off"}</span></div>})}</div></section>

  <section style={card}><div style={{display:"flex",justifyContent:"space-between",gap:12,alignItems:"center",flexWrap:"wrap",marginBottom:12}}><div><h2 style={{fontSize:19,margin:"0 0 4px"}}>Object sync configuration</h2><p style={{margin:0,color:"#647184"}}>Other readable HubSpot objects are available but do not download records unless a permissioned admin enables them.</p></div><div style={{position:"relative"}}><Search size={15} style={{position:"absolute",left:10,top:10,color:"#718096"}}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search HubSpot objects" style={{padding:"8px 10px 8px 31px",border:"1px solid #cad5df",borderRadius:8,minWidth:250}}/></div></div>
   <div style={{display:"grid",gap:14}}>
    <div><h3 style={{fontSize:14,margin:"0 0 7px"}}>Syncing records ({synced.length})</h3><div style={{display:"grid",gap:6}}>{synced.map(o=><div key={o.hubspot_object_type} style={{border:"1px solid #e2e8ee",borderRadius:9,padding:10,display:"flex",justifyContent:"space-between",gap:12,alignItems:"center"}}><div><b>{o.hubspot_object_type==="MEETING_EVENT"?"Meetings":label(o.internal_object_key)}</b><code style={{display:"block",fontSize:10,color:"#718096"}}>{o.hubspot_object_type}</code></div><label style={{fontSize:12,fontWeight:800,display:"flex",gap:6,alignItems:"center"}}><input type="checkbox" checked disabled={coreObjects.has(o.hubspot_object_type)||!canEdit||busy} onChange={()=>toggle(o,false)}/> Sync records {coreObjects.has(o.hubspot_object_type)&&<span style={{color:"#647184"}}>· v1 required</span>}</label></div>)}</div></div>
    <div><h3 style={{fontSize:14,margin:"0 0 7px"}}>Available to enable ({available.length})</h3><div style={{display:"grid",gap:6}}>{available.map(o=><div key={o.hubspot_object_type} style={{border:"1px solid #edf1f5",borderRadius:9,padding:10,display:"flex",justifyContent:"space-between",gap:12,alignItems:"center"}}><div><b>{label(o.internal_object_key)}</b><code style={{display:"block",fontSize:10,color:"#718096"}}>{o.hubspot_object_type}</code>{o.description&&<small style={{display:"block",color:"#647184",marginTop:3}}>{o.description}</small>}</div><label style={{fontSize:12,fontWeight:800,display:"flex",gap:6,alignItems:"center"}}><input type="checkbox" checked={false} disabled={!canEdit||busy} onChange={()=>toggle(o,true)}/> Sync records</label></div>)}</div></div>
    {restricted.length>0&&<div><h3 style={{fontSize:14,margin:"0 0 7px"}}>Unavailable with current HubSpot access ({restricted.length})</h3><div style={{display:"grid",gap:6}}>{restricted.map(o=><div key={o.hubspot_object_type} style={{border:"1px solid #edf1f5",borderRadius:9,padding:10,display:"flex",justifyContent:"space-between",gap:12}}><div><b>{label(o.internal_object_key)}</b><code style={{display:"block",fontSize:10,color:"#718096"}}>{o.hubspot_object_type}</code></div><span style={{fontSize:11,fontWeight:900,color:"#9b6b17"}}>{label(o.read_access)}</span></div>)}</div></div>}
   </div>
  </section>

  {last&&<section style={{...card,marginTop:14}}><h2 style={{fontSize:19,margin:"0 0 5px"}}>Last re-sync</h2><p style={{margin:"0 0 10px",color:"#647184"}}>{new Date(last.started_at).toLocaleString()} · <b>{label(last.status)}</b></p><div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(180px,1fr))",gap:8}}><div><small>New configuration</small><b style={{display:"block",fontSize:20}}>{Number(last.change_summary?.added||0)}</b></div><div><small>Updated configuration</small><b style={{display:"block",fontSize:20}}>{Number(last.change_summary?.changed||0)}</b></div><div><small>Removed configuration</small><b style={{display:"block",fontSize:20}}>{Number(last.change_summary?.removed||0)}</b></div><div><small>Open review items</small><b style={{display:"block",fontSize:20}}>{Number(last.change_summary?.open_changes||0)}</b></div></div></section>}

  <div style={{marginTop:14,fontSize:13,color:"#647184"}}>Compensation eligibility is configured separately in <Link href="/settings/hubspot-mapping">HubSpot Compensation Mapping</Link>.</div>
 </div></main>;
}
