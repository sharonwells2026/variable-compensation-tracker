"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,Braces,Eye,ExternalLink,Plus,Save,Trash2} from "lucide-react";
import ValueEditor,{RuleFieldOption} from "./value-editor";

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
const inputStyle={width:"100%",padding:"8px 9px",border:"1px solid #cad5df",borderRadius:7,background:"white"} as const;
function money(v:number|null|undefined){return v==null?"—":new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(v))}

function blankRule(n:number):Rule{
  return {id:uid(),key:`rule_${n}`,name:`Rule ${n}`,objectType:"deal",property:"dealtype",operator:"is",value:"",quantifier:"record",caseSensitive:false,includeNull:false};
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
      <b>{isRoot?"Root group":"Group"}</b>
      <select value={node.op} onChange={e=>onChange({...node,op:e.target.value as "AND"|"OR"})} style={inputStyle}><option>AND</option><option>OR</option></select>
      <label><input type="checkbox" checked={node.negate} onChange={e=>onChange({...node,negate:e.target.checked})}/> NOT this group</label>
      <button type="button" onClick={()=>onChange({...node,children:[...node.children,{id:uid(),type:"rule",ruleId:rules[0]?.id||"",negate:false}]})}>+ Rule reference</button>
      <button type="button" onClick={()=>onChange({...node,children:[...node.children,{id:uid(),type:"group",op:"AND",negate:false,children:[]}]})}>+ Group</button>
    </div>
    {node.children.map(child=>child.type==="group"?
      <div key={child.id} style={{marginLeft:18}}>
        <GroupEditor node={child} rules={rules} onChange={n=>patchChild(child.id,n)}/>
        <button type="button" onClick={()=>remove(child.id)} style={{fontSize:12}}>Remove group</button>
      </div>:
      <div key={child.id} style={{display:"flex",gap:8,alignItems:"center",padding:"9px 0 0 18px",flexWrap:"wrap"}}>
        <span style={{fontWeight:800,color:"#647184"}}>{node.op}</span>
        <select value={child.ruleId} onChange={e=>patchChild(child.id,{...child,ruleId:e.target.value})} style={inputStyle}>{rules.map(r=><option key={r.id} value={r.id}>{r.name}</option>)}</select>
        <label><input type="checkbox" checked={child.negate} onChange={e=>patchChild(child.id,{...child,negate:e.target.checked})}/> NOT</label>
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
  const[savedRuleSetId,setSavedRuleSetId]=useState<string|null>(null);
  const[preview,setPreview]=useState<Preview|null>(null);
  const[previewing,setPreviewing]=useState(false);

  useEffect(()=>{(async()=>{
    const p=await supabase.rpc("get_compensation_plan_admin_data");
    if(!p.error){
      const ps=(p.data?.plans||[]) as Plan[];
      setPlans(ps);
      const first=ps.flatMap(x=>x.versions.flatMap(v=>v.components))[0];
      if(first)setComponent(first.component_id);
    }
    const c=await supabase.rpc("get_comp_rule_builder_catalog",{target_plan_component_id:null});
    if(c.error)setError(c.error.message);
    else{
      setObjects(c.data?.objects||[]);
      setFields(c.data?.fields||[]);
      setOps(c.data?.operators||[]);
    }
  })()},[]);

  const components=useMemo(()=>plans.flatMap(p=>p.versions.flatMap(v=>v.components.map(c=>({...c,plan:p.name,status:v.status})))),[plans]);
  const markDirty=()=>{setPreview(null);setSavedRuleSetId(null)};
  const updateRule=(id:string,patch:Partial<Rule>)=>{markDirty();setRules(rs=>rs.map(r=>r.id===id?{...r,...patch}:r))};
  const updateRoot=(next:GroupNode)=>{markDirty();setRoot(next)};
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
    return {plan_component_id:component,name,purpose,evaluation_scope:"record",predicates,nodes:flatten(root)};
  };
  const validate=()=>{
    if(!component)return "Choose a plan component.";
    if(root.children.length===0)return "Add at least one rule reference to the expression.";
    const missing=rules.find(r=>!r.property||!r.operator);
    if(missing)return `${missing.name} needs a field and operator.`;
    return null;
  };
  const save=async()=>{
    setError("");setMessage("");setPreview(null);
    const problem=validate();if(problem){setError(problem);return null}
    const{data:id,error:e}=await supabase.rpc("save_comp_rule_set",{payload:buildPayload()});
    if(e){setError(e.message);return null}
    const saved=String(id);
    setSavedRuleSetId(saved);
    setMessage("Rule set saved. You can now preview it against the HubSpot snapshot before using it in a plan.");
    return saved;
  };
  const runPreview=async()=>{
    setError("");setPreview(null);setPreviewing(true);
    let id=savedRuleSetId;
    if(!id)id=await save();
    if(!id){setPreviewing(false);return}
    const{data:result,error:e}=await supabase.rpc("preview_comp_rule_set",{target_rule_set_id:id,max_results:25});
    if(e)setError(e.message);else setPreview((result||null) as Preview|null);
    setPreviewing(false);
  };

  return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}>
    <div style={{maxWidth:1380,margin:"0 auto"}}>
      <Link href="/plans" style={{color:"#647184",fontWeight:700,textDecoration:"none"}}><ArrowLeft size={15}/> Plans</Link>
      <div style={{display:"flex",justifyContent:"space-between",gap:16,alignItems:"start",margin:"12px 0 18px",flexWrap:"wrap"}}>
        <div><small style={{fontWeight:900,color:"#2095f3",letterSpacing:1}}>PLAN RULE ENGINE</small><h1 style={{margin:"5px 0"}}>Rule builder</h1><p style={{margin:0,color:"#647184"}}>HubSpot-style field filters with reusable rules and nested AND / OR / NOT logic.</p></div>
        <div style={{display:"flex",gap:8}}><button type="button" onClick={runPreview} disabled={previewing} style={{background:"white",color:"#051b34",border:"1px solid #bac8d5",borderRadius:9,padding:"10px 14px",fontWeight:800}}><Eye size={16}/> {previewing?"Previewing…":"Preview matches"}</button><button type="button" onClick={save} style={{background:"#2095f3",color:"white",border:0,borderRadius:9,padding:"10px 14px",fontWeight:800}}><Save size={16}/> Save rule set</button></div>
      </div>
      {error&&<div style={{...box,background:"#fff1f1",marginBottom:12}}>{error}</div>}
      {message&&<div style={{...box,background:"#edf9f2",marginBottom:12}}>{message}</div>}

      <section style={{...box,display:"grid",gridTemplateColumns:"2fr 1fr 1fr",gap:10,marginBottom:14}}>
        <label>Plan component<select value={component} onChange={e=>{markDirty();setComponent(e.target.value)}} style={{...inputStyle,display:"block",marginTop:5}}>{components.map(c=><option key={c.component_id} value={c.component_id}>{c.plan} · {c.name} ({c.status})</option>)}</select></label>
        <label>Rule-set name<input value={name} onChange={e=>{markDirty();setName(e.target.value)}} style={{...inputStyle,display:"block",marginTop:5}}/></label>
        <label>Purpose<select value={purpose} onChange={e=>{markDirty();setPurpose(e.target.value)}} style={{...inputStyle,display:"block",marginTop:5}}>{["qualification","rate_selection","calculation","eligibility","credit","payout","exception"].map(x=><option key={x}>{x}</option>)}</select></label>
      </section>

      <section style={{...box,marginBottom:14}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",gap:12}}>
          <div><h2 style={{margin:"0 0 3px"}}>1. Define reusable rules</h2><small style={{color:"#647184"}}>Select an object, HubSpot property, operator and value. Available operators and value controls adapt to the property type.</small></div>
          <button type="button" onClick={()=>{markDirty();setRules(r=>[...r,blankRule(r.length+1)])}}><Plus size={15}/> Add rule</button>
        </div>
        <div style={{display:"grid",gap:10,marginTop:12}}>
          {rules.map((r,i)=>{
            const availableFields=fields.filter(f=>f.object_type===r.objectType);
            const field=availableFields.find(f=>f.property_name===r.property);
            const fieldType=field?.data_type;
            const availableOps=ops.filter(o=>!fieldType||o.supported_data_types.includes(fieldType));
            const selectedOp=ops.find(o=>o.operator_key===r.operator);
            return <div key={r.id} style={{border:"1px solid #e3e9ef",borderRadius:10,padding:12}}>
              <div style={{display:"grid",gridTemplateColumns:"150px 135px minmax(210px,1.4fr) 175px minmax(180px,1fr) 36px",gap:8,alignItems:"end"}}>
                <label>Name<input value={r.name} onChange={e=>updateRule(r.id,{name:e.target.value,key:`rule_${i+1}`})} style={inputStyle}/></label>
                <label>HubSpot object<select value={r.objectType} onChange={e=>updateRule(r.id,{objectType:e.target.value,property:"",value:"",quantifier:e.target.value==="deal"?"record":"any"})} style={inputStyle}>{objects.map(o=><option key={o.object_type} value={o.object_type}>{o.display_name}</option>)}</select></label>
                <label>Field<select value={r.property} onChange={e=>{const next=availableFields.find(f=>f.property_name===e.target.value);const compatible=ops.find(o=>next?.data_type&&o.supported_data_types.includes(next.data_type));updateRule(r.id,{property:e.target.value,operator:compatible?.operator_key||"is",value:""})}} style={inputStyle}><option value="">Choose field…</option>{availableFields.map(f=><option key={f.property_name} value={f.property_name}>{f.display_name}</option>)}</select><input placeholder="or HubSpot internal property name" value={r.property} onChange={e=>updateRule(r.id,{property:e.target.value})} style={{...inputStyle,marginTop:5}}/></label>
                <label>Operator<select value={r.operator} onChange={e=>updateRule(r.id,{operator:e.target.value,value:""})} style={inputStyle}>{availableOps.map(o=><option key={o.operator_key} value={o.operator_key}>{o.display_name}</option>)}</select></label>
                <label>Value<ValueEditor field={field} operator={selectedOp} value={r.value} onChange={value=>updateRule(r.id,{value})}/></label>
                <button type="button" onClick={()=>removeRule(r.id)} aria-label={`Remove ${r.name}`}><Trash2 size={15}/></button>
              </div>
              <div style={{display:"flex",gap:16,alignItems:"center",flexWrap:"wrap",marginTop:9,fontSize:12,color:"#56677a"}}>
                {r.objectType!=="deal"&&<label>Associated records: <select value={r.quantifier} onChange={e=>updateRule(r.id,{quantifier:e.target.value as Rule["quantifier"]})}><option value="any">any match</option><option value="all">all match</option><option value="none">none match</option></select></label>}
                <label><input type="checkbox" checked={r.caseSensitive} onChange={e=>updateRule(r.id,{caseSensitive:e.target.checked})}/> Case sensitive</label>
                <label><input type="checkbox" checked={r.includeNull} onChange={e=>updateRule(r.id,{includeNull:e.target.checked})}/> Treat blank as match</label>
                {field&&<span>{field.data_type}{field.is_multi_value?" · multi-value":""}{field.description?` · ${field.description}`:""}</span>}
              </div>
            </div>;
          })}
        </div>
      </section>

      <section style={{...box,marginBottom:14}}>
        <h2 style={{margin:"0 0 3px"}}>2. Build the logic expression</h2>
        <small style={{color:"#647184"}}>Groups can be nested indefinitely, switched between AND/OR, and negated. Reuse a rule anywhere in the expression.</small>
        <GroupEditor node={root} rules={rules} onChange={updateRoot} isRoot/>
      </section>

      <section style={{...box,background:"#051b34",color:"white",marginBottom:14}}>
        <div style={{display:"flex",gap:8,alignItems:"center"}}><Braces size={18}/><b>Expression preview</b></div>
        <code style={{display:"block",marginTop:10,whiteSpace:"pre-wrap",color:"#badefa"}}>{expressionText(root,rules)}</code>
        <p style={{margin:"10px 0 0",fontSize:13,color:"#c5d2df"}}>Supports expressions such as (Rule 1 AND Rule 2) OR (Rule 1 AND NOT Rule 3), including nested NOT groups.</p>
      </section>

      {preview&&<section style={{...box,marginBottom:14}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"start",gap:12,flexWrap:"wrap"}}><div><h2 style={{margin:"0 0 3px"}}>3. Validate against HubSpot</h2><small style={{color:"#647184"}}>Read-only preview. It does not create earnings or change HubSpot.</small></div>{preview.supported&&<b style={{fontSize:20}}>{preview.matched_count||0} of {preview.scanned_count||0} deals match</b>}</div>
        {!preview.supported?<div style={{marginTop:12,padding:12,background:"#fff8e8",border:"1px solid #ecd79a",borderRadius:9}}><b>Preview not yet available for this expression.</b><div style={{marginTop:4}}>{preview.reason}</div></div>:
        <div style={{marginTop:12}}>{(preview.samples||[]).length===0?<div style={{color:"#647184"}}>No current HubSpot deals match this rule set.</div>:<div style={{display:"grid",gap:7}}>{(preview.samples||[]).map(s=><div key={s.hubspot_deal_id} style={{display:"grid",gridTemplateColumns:"minmax(260px,1.5fr) 120px 135px 120px",gap:10,alignItems:"center",padding:"9px 10px",border:"1px solid #e3e9ef",borderRadius:8}}><div><b>{s.deal_name}</b><small style={{display:"block",color:"#718096"}}>{s.deal_type||"—"} · {s.close_date||"No close date"}</small></div><span>{money(s.amount)}</span><code>{s.hubspot_deal_id}</code><span>{s.record_url?<a href={s.record_url} target="_blank" rel="noreferrer" style={{display:"inline-flex",gap:4,alignItems:"center"}}>Open HubSpot <ExternalLink size={13}/></a>:"—"}</span></div>)}</div>}</div>}
      </section>}
    </div>
  </main>;
}
