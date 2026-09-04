"use client";

import {useEffect,useState} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;
type Access={roles?:string[];permissions?:string[];employee_id?:string|null};
export default function Home(){const router=useRouter();const[message,setMessage]=useState("Opening your compensation workspace…");useEffect(()=>{(async()=>{if(!supabase){setMessage("Database connection unavailable.");return}const{data:{session}}=await supabase.auth.getSession();if(!session){setMessage("Please sign in to access the compensation tracker.");return}const{data,error}=await supabase.rpc("get_current_user_access");if(error){setMessage(error.message);return}const access=(data||{}) as Access;const roles=access.roles||[],permissions=access.permissions||[];const management=roles.includes("system_administrator")||roles.includes("management_approver")||roles.includes("finance_payroll")||roles.includes("plan_administrator")||roles.includes("auditor_read_only")||permissions.includes("earnings.approve")||permissions.includes("payments.view");router.replace(management?"/manage":"/me")})()},[router]);return <main style={{minHeight:"100vh",display:"grid",placeItems:"center",background:"#f5f7fa",fontFamily:"Inter,Arial,sans-serif",color:"#051b34"}}><div style={{textAlign:"center",padding:28}}><div style={{fontWeight:900,letterSpacing:1.2,color:"#2095f3",fontSize:13}}>ENGAGIFII COMPENSATION</div><h1 style={{margin:"10px 0 6px"}}>Compensation Tracker</h1><p style={{color:"#647184"}}>{message}</p></div></main>}
