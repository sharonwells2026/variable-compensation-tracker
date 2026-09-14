"use client";

import {FormEvent,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,ChevronRight,Save} from "lucide-react";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Version={version_id:string;version_number:number;status:string};
type Plan={plan_id:string;name:string;versions:Version[]};

function slug(value:string){
  return value.toUpperCase().trim().replace(/[^A-Z0-9]+/g,"_").replace(/^_+|_+$/g,"").slice(0,80);
}

export default function NewEarningTypePage(){
  const router=useRouter();
  const[versionId,setVersionId]=useState("");
  const[plans,setPlans]=useState<Plan[]>([]);
  const[name,setName]=useState("");
  const[code,setCode]=useState("");
  const[codeTouched,setCodeTouched]=useState(false);
  const[description,setDescription]=useState("");
  const[loading,setLoading]=useState(true);
  const[saving,setSaving]=useState(false);
  const[error,setError]=useState("");

  useEffect(()=>{
    const requested=new URLSearchParams(window.location.search).get("version")||"";
    setVersionId(requested);
    (async()=>{
      const{data,error:rpcError}=await supabase.rpc("get_compensation_plan_admin_data");
      if(rpcError)setError(rpcError.message);
      else setPlans((data?.plans||[]) as Plan[]);
      setLoading(false);
    })();
  },[]);

  const plan=useMemo(()=>plans.find(p=>p.versions.some(v=>v.version_id===versionId))||null,[plans,versionId]);
  const version=plan?.versions.find(v=>v.version_id===versionId)||null;

  const submit=async(e:FormEvent)=>{
    e.preventDefault();
    if(!versionId){setError("A draft plan version is required.");return;}
    if(version?.status!=="draft"){setError("Only a draft plan can be edited.");return;}
    if(!name.trim()||!code.trim()){setError("Name and code are required.");return;}
    setSaving(true);setError("");
    const{data,error:rpcError}=await supabase.rpc("save_compensation_plan_component",{
      selected_plan_version_id:versionId,
      selected_component_id:null,
      selected_name:name.trim(),
      selected_component_code:code.trim(),
      selected_description:description.trim()||null,
      selected_calculation_type:"percentage",
      selected_measurement_source:"amount",
      selected_measurement_period:"per_deal",
      selected_calculation_order:1,
      selected_rule_configuration:{},
      selected_maximum_payout:null,
      selected_is_active:true,
      selected_payout_timing_method:"annual",
      selected_allow_manager_payout_override:true,
      selected_measurement_label:null
    });
    setSaving(false);
    if(rpcError){setError(rpcError.message);return;}
    const id=String(data?.component_id||"");
    if(!id){setError("The Earning Type was created but could not be opened. Return to the plan and try again.");return;}
    router.push(`/plans/component/${id}?version=${versionId}&setup=1`);
  };

  if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Loading plan…</div></div></main>;

  return <main className="plan-workspace"><div className="plan-page-shell">
    <div className="plan-breadcrumb">
      <Link href={versionId?`/plans/manage/${versionId}`:"/plans"}><ArrowLeft size={15}/>Plan setup</Link><span>/</span><span>Add Earning Type</span>
    </div>
    <header className="plan-page-header"><div>
      <span className="plan-kicker">EARNING TYPE SETUP</span>
      <h1>Add an Earning Type</h1>
      <p>Give this earning a recognizable name first. On the next screen you will configure what it pays, when it is Earned, and when it becomes Eligible for payment.</p>
    </div>{version&&<span className="plan-status draft">Draft v{version.version_number}</span>}</header>

    {error&&<div className="plan-alert error">{error}</div>}
    <form className="plan-editor-card" onSubmit={submit}>
      <div className="plan-editor-heading"><div><span className="plan-step-number">1</span><div><h2>Name the Earning Type</h2><p>This creates the draft Earning Type so all of its rule builders are available immediately on the next screen.</p></div></div></div>
      <div className="plan-form-grid two">
        <label>Earning Type name *<input value={name} onChange={e=>{const value=e.target.value;setName(value);if(!codeTouched)setCode(slug(value))}} placeholder="e.g. New Business Commission" required/><small>Use the name employees should see on their compensation statements.</small></label>
        <label>Earning Type code *<input value={code} onChange={e=>{setCodeTouched(true);setCode(slug(e.target.value))}} required/><small>Generated from the name. Change it only when you need a specific internal code.</small></label>
      </div>
      <label className="plan-full-field">Description<textarea rows={2} value={description} onChange={e=>setDescription(e.target.value)} placeholder="Optional plain-language description"/></label>
      <div className="plan-info-row"><ChevronRight size={16}/><span>Next: configure payout → Earned conditions → payment conditions. You will not need to save a partial payout just to unlock the rule builders.</span></div>
      <div className="plan-actions"><Link href={versionId?`/plans/manage/${versionId}`:"/plans"} className="plan-button secondary">Cancel</Link><button className="plan-button primary" disabled={saving||!versionId||version?.status!=="draft"} type="submit"><Save size={15}/>{saving?"Creating…":"Create & continue"}</button></div>
    </form>
  </div></main>;
}
