"use client";

import Link from "next/link";
import {useParams,usePathname,useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {useState} from "react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");

export default function ManagePlanLayout({children}:{children:React.ReactNode}){
  const params=useParams<{versionId:string}>();
  const pathname=usePathname();
  const router=useRouter();
  const[deleting,setDeleting]=useState(false);
  const[deleteError,setDeleteError]=useState("");
  const id=params.versionId;
  const base=`/plans/manage/${id}`;
  const items=[
    {href:base,label:"Plan setup",active:pathname===base},
    {href:`/plans/applicability/${id}`,label:"People",active:pathname===`/plans/applicability/${id}`},
    {href:`/plans/agreements/${id}`,label:"Agreements",active:pathname===`/plans/agreements/${id}`},
    {href:`${base}/approvals`,label:"Approvals",active:pathname===`${base}/approvals`},
    {href:`/plans?version=${id}`,label:"Readiness & activation",active:false},
  ];
  const deleteDraft=async()=>{
    const ok=window.confirm("Delete this unused draft plan? This is only allowed when it has no earnings or historical dependencies. Active or historical plans cannot be deleted.");
    if(!ok)return;
    setDeleting(true);setDeleteError("");
    const{error}=await supabase.rpc("delete_compensation_plan_draft",{selected_plan_version_id:id});
    setDeleting(false);
    if(error){setDeleteError("This draft could not be deleted. It may already have assignments, earnings, or historical dependencies.");return}
    router.push("/plans");router.refresh();
  };
  return <>
    <div className="plan-page-shell" style={{paddingTop:18,paddingBottom:0}}>
      <div style={{display:"flex",gap:12,alignItems:"flex-start",justifyContent:"space-between",flexWrap:"wrap",borderBottom:"1px solid var(--eng-border, #e3e8ef)",paddingBottom:10}}>
        <nav aria-label="Plan setup sections" style={{display:"flex",gap:6,alignItems:"center",flexWrap:"wrap"}}>
          {items.map(item=><Link key={item.href} href={item.href} className={`plan-button ${item.active?"primary":"secondary"}`} aria-current={item.active?"page":undefined}>{item.label}</Link>)}
        </nav>
        <button type="button" className="plan-button secondary" onClick={()=>void deleteDraft()} disabled={deleting} style={{color:"var(--eng-danger, #8b3030)",borderColor:"var(--eng-danger-border, #efcaca)"}}>{deleting?"Deleting…":"Delete unused draft"}</button>
      </div>
      {deleteError&&<div className="plan-alert error" style={{marginTop:10}}>{deleteError}</div>}
    </div>
    {children}
  </>;
}
