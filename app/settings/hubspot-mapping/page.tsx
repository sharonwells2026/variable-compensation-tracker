"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,ArrowLeft,CheckCircle2,ChevronRight,Database,RefreshCw,Search,ShieldAlert} from "lucide-react";

const supabase=createClient(
 process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Access={roles?:string[];permissions?:string[]};
type MappingVersion={id:string;version_number:number;status:string;effective_from:string|null;effective_to:string|null;notes?:string|null};
type Obj={object_type:string;display_name:string;hubspot_object_type:string;description?:string;discovered_active:boolean;eligible:boolean};
type Field={object_type:string;property_name:string;display_name:string;data_type:string;description?:string;is_multi_value:boolean;source_system:string;discovered_active:boolean;eligible:boolean;value_policy:"all"|"selected";selected_value_count:number};
type Value={object_type:string;property_name:string;hubspot_value:string;display_label:string;context:Record<string,unknown>;discovered_active:boolean;eligible:boolean};
type MappingData={mapping_version:MappingVersion;objects:Obj[];fields:Field[];values:Value[]};
type Impact={risk:string;affected_rule_sets:number;affected_active_rule_sets:number;affected_draft_rule_sets:number;affected_plan_components:number;affected_current_earnings:number;approved_unpaid_earnings:number;paid_earnings:number;requires_explicit_resolution:boolean;resolution_options:string[]};
type ChangeRequest={mapping_version_id:string;level:"object"|"field"|"value";object_type:string;property_name?:string;hubspot_value?:string;context?:Record<string,unknown>;is_eligible:boolean;value_policy?:"all"|"selected";resolution_action?:string};
type ConfigChange={id:string;change_type:string;entity_type:string;object_type:string;property_name?:string|null;hubspot_value?:string|null;severity:string;display_summary?:string;old_state?:Record<string,unknown>;new_state?:Record<string,unknown>;mapping_impact?:Impact;detected_at:string;review_status:string};
type ChangeData={summary:{open:number;critical:number;action_required:number;review_recommended:number};changes:ConfigChange[]};

const box={background:"white",border:"1px solid #dfe6ee",borderRadius:14,padding:18} as const;
const button={border:"1px solid #c8d4df",borderRadius:9,padding:"9px 12px",background:"white",fontWeight:800,color:"#051b34",cursor:"pointer"} as const;
const riskLabel=(x:string)=>x.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());
const resolutionLabel=(x:string)=>({cancel_change:"Cancel change",apply_future_only:"Apply to future activity only",create_successor_rule_versions:"Create successor rule versions",grandfather_existing_earnings:"Grandfather existing earnings",dry_run_recalculation:"Dry-run recalculation",send_unpaid_to_review:"Send unpaid items to review",preserve_paid_and_use_correction_workflow:"Preserve paid earnings; use correction workflow",acknowledge:"Acknowledge",update_mapping:"Update mapping",create_successor_mapping:"Create successor mapping",future_only:"Future only",grandfather_existing:"Grandfather existing",send_to_review:"Send affected items to review",ignore:"Ignore"}[x]||riskLabel(x));

export default function HubSpotMappingPage(){
 const[access,setAccess]=useState<Access|null>(null),[data,setData]=useState<MappingData|null>(null),[changes,setChanges]=useState<ChangeData|null>(null);
 const[selectedObject,setSelectedObject]=useState(""),[selectedField,setSelectedField]=useState(""),[search,setSearch]=useState("");
 const[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 const[pending,setPending]=useState<{request:ChangeRequest;impact:Impact}|null>(null),[resolution,setResolution]=useState("");
 const[changeResolution,setChangeResolution]=useState<Record<string,string>>({});
 const perms=access?.permissions||[],roles=access?.roles||[];
 const admin=roles.includes("system_administrator");
 const has=(p:string)=>admin||perms.includes(p);
 const canView=has("settings.manage")||has("settings.hubspot_mapping.view")||has("settings.hubspot_mapping.edit");
 const canEdit=has("settings.manage")||has("settings.hubspot_mapping.edit");
 const isDraft=data?.mapping_version.status==="draft";

 const load=async()=>{
  setLoading(true);setError("");
  const[a,m,c]=await Promise.all([
   supabase.rpc("get_current_user_access"),
   supabase.rpc("get_hubspot_comp_mapping_admin_data",{target_mapping_version_id:null}),
   supabase.rpc("get_hubspot_comp_configuration_changes")
  ]);
  if(a.data)setAccess(a.data as Access);
  if(m.error)setError(m.error.message); else {const next=m.data as MappingData;setData(next);setSelectedObject(x=>x||next.objects.find(o=>o.eligible)?.object_type||next.objects[0]?.object_type||"");}
  if(!c.error)setChanges(c.data as ChangeData);
  setLoading(false);
 };
 useEffect(()=>{load()},[]);

 const object=data?.objects.find(o=>o.object_type===selectedObject);
 const fields=useMemo(()=>data?.fields.filter(f=>f.object_type===selectedObject)??[],[data,selectedObject]);
 const field=fields.find(f=>f.property_name===selectedField)||null;
 const values=useMemo(()=>{
  const all=(data?.values||[]).filter(v=>v.object_type===selectedObject&&v.property_name===selectedField);
  const q=search.trim().toLowerCase();
  return q?all.filter(v=>`${v.display_label} ${v.hubspot_value} ${String(v.context?.pipeline_name||"")}`.toLowerCase().includes(q)):all;
 },[data,selectedObject,selectedField,search]);
 const groups=useMemo(()=>{
  const g=new Map<string,Value[]>();
  values.forEach(v=>{const key=String(v.context?.pipeline_name||"Available values");g.set(key,[...(g.get(key)||[]),v])});
  return [...g.entries()];
 },[values]);

 const beginChange=async(request:ChangeRequest)=>{
  if(!data||!canEdit||!isDraft)return;
  setBusy(true);setError("");setMessage("");
  const{data:impact,error:e}=await supabase.rpc("analyze_hubspot_comp_mapping_change",{change_request:request});
  setBusy(false);
  if(e){setError(e.message);return}
  setPending({request,impact:impact as Impact});setResolution("");
 };
 const applyPending=async()=>{
  if(!pending)return;
  if(pending.impact.requires_explicit_resolution&&!resolution){setError("Choose how to address the compensation impact before applying this change.");return}
  setBusy(true);setError("");
  const request={...pending.request,...(resolution?{resolution_action:resolution}:{})};
  const{data:result,error:e}=await supabase.rpc("apply_hubspot_comp_mapping_change",{change_request:request});
  if(e){setError(e.message);setBusy(false);return}
  if(result?.requires_resolution){setPending({request:pending.request,impact:result.impact as Impact});setBusy(false);return}
  setPending(null);setResolution("");setMessage("Draft mapping updated. No active compensation configuration changed.");await load();setBusy(false);
 };
 const refreshChanges=async()=>{setBusy(true);setError("");const{error:e}=await supabase.rpc("refresh_hubspot_comp_configuration_changes");if(e)setError(e.message);else{setMessage("HubSpot configuration compared with the prior snapshot.");await load()}setBusy(false)};
 const resolveChange=async(id:string)=>{const action=changeResolution[id];if(!action){setError("Choose a resolution first.");return}setBusy(true);const{error:e}=await supabase.rpc("resolve_hubspot_comp_configuration_change",{target_change_id:id,resolution:action,note:null});if(e)setError(e.message);else await load();setBusy(false)};
 const createDraft=async()=>{setBusy(true);const{error:e}=await supabase.rpc("create_hubspot_comp_mapping_version",{source_mapping_version_id:data?.mapping_version.id||null,note:"Successor mapping created from Settings"});if(e)setError(e.message);else await load();setBusy(false)};
 const activate=async()=>{if(!data||!window.confirm(`Activate HubSpot Compensation Mapping v${data.mapping_version.version_number}? The current active mapping will be retired and this version will govern future compensation from now.`))return;setBusy(true);const{error:e}=await supabase.rpc("activate_hubspot_comp_mapping_version",{target_mapping_version_id:data.mapping_version.id,effective_at:new Date().toISOString()});if(e)setError(e.message);else{setMessage("Mapping version activated.");await load()}setBusy(false)};

 if(loading)return <main style={{padding:28,fontFamily:"Inter,Arial,sans-serif"}}>Loading HubSpot compensation mapping…</main>;
 if(!canView)return <main style={{padding:28,fontFamily:"Inter,Arial,sans-serif"}}><h1>HubSpot Compensation Mapping</h1><p>You do not have permission to view this configuration.</p></main>;
 if(!data)return <main style={{padding:28,fontFamily:"Inter,Arial,sans-serif"}}><h1>HubSpot Compensation Mapping</h1><p>{error||"Mapping data is unavailable."}</p></main>;

 return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{maxWidth:1380,margin:"0 auto"}}>
  <Link href="/settings" style={{display:"inline-flex",alignItems:"center",gap:6,color:"#647184",fontWeight:800,textDecoration:"none",fontSize:13}}><ArrowLeft size={15}/> Settings</Link>
  <header style={{display:"flex",justifyContent:"space-between",gap:18,alignItems:"flex-start",margin:"12px 0 18px",flexWrap:"wrap"}}><div><small style={{fontWeight:900,color:"#2095f3",letterSpacing:1}}>SOURCE CONFIGURATION</small><h1 style={{fontSize:34,margin:"5px 0"}}>HubSpot Compensation Mapping</h1><p style={{margin:0,color:"#647184",maxWidth:850}}>Control exactly which HubSpot objects, fields, and values may be used by compensation rules. HubSpot identifiers remain the source of truth; labels are shown for usability.</p></div><div style={{display:"flex",gap:8,flexWrap:"wrap"}}><button style={button} onClick={refreshChanges} disabled={!canEdit||busy}><RefreshCw size={15}/> Check HubSpot changes</button>{isDraft?<button style={{...button,background:"#2095f3",color:"white",borderColor:"#2095f3"}} onClick={activate} disabled={!canEdit||busy}>Activate mapping v{data.mapping_version.version_number}</button>:<button style={{...button,background:"#2095f3",color:"white",borderColor:"#2095f3"}} onClick={createDraft} disabled={!canEdit||busy}>Create successor draft</button>}</div></header>
  {error&&<div style={{...box,background:"#fff1f1",borderColor:"#efc7c7",marginBottom:12}}>{error}</div>}
  {message&&<div style={{...box,background:"#edf9f2",borderColor:"#cce8d7",marginBottom:12}}>{message}</div>}

  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(190px,1fr))",gap:10,marginBottom:14}}>
   <div style={box}><small>Mapping version</small><b style={{display:"block",fontSize:24,marginTop:4}}>v{data.mapping_version.version_number}</b><span style={{fontSize:12,textTransform:"uppercase",fontWeight:900,color:isDraft?"#b7791f":"#0f7a50"}}>{data.mapping_version.status}</span></div>
   <div style={box}><small>HubSpot objects</small><b style={{display:"block",fontSize:24,marginTop:4}}>{data.objects.length}</b><span style={{fontSize:12,color:"#647184"}}>{data.objects.filter(x=>x.eligible).length} enabled</span></div>
   <div style={box}><small>HubSpot fields</small><b style={{display:"block",fontSize:24,marginTop:4}}>{data.fields.length}</b><span style={{fontSize:12,color:"#647184"}}>{data.fields.filter(x=>x.eligible).length} enabled</span></div>
   <div style={box}><small>Exact values discovered</small><b style={{display:"block",fontSize:24,marginTop:4}}>{data.values.length}</b><span style={{fontSize:12,color:"#647184"}}>IDs preserved exactly</span></div>
   <div style={{...box,borderColor:(changes?.summary.open||0)>0?"#e5c985":"#dfe6ee"}}><small>HubSpot changes to review</small><b style={{display:"block",fontSize:24,marginTop:4}}>{changes?.summary.open||0}</b><span style={{fontSize:12,color:"#647184"}}>{changes?.summary.critical||0} critical · {changes?.summary.action_required||0} action required</span></div>
  </section>

  {!isDraft&&<div style={{...box,background:"#f2f7fb",marginBottom:14}}><b>This mapping version is read-only.</b><p style={{margin:"5px 0 0",color:"#647184"}}>Create a successor draft before changing which HubSpot data compensation may use.</p></div>}
  {!canEdit&&<div style={{...box,background:"#f2f7fb",marginBottom:14}}><b>View-only access</b><p style={{margin:"5px 0 0",color:"#647184"}}>You can inspect the compensation mapping but cannot change or activate it.</p></div>}

  <section style={{display:"grid",gridTemplateColumns:"280px minmax(420px,1fr) minmax(360px,.85fr)",gap:14,alignItems:"start"}}>
   <div style={box}><div style={{display:"flex",gap:9,alignItems:"center",marginBottom:12}}><Database size={18}/><div><h2 style={{fontSize:18,margin:0}}>1. HubSpot objects</h2><small style={{color:"#647184"}}>Choose eligible objects.</small></div></div><div style={{display:"grid",gap:7}}>{data.objects.map(o=><button key={o.object_type} onClick={()=>{setSelectedObject(o.object_type);setSelectedField("");setSearch("")}} style={{textAlign:"left",border:selectedObject===o.object_type?"2px solid #2095f3":"1px solid #dfe6ee",background:selectedObject===o.object_type?"#f1f8fe":"white",borderRadius:10,padding:10,cursor:"pointer"}}><div style={{display:"flex",justifyContent:"space-between",gap:8,alignItems:"center"}}><b>{o.display_name}</b><ChevronRight size={15}/></div><code style={{fontSize:11,color:"#647184"}}>{o.hubspot_object_type||o.object_type}</code><label style={{display:"flex",gap:6,alignItems:"center",marginTop:8,fontSize:12,fontWeight:800}} onClick={e=>e.stopPropagation()}><input type="checkbox" checked={o.eligible} disabled={!canEdit||!isDraft||busy} onChange={e=>beginChange({mapping_version_id:data.mapping_version.id,level:"object",object_type:o.object_type,is_eligible:e.target.checked})}/> Use for compensation</label></button>)}</div></div>

   <div style={box}><h2 style={{fontSize:18,margin:"0 0 3px"}}>2. Fields {object?`in ${object.display_name}`:""}</h2><p style={{margin:"0 0 12px",color:"#647184",fontSize:13}}>Enable only fields that plan designers should be able to use. Internal HubSpot property names remain attached to every selection.</p><div style={{display:"grid",gap:8}}>{fields.map(f=><div key={f.property_name} style={{border:selectedField===f.property_name?"2px solid #2095f3":"1px solid #e1e7ed",borderRadius:10,padding:11,background:selectedField===f.property_name?"#f8fcff":"white"}}><div style={{display:"flex",justifyContent:"space-between",gap:10,alignItems:"flex-start"}}><button onClick={()=>{setSelectedField(f.property_name);setSearch("")}} style={{border:0,background:"transparent",padding:0,textAlign:"left",cursor:"pointer",flex:1}}><b>{f.display_name}</b><div><code style={{fontSize:11,color:"#647184"}}>{f.property_name}</code> <span style={{fontSize:11,color:"#8a96a3"}}>· {f.data_type}</span></div></button><label style={{fontSize:12,fontWeight:800,display:"flex",gap:6,alignItems:"center"}}><input type="checkbox" checked={f.eligible} disabled={!canEdit||!isDraft||busy} onChange={e=>beginChange({mapping_version_id:data.mapping_version.id,level:"field",object_type:f.object_type,property_name:f.property_name,is_eligible:e.target.checked,value_policy:f.value_policy})}/> Eligible</label></div>{f.eligible&&<div style={{display:"flex",gap:14,marginTop:9,fontSize:12}}><label><input type="radio" checked={f.value_policy==="all"} disabled={!canEdit||!isDraft||busy} onChange={()=>beginChange({mapping_version_id:data.mapping_version.id,level:"field",object_type:f.object_type,property_name:f.property_name,is_eligible:true,value_policy:"all"})}/> All HubSpot values</label><label><input type="radio" checked={f.value_policy==="selected"} disabled={!canEdit||!isDraft||busy} onChange={()=>{setSelectedField(f.property_name);beginChange({mapping_version_id:data.mapping_version.id,level:"field",object_type:f.object_type,property_name:f.property_name,is_eligible:true,value_policy:"selected"})}}/> Selected values only</label></div>}</div>)}</div></div>

   <div style={box}><h2 style={{fontSize:18,margin:"0 0 3px"}}>3. Exact HubSpot values</h2>{!field?<p style={{color:"#647184",fontSize:13}}>Select a field to inspect its available HubSpot values.</p>:field.value_policy!=="selected"?<div style={{background:"#f4f7fa",borderRadius:9,padding:12,fontSize:13}}><b>{field.display_name}</b><p style={{margin:"5px 0 0",color:"#647184"}}>All values are currently allowed. New HubSpot values will be detected by configuration monitoring.</p></div>:values.length===0?<p style={{color:"#647184",fontSize:13}}>No discrete HubSpot values are currently discovered for this field.</p>:<><div style={{position:"relative",margin:"10px 0 12px"}}><Search size={15} style={{position:"absolute",left:10,top:10,color:"#7d8995"}}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search values or IDs" style={{width:"100%",boxSizing:"border-box",padding:"8px 10px 8px 32px",border:"1px solid #cad5df",borderRadius:8}}/></div><div style={{maxHeight:620,overflow:"auto",display:"grid",gap:12}}>{groups.map(([group,items])=><div key={group}><div style={{fontSize:11,fontWeight:900,textTransform:"uppercase",letterSpacing:.6,color:"#647184",marginBottom:5}}>{group}</div><div style={{display:"grid",gap:5}}>{items.map(v=><label key={`${v.hubspot_value}-${JSON.stringify(v.context)}`} style={{display:"flex",gap:8,alignItems:"flex-start",padding:"7px 8px",border:"1px solid #edf1f5",borderRadius:8,cursor:canEdit&&isDraft?"pointer":"default"}}><input type="checkbox" checked={v.eligible} disabled={!canEdit||!isDraft||busy} onChange={e=>beginChange({mapping_version_id:data.mapping_version.id,level:"value",object_type:v.object_type,property_name:v.property_name,hubspot_value:v.hubspot_value,context:v.context,is_eligible:e.target.checked,value_policy:"selected"})}/><span><b style={{fontSize:13}}>{v.display_label}</b><code style={{display:"block",fontSize:10,color:"#7b8794",marginTop:2}}>{v.hubspot_value}</code></span></label>)}</div></div>)}</div></>}</div>
  </section>

  {pending&&<section style={{...box,marginTop:14,borderColor:pending.impact.risk==="critical"?"#d66":"#e5c985",background:"#fffdf6"}}><div style={{display:"flex",gap:10,alignItems:"flex-start"}}><ShieldAlert size={22}/><div style={{flex:1}}><h2 style={{fontSize:18,margin:"0 0 4px"}}>Review compensation impact before changing configuration</h2><p style={{margin:"0 0 12px",color:"#647184"}}>This draft change will not be applied until you review its impact. Risk: <b>{riskLabel(pending.impact.risk)}</b>.</p><div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(145px,1fr))",gap:8,marginBottom:12}}>{[["Rule sets",pending.impact.affected_rule_sets],["Active rules",pending.impact.affected_active_rule_sets],["Current earnings",pending.impact.affected_current_earnings],["Approved unpaid",pending.impact.approved_unpaid_earnings],["Paid earnings",pending.impact.paid_earnings]].map(([k,v])=><div key={String(k)} style={{background:"white",border:"1px solid #eadfbf",borderRadius:9,padding:9}}><small>{k}</small><b style={{display:"block",fontSize:20}}>{Number(v)}</b></div>)}</div>{pending.impact.requires_explicit_resolution&&<label style={{display:"block",fontSize:13,fontWeight:800,marginBottom:12}}>How should this be addressed?<select value={resolution} onChange={e=>setResolution(e.target.value)} style={{display:"block",width:"100%",maxWidth:520,marginTop:5,padding:9,border:"1px solid #c9d3dc",borderRadius:8}}><option value="">Choose a resolution…</option>{pending.impact.resolution_options.filter(x=>x!=="cancel_change").map(x=><option key={x} value={x}>{resolutionLabel(x)}</option>)}</select></label>}<div style={{display:"flex",gap:8}}><button style={button} onClick={()=>{setPending(null);setResolution("")}}>Cancel</button><button style={{...button,background:"#2095f3",color:"white",borderColor:"#2095f3"}} onClick={applyPending} disabled={busy}>Apply to draft mapping</button></div></div></div></section>}

  <section style={{...box,marginTop:14}}><div style={{display:"flex",justifyContent:"space-between",gap:10,alignItems:"center",marginBottom:12}}><div><h2 style={{fontSize:19,margin:"0 0 3px"}}>HubSpot configuration changes</h2><p style={{margin:0,color:"#647184",fontSize:13}}>Changes discovered in HubSpot stay here until a permissioned administrator reviews them.</p></div>{(changes?.summary.open||0)===0&&<span style={{display:"inline-flex",gap:6,alignItems:"center",fontSize:12,fontWeight:900,color:"#0f7a50"}}><CheckCircle2 size={16}/> No open changes</span>}</div>{(changes?.changes||[]).length>0&&<div style={{display:"grid",gap:8}}>{changes!.changes.map(c=><div key={c.id} style={{border:"1px solid #e3e9ef",borderRadius:10,padding:11,display:"grid",gridTemplateColumns:"minmax(260px,1fr) 160px minmax(240px,.8fr)",gap:12,alignItems:"center"}}><div><div style={{display:"flex",gap:7,alignItems:"center"}}><AlertTriangle size={15}/><b>{riskLabel(c.change_type)} · {c.object_type}{c.property_name?` / ${c.property_name}`:""}</b></div>{c.hubspot_value&&<code style={{fontSize:11,color:"#647184"}}>Value: {c.hubspot_value}</code>}</div><span style={{fontSize:11,fontWeight:900,textTransform:"uppercase",color:c.severity==="critical"?"#b42318":c.severity==="action_required"?"#b7791f":"#647184"}}>{riskLabel(c.severity)}</span>{canEdit?<div style={{display:"flex",gap:6}}><select value={changeResolution[c.id]||""} onChange={e=>setChangeResolution(x=>({...x,[c.id]:e.target.value}))} style={{flex:1,minWidth:0,padding:7,border:"1px solid #cbd5df",borderRadius:7}}><option value="">Resolution…</option>{["acknowledge","update_mapping","create_successor_mapping","future_only","grandfather_existing","send_to_review","ignore"].map(x=><option key={x} value={x}>{resolutionLabel(x)}</option>)}</select><button style={button} onClick={()=>resolveChange(c.id)} disabled={busy}>Resolve</button></div>:<span style={{fontSize:12,color:"#647184"}}>View only</span>}</div>)}</div>}</section>
 </div></main>;
}