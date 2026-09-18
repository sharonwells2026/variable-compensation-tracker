"use client";

import {useEffect} from "react";
import {useParams,useRouter,useSearchParams} from "next/navigation";

export default function LegacyAggregateRedirect(){
 const params=useParams<{componentId:string}>();
 const router=useRouter();
 const search=useSearchParams();
 useEffect(()=>{
   const version=search.get("version");
   const query=version?`?version=${encodeURIComponent(version)}`:"";
   router.replace(`/plans/component/${params.componentId}${query}`);
 },[params.componentId,router,search]);
 return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Opening the current Earning Type editor…</div></div></main>;
}
