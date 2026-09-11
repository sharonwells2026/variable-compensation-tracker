"use client";

import Link from "next/link";
import {useParams} from "next/navigation";

export default function EarningTypeLayout({children}:{children:React.ReactNode}){
  const params=useParams<{componentId:string}>();
  const id=params.componentId;
  if(id==="new")return <>{children}</>;
  const base=`/plans/component/${id}`;
  return <>
    <div style={{maxWidth:1180,margin:"18px auto 0",padding:"0 24px"}}>
      <nav aria-label="Earning Type sections" style={{display:"flex",gap:8,flexWrap:"wrap",borderBottom:"1px solid #e3e8ef",paddingBottom:10}}>
        <Link href={base} className="plan-button secondary">Earning Type</Link>
        <Link href={`${base}/payout`} className="plan-button secondary">Payout</Link>
        <Link href={`${base}/payment-condition`} className="plan-button secondary">Payment condition</Link>
      </nav>
    </div>
    {children}
  </>;
}
