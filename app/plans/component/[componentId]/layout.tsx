"use client";

import Link from "next/link";
import {useParams,useSearchParams} from "next/navigation";

export default function EarningTypeLayout({children}:{children:React.ReactNode}){
  const params=useParams<{componentId:string}>();
  const search=useSearchParams();
  const id=params.componentId;
  if(id==="new")return <>{children}</>;
  const versionId=search.get("version");
  return <>
    <div className="plan-page-shell" style={{paddingTop:18,paddingBottom:0}}>
      <nav aria-label="Earning Type workspace" style={{display:"flex",gap:10,alignItems:"center",justifyContent:"space-between",flexWrap:"wrap",borderBottom:"1px solid var(--eng-border, #e3e8ef)",paddingBottom:10}}>
        <div style={{display:"flex",gap:8,alignItems:"center",flexWrap:"wrap"}}>
          {versionId&&<Link href={`/plans/manage/${versionId}`} className="plan-button secondary">Back to plan setup</Link>}
          <span className="plan-kicker" style={{margin:0}}>EARNING TYPE WORKSPACE</span>
        </div>
        <span style={{fontSize:12,fontWeight:700,color:"var(--eng-text-secondary, #667085)"}}>Payout, Earned conditions, and payment conditions are managed together here.</span>
      </nav>
    </div>
    {children}
  </>;
}
