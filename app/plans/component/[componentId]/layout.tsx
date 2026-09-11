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
    <div style={{maxWidth:1280,margin:"18px auto 0",padding:"0 24px"}}>
      <nav aria-label="Earning Type workspace" style={{display:"flex",gap:8,alignItems:"center",flexWrap:"wrap",borderBottom:"1px solid #e3e8ef",paddingBottom:10}}>
        {versionId&&<Link href={`/plans/manage/${versionId}`} className="plan-button secondary">Back to plan setup</Link>}
        <span style={{fontSize:12,fontWeight:800,color:"#667085"}}>Payout, Earned conditions, and payment conditions are managed together on this Earning Type.</span>
      </nav>
    </div>
    {children}
  </>;
}
