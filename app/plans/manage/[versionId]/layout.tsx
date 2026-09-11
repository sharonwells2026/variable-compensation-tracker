"use client";

import Link from "next/link";
import {useParams} from "next/navigation";

export default function ManagePlanLayout({children}:{children:React.ReactNode}){
  const params=useParams<{versionId:string}>();
  const id=params.versionId;
  const base=`/plans/manage/${id}`;
  return <>
    <div style={{maxWidth:1280,margin:"18px auto 0",padding:"0 24px"}}>
      <nav aria-label="Plan setup sections" style={{display:"flex",gap:8,flexWrap:"wrap",borderBottom:"1px solid #e3e8ef",paddingBottom:10}}>
        <Link href={base} className="plan-button secondary">Plan setup</Link>
        <Link href={`/plans/applicability/${id}`} className="plan-button secondary">People</Link>
        <Link href={`/plans/agreements/${id}`} className="plan-button secondary">Agreements</Link>
        <Link href={`${base}/approvals`} className="plan-button secondary">Approvals</Link>
        <Link href={`/plans?version=${id}`} className="plan-button secondary">Readiness & activation</Link>
      </nav>
    </div>
    {children}
  </>;
}
