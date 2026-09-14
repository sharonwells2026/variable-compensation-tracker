"use client";

import {useEffect,useState} from "react";
import {createClient} from "@supabase/supabase-js";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey,{auth:{flowType:"pkce",detectSessionInUrl:false,persistSession:true,autoRefreshToken:true}}):null;

export default function AuthCallback(){
 const[message,setMessage]=useState("Finishing sign-in…");
 useEffect(()=>{(async()=>{
  if(!supabase){setMessage("Database connection unavailable.");return}
  const url=new URL(window.location.href);
  const authError=url.searchParams.get("error_description")||url.searchParams.get("error");
  if(authError){setMessage(`Sign-in could not be completed: ${authError}`);return}
  const code=url.searchParams.get("code");
  if(code){
   const{error}=await supabase.auth.exchangeCodeForSession(code);
   if(error){setMessage(`Sign-in could not be completed: ${error.message}`);return}
  }
  const{data:{session}}=await supabase.auth.getSession();
  if(!session){setMessage("Sign-in returned without a session. Please return to the sign-in page and try again.");return}
  window.location.replace(window.location.origin);
 })()},[]);
 return <main style={{minHeight:"100vh",display:"grid",placeItems:"center",background:"#f5f7fa",fontFamily:"Inter,Arial,sans-serif",color:"#051b34",padding:20}}><div style={{width:"min(100%,440px)",background:"white",border:"1px solid #dfe6ee",borderRadius:16,padding:"clamp(24px,6vw,38px)",boxShadow:"0 18px 45px rgba(5,27,52,.08)",textAlign:"center"}}><div style={{fontWeight:900,letterSpacing:1.2,color:"#2095f3",fontSize:13}}>ENGAGIFII COMPENSATION</div><h1 style={{margin:"12px 0 7px",fontSize:"clamp(27px,6vw,34px)"}}>Signing you in</h1><p style={{color:"#647184",lineHeight:1.5,margin:0}}>{message}</p></div></main>
}
