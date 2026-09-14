"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,CheckCircle2,ChevronRight,Database,RefreshCw,Search,ShieldAlert} from "lucide-react";

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

const riskLabel=(x:string)=>x.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());
const resolutionLabel=(x:string)=>({cancel_change:"Cancel change",apply_future_only:"Apply to future activity only",create_successor_rule_versions:"Create successor rule versions",grandfather_existing_earnings:"Grandfather existing earnings",dry_run_recalculation:"Dry-run recalculation",send_unpaid_to_review:"Send unpaid items to review",preserve_paid_and_use_correction_workflow:"Preserve paid earnings; use correction workflow",acknowledge:"Acknowledge",update_mapping:"Update mapping",create_successor_mapping:"Create successor mapping",future_only:"Future only",grandfather_existing:"Grandfather existing",send_to_review:"Send affected items to review",ignore:"Ignore"}[x]||riskLabel(x));

export default function HubSpotMappingPage(){
 const[access,setAccess]=useState<Access|null>(null),[data,setData]=useState<MappingData|null>(null),[changes,setChanges]=useState<ChangeData|null>(null);
 const[selectedObject,setSelectedObject]=useState(""),[selectedField,setSelectedField]=useState("");
 const[objectSearch,setObjectSearch]=useState(""),[fieldSearch,setFieldSearch]=useState(""),[valueSearch,setValueSearch]=useState("");
 const[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 const[pending,setPending]=useState<{request:ChangeRequest;impact:Impact}|null>(null),[resolution,setResolution]=useState("");
 const[changeResolution,setChangeResolution]=useState<Record<string,string>>({});
 const perms=access?.permissions||[],roles=access?.roles||[];
 const admin=roles.includes("system_administrator");
 const has=(p:string)=>admin||perms.includes(p);
 const canView=has("settings.manage")||has("settings.hubspot_mapping.view")||has("settings.hubspot_mapping.edit");
 const canEdit=has("settings.manage")||has("settings.hubspot_mapping.edit");
 const isDraft=data?.mapping_version.status==="draft";

 const humanError=(fallback:string)=>fallback;
 const load=async()=>{
  setLoading(true);setError("");
  const[a,m,c]=await Promise.all([
   supabase.rpc("get_current_user_access"),
   supabase.rpc("get_hubspot_comp_mapping_admin_data",{target_mapping_version_id:null}),
   supabase.rpc("get_hubspot_comp_configuration_changes")
  ]);
  if(a.data)setAccess(a.data as Access);
  if(m.error)setError(humanError("HubSpot Rule Data could not be loaded. Try again, or check the HubSpot integration if the problem continues.")); else {const next=m.data as MappingData;setData(next);setSelectedObject(x=>x||next.objects.find(o=>o.eligible)?.object_type||next.objects[0]?.object_type||"");}
  if(!c.error)setChanges(c.data as ChangeData);
  setLoading(false);
 };
 useEffect(()=>{load()},[]);

 const sortedObjects=useMemo(()=>{
  const q=objectSearch.trim().toLowerCase();
  return [...(data?.objects||[])].filter(o=>!q||`${o.display_name} ${o.object_type} ${o.hubspot_object_type}`.toLowerCase().includes(q)).sort((a,b)=>Number(b.eligible)-Number(a.eligible)||a.display_name.localeCompare(b.display_name));
 },[data,objectSearch]);
 const object=data?.objects.find(o=>o.object_type===selectedObject);
 const fields=useMemo(()=>{
  const q=fieldSearch.trim().toLowerCase();
  return (data?.fields||[]).filter(f=>f.object_type===selectedObject).filter(f=>!q||`${f.display_name} ${f.property_name} ${f.data_type}`.toLowerCase().includes(q)).sort((a,b)=>Number(b.eligible)-Number(a.eligible)||a.display_name.localeCompare(b.display_name));
 },[data,selectedObject,fieldSearch]);
 const field=(data?.fields||[]).find(f=>f.object_type===selectedObject&&f.property_name===selectedField)||null;
 const values=useMemo(()=>{
  const all=(data?.values||[]).filter(v=>v.object_type===selectedObject&&v.property_name===selectedField);
  const q=valueSearch.trim().toLowerCase();
  return all.filter(v=>!q||`${v.display_label} ${v.hubspot_value} ${String(v.context?.pipeline_name||"")}`.toLowerCase().includes(q)).sort((a,b)=>Number(b.eligible)-Number(a.eligible)||a.display_label.localeCompare(b.display_label));
 },[data,selectedObject,selectedField,valueSearch]);
 const groups=useMemo(()=>{const g=new Map<string,Value[]>();values.forEach(v=>{const key=String(v.context?.pipeline_name||"Available values");g.set(key,[...(g.get(key)||[]),v])});return [...g.entries()]},[values]);

 const beginChange=async(request:ChangeRequest)=>{
  if(!data||!canEdit||!isDraft)return;
  setBusy(true);setError("");setMessage("");
  const{data:impact,error:e}=await supabase.rpc("analyze_hubspot_comp_mapping_change",{change_request:request});
  setBusy(false);
  if(e){setError("We could not analyze the impact of that change. Nothing was changed.");return}
  setPending({request,impact:impact as Impact});setResolution("");
 };
 const applyPending=async()=>{
  if(!pending)return;
  if(pending.impact.requires_explicit_resolution&&!resolution){setError("Choose how to address the compensation impact before applying this change.");return}
  setBusy(true);setError("");
  const request={...pending.request,...(resolution?{resolution_action:resolution}:{})};
  const{data:result,error:e}=await supabase.rpc("apply_hubspot_comp_mapping_change",{change_request:request});
  if(e){setError("The draft mapping change could not be applied. Nothing active was changed.");setBusy(false);return}
  if(result?.requires_resolution){setPending({request:pending.request,impact:result.impact as Impact});setBusy(false);return}
  setPending(null);setResolution("");setMessage("Rule Data updated in the draft. Active compensation configuration is unchanged until this version is activated.");await load();setBusy(false);
 };
 const refreshChanges=async()=>{setBusy(true);setError("");const{error:e}=await supabase.rpc("refresh_hubspot_comp_configuration_changes");if(e)setError("HubSpot changes could not be checked right now.");else{setMessage("HubSpot configuration compared with the prior snapshot.");await load()}setBusy(false)};
 const resolveChange=async(id:string)=>{const action=changeResolution[id];if(!action){setError("Choose a resolution first.");return}setBusy(true);const{error:e}=await supabase.rpc("resolve_hubspot_comp_configuration_change",{target_change_id:id,resolution:action,note:null});if(e)setError("That HubSpot configuration change could not be resolved.");else await load();setBusy(false)};
 const createDraft=async()=>{setBusy(true);const{error:e}=await supabase.rpc("create_hubspot_comp_mapping_version",{source_mapping_version_id:data?.mapping_version.id||null,note:"Successor mapping created from Settings"});if(e)setError("A successor Rule Data draft could not be created.");else await load();setBusy(false)};
 const activate=async()=>{if(!data||!window.confirm(`Activate HubSpot Rule Data v${data.mapping_version.version_number}? The current active version will be retired and this version will govern future compensation rule choices.`))return;setBusy(true);const{error:e}=await supabase.rpc("activate_hubspot_comp_mapping_version",{target_mapping_version_id:data.mapping_version.id,effective_at:new Date().toISOString()});if(e)setError("Rule Data could not be activated.");else{setMessage("Rule Data version activated.");await load()}setBusy(false)};

 if(loading)return <main className="eng-page"><div className="eng-page__shell"><div className="eng-empty eng-empty--inline">Loading HubSpot Rule Data…</div></div></main>;
 if(!canView)return <main className="eng-page"><div className="eng-page__shell"><div className="eng-empty"><h2>HubSpot Rule Data</h2><p>You do not have permission to view this configuration.</p></div></div></main>;
 if(!data)return <main className="eng-page"><div className="eng-page__shell"><div className="eng-empty"><h2>HubSpot Rule Data</h2><p>{error||"Rule Data is unavailable."}</p></div></div></main>;

 const enabledFields=(data.fields||[]).filter(x=>x.eligible).length;
 const enabledObjects=(data.objects||[]).filter(x=>x.eligible).length;

 return <main className="eng-page"><div className="eng-page__shell">
  <nav className="eng-breadcrumb" aria-label="Breadcrumb"><Link href="/manage">Control Center</Link><span className="eng-breadcrumb__sep">/</span><Link href="/settings">Settings</Link><span className="eng-breadcrumb__sep">/</span><span className="eng-breadcrumb__current">HubSpot Rule Data</span></nav>
  <header className="eng-page-header"><div className="eng-page-header__main"><span className="eng-page-header__eyebrow">SOURCE CONFIGURATION</span><div className="eng-page-header__titlerow"><h1>HubSpot Rule Data</h1><span className={`eng-badge ${isDraft?"eng-badge--warn":"eng-badge--success"}`}>v{data.mapping_version.version_number} · {riskLabel(data.mapping_version.status)}</span></div><p className="eng-page-header__lede">Choose which HubSpot objects, fields, and values plan rules are allowed to use. This controls rule-builder availability; it does not make an earning eligible for payment.</p></div><div className="eng-page-header__actions"><Link className="eng-btn" href="/settings/hubspot-integration">Integration</Link><Link className="eng-btn" href="/hubspot">Source Data</Link><button className="eng-btn" onClick={refreshChanges} disabled={!canEdit||busy}><RefreshCw size={15}/>Check HubSpot changes</button>{isDraft?<button className="eng-btn eng-btn--primary" onClick={activate} disabled={!canEdit||busy}>Activate Rule Data v{data.mapping_version.version_number}</button>:<button className="eng-btn eng-btn--primary" onClick={createDraft} disabled={!canEdit||busy}>Create successor draft</button>}</div></header>

  {error&&<div className="eng-callout eng-callout--danger" style={{marginBottom:12}}>{error}</div>}
  {message&&<div className="eng-callout eng-callout--success" style={{marginBottom:12}}>{message}</div>}

  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(190px,1fr))",gap:10,marginBottom:14}}>
   <div className="eng-card"><div className="eng-card__body"><small>Objects enabled for rules</small><b className="eng-figure" style={{display:"block",fontSize:24,marginTop:4}}>{enabledObjects} <span style={{fontSize:13,fontWeight:500,color:"var(--eng-ink-meta)"}}>of {data.objects.length}</span></b></div></div>
   <div className="eng-card"><div className="eng-card__body"><small>Fields enabled for rules</small><b className="eng-figure" style={{display:"block",fontSize:24,marginTop:4}}>{enabledFields} <span style={{fontSize:13,fontWeight:500,color:"var(--eng-ink-meta)"}}>of {data.fields.length}</span></b></div></div>
   <div className="eng-card"><div className="eng-card__body"><small>Exact values discovered</small><b className="eng-figure" style={{display:"block",fontSize:24,marginTop:4}}>{data.values.length}</b><span style={{fontSize:12,color:"var(--eng-ink-meta)"}}>HubSpot IDs preserved</span></div></div>
   <div className="eng-card"><div className="eng-card__body"><small>Changes to review</small><b className="eng-figure" style={{display:"block",fontSize:24,marginTop:4}}>{changes?.summary.open||0}</b><span style={{fontSize:12,color:"var(--eng-ink-meta)"}}>{changes?.summary.critical||0} critical · {changes?.summary.action_required||0} action required</span></div></div>
  </section>

  {!isDraft&&<div className="eng-callout eng-callout--info" style={{marginBottom:14}}><div className="eng-callout__body"><b>This Rule Data version is active and read-only.</b>Create a successor draft before changing which HubSpot data plan rules may use.</div></div>}
  {!canEdit&&<div className="eng-callout eng-callout--info" style={{marginBottom:14}}><div className="eng-callout__body"><b>View-only access</b>You can inspect Rule Data but cannot change or activate it.</div></div>}

  <section className="hubspot-rule-grid" style={{display:"grid",gridTemplateColumns:"minmax(240px,.72fr) minmax(360px,1.15fr) minmax(320px,.95fr)",gap:14,alignItems:"start"}}>
   <div className="eng-card"><div className="eng-card__head"><Database size={18}/><div><h2>1. Objects</h2><p>Enabled objects appear first.</p></div></div><div className="eng-card__body"><div style={{position:"relative",marginBottom:10}}><Search size={15} style={{position:"absolute",left:10,top:11,color:"var(--eng-ink-faint)"}}/><input className="eng-input" value={objectSearch} onChange={e=>setObjectSearch(e.target.value)} placeholder="Search objects" style={{paddingLeft:32}}/></div><div style={{display:"grid",gap:7}}>{sortedObjects.map(o=><button key={o.object_type} onClick={()=>{setSelectedObject(o.object_type);setSelectedField("");setFieldSearch("");setValueSearch("")}} style={{textAlign:"left",border:selectedObject===o.object_type?"2px solid var(--eng-blue)":"1px solid var(--eng-border)",background:selectedObject===o.object_type?"var(--eng-blue-tint)":"var(--eng-surface)",borderRadius:10,padding:10,cursor:"pointer",color:"var(--eng-ink)"}}><div style={{display:"flex",justifyContent:"space-between",gap:8,alignItems:"center"}}><b>{o.display_name}</b><ChevronRight size={15}/></div><code className="eng-ident">{o.hubspot_object_type||o.object_type}</code><label style={{display:"flex",gap:6,alignItems:"center",marginTop:8,fontSize:12,fontWeight:700}} onClick={e=>e.stopPropagation()}><input type="checkbox" checked={o.eligible} disabled={!canEdit||!isDraft||busy} onChange={e=>beginChange({mapping_version_id:data.mapping_version.id,level:"object",object_type:o.object_type,is_eligible:e.target.checked})}/> Enabled for plan rules</label></button>)}</div></div></div>

   <div className="eng-card"><div className="eng-card__head"><div><h2>2. Fields {object?`in ${object.display_name}`:""}</h2><p>Enable only the properties plan designers should be able to select.</p></div></div><div className="eng-card__body"><div style={{position:"relative",marginBottom:10}}><Search size={15} style={{position:"absolute",left:10,top:11,color:"var(--eng-ink-faint)"}}/><input className="eng-input" value={fieldSearch} onChange={e=>setFieldSearch(e.target.value)} placeholder="Search field name or HubSpot property" style={{paddingLeft:32}}/></div><div style={{display:"grid",gap:8,maxHeight:660,overflow:"auto"}}>{fields.map(f=><div key={f.property_name} style={{border:selectedField===f.property_name?"2px solid var(--eng-blue)":"1px solid var(--eng-border-soft)",borderRadius:10,padding:11,background:selectedField===f.property_name?"var(--eng-blue-tint)":"var(--eng-surface)"}}><div style={{display:"flex",justifyContent:"space-between",gap:10,alignItems:"flex-start"}}><button onClick={()=>{setSelectedField(f.property_name);setValueSearch("")}} style={{border:0,background:"transparent",padding:0,textAlign:"left",cursor:"pointer",flex:1,color:"var(--eng-ink)"}}><b>{f.display_name}</b><div><code className="eng-ident">{f.property_name}</code> <span style={{fontSize:11,color:"var(--eng-ink-faint)"}}>· {f.data_type}</span></div></button><label style={{fontSize:12,fontWeight:700,display:"flex",gap:6,alignItems:"center",whiteSpace:"nowrap"}}><input type="checkbox" checked={f.eligible} disabled={!canEdit||!isDraft||busy} onChange={e=>beginChange({mapping_version_id:data.mapping_version.id,level:"field",object_type:f.object_type,property_name:f.property_name,is_eligible:e.target.checked,value_policy:f.value_policy})}/> Enabled</label></div>{f.eligible&&<div style={{display:"flex",gap:14,marginTop:9,fontSize:12,flexWrap:"wrap"}}><label><input type="radio" checked={f.value_policy==="all"} disabled={!canEdit||!isDraft||busy} onChange={()=>beginChange({mapping_version_id:data.mapping_version.id,level:"field",object_type:f.object_type,property_name:f.property_name,is_eligible:true,value_policy:"all"})}/> All HubSpot values</label><label><input type="radio" checked={f.value_policy==="selected"} disabled={!canEdit||!isDraft||busy} onChange={()=>{setSelectedField(f.property_name);beginChange({mapping_version_id:data.mapping_version.id,level:"field",object_type:f.object_type,property_name:f.property_name,is_eligible:true,value_policy:"selected"})}}/> Selected values only</label></div>}</div>)}</div></div></div>

   <div className="eng-card"><div className="eng-card__head"><div><h2>3. Values</h2><p>Limit discrete values only when a field requires it.</p></div></div><div className="eng-card__body">{!field?<div className="eng-empty eng-empty--inline"><p>Select a field to inspect its available HubSpot values.</p></div>:field.value_policy!=="selected"?<div className="eng-callout eng-callout--info"><div className="eng-callout__body"><b>{field.display_name}</b>All values are currently available to plan rules. Newly discovered HubSpot values will be detected by configuration monitoring.</div></div>:<><div style={{position:"relative",marginBottom:12}}><Search size={15} style={{position:"absolute",left:10,top:11,color:"var(--eng-ink-faint)"}}/><input className="eng-input" value={valueSearch} onChange={e=>setValueSearch(e.target.value)} placeholder="Search values or IDs" style={{paddingLeft:32}}/></div>{values.length===0?<div className="eng-empty eng-empty--inline"><p>No discrete HubSpot values match this field or search.</p></div>:<div style={{maxHeight:620,overflow:"auto",display:"grid",gap:12}}>{groups.map(([group,items])=><div key={group}><div style={{fontSize:11,fontWeight:700,textTransform:"uppercase",letterSpacing:.6,color:"var(--eng-ink-meta)",marginBottom:5}}>{group}</div><div style={{display:"grid",gap:5}}>{items.map(v=><label key={`${v.hubspot_value}-${JSON.stringify(v.context)}`} style={{display:"flex",gap:8,alignItems:"flex-start",padding:"7px 8px",border:"1px solid var(--eng-border-soft)",borderRadius:8,cursor:canEdit&&isDraft?"pointer":"default",background:v.eligible?"var(--eng-blue-tint)":"var(--eng-surface)"}}><input type="checkbox" checked={v.eligible} disabled={!canEdit||!isDraft||busy} onChange={e=>beginChange({mapping_version_id:data.mapping_version.id,level:"value",object_type:v.object_type,property_name:v.property_name,hubspot_value:v.hubspot_value,context:v.context,is_eligible:e.target.checked,value_policy:"selected"})}/><span><b style={{fontSize:13}}>{v.display_label}</b><code className="eng-ident" style={{display:"block",marginTop:2}}>{v.hubspot_value}</code></span></label>)}</div></div>)}</div>}</>}</div></div>
  </section>

  {pending&&<section className="eng-card eng-card--warn" style={{marginTop:14}}><div className="eng-card__body"><div style={{display:"flex",gap:10,alignItems:"flex-start"}}><ShieldAlert size={22}/><div style={{flex:1}}><h2 style={{fontSize:18,margin:"0 0 4px"}}>Review impact before changing Rule Data</h2><p style={{margin:"0 0 12px",color:"var(--eng-ink-meta)"}}>The checkbox is not changed yet. Review the downstream impact, then apply or cancel. Risk: <b>{riskLabel(pending.impact.risk)}</b>.</p><div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(145px,1fr))",gap:8,marginBottom:12}}>{[["Rule sets",pending.impact.affected_rule_sets],["Active rules",pending.impact.affected_active_rule_sets],["Current earnings",pending.impact.affected_current_earnings],["Approved unpaid",pending.impact.approved_unpaid_earnings],["Paid earnings",pending.impact.paid_earnings]].map(([k,v])=><div key={String(k)} className="eng-card"><div className="eng-card__body" style={{padding:9}}><small>{k}</small><b className="eng-figure" style={{display:"block",fontSize:20}}>{Number(v)}</b></div></div>)}</div>{pending.impact.requires_explicit_resolution&&<label style={{display:"block",fontSize:13,fontWeight:700,marginBottom:12}}>How should this be addressed?<select className="eng-input" value={resolution} onChange={e=>setResolution(e.target.value)} style={{display:"block",maxWidth:520,marginTop:5}}><option value="">Choose a resolution…</option>{pending.impact.resolution_options.filter(x=>x!=="cancel_change").map(x=><option key={x} value={x}>{resolutionLabel(x)}</option>)}</select></label>}<div style={{display:"flex",gap:8}}><button className="eng-btn" onClick={()=>{setPending(null);setResolution("")}}>Cancel</button><button className="eng-btn eng-btn--primary" onClick={applyPending} disabled={busy}>Apply to draft Rule Data</button></div></div></div></div></section>}

  <section className="eng-card" style={{marginTop:14}}><div className="eng-card__head"><div><h2>HubSpot configuration changes</h2><p>Changes discovered in HubSpot stay here until a permissioned administrator reviews them.</p></div>{(changes?.summary.open||0)===0&&<span className="eng-badge eng-badge--success"><CheckCircle2 size={12}/>No open changes</span>}</div><div className="eng-card__body">{(changes?.changes||[]).length===0?<div className="eng-empty eng-empty--inline"><p>No HubSpot configuration changes need review.</p></div>:<div style={{display:"grid",gap:8}}>{changes!.changes.map(c=><div key={c.id} style={{border:"1px solid var(--eng-border-soft)",borderRadius:10,padding:11,display:"grid",gridTemplateColumns:"minmax(240px,1fr) 140px minmax(220px,.8fr)",gap:12,alignItems:"center"}}><div><div style={{display:"flex",gap:7,alignItems:"center"}}><AlertTriangle size={15}/><b>{riskLabel(c.change_type)} · {c.object_type}{c.property_name?` / ${c.property_name}`:""}</b></div>{c.hubspot_value&&<code className="eng-ident">Value: {c.hubspot_value}</code>}</div><span className={`eng-badge ${c.severity==="critical"?"eng-badge--danger":c.severity==="action_required"?"eng-badge--warn":"eng-badge--neutral"}`}>{riskLabel(c.severity)}</span>{canEdit?<div style={{display:"flex",gap:6}}><select className="eng-input" value={changeResolution[c.id]||""} onChange={e=>setChangeResolution(x=>({...x,[c.id]:e.target.value}))}><option value="">Resolution…</option>{["acknowledge","update_mapping","create_successor_mapping","future_only","grandfather_existing","send_to_review","ignore"].map(x=><option key={x} value={x}>{resolutionLabel(x)}</option>)}</select><button className="eng-btn" onClick={()=>resolveChange(c.id)} disabled={busy}>Resolve</button></div>:<span style={{fontSize:12,color:"var(--eng-ink-meta)"}}>View only</span>}</div>)}</div>}</div></section>
  <style jsx>{`@media(max-width:1100px){.hubspot-rule-grid{grid-template-columns:1fr!important}}`}</style>
 </div></main>;
}