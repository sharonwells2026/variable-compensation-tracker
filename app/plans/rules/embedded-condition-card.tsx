"use client";

import Link from "next/link";
import {CheckCircle2,ExternalLink,Plus} from "lucide-react";

type RuleSet={id:string;name:string;version:number;is_active:boolean};

export default function EmbeddedConditionCard({title,question,emptyText,ruleSets,selectedRuleSetId,builderHref,onSelect,disabled=false}:{title:string;question:string;emptyText:string;ruleSets:RuleSet[];selectedRuleSetId?:string;builderHref:(ruleSetId?:string)=>string;onSelect?:(id:string)=>void;disabled?:boolean}){
 const selected=ruleSets.find(r=>r.id===selectedRuleSetId)||ruleSets[0];
 return <div style={{border:"1px solid #d7e1eb",borderRadius:12,background:"#f8fbfe",padding:14}}><div style={{display:"flex",justifyContent:"space-between",gap:12,alignItems:"flex-start"}}><div><div style={{fontSize:11,fontWeight:800,letterSpacing:.6,color:"#667085",textTransform:"uppercase"}}>{title}</div><b style={{display:"block",marginTop:3,color:"#051b34"}}>{question}</b></div>{!disabled&&<Link href={builderHref(selected?.id)} style={{display:"inline-flex",gap:5,alignItems:"center",fontSize:12,fontWeight:800,color:"#1267a5"}}>{selected?"Edit conditions":"Add conditions"}{selected?<ExternalLink size={13}/>:<Plus size={13}/>}</Link>}</div>{selected?<div style={{display:"flex",gap:9,alignItems:"center",marginTop:12,padding:"10px 11px",border:"1px solid #cfe0ef",borderRadius:9,background:"white"}}><CheckCircle2 size={17} color="#16855b"/><div style={{minWidth:0,flex:1}}><b style={{display:"block",fontSize:13}}>{selected.name}</b><span style={{fontSize:11,color:"#667085"}}>Version {selected.version}{selected.is_active?" · Active":" · Draft"}</span></div>{ruleSets.length>1&&onSelect&&<select aria-label={`Choose ${title}`} value={selectedRuleSetId||selected.id} onChange={e=>onSelect(e.target.value)} disabled={disabled} style={{maxWidth:190}}>{ruleSets.map(r=><option key={r.id} value={r.id}>{r.name} · v{r.version}</option>)}</select>}</div>:<div style={{marginTop:11,padding:"11px",border:"1px dashed #b8c8d8",borderRadius:9,background:"white",fontSize:12,color:"#667085"}}>{emptyText}</div>}</div>;
}
