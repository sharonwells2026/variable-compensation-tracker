"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useParams,useSearchParams} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,CalendarClock,CheckCircle2,ExternalLink,Save} from "lucide-react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");

type RuleSet={id:string;plan_component_id:string;name:string;purpose:string;version:number;is_active:boolean};
type Component={component_id:string;name:string;rule_configuration:any;additional_eligibility_waiting_days:number|null};
type Version={version_id:string;version_number:number;status:string;components:Component[]};
type Plan={plan_id:string;name:string;versions:Version[]};
type Mode="immediate"|"waiting_period"|"customer_payment"|"rule";

function currentMode(c:Component|null):Mode{
 const e=c?.rule_configuration?.eligibility;
 if(e?.business_concept==="customer_payment_received")return "customer_payment";
 if(e?.mode==="waiting_period"||e?.mode==="rule"||e?.mode==="immediate")return e.mode;
 return "immediate";
}

export default function PaymentConditionPage(){
 const params=useParams<{componentId:string}>();const search=useSearchParams();
 const[plans,setPlans]=useState<Plan[]>([]),[rules,setRules]=useState<RuleSet[]>([]),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 const[mode,setMode]=useState<Mode>("immediate"),[waitingDays,setWaitingDays]=useState("0"),[ruleSetId,setRuleSetId]=useState("");

 async function load(){
  setLoading(true);setError("");
  const [planData,catalog]=await Promise.all([
    supabase.rpc("get_compensation_plan_admin_data"),
    supabase.rpc("get_comp_rule_builder_catalog",{target_plan_component_id:params.componentId})
  ]);
  if(planData.error){setError(planData.error.message);setLoading(false);return}
  if(catalog.error){setError(catalog.error.message);setLoading(false);return}
  const ps=(planData.data?.plans||[]) as Plan[];setPlans(ps);
  setRules(((catalog.data?.rule_sets||[]) as RuleSet[]).filter(r=>r.purpose==="eligibility"));
  for(const p of ps)for(const v of p.versions){const c=v.components.find(x=>x.component_id===params.componentId);if(c){const m=currentMode(c);setMode(m);setWaitingDays(String(c.rule_configuration?.eligibility?.waiting_days??c.additional_eligibility_waiting_days??0));setRuleSetId(search.get("ruleSet")||c.rule_configuration?.eligibility?.rule_set_id||"");}}
  setLoading(false);
 }
 useEffect(()=>{void load()},[params.componentId]);

 const found=useMemo(()=>{for(const p of plans)for(const v of p.versions){const c=v.components.find(x=>x.component_id===params.componentId);if(c)return{plan:p,version:v,component:c}}return null},[plans,params.componentId]);
 const editable=found?.version.status==="draft";
 const builderHref=()=>{const q=new URLSearchParams();if(ruleSetId)q.set("ruleSet",ruleSetId);else{q.set("component",params.componentId);q.set("purpose","eligibility")}q.set("returnTo",`/plans/component/${params.componentId}/payment-condition`);return `/plans/rules?${q.toString()}`};

 const save=async()=>{
  if(!editable){setError("Only draft plan versions can have payment conditions edited.");return}
  if(mode==="rule"&&!ruleSetId){setError("Create or select a custom payment rule first.");return}
  setSaving(true);setError("");setMessage("");
  const{data,error:e}=await supabase.rpc("save_compensation_plan_component_eligibility",{
    selected_component_id:params.componentId,
    selected_mode:mode,
    selected_waiting_days:mode==="waiting_period"?Number(waitingDays||0):null,
    selected_rule_set_id:mode==="rule"?ruleSetId:null,
    selected_description:mode==="customer_payment"?"Invoice Paid Date is known":mode==="waiting_period"?`Eligible ${Number(waitingDays||0)} days after earned`:mode==="immediate"?"Eligible immediately after earned":null
  });
  setSaving(false);
  if(e){setError(e.message);return}
  if(mode==="customer_payment"&&data?.rule_set_id)setRuleSetId(String(data.rule_set_id));
  setMessage("Payment condition saved.");
  await load();
 };

 if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Loading payment condition…</div></div></main>;
 if(!found)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-alert error">Earning Type not found.</div></div></main>;

 return <main className="plan-workspace"><div className="plan-page-shell" style={{paddingBottom:90}}>
  <div className="plan-breadcrumb"><Link href={`/plans/manage/${found.version.version_id}`}><ArrowLeft size={15}/>Plan</Link><span>/</span><span>{found.component.name}</span><span>/</span><span>Payment condition</span></div>
  <header className="plan-page-header"><div><span className="plan-kicker">ELIGIBLE FOR PAYMENT</span><h1>{found.component.name}</h1><p>Define what must be true after an earning is earned before it can move into the payment process.</p></div><span className={`plan-status ${found.version.status}`}>{found.version.status} v{found.version.version_number}</span></header>
  {error&&<div className="plan-alert error">{error}</div>}{message&&<div className="plan-info-row"><CheckCircle2 size={16}/>{message}</div>}
  <section className="plan-section"><div className="plan-section-title"><div><h3>When can this earning be paid?</h3><p>Choose a common pattern or build a condition from HubSpot fields that are enabled for plan rules.</p></div></div>
   <div style={{display:"grid",gap:10}}>
    <label style={{border:"1px solid #e3e8ef",borderRadius:10,padding:14,display:"flex",gap:10,alignItems:"flex-start"}}><input type="radio" name="mode" checked={mode==="immediate"} disabled={!editable} onChange={()=>setMode("immediate")}/><span><b>Immediately after it is earned</b><small style={{display:"block",color:"#667085",marginTop:3}}>No additional payment condition.</small></span></label>
    <label style={{border:"1px solid #e3e8ef",borderRadius:10,padding:14,display:"flex",gap:10,alignItems:"flex-start"}}><input type="radio" name="mode" checked={mode==="waiting_period"} disabled={!editable} onChange={()=>setMode("waiting_period")}/><span style={{width:"100%"}}><b>After a waiting period</b><small style={{display:"block",color:"#667085",marginTop:3}}>Useful when payment eligibility is based on elapsed time rather than another system field.</small>{mode==="waiting_period"&&<div style={{marginTop:10,maxWidth:220}}><label>Days after earned<input type="number" min="0" value={waitingDays} onChange={e=>setWaitingDays(e.target.value)} disabled={!editable}/></label></div>}</span></label>
    <label style={{border:"1px solid #e3e8ef",borderRadius:10,padding:14,display:"flex",gap:10,alignItems:"flex-start"}}><input type="radio" name="mode" checked={mode==="customer_payment"} disabled={!editable} onChange={()=>setMode("customer_payment")}/><span style={{width:"100%"}}><b>When the customer has paid</b><small style={{display:"block",color:"#667085",marginTop:3}}>Current configured rule: <b>Deal → Invoice Paid Date → is known</b>.</small>{mode==="customer_payment"&&ruleSetId&&<Link href={builderHref()} className="plan-button secondary" style={{marginTop:10,display:"inline-flex"}}>Edit this rule <ExternalLink size={13}/></Link>}</span></label>
    <label style={{border:"1px solid #e3e8ef",borderRadius:10,padding:14,display:"flex",gap:10,alignItems:"flex-start"}}><input type="radio" name="mode" checked={mode==="rule"} disabled={!editable} onChange={()=>setMode("rule")}/><span style={{width:"100%"}}><b>Custom rule or condition</b><small style={{display:"block",color:"#667085",marginTop:3}}>Use any HubSpot field/value enabled for plan rules, with AND/OR/NOT logic just like Earned conditions.</small>{mode==="rule"&&<div style={{marginTop:10,display:"flex",gap:10,alignItems:"center",flexWrap:"wrap"}}><select value={ruleSetId} onChange={e=>setRuleSetId(e.target.value)} disabled={!editable} style={{minWidth:260}}><option value="">Choose saved rule</option>{rules.map(r=><option key={r.id} value={r.id}>{r.name} · v{r.version}</option>)}</select><Link href={builderHref()} className="plan-button secondary">{ruleSetId?"Edit rule":"Build rule"} <ExternalLink size={13}/></Link></div>}</span></label>
   </div>
   <div className="plan-info-row" style={{marginTop:16}}><CalendarClock size={16}/><span>HubSpot fields must first be enabled under <Link href="/settings/hubspot-mapping"><b>Settings → HubSpot Rule Data</b></Link>. Enabling a field there only makes it available to plan conditions; it does not change compensation by itself.</span></div>
   {editable&&<div style={{display:"flex",justifyContent:"flex-end",marginTop:18}}><button className="plan-button brand" type="button" disabled={saving} onClick={()=>void save()}><Save size={14}/>{saving?"Saving…":"Save payment condition"}</button></div>}
  </section>
 </div></main>;
}
