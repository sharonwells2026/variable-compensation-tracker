"use client";

import { useEffect, useRef, useState } from "react";
import { CircleUserRound, LogOut, Settings, ShieldCheck, Users } from "lucide-react";
import { createClient } from "@supabase/supabase-js";
import "./global-account-controller.css";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY||"";
const supabase=supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type AccessSummary={authenticated:boolean;user_id?:string;email?:string;full_name?:string;employee_id?:string|null;roles:string[];permissions:string[]};

function roleLabel(role:string){return role.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase())}

export default function GlobalAccountController(){
 const[open,setOpen]=useState(false);const[access,setAccess]=useState<AccessSummary|null>(null);const ref=useRef<HTMLDivElement|null>(null);
 useEffect(()=>{
  const path=window.location.pathname;
  if(path!=="/")return;
  const load=async()=>{if(!supabase)return;const{data}=await supabase.rpc("get_current_user_access");if(data)setAccess(data as AccessSummary)};load();
  const onClick=(event:MouseEvent)=>{const target=event.target as HTMLElement|null;const avatar=target?.closest?.(".avatar");if(avatar){event.preventDefault();event.stopPropagation();setOpen(v=>!v);return}if(ref.current&&!ref.current.contains(target as Node))setOpen(false)};
  document.addEventListener("click",onClick,true);
  return()=>document.removeEventListener("click",onClick,true);
 },[]);
 if(typeof window!=="undefined"&&window.location.pathname!=="/")return null;
 const roles=access?.roles||[];const isAdmin=roles.includes("system_administrator")||access?.permissions?.includes("workspace.view_administration");const hasTeam=roles.some(r=>["management_approver","finance_payroll","plan_administrator","executive_administrator","auditor_read_only","system_administrator"].includes(r));
 const signOut=async()=>{if(supabase)await supabase.auth.signOut();window.location.href="/"};
 if(!open)return null;
 return <div ref={ref} className="global-account-menu-v2" role="menu">
   <div className="global-account-identity"><CircleUserRound size={18}/><span><b>{access?.full_name||access?.email||"My account"}</b><small>{access?.email||"Signed in"}</small>{roles.length>0&&<em>{roles.map(roleLabel).join(" · ")}</em>}</span></div>
   {access?.employee_id&&<button onClick={()=>{document.querySelector<HTMLButtonElement>(".workspace-switch button:first-child")?.click();setOpen(false)}}><CircleUserRound size={15}/>My compensation</button>}
   {hasTeam&&<button onClick={()=>{const buttons=[...document.querySelectorAll<HTMLButtonElement>(".workspace-switch button")];buttons.find(b=>b.textContent?.includes("Team"))?.click();setOpen(false)}}><Users size={15}/>Team workspace</button>}
   {isAdmin&&<a href="/employee-administration"><ShieldCheck size={15}/>Administration</a>}
   <a href="/settings"><Settings size={15}/>Preferences & settings</a>
   <button className="danger" onClick={signOut}><LogOut size={15}/>Log out</button>
 </div>
}
