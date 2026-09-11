import Link from "next/link";

export default function ManagePlanLayout({children,params}:{children:React.ReactNode;params:{versionId:string}}){
  const base=`/plans/manage/${params.versionId}`;
  return <>
    <div style={{maxWidth:1180,margin:"18px auto 0",padding:"0 24px"}}>
      <nav aria-label="Plan setup sections" style={{display:"flex",gap:8,flexWrap:"wrap",borderBottom:"1px solid #e3e8ef",paddingBottom:10}}>
        <Link href={base} className="plan-button secondary">Plan setup</Link>
        <Link href={`${base}/approvals`} className="plan-button secondary">Approvals</Link>
      </nav>
    </div>
    {children}
  </>;
}
