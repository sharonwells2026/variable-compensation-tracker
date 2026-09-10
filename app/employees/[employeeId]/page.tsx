"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {useParams} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,Download,FileText} from "lucide-react";

const supabase=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH");
type Employee={employee_id:string;full_name:string;email:string;title:string|null;department:string|null;manager_name:string|null;is_active:boolean;plan_name:string|null;plan_status:string|null;plan_effective_start_date:string|null;plan_effective_end_date:string|null;readiness:string;readiness_reasons:string[]};
type Agreement={agreement_id:string;file_name:string;storage_path:string;mime_type:string|null;file_size_bytes:number|null;signed_at:string|null;notes:string|null;applies_to_everyone:boolean;plan_version_id:string;version_number:number;plan_name:string;plan_code:string;created_at:string};
const size=(n:number|null)=>n==null?"":n<1048576?`${Math.max(1,Math.round(n/1024))} KB`:`${(n/1048576).toFixed(1)} MB`;
export default function EmployeeRecordPage(){
 const params=useParams<{employeeId:string}>();const employeeId=params.employeeId;
 const[employees,setEmployees]=useState<Employee[]>([]),[agreements,setAgreements]=useState<Agreement[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState("");
 const employee=useMemo(()=>employees.find(e=>e.employee_id===employeeId),[employees,employeeId]);
 const load=async()=>{setLoading(true);setError("");const[e,a]=await Promise.all([supabase.rpc("get_employee_administration_data"),supabase.rpc("get_employee_comp_plan_agreements",{selected_employee_id:employeeId})]);if(e.error)setError(e.error.message);else setEmployees((e.data?.employees||[]) as Employee[]);if(a.error)setError(x=>x||a.error!.message);else setAgreements((a.data||[]) as Agreement[]);setLoading(false)};
 useEffect(()=>{load()},[employeeId]);
 const open=async(a:Agreement)=>{setError("");const{data,error:e}=await supabase.storage.from("compensation-agreements").createSignedUrl(a.storage_path,60);if(e||!data?.signedUrl){setError(e?.message||"Could not open agreement.");return}window.open(data.signedUrl,"_blank","noopener,noreferrer")};
 if(loading)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-empty">Loading employee record…</div></div></main>;
 if(!employee)return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-alert error">{error||"Employee not found."}</div></div></main>;
 return <main className="plan-workspace"><div className="plan-page-shell"><div className="plan-breadcrumb"><Link href="/employees"><ArrowLeft size={15}/>Employees</Link><span>/</span><span>{employee.full_name}</span></div><header className="plan-page-header"><div><span className="plan-kicker">EMPLOYEE RECORD</span><h1>{employee.full_name}</h1><p>{employee.title||"No title"}{employee.department?` · ${employee.department}`:""} · {employee.email}</p></div></header>{error&&<div className="plan-alert error">{error}</div>}
 <div style={{display:"grid",gridTemplateColumns:"repeat(3,minmax(0,1fr))",gap:12,marginBottom:16}}><section className="plan-section" style={{margin:0}}><small>Current plan</small><h3 style={{margin:"5px 0"}}>{employee.plan_name||"No plan assigned"}</h3><p style={{margin:0,fontSize:12,color:"#667085"}}>{employee.plan_status||""}</p></section><section className="plan-section" style={{margin:0}}><small>Manager</small><h3 style={{margin:"5px 0"}}>{employee.manager_name||"Not assigned"}</h3></section><section className="plan-section" style={{margin:0}}><small>Readiness</small><h3 style={{margin:"5px 0"}}>{employee.readiness.replaceAll("_"," ")}</h3></section></div>
 <section className="plan-section"><div className="plan-section-title"><div><h3>Compensation agreements</h3><p>Agreements attached to this employee or to everyone on one of their plan versions.</p></div><FileText size={18}/></div>{agreements.length?agreements.map(a=><div key={a.agreement_id} style={{display:"grid",gridTemplateColumns:"1fr auto",gap:12,alignItems:"center",padding:"12px 0",borderTop:"1px solid #e6e8ec"}}><div><b>{a.file_name}</b><div style={{fontSize:12,color:"#667085",marginTop:3}}>{a.plan_name} · v{a.version_number}{a.applies_to_everyone?" · plan-wide agreement":""}{a.signed_at?` · signed ${a.signed_at}`:""}{a.file_size_bytes?` · ${size(a.file_size_bytes)}`:""}</div>{a.notes&&<div style={{fontSize:12,color:"#475467",marginTop:4}}>{a.notes}</div>}</div><button className="plan-button secondary" onClick={()=>open(a)}><Download size={14}/>Open</button></div>):<div className="plan-empty">No compensation agreements are on file for this employee.</div>}</section>
 </div></main>;
}
