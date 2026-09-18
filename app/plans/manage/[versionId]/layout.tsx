"use client";

import Link from "next/link";
import {useParams,useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {Trash2} from "lucide-react";
import {useState} from "react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");

export default function ManagePlanLayout({children}:{children:React.ReactNode}){
  const params=useParams<{versionId:string}>();const router=useRouter();const[deleting,setDeleting]=useState(false),[deleteError,setDeleteError]=useState("");const id=params.versionId;
  const deleteDraft=async()=>{if(document.body.dataset.planDirty==="true"){window.alert("Save your changes before deleting this draft.");return}const ok=window.confirm("Delete this draft plan? Drafts can be deleted only when they have no earnings or protected history. This cannot be undone.");if(!ok)return;setDeleting(true);setDeleteError("");const{error}=await supabase.rpc("delete_compensation_plan_draft",{selected_plan_version_id:id});setDeleting(false);if(error){setDeleteError("This draft cannot be deleted because it already has protected history or another dependency.");return}router.push("/plans");router.refresh()};
  return <>
    <div className="plan-page-shell" style={{paddingTop:10,paddingBottom:0}}>
      <div style={{display:"flex",justifyContent:"space-between",gap:10,alignItems:"center",flexWrap:"wrap"}}><Link href="/plans" className="plan-button secondary">All plans</Link><button type="button" className="plan-button secondary plan-danger-button" onClick={()=>void deleteDraft()} disabled={deleting}><Trash2 size={14}/>{deleting?"Deleting…":"Delete draft"}</button></div>
      {deleteError&&<div className="plan-alert error" style={{marginTop:10}}>{deleteError}</div>}
    </div>
    {children}
  </>;
}
