"use client";

import Link from "next/link";
import {useParams,useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {useState} from "react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");

export default function ManagePlanLayout({children}:{children:React.ReactNode}){
  const params=useParams<{versionId:string}>();
  const router=useRouter();
  const[deleting,setDeleting]=useState(false);
  const[deleteError,setDeleteError]=useState("");
  const id=params.versionId;
  const base=`/plans/manage/${id}`;
  const deleteDraft=async()=>{
    const ok=window.confirm("Delete this unused draft plan? This is only allowed when it has no earnings or historical dependencies. Active or historical plans cannot be deleted.");
    if(!ok)return;
    setDeleting(true);setDeleteError("");
    const{error}=await supabase.rpc("delete_compensation_plan_draft",{selected_plan_version_id:id});
    setDeleting(false);
    if(error){setDeleteError(error.message);return}
    router.push("/plans");router.refresh();
  };
  return <>
    <div style={{maxWidth:1280,margin:"18px auto 0",padding:"0 24px"}}>
      <nav aria-label="Plan setup sections" style={{display:"flex",gap:8,alignItems:"center",flexWrap:"wrap",borderBottom:"1px solid #e3e8ef",paddingBottom:10}}>
        <Link href={base} className="plan-button secondary">Plan setup</Link>
        <Link href={`/plans/applicability/${id}`} className="plan-button secondary">People</Link>
        <Link href={`/plans/agreements/${id}`} className="plan-button secondary">Agreements</Link>
        <Link href={`${base}/approvals`} className="plan-button secondary">Approvals</Link>
        <Link href={`/plans?version=${id}`} className="plan-button secondary">Readiness & activation</Link>
        <button type="button" className="plan-button secondary" onClick={()=>void deleteDraft()} disabled={deleting} style={{marginLeft:"auto",color:"#8b3030",borderColor:"#efcaca"}}>{deleting?"Deleting…":"Delete draft"}</button>
      </nav>
      {deleteError&&<div className="plan-alert error" style={{marginTop:10}}>{deleteError}</div>}
    </div>
    {children}
  </>;
}
