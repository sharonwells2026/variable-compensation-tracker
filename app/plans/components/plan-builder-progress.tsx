"use client";

import Link from "next/link";
import {Check,ChevronRight} from "lucide-react";

type StepKey="basics"|"people"|"earnings"|"agreements"|"approvals"|"review";

type Props={
  versionId:string;
  current:StepKey;
  completed?:Partial<Record<StepKey,boolean>>;
  onNavigate?:(href:string)=>void;
};

const steps:{key:StepKey;label:string;short:string;href:(id:string)=>string}[]=[
  {key:"basics",label:"Plan basics",short:"Basics",href:id=>`/plans/manage/${id}`},
  {key:"people",label:"Who it applies to",short:"People",href:id=>`/plans/applicability/${id}`},
  {key:"earnings",label:"What they can earn",short:"Earning Types",href:id=>`/plans/manage/${id}#earning-types`},
  {key:"agreements",label:"Agreements",short:"Agreements",href:id=>`/plans/agreements/${id}`},
  {key:"approvals",label:"Approval workflow",short:"Approvals",href:id=>`/plans/manage/${id}/approvals`},
  {key:"review",label:"Review & activate",short:"Review",href:id=>`/plans/manage/${id}/review`},
];

export default function PlanBuilderProgress({versionId,current,completed={},onNavigate}:Props){
  const currentIndex=steps.findIndex(s=>s.key===current);
  return <div className="plan-builder-progress" aria-label="Plan setup progress">
    <div className="plan-builder-progress__eyebrow">PLAN BUILDER</div>
    <div className="plan-builder-progress__steps">
      {steps.map((step,index)=>{
        const done=completed[step.key]===true||index<currentIndex;
        const active=step.key===current;
        const href=step.href(versionId);
        const content=<>
          <span className={`plan-builder-progress__number ${done?"is-done":""} ${active?"is-active":""}`}>{done?<Check size={13}/>:index+1}</span>
          <span className="plan-builder-progress__label"><b>{step.label}</b><small>{active?"Current step":done?"Saved":"Not started"}</small></span>
        </>;
        return <div key={step.key} className="plan-builder-progress__item">
          {onNavigate?<button type="button" className={`plan-builder-progress__link ${active?"is-active":""}`} onClick={()=>onNavigate(href)} aria-current={active?"step":undefined}>{content}</button>:<Link className={`plan-builder-progress__link ${active?"is-active":""}`} href={href} aria-current={active?"step":undefined}>{content}</Link>}
          {index<steps.length-1&&<ChevronRight className="plan-builder-progress__chevron" size={15}/>} 
        </div>;
      })}
    </div>
  </div>;
}
