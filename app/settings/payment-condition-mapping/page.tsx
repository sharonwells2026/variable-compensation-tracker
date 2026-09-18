"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,Save} from "lucide-react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");
type Field={object_type:string;property_name:string;display_name:string;data_type:string};
type Operator={operator_key:string;display_name:string;value_arity:string;supported_data_types:string[]};
type Setting={business_concept:string;display_name:string;description:string|null;configuration:any};

export default function PaymentConditionMappingPage(){
 const[fields,setFields]=useState<Field[]>([]),[operators,setOperators]=useState<Operator[]>([]),[setting,setSetting]=useState<Setting|null>(null);
 const[objectType,setObjectType]=useState("deal"),[propertyName,setPropertyName]=useState(""),[operatorKey,setOperatorKey]=useState("is_known"),[label,setLabel]=useState("Customer payment received"),[description,setDescription]=useState("");
 const[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 useEffect(()=>{(async()=>{setLoading(true);setError("");const[s,c]=await Promise.all([supabase.rpc("get_comp_business_condition_settings"),supabase.rpc("get_comp_rule_builder_catalog",{target_plan_component_id:null})]);if(s.error||c.error){setError("We couldn't load the payment-condition mapping.");setLoading(false);return}const current=((s.data||[]) as Setting[]).find(x=>x.business_concept==="customer_payment_received")||null;setSetting(current);setFields((c.data?.fields||[]) as Field[]);setOperators((c.data?.operators||[]) as Operator[]);const signal=current?.configuration?.signals?.[0];if(current){setLabel(current.display_name||"Customer payment received");setDescription(current.description||"")}if(signal){setObjectType(signal.object_type||"deal");setPropertyName(signal.property_name||"");setOperatorKey(signal.operator_key||"is_known")}setLoading(false)})()},[]);
 const objectFields=useMemo(()=>fields.filter(f=>f.object_type===objectType),[fields,objectType]);
 const selectedField=objectFields.find(f=>f.property_name===propertyName);
 const validOperators=useMemo(()=>operators.filter(o=>!selectedField||o.supported_data_types.includes(selectedField.data_type)),[operators,selectedField]);
 const save=async()=>{if(!propertyName){setError("Choose the HubSpot field that represents customer payment.");return}if(!operatorKey){setError("Choose how that field indicates payment.");return}setSaving(true);setError("");setMessage("");const configuration={logic:"AND",signals:[{label:label.trim()||"Customer payment received",object_type:objectType,property_name:propertyName,operator_key:operatorKey}]};const{error:e}=await supabase.rpc("save_comp_business_condition_setting",{selected_business_concept:"customer_payment_received",selected_display_name:label.trim()||"Customer payment received",selected_description:description.trim()||null,selected_configuration:configuration});setSaving(false);if(e){setError("We couldn't save the payment mapping. Your choices are still on this page.");return}setMessage("Customer payment mapping saved. Plans that use “The customer has paid” will use this business mapping when their payment condition is configured.")};
 if(loading)return <main className="eng-page"><div className="eng-page__shell"><div className="eng-card"><div className="eng-card__body">Loading payment mapping…</div></div></div></main>;
 return <main className="eng-page"><div className="eng-page__shell">
  <nav className="eng-breadcrumb"><Link href="/settings"><ArrowLeft size={14}/>Settings</Link><span className="eng-breadcrumb__sep">/</span><span className="eng-breadcrumb__current">Payment condition mapping</span></nav>
  <header className="eng-page-header"><div className="eng-page-header__main"><span className="eng-page-header__eyebrow">COMPENSATION BUSINESS CONCEPT</span><h1>What does “customer has paid” mean?</h1><p className="eng-page-header__lede">Keep plans stable even when the HubSpot process changes. Plan administrators can choose the business concept “The customer has paid”; this setting defines which synchronized HubSpot field currently proves that payment occurred.</p></div></header>
  {error&&<div className="eng-callout eng-callout--danger"><div className="eng-callout__body">{error}</div></div>}{message&&<div className="eng-callout eng-callout--info"><div className="eng-callout__body">{message}</div></div>}
  <section className="eng-card"><div className="eng-card__body"><div className="plan-form-grid two">
   <label>Business label<input value={label} onChange={e=>setLabel(e.target.value)}/><small>This is the plain-language concept administrators see.</small></label>
   <label>HubSpot object<select value={objectType} onChange={e=>{setObjectType(e.target.value);setPropertyName("")}}><option value="deal">Deal</option><option value="company">Company</option></select></label>
   <label>Field<select value={propertyName} onChange={e=>{setPropertyName(e.target.value);const f=fields.find(x=>x.object_type===objectType&&x.property_name===e.target.value);const first=operators.find(o=>!f||o.supported_data_types.includes(f.data_type));if(first)setOperatorKey(first.operator_key)}}><option value="">Choose synchronized field…</option>{objectFields.map(f=><option key={f.property_name} value={f.property_name}>{f.display_name}</option>)}</select></label>
   <label>Payment is true when<select value={operatorKey} onChange={e=>setOperatorKey(e.target.value)}>{validOperators.map(o=><option key={o.operator_key} value={o.operator_key}>{o.display_name}</option>)}</select></label>
  </div><label className="plan-full-field">Description<textarea rows={2} value={description} onChange={e=>setDescription(e.target.value)} placeholder="Explain the current payment signal for administrators."/></label>
  <div className="eng-callout eng-callout--info" style={{marginTop:16}}><div className="eng-callout__body"><b>Current behavior</b>{setting?.configuration?.signals?.[0]?`${setting.configuration.signals[0].object_type}.${setting.configuration.signals[0].property_name} → ${setting.configuration.signals[0].operator_key}`:"No customer-payment signal is configured."}</div></div>
  <div className="plan-actions"><Link href="/settings" className="plan-button secondary">Cancel</Link><button type="button" className="plan-button brand" onClick={()=>void save()} disabled={saving}><Save size={14}/>{saving?"Saving…":"Save mapping"}</button></div>
  </div></section>
 </div></main>;
}
