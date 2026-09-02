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

const screenLabels:Record<string,string>={
 dashboard:"Dashboard",
 approvals:"Approvals",
 employees:"Employees",
 plans:"Compensation Plans",
 payments:"Payments",
 reconciliation:"Reconciliation",
 hubspot:"HubSpot Integration",
 rules:"Rules & Calculations",
 logs:"Activity Log",
 help:"Help"
};

function clickWorkspace(name:"self"|"team"|"administration"){
 const buttons=[...document.querySelectorAll<HTMLButtonElement>(".workspace-switch button")];
 const match=name==="self"?buttons.find(b=>b.textContent?.includes("My dashboard")):name==="team"?buttons.find(b=>b.textContent?.includes("Team dashboard")):buttons.find(b=>b.textContent?.includes("Administration"));
 match?.click();
 return Boolean(match);
}

function clickLegacyScreen(screen:string){
 const label=screenLabels[screen];if(!label)return false;
 const buttons=[...document.querySelectorAll<HTMLButtonElement>("aside nav button")];
 const match=buttons.find(b=>b.textContent?.trim()===label);
 match?.click();
 return Boolean(match);
}

export default function GlobalAccountController(){
 const[open,setOpen]=useState(false);const[access,setAccess]=useState<AccessSummary|null>(null);const ref=useRef<HTMLDivElement|null>(null);
 useEffect(()=>{
  const path=window.location.pathname;
  if(path!=="/")return;
  const load=async()=>{if(!supabase)return;const{data}=await supabase.rpc("get_current_user_access");if(data)setAccess(data as AccessSummary)};load();

  const params=new URLSearchParams(window.location.search);const requestedWorkspace=params.get("workspace");const requestedScreen=params.get("screen");
  let attempts=0;const applyRequestedRoute=()=>{attempts+=1;const workspaceOk=!requestedWorkspace||clickWorkspace(requestedWorkspace==="admin"?"administration":requestedWorkspace as "self"|"team"|"administration");if(workspaceOk&&requestedScreen){window.setTimeout(()=>clickLegacyScreen(requestedScreen),60)}if(!workspaceOk&&attempts<20)window.setTimeout(applyRequestedRoute,100)};
  if(requestedWorkspace||requestedScreen)window.setTimeout(applyRequestedRoute,80);

  const onClick=(event:MouseEvent)=>{
    const target=event.target as HTMLElement|null;
    const avatar=target?.closest?.(".avatar");
    if(avatar){event.preventDefault();event.stopPropagation();setOpen(v=>!v);return}
    const button=target?.closest?.("button");
    if(button?.textContent?.trim()==="Add employee"){
      event.preventDefault();event.stopPropagation();window.location.href="/user-administration";return;
    }
    if(ref.current&&!ref.current.contains(target as Node))setOpen(false)
  };
  document.addEventListener("click",onClick,true);
  return()=>document.removeEventListener("click",onClick,true);
 },[]);
 if(typeof window!=="undefined"&&window.location.pathname!=="/")return null;
 const roles=access?.roles||[];const isAdmin=roles.includes("system_administrator")||access?.permissions?.includes("workspace.view_administration");const hasTeam=roles.some(r=>["management_approver","finance_payroll","plan_administrator","executive_administrator","auditor_read_only","system_administrator"].includes(r));
 const signOut=async()=>{if(supabase)await supabase.auth.signOut();window.location.href="/"};
 if(!open)return null;
 return <div ref={ref} className="global-account-menu-v2" role="menu">
   <div className="global-account-identity"><CircleUserRound size={18}/><span><b>{access?.full_name||access?.email||"My account"}</b><small>{access?.email||"Signed in"}</small>{roles.length>0&&<em>{roles.map(roleLabel).join(" · ")}</em>}</span></div>
   {access?.employee_id&&<button onClick={()=>{clickWorkspace("self");setOpen(false)}}><CircleUserRound size={15}/>My compensation</button>}
   {hasTeam&&<button onClick={()=>{clickWorkspace("team");setOpen(false)}}><Users size={15}/>Team workspace</button>}
   {isAdmin&&<a href="/employee-administration"><ShieldCheck size={15}/>Administration</a>}
   <a href="/settings"><Settings size={15}/>Preferences & settings</a>
   <button className="danger" onClick={signOut}><LogOut size={15}/>Log out</button>
 </div>
}
