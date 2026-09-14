"use client";

import Link from "next/link";
import {useEffect,useMemo,useState} from "react";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,CheckCircle2,Clock3,Database,GitBranch,RefreshCw,Users} from "lucide-react";

const supabase=createClient(
 process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Summary={candidate_count?:number;eligible_candidate_count?:number;pending_condition_count?:number;generated_earning_count?:number;open_review_count?:number};
type Row={candidate_key:string;hubspot_deal_id:string;deal_name:string;company_name:string;employee_name:string;plan_name:string;component_name:string;credit_percentage:number;source_amount:number;calculated_earning_amount:number;calculation_status:string;eligibility_status:string;earned_date?:string;earning_id?:string;earning_amount?:number;earning_eligibility_status?:string;payment_status?:string;review_status?:string;review_type?:string;review_question?:string;hubspot_record_url?:string};
type Review={id:string;employee_name:string;hubspot_deal_id:string;review_type:string;review_question:string;review_status:string;decision_notes?:string};
type Payload={summary?:Summary;lineage?:Row[];reviews?:Review[]};

const money=(value?:number)=>new Intl.NumberFormat("en-US",{style:"currency",currency:"USD"}).format(Number(value||0));
const statusLabel=(value?:string)=>({eligible:"Eligible",pending_condition:"Waiting on payment condition",ready_for_payroll:"Accepted / unpaid",not_payable:"Unpaid",paid:"Paid",ready:"Calculated"}[value||""]||String(value||"—").replaceAll("_"," "));
const statusTone=(value?:string)=>value==="paid"||value==="eligible"?"success":value==="pending_condition"?"warn":value?"info":"neutral";

export default function CreditsPage(){
 const[data,setData]=useState<Payload>({}),[error,setError]=useState(""),[loading,setLoading]=useState(true),[filter,setFilter]=useState("all");
 const load=async()=>{setLoading(true);setError("");const{data:result,error:rpcError}=await supabase.rpc("get_compensation_credits_workspace_data");if(rpcError)setError("Credit lineage could not be loaded. No compensation records were changed.");else setData((result||{}) as Payload);setLoading(false)};
 useEffect(()=>{void load()},[]);
 const rows=data.lineage||[];
 const visible=useMemo(()=>rows.filter(row=>filter==="all"||(filter==="eligible"&&row.eligibility_status==="eligible")||(filter==="waiting"&&row.eligibility_status==="pending_condition")||(filter==="review"&&Boolean(row.review_status))),[rows,filter]);
 const summary=data.summary||{};
 const metrics=[
  {icon:<Database size={18}/>,title:"Source candidates",value:summary.candidate_count||0,copy:"Transactions evaluated against active plan rules"},
  {icon:<CheckCircle2 size={18}/>,title:"Eligible",value:summary.eligible_candidate_count||0,copy:"Calculated and currently eligible for payment"},
  {icon:<Clock3 size={18}/>,title:"Waiting",value:summary.pending_condition_count||0,copy:"Earned but waiting on a payment condition"},
  {icon:<GitBranch size={18}/>,title:"Generated earnings",value:summary.generated_earning_count||0,copy:"Current earning-ledger records"},
  {icon:<AlertTriangle size={18}/>,title:"Open reviews",value:summary.open_review_count||0,copy:"Attribution decisions still requiring resolution"},
 ];
 const filters=[["all","All"],["eligible","Eligible"],["waiting","Waiting"],["review","Attribution review"]];

 return <main className="eng-page"><div className="eng-page__shell">
  <nav className="eng-breadcrumb" aria-label="Breadcrumb"><Link href="/manage">Control Center</Link><span className="eng-breadcrumb__sep">/</span><Link href="/earnings">Earnings</Link><span className="eng-breadcrumb__sep">/</span><span className="eng-breadcrumb__current">Credit Lineage</span></nav>
  <header className="eng-page-header"><div className="eng-page-header__main"><span className="eng-page-header__eyebrow">COMPENSATION ADMINISTRATION</span><div className="eng-page-header__titlerow"><h1>Credit Lineage</h1></div><p className="eng-page-header__lede">Trace each source transaction through attribution, plan component, calculated obligation, eligibility, and the earning ledger. This is the explanation layer behind Earnings, not a second earnings ledger.</p></div><div className="eng-page-header__actions"><button className="eng-btn" onClick={load} disabled={loading}><RefreshCw size={15}/>{loading?"Refreshing…":"Refresh"}</button><Link className="eng-btn eng-btn--primary" href="/corrections">Attribution corrections</Link></div></header>

  {error&&<div className="eng-callout eng-callout--danger"><div className="eng-callout__body"><b>Unable to load credit lineage</b>{error}</div></div>}

  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(180px,1fr))",gap:10,margin:"16px 0"}}>{metrics.map(metric=><div key={metric.title} className="eng-card"><div className="eng-card__body"><span style={{color:"var(--eng-blue)"}}>{metric.icon}</span><b className="eng-figure eng-figure--strong" style={{display:"block",fontSize:26,marginTop:6}}>{loading?"—":metric.value}</b><strong>{metric.title}</strong><p style={{fontSize:12,color:"var(--eng-ink-faint)",lineHeight:1.45,margin:"5px 0 0"}}>{metric.copy}</p></div></div>)}</section>

  <section className="eng-card" style={{marginBottom:18}}><div className="eng-card__head"><div><h2>Transaction → credit → earning</h2><p>Each row preserves the source deal, attributed employee, plan component, calculated obligation, and ledger state.</p></div><div className="eng-card__head-actions" style={{flexWrap:"wrap"}}>{filters.map(([key,label])=><button key={key} onClick={()=>setFilter(key)} className={`eng-btn eng-btn--sm${filter===key?" eng-btn--primary":""}`}>{label}</button>)}</div></div>
   <div style={{overflowX:"auto"}}><table style={{width:"100%",borderCollapse:"collapse",minWidth:1000}}><thead><tr>{["Source transaction","Employee / credit","Plan component","Basis","Calculated earning","Eligibility","Ledger"].map(heading=><th key={heading} style={{textAlign:"left",fontSize:11,textTransform:"uppercase",letterSpacing:.6,color:"var(--eng-ink-faint)",padding:"11px 14px",background:"var(--eng-surface-alt)",borderBottom:"1px solid var(--eng-border-soft)"}}>{heading}</th>)}</tr></thead><tbody>{visible.map(row=><tr key={row.candidate_key}>
    <td style={td}><b>{row.company_name||row.deal_name}</b><div style={sub}>{row.deal_name}</div><code className="eng-ident">HubSpot #{row.hubspot_deal_id}</code></td>
    <td style={td}><b>{row.employee_name}</b><div style={sub}>{Number(row.credit_percentage||0)}% credit</div>{row.review_status&&<span className="eng-badge eng-badge--warn" style={{marginTop:5}}>Review: {statusLabel(row.review_status)}</span>}</td>
    <td style={td}>{row.component_name}<div style={sub}>{row.plan_name}</div></td>
    <td style={td}><span className="eng-figure">{money(row.source_amount)}</span></td>
    <td style={td}><b className="eng-figure">{money(row.calculated_earning_amount)}</b></td>
    <td style={td}><span className={`eng-badge eng-badge--chip eng-badge--${statusTone(row.eligibility_status)}`}>{statusLabel(row.eligibility_status)}</span></td>
    <td style={td}>{row.earning_id?<><b className="eng-figure">{money(row.earning_amount)}</b><div style={{marginTop:4}}><span className={`eng-badge eng-badge--chip eng-badge--${statusTone(row.payment_status)}`}>{statusLabel(row.payment_status)}</span></div></>:<span className="eng-badge eng-badge--warn">Candidate only</span>}</td>
   </tr>)}{!loading&&visible.length===0&&<tr><td colSpan={7} style={{padding:32}}><div className="eng-empty eng-empty--inline"><h2>No records match this view</h2><p>Choose another filter to inspect additional transaction lineage.</p></div></td></tr>}</tbody></table></div>
  </section>

  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(320px,1fr))",gap:14}}>
   <div className="eng-card"><div className="eng-card__head"><AlertTriangle size={18}/><div><h2>Attribution reviews</h2><p>Conflicts remain explicit decisions rather than silent guesses.</p></div></div><div className="eng-card__body">{(data.reviews||[]).map(review=><div key={review.id} style={{padding:"11px 0",borderTop:"1px solid var(--eng-border-soft)"}}><b>{review.employee_name}</b><span className="eng-badge eng-badge--warn" style={{marginLeft:8}}>{statusLabel(review.review_status)}</span><div style={{fontSize:13,marginTop:5}}>{review.review_question}</div>{review.decision_notes&&<div style={sub}>{review.decision_notes}</div>}</div>)}{!loading&&(data.reviews||[]).length===0&&<div className="eng-empty eng-empty--inline"><h2>No attribution reviews</h2><p>No transaction attribution currently needs review.</p></div>}</div></div>
   <div className="eng-card"><div className="eng-card__head"><Users size={18}/><div><h2>Attribution controls</h2><p>How credit assignment is protected.</p></div></div><div className="eng-card__body"><p style={{marginTop:0,color:"var(--eng-ink-meta)",lineHeight:1.55}}>Deal Owner defaults to 100% applicable credit unless a configured rule says otherwise. Multiple plan components do not imply split credit. Historical ownership is snapshotted. Approved and Paid history is corrected through controlled adjustments, never silent mutation.</p><div className="eng-callout eng-callout--info"><div className="eng-callout__body"><b>Controlled correction path</b>Reassignment requires a reason, audit history, and recalculation before approval. Approved or paid items route through return or adjustment workflows.</div></div></div></div>
  </section>
 </div></main>;
}

const td:React.CSSProperties={padding:14,borderBottom:"1px solid var(--eng-border-soft)",verticalAlign:"top"};
const sub:React.CSSProperties={fontSize:12,color:"var(--eng-ink-meta)",marginTop:3};
