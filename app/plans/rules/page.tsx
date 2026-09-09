"use client";

import {useEffect,useMemo,useRef,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,ArrowLeft,Braces,Eye,ExternalLink,Plus,Save,Trash2} from "lucide-react";
import ValueEditor,{RuleFieldOption} from "./value-editor";
import {hydrateExpression,hydrateRules,SavedRuleSet} from "./rule-hydration";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Obj={object_type:string;display_name:string;description?:string};
type Field={object_type:string;property_name:string;display_name:string;data_type:string;description?:string;options?:RuleFieldOption[];is_multi_value?:boolean};
type Op={operator_key:string;display_name:string;value_arity:string;supported_data_types:string[];description?:string};
type Comp={component_id:string;name:string;component_code:string};
type Plan={name:string;versions:{status:string;components:Comp[]}[]};
type Rule={id:string;key:string;name:string;objectType:string;property:string;operator:string;value:string;quantifier:"record"|"any"|"all"|"none";caseSensitive:boolean;includeNull:boolean};
type RuleNode={id:string;type:"rule";ruleId:string;negate:boolean};
type GroupNode={id:string;type:"group";op:"AND"|"OR";negate:boolean;children:(RuleNode|GroupNode)[]};
type Node=RuleNode|GroupNode;
type PreviewSample={hubspot_deal_id:string;deal_name:string;close_date:string|null;deal_type:string|null;amount:number|null;stage_id:string|null;owner_id:string|null;record_url:string|null};
type Preview={supported:boolean;reason?:string;unsupported_predicates?:number;scanned_count?:number;matched_count?:number;sample_count?:number;samples?:PreviewSample[]};

const uid=()=>Math.random().toString(36).slice(2,10);
const box={background:"white",border:"1px solid #dfe6ee",borderRadius:12,padding:14} as const;
const inputStyle={width:"100%",padding:"8px 9px",border:"1px solid #cad5df",borderRadius:7,background:"white",boxSizing:"border-box" as const};
const actionButton={background:"white",color:"#051b34",border:"1px solid #bac8d5",borderRadius:9,padding:"10px 14px",fontWeight:800,cursor:"pointer"} as const;
function money(v:number|null|undefined){return v==null?"—":new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(v))}

function blankRule(n:number):Rule{
  return {id:uid(),key:`rule_${n}`,name:`Rule ${n}`,objectType:"deal",property:"dealtype",operator:"is",value:"",quantifier:"record",caseSensitive:false,includeNull:false};
}
function nextRuleNumber(rules:Rule[]){
  const used=rules.map(r=>Number(r.key.match(/(\d+)$/)?.[1]||r.name.match(/(\d+)$/)?.[1]||0));
  return Math.max(0,...used)+1;
}
function expressionText(node:Node,rules:Rule[]):string{
  if(node.type==="rule"){
    const r=rules.find(x=>x.id===node.ruleId);
    return `${node.negate?"NOT ":""}${r?.name||"Unassigned rule"}`;
  }
  const inner=node.children.map(x=>expressionText(x,rules)).join(` ${node.op} `)||"(empty)";
  return `${node.negate?"NOT ":""}(${inner})`;
}
function comparisonValue(value:string,arity:string|undefined){
  if(arity==="none")return null;
  if(arity==="multiple")return value.includes("\u001f")?value.split("\u001f").filter(Boolean):value.split(",").map(x=>x.trim()).filter(Boolean);
  if(arity==="range"){
    const [low,high]=value.split("\u001f");
    return {low:low||null,high:high||null};
  }
  return value;
}

function GroupEditor({node,rules,onChange,isRoot=false}:{node:GroupNode;rules:Rule[];onChange:(n:GroupNode)=>void;isRoot?:boolean}){
  const patchChild=(id:string,next:Node)=>onChange({...node,children:node.children.map(c=>c.id===id?next:c)});
  const remove=(id:string)=>onChange({...node,children:node.children.filter(c=>c.id!==id)});
  return <div style={{border:"1px solid #d7e1eb",borderRadius:10,padding:12,background:isRoot?"#f8fbfe":"white",marginTop:8}}>
    <div style={{display:"flex",gap:8,alignItems:"center",flexWrap:"wrap"}}>
      <b>{isRoot?"Logic group":"Nested group"}</b>
      <select value={node.op} onChange={e=>onChange({...node,op:e.target.value as "AND"|"OR"})} style={{...inputStyle,maxWidth:180}}><option>AND</option><option>OR</option></select>
      <label style={{fontSize:13}}><input type="checkbox" checked={node.negate} onChange={e=>onChange({...node,negate:e.target.checked})}/> Exclude this entire group (NOT)</label>
      <button type="button" onClick={()=>onChange({...node,children:[...node.children,{id:uid(),type:"rule",ruleId:rules[0]?.id||"",negate:false}]})} style={actionButton}>+ Add condition</button>
      <button type="button" onClick={()=>onChange({...node,children:[...node.children,{id:uid(),type:"group",op:"AND",negate:false,children:[]}]})} style={actionButton}>+ Add nested group</button>
    </div>
    {node.children.map(child=>child.type==="group"?
      <div key={child.id} style={{marginLeft:18}}>
        <GroupEditor node={child} rules={rules} onChange={n=>patchChild(child.id,n)}/>
        <button type="button" onClick={()=>remove(child.id)} style={{fontSize:12,marginTop:5}}>Remove group</button>
      </div>:
      <div key={child.id} style={{display:"grid",gridTemplateColumns:"54px minmax(220px,1fr) 130px 36px",gap:8,alignItems:"center",padding:"10px 0 0 18px"}}>
        <span style={{fontWeight:800,color:"#647184"}}>{node.op}</span>
        <select value={child.ruleId} onChange={e=>patchChild(child.id,{...child,ruleId:e.target.value})} style={inputStyle}>{rules.map(r=><option key={r.id} value={r.id}>{r.name}</option>)}</select>
        <label style={{fontSize:13}}><input type="checkbox" checked={child.negate} onChange={e=>patchChild(child.id,{...child,negate:e.target.checked})}/> Exclude (NOT)</label>
        <button type="button" onClick={()=>remove(child.id)} aria-label="remove"><Trash2 size={14}/></button>
      </div>
    )}
  </div>;
}

export default function RuleBuilder(){
  const[plans,setPlans]=useState<Plan[]>([]);
  const[objects,setObjects]=useState<Obj[]>([]);
  const[fields,setFields]=useState<Field[]>([]);
  const[ops,setOps]=useState<Op[]>([]);
  const[component,setComponent]=useState("");
  const[name,setName]=useState("Qualification rules");
  const[purpose,setPurpose]=useState("qualification");
  const[rules,setRules]=useState<Rule[]>([blankRule(1)]);
  const[root,setRoot]=useState<GroupNode>({id:"root",type:"group",op:"AND",negate:false,children:[]});
  const[message,setMessage]=useState("");
  const[error,setError]=useState("");
  const[editingRuleSetId,setEditingRuleSetId]=useState<string|null>(null);
  const[savedRuleSetId,setSavedRuleSetId]=useState<string|null>(null);
  const[readOnly,setReadOnly]=useState(false);
  const[versionLabel,setVersionLabel]=useState<number|null>(null);
  const[loadingExisting,setLoadingExisting]=useState(false);
  const[preview,setPreview]=useState<Preview|null>(null);
  const[previewing,setPreviewing]=useState(false);
  const[dirty,setDirty]=useState(false);
  const[pendingHref,setPendingHref]=useState<string|null>(null);
  const[navigationPrompt,setNavigationPrompt]=useState(false);
  const previewRef=useRef<HTMLElement|null>(null);

  useEffect(()=>{(async()=>{
    setError("");
    const requested=typeof window!=="undefined"?new URLSearchParams(window.location.search).get("ruleSet"):null;
    const[p,c]=await Promise.all([
      supabase.rpc("get_compensation_plan_admin_data"),
      supabase.rpc("get_comp_rule_builder_catalog",{target_plan_component_id:null})
    ]);
    if(!p.error){
      const ps=(p.data?.plans||[]) as Plan[];
      setPlans(ps);
      if(!requested){const first=ps.flatMap(x=>x.versions.flatMap(v=>v.components))[0];if(first)setComponent(first.component_id);}
    }
    if(c.error)setError(c.error.message);
    else{setObjects(c.data?.objects||[]);setFields(c.data?.fields||[]);setOps(c.data?.operators||[]);}

    if(requested){
      setLoadingExisting(true);
      const loaded=await supabase.rpc("get_comp_rule_set_for_editing",{target_rule_set_id:requested});
      if(loaded.error)setError(loaded.error.message);
      else if(loaded.data){
        const saved=loaded.data as SavedRuleSet;
        setEditingRuleSetId(saved.id);
        setSavedRuleSetId(saved.id);
        setComponent(saved.plan_component_id);
        setName(saved.name);
        setPurpose(saved.purpose);
        setRules(hydrateRules(saved) as Rule[]);
        setRoot(hydrateExpression(saved) as GroupNode);
        setReadOnly(!!saved.is_active);
        setVersionLabel(saved.version);
        setDirty(false);
        setMessage(saved.is_active?`Version ${saved.version} is active and read-only. Create a new version from Rule Sets & Versions to change it.`:`Version ${saved.version} loaded for editing.`);
      }
      setLoadingExisting(false);
    }
  })()},[]);

  useEffect(()=>{
    const beforeUnload=(e:BeforeUnloadEvent)=>{if(!dirty)return;e.preventDefault();e.returnValue=""};
    const click=(e:MouseEvent)=>{
      if(!dirty||readOnly||e.defaultPrevented||e.button!==0||e.metaKey||e.ctrlKey||e.shiftKey||e.altKey)return;
      const target=e.target as HTMLElement|null;
      const anchor=target?.closest("a") as HTMLAnchorElement|null;
      if(!anchor||anchor.target==="_blank"||!anchor.href)return;
      const url=new URL(anchor.href,window.location.href);
      if(url.origin!==window.location.origin)return;
      e.preventDefault();setPendingHref(url.pathname+url.search+url.hash);setNavigationPrompt(true);
    };
    window.addEventListener("beforeunload",beforeUnload);
    document.addEventListener("click",click,true);
    return()=>{window.removeEventListener("beforeunload",beforeUnload);document.removeEventListener("click",click,true)};
  },[dirty,readOnly]);

  const components=useMemo(()=>plans.flatMap(p=>p.versions.flatMap(v=>v.components.map(c=>({...c,plan:p.name,status:v.status})))),[plans]);
  const markDirty=()=>{if(readOnly)return;setDirty(true);setPreview(null);setSavedRuleSetId(null);setMessage("")};
  const updateRule=(id:string,patch:Partial<Rule>)=>{markDirty();setRules(rs=>rs.map(r=>r.id===id?{...r,...patch}:r))};
  const updateRoot=(next:GroupNode)=>{markDirty();setRoot(next)};
  const addRule=()=>{
    markDirty();
    const next=blankRule(nextRuleNumber(rules));
    setRules([...rules,next]);
    window.setTimeout(()=>document.getElementById(`rule-card-${next.id}`)?.scrollIntoView({behavior:"smooth",block:"center"}),50);
  };
  const removeRule=(id:string)=>{
    markDirty();
    setRules(rs=>rs.filter(r=>r.id!==id));
    const scrub=(n:GroupNode):GroupNode=>({...n,children:n.children.filter(c=>c.type!=="rule"||c.ruleId!==id).map(c=>c.type==="group"?scrub(c):c)});
    setRoot(scrub(root));
  };
  const flatten=(g:GroupNode,parent:string|null=null,out:any[]=[]):any[]=>{
    out.push({client_key:g.id,parent_client_key:parent,node_type:"group",logical_operator:g.op,negate:g.negate,sort_order:out.length});
    g.children.forEach((c,i)=>{
      if(c.type==="group")flatten(c,g.id,out);
      else out.push({client_key:c.id,parent_client_key:g.id,node_type:"predicate",predicate_client_key:c.ruleId,negate:c.negate,sort_order:i});
    });
    return out;
  };
  const buildPayload=()=>{
    const predicates=rules.map(r=>{
      const field=fields.find(f=>f.object_type===r.objectType&&f.property_name===r.property);
      const op=ops.find(o=>o.operator_key===r.operator);
      return {
        client_key:r.id,rule_key:r.key,display_name:r.name,object_type:r.objectType,property_name:r.property,
        operator_key:r.operator,comparison_value:comparisonValue(r.value,op?.value_arity),comparison_value_type:field?.data_type||"string",
        association_path:[],association_quantifier:r.objectType==="deal"?"record":r.quantifier,
        case_sensitive:r.caseSensitive,include_null_as_match:r.includeNull
      };
    });
    return {id:editingRuleSetId||undefined,plan_component_id:component,name,purpose,evaluation_scope:"record",predicates,nodes:flatten(root)};
  };
  const validate=()=>{
    if(!component)return "Choose a plan component.";
    if(root.children.length===0)return "Add at least one condition to the logic.";
    const missing=rules.find(r=>!r.property||!r.operator);
    if(missing)return `${missing.name} needs a field and operator.`;
    const referenced=new Set<string>();
    const collect=(n:GroupNode)=>n.children.forEach(c=>c.type==="rule"?referenced.add(c.ruleId):collect(c));
    collect(root);
    const unused=rules.find(r=>!referenced.has(r.id));
    if(unused)return `${unused.name} is defined but is not used in the logic. Add it to the logic or remove it.`;
    return null;
  };
  const save=async()=>{
    if(readOnly){setError("Active rule versions are read-only. Create a new inactive version before editing.");return null}
    setError("");setMessage("");setPreview(null);
    const problem=validate();if(problem){setError(problem);return null}
    const{data:id,error:e}=await supabase.rpc("save_comp_rule_set",{payload:buildPayload()});
    if(e){setError(e.message);return null}
    const saved=String(id);
    setEditingRuleSetId(saved);setSavedRuleSetId(saved);setDirty(false);
    if(typeof window!=="undefined")window.history.replaceState(null,"",`/plans/rules?ruleSet=${saved}`);
    setMessage(`${versionLabel?`Version ${versionLabel} `:"Rule set "}saved. Preview it against HubSpot before activation.`);
    return saved;
  };
  const runPreview=async()=>{
    setError("");setPreview(null);setPreviewing(true);
    let id=savedRuleSetId;
    if(!id)id=await save();
    if(!id){setPreviewing(false);return}
    const{data:result,error:e}=await supabase.rpc("preview_comp_rule_set",{target_rule_set_id:id,max_results:25});
    if(e)setError(e.message);else{
      setPreview((result||null) as Preview|null);
      window.setTimeout(()=>previewRef.current?.scrollIntoView({behavior:"smooth",block:"start"}),60);
    }
    setPreviewing(false);
  };
  const navigateAfterSave=async()=>{
    const href=pendingHref;
    if(!href)return;
    const id=await save();
    if(id){setNavigationPrompt(false);setPendingHref(null);window.location.assign(href)}
  };
  const discardAndNavigate=()=>{
    const href=pendingHref;if(!href)return;
    setDirty(false);setNavigationPrompt(false);setPendingHref(null);
    window.setTimeout(()=>window.location.assign(href),0);
  };

  return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}>
    <div style={{maxWidth:1380,margin:"0 auto"}}>
      <Link href="/plans" style={{color:"#647184",fontWeight:700,textDecoration:"none",display:"inline-flex",gap:5,alignItems:"center"}}><ArrowLeft size={15}/> Plans</Link>
      <div style={{display:"flex",justifyContent:"space-between",gap:16,alignItems:"start",margin:"12px 0 18px",flexWrap:"wrap"}}>
        <div><small style={{fontWeight:900,color:"#2095f3",letterSpacing:1}}>PLAN RULE ENGINE</small><h1 style={{margin:"5px 0"}}>{editingRuleSetId?readOnly?"View rule version":"Edit rule version":"Rule builder"}</h1><p style={{margin:0,color:"#647184"}}>Build qualification logic from approved HubSpot objects, fields, and values.{versionLabel?` Version ${versionLabel}.`:""}</p></div>
        <div style={{display:"flex",gap:8,alignItems:"center",flexWrap:"wrap"}}>{dirty&&<span style={{display:"inline-flex",gap:6,alignItems:"center",background:"#fff8e8",border:"1px solid #ecd79a",borderRadius:999,padding:"7px 10px",fontSize:12,fontWeight:800,color:"#8a5b00"}}><AlertTriangle size={14}/> Unsaved changes</span>}<Link href="/plans/rules/manage" style={{...actionButton,textDecoration:"none"}}>Rule versions</Link><button type="button" onClick={runPreview} disabled={previewing||loadingExisting} style={actionButton}><Eye size={16}/> {previewing?"Previewing…":"Preview matches"}</button><button type="button" onClick={save} disabled={readOnly||loadingExisting||!dirty&&!!savedRuleSetId} style={{background:readOnly?"#a8b4c0":"#2095f3",color:"white",border:0,borderRadius:9,padding:"10px 14px",fontWeight:800,cursor:readOnly?"not-allowed":"pointer"}}><Save size={16}/> {readOnly?"Active version locked":dirty?"Save changes":"Saved"}</button></div>
      </div>
      {error&&<div style={{...box,background:"#fff1f1",borderColor:"#efc7c7",marginBottom:12}}>{error}</div>}
      {message&&<div style={{...box,background:readOnly?"#fff8e8":"#edf9f2",marginBottom:12}}>{message}</div>}

      <fieldset disabled={readOnly||loadingExisting} style={{border:0,padding:0,margin:0,minWidth:0}}>
      <section style={{...box,display:"grid",gridTemplateColumns:"2fr 1fr 1fr",gap:10,marginBottom:14}}>
        <label>Plan component<select disabled={!!editingRuleSetId} value={component} onChange={e=>{markDirty();setComponent(e.target.value)}} style={{...inputStyle,display:"block",marginTop:5}}>{components.map(c=><option key={c.component_id} value={c.component_id}>{c.plan} · {c.name} ({c.status})</option>)}</select></label>
        <label>Rule-set name<input value={name} onChange={e=>{markDirty();setName(e.target.value)}} style={{...inputStyle,display:"block",marginTop:5}}/></label>
        <label>Purpose<select value={purpose} onChange={e=>{markDirty();setPurpose(e.target.value)}} style={{...inputStyle,display:"block",marginTop:5}}>{["qualification","rate_selection","calculation","eligibility","credit","payout","exception"].map(x=><option key={x}>{x}</option>)}</select></label>
      </section>

      <section style={{...box,marginBottom:14}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:12}}>
          <div><h2 style={{margin:"0 0 3px"}}>1. Define conditions</h2><small style={{color:"#647184"}}>Each condition maps to an approved HubSpot object, field, operator, and exact value.</small></div>
          <button type="button" onClick={addRule} style={actionButton}><Plus size={15}/> Add condition</button>
        </div>
        <div style={{display:"grid",gap:10,marginTop:12}}>
          {rules.map(r=>{
            const availableFields=fields.filter(f=>f.object_type===r.objectType);
            const field=availableFields.find(f=>f.property_name===r.property);
            const fieldType=field?.data_type;
            const availableOps=ops.filter(o=>!fieldType||o.supported_data_types.includes(fieldType));
            const selectedOp=ops.find(o=>o.operator_key===r.operator);
            return <div id={`rule-card-${r.id}`} key={r.id} style={{border:"1px solid #dce5ed",borderRadius:12,padding:14,scrollMarginTop:90}}>
              <div style={{display:"flex",justifyContent:"space-between",gap:10,alignItems:"center",marginBottom:10}}><div><b style={{fontSize:15}}>{r.name}</b><div style={{fontSize:11,color:"#7a8794",marginTop:2}}>Condition ID: {r.key}</div></div><button type="button" onClick={()=>removeRule(r.id)} aria-label={`Remove ${r.name}`} style={{border:"1px solid #d9e1e8",background:"white",borderRadius:8,padding:7}}><Trash2 size={15}/></button></div>
              <div style={{display:"grid",gridTemplateColumns:"150px 145px minmax(230px,1.35fr) 180px minmax(220px,1fr)",gap:10,alignItems:"start"}}>
                <label>Condition name<input value={r.name} onChange={e=>updateRule(r.id,{name:e.target.value})} style={inputStyle}/></label>
                <label>HubSpot object<select value={r.objectType} onChange={e=>updateRule(r.id,{objectType:e.target.value,property:"",value:"",quantifier:e.target.value==="deal"?"record":"any"})} style={inputStyle}>{objects.map(o=><option key={o.object_type} value={o.object_type}>{o.display_name}</option>)}</select></label>
                <label>HubSpot field<select value={r.property} onChange={e=>{const next=availableFields.find(f=>f.property_name===e.target.value);const compatible=ops.find(o=>next?.data_type&&o.supported_data_types.includes(next.data_type));updateRule(r.id,{property:e.target.value,operator:compatible?.operator_key||"is",value:""})}} style={inputStyle}><option value="">Choose field…</option>{availableFields.map(f=><option key={f.property_name} value={f.property_name}>{f.display_name}</option>)}</select>{r.property&&<code style={{display:"block",fontSize:10,color:"#7b8794",marginTop:4}}>{r.property}</code>}</label>
                <label>Operator<select value={r.operator} onChange={e=>updateRule(r.id,{operator:e.target.value,value:""})} style={inputStyle}>{availableOps.map(o=><option key={o.operator_key} value={o.operator_key}>{o.display_name}</option>)}</select></label>
                <label>Value<ValueEditor field={field} operator={selectedOp} value={r.value} onChange={value=>updateRule(r.id,{value})}/></label>
              </div>
              <div style={{display:"flex",gap:14,alignItems:"center",flexWrap:"wrap",marginTop:10,paddingTop:10,borderTop:"1px solid #edf1f4",fontSize:12,color:"#56677a"}}>
                {r.objectType!=="deal"&&<label style={{display:"inline-flex",gap:6,alignItems:"center",background:"#f4f7fa",border:"1px solid #dbe4ec",borderRadius:8,padding:"6px 8px",fontWeight:700}}>Associated records <select value={r.quantifier} onChange={e=>updateRule(r.id,{quantifier:e.target.value as Rule["quantifier"]})} style={{border:"1px solid #c9d4de",borderRadius:6,padding:"4px 6px"}}><option value="any">Any matching record</option><option value="all">All associated records</option><option value="none">No associated records</option></select></label>}
                <label><input type="checkbox" checked={r.caseSensitive} onChange={e=>updateRule(r.id,{caseSensitive:e.target.checked})}/> Case sensitive</label>
                <label><input type="checkbox" checked={r.includeNull} onChange={e=>updateRule(r.id,{includeNull:e.target.checked})}/> Treat blank as match</label>
                {field&&<span>{field.data_type}{field.is_multi_value?" · multi-value":""}{field.description?` · ${field.description}`:""}</span>}
              </div>
            </div>;
          })}
        </div>
      </section>

      <section style={{...box,marginBottom:14}}>
        <h2 style={{margin:"0 0 3px"}}>2. Combine conditions</h2>
        <small style={{color:"#647184"}}>Choose whether conditions must all match (AND), whether any may match (OR), or create nested groups. Use Exclude (NOT) only when you explicitly want the opposite of a condition.</small>
        <GroupEditor node={root} rules={rules} onChange={updateRoot} isRoot/>
      </section>
      </fieldset>

      <section style={{...box,background:"#051b34",color:"white",marginBottom:14}}>
        <div style={{display:"flex",gap:8,alignItems:"center"}}><Braces size={18}/><b>Logic summary</b></div>
        <code style={{display:"block",marginTop:10,whiteSpace:"pre-wrap",color:"#badefa"}}>{expressionText(root,rules)}</code>
        <p style={{margin:"10px 0 0",fontSize:13,color:"#c5d2df"}}>This is the exact condition structure that will be evaluated against HubSpot.</p>
      </section>

      {preview&&<section ref={previewRef} style={{...box,marginBottom:14,scrollMarginTop:90}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"start",gap:12,flexWrap:"wrap"}}><div><h2 style={{margin:"0 0 3px"}}>3. Preview matching HubSpot records</h2><small style={{color:"#647184"}}>Read-only preview. It does not create earnings or change HubSpot.</small></div>{preview.supported&&<b style={{fontSize:20}}>{preview.matched_count||0} of {preview.scanned_count||0} deals match</b>}</div>
        {!preview.supported?<div style={{marginTop:12,padding:12,background:"#fff8e8",border:"1px solid #ecd79a",borderRadius:9}}><b>Preview not yet available for this expression.</b><div style={{marginTop:4}}>{preview.reason}</div></div>:
        <div style={{marginTop:12}}>{(preview.samples||[]).length===0?<div style={{color:"#647184"}}>No current HubSpot deals match this rule set.</div>:<div style={{display:"grid",gap:7}}>{(preview.samples||[]).map(s=><div key={s.hubspot_deal_id} style={{display:"grid",gridTemplateColumns:"minmax(260px,1.5fr) 120px 135px 120px",gap:10,alignItems:"center",padding:"9px 10px",border:"1px solid #e3e9ef",borderRadius:8}}><div><b>{s.deal_name}</b><small style={{display:"block",color:"#718096"}}>{s.deal_type||"—"} · {s.close_date||"No close date"}</small></div><span>{money(s.amount)}</span><code>{s.hubspot_deal_id}</code><span>{s.record_url?<a href={s.record_url} target="_blank" rel="noreferrer" style={{display:"inline-flex",gap:4,alignItems:"center"}}>Open HubSpot <ExternalLink size={13}/></a>:"—"}</span></div>)}</div>}</div>}
      </section>}
    </div>

    {navigationPrompt&&<div role="dialog" aria-modal="true" style={{position:"fixed",inset:0,background:"rgba(5,27,52,.42)",display:"grid",placeItems:"center",padding:20,zIndex:1000}}><div style={{width:"min(520px,100%)",background:"white",borderRadius:14,padding:22,boxShadow:"0 20px 60px rgba(5,27,52,.25)"}}><div style={{display:"flex",gap:10,alignItems:"center",marginBottom:8}}><AlertTriangle size={22} color="#b7791f"/><h2 style={{margin:0,fontSize:20}}>You have unsaved changes</h2></div><p style={{color:"#647184",lineHeight:1.5,margin:"0 0 18px"}}>Save your changes before leaving this rule version, continue without saving, or stay here and keep editing.</p><div style={{display:"flex",justifyContent:"flex-end",gap:8,flexWrap:"wrap"}}><button type="button" onClick={()=>{setNavigationPrompt(false);setPendingHref(null)}} style={actionButton}>Stay here</button><button type="button" onClick={discardAndNavigate} style={{...actionButton,color:"#9b2c2c"}}>Continue without saving</button><button type="button" onClick={navigateAfterSave} style={{...actionButton,background:"#2095f3",color:"white",borderColor:"#2095f3"}}><Save size={15}/> Save & continue</button></div></div></div>}
  </main>;
}