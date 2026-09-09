"use client";

import {FormEvent,useEffect,useState} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@supabase/supabase-js";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;
type Access={roles?:string[];permissions?:string[]};

export default function Home(){
 const router=useRouter();const[message,setMessage]=useState("Opening your compensation workspace…"),[signedOut,setSignedOut]=useState(false),[email,setEmail]=useState(""),[sending,setSending]=useState(false),[sent,setSent]=useState(false);
 useEffect(()=>{(async()=>{if(!supabase){setMessage("Database connection unavailable.");return}const{data:{session}}=await supabase.auth.getSession();if(!session){setSignedOut(true);setMessage("Sign in with your existing Engagifii Compensation account.");return}const{data,error}=await supabase.rpc("get_current_user_access");if(error){setMessage(error.message);return}const access=(data||{}) as Access;const roles=access.roles||[];
  if(roles.includes("system_administrator")){router.replace("/manage");return}
  if(roles.includes("finance_payroll")){router.replace("/finance");return}
  if(roles.includes("executive_administrator")){router.replace("/executive");return}
  if(roles.includes("management_approver")){router.replace("/submissions");return}
  if(roles.includes("plan_administrator")){router.replace("/plans");return}
  router.replace("/me");
 })()},[router]);
 const signIn=async(e:FormEvent)=>{e.preventDefault();if(!supabase||!email.trim())return;setSending(true);setMessage("");const{error}=await supabase.auth.signInWithOtp({email:email.trim(),options:{shouldCreateUser:false,emailRedirectTo:window.location.origin}});if(error){setMessage(error.message);setSent(false)}else{setSent(true);setMessage(`Check ${email.trim()} for your secure sign-in link.`)}setSending(false)};
 return <main style={{minHeight:"100vh",display:"grid",placeItems:"center",background:"#f5f7fa",fontFamily:"Inter,Arial,sans-serif",color:"#051b34",padding:20}}><div style={{width:"min(100%,440px)",background:"white",border:"1px solid #dfe6ee",borderRadius:16,padding:"clamp(24px,6vw,38px)",boxShadow:"0 18px 45px rgba(5,27,52,.08)",textAlign:"center"}}><div style={{fontWeight:900,letterSpacing:1.2,color:"#2095f3",fontSize:13}}>ENGAGIFII COMPENSATION</div><h1 style={{margin:"12px 0 7px",fontSize:"clamp(27px,6vw,34px)"}}>Compensation Tracker</h1><p style={{color:"#647184",lineHeight:1.5,margin:"0 0 22px"}}>{message}</p>{signedOut&&!sent&&<form onSubmit={signIn} style={{display:"grid",gap:10,textAlign:"left"}}><label style={{fontSize:12,fontWeight:800,color:"#42566a"}}>Work email</label><input type="email" autoComplete="email" required value={email} onChange={e=>setEmail(e.target.value)} placeholder="name@engagifii.com" style={{width:"100%",padding:"12px 13px",border:"1px solid #ccd8e4",borderRadius:9,fontSize:16}}/><button type="submit" disabled={sending} style={{marginTop:3,padding:"12px 14px",border:0,borderRadius:9,background:"#2095f3",color:"white",fontWeight:800,fontSize:15}}>{sending?"Sending secure link…":"Email me a sign-in link"}</button><small style={{color:"#718096",lineHeight:1.45,textAlign:"center"}}>Only an already-provisioned account can sign in. This does not create or invite a new user.</small></form>}{sent&&<button onClick={()=>{setSent(false);setMessage("Sign in with your existing Engagifii Compensation account.")}} style={{padding:"10px 13px",border:"1px solid #ccd8e4",borderRadius:9,background:"white",fontWeight:750}}>Use a different email</button>}</div></main>
}
