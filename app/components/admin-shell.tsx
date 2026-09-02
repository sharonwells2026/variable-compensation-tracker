"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Bell, Bot, ChevronDown, CircleUserRound, HelpCircle, LogOut, Search, Settings, ShieldCheck, Users, Workflow, WalletCards, FileBarChart, Database, Scale, History, LayoutDashboard, BadgeDollarSign } from "lucide-react";
import { createClient } from "@supabase/supabase-js";
import "./admin-shell.css";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY||"";
const supabase=supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type AdminSection="overview"|"people"|"plans"|"earnings"|"approvals"|"payroll"|"data"|"reconciliation"|"reports"|"audit"|"settings";
type Props={section:AdminSection;title:string;description?:string;children:React.ReactNode};
type AccessSummary={authenticated:boolean;user_id?:string;email?:string;full_name?:string;employee_id?:string|null;roles:string[];permissions:string[]};
type NavItem={key:AdminSection;label:string;icon:any;href:string;permissions?:string[]};

const nav:NavItem[]=[
 {key:"overview",label:"Overview",icon:LayoutDashboard,href:"/?workspace=admin"},
 {key:"people",label:"People & Access",icon:Users,href:"/employee-administration",permissions:["users.manage"]},
 {key:"plans",label:"Plans & Programs",icon:BadgeDollarSign,href:"/plans",permissions:["plans.view","plans.edit"]},
 {key:"earnings",label:"Earnings & Credits",icon:WalletCards,href:"/?workspace=admin&screen=employees",permissions:["earnings.view","earnings.approve"]},
 {key:"approvals",label:"Approval Workflows",icon:Workflow,href:"/approval-workflows",permissions:["users.manage","settings.manage","earnings.approve"]},
 {key:"payroll",label:"Payroll",icon:WalletCards,href:"/payroll",permissions:["payments.view","payments.schedule","payments.mark_paid"]},
 {key:"data",label:"Data & Integrations",icon:Database,href:"/data-integrations",permissions:["hubspot.refresh","settings.manage"]},
 {key:"reconciliation",label:"Reconciliation",icon:Scale,href:"/reconciliation",permissions:["flags.resolve","audit.view_assigned","audit.view_all"]},
 {key:"reports",label:"Reports & Analytics",icon:FileBarChart,href:"/reports",permissions:["earnings.view","payments.view","audit.view_assigned","audit.view_all"]},
 {key:"audit",label:"Audit & Activity",icon:History,href:"/?workspace=admin&screen=logs",permissions:["audit.view_assigned","audit.view_all"]},
 {key:"settings",label:"Settings",icon:Settings,href:"/settings",permissions:["settings.manage"]},
];

function initials(name:string){return name.split(/\s+/).filter(Boolean).slice(0,2).map(x=>x[0]?.toUpperCase()).join("")||"ME"}
function roleLabel(role:string){return role.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase())}

export default function AdminShell({section,title,description,children}:Props){
 const[accountOpen,setAccountOpen]=useState(false);const[access,setAccess]=useState<AccessSummary|null>(null);const menuRef=useRef<HTMLDivElement|null>(null);
 useEffect(()=>{let live=true;const load=async()=>{if(!supabase)return;const{data}=await supabase.auth.getUser();if(!data.user||!live)return;const{data:a}=await supabase.rpc("get_current_user_access");if(a&&live)setAccess(a as AccessSummary)};load();const close=(e:MouseEvent)=>{if(menuRef.current&&!menuRef.current.contains(e.target as Node))setAccountOpen(false)};document.addEventListener("mousedown",close);return()=>{live=false;document.removeEventListener("mousedown",close)}},[]);
 const isSystemAdmin=Boolean(access?.roles?.includes("system_administrator"));
 const can=(permission:string)=>Boolean(access?.permissions?.includes(permission));
 const visibleNav=useMemo(()=>nav.filter(item=>isSystemAdmin||!item.permissions?.length||item.permissions.some(can)),[access,isSystemAdmin]);
 const current=useMemo(()=>nav.find(x=>x.key===section),[section]);
 const hasMy=Boolean(access?.employee_id)||isSystemAdmin;
 const hasTeam=isSystemAdmin||Boolean(access?.roles?.some(role=>["management_approver","finance_payroll","plan_administrator","executive_administrator","auditor_read_only"].includes(role)));
 const identityName=access?.full_name||access?.email?.split("@")[0]||"My account";
 const roleSummary=access?.roles?.length?access.roles.map(roleLabel).join(" · "):"Administration workspace";
 const signOut=async()=>{if(supabase)await supabase.auth.signOut();window.location.href="/"};
 return <div className="admin-shell-v2"><div className="admin-shell-sidebar" role="navigation" aria-label="Administration sidebar"><a className="admin-shell-brand" href="/"><span>ENGAGIFII</span><b>Variable Compensation</b></a><div className="admin-shell-workspace"><small>WORKSPACE</small><b>Administration</b><span>Configure and operate compensation</span></div><nav className="admin-shell-nav" aria-label="Administration navigation">{visibleNav.map(item=>{const Icon=item.icon;return <a key={item.key} href={item.href} className={item.key===section?"active":""}><Icon size={17}/><span>{item.label}</span></a>})}</nav><div className="admin-shell-side-footer"><a href="/"><HelpCircle size={16}/>Help & knowledge</a></div></div><div className="admin-shell-main"><header className="admin-shell-header"><div className="admin-shell-context"><small>ADMINISTRATION / {current?.label.toUpperCase()}</small><b>{title}</b>{description&&<span>{description}</span>}</div><div className="admin-shell-global"><button className="admin-shell-icon" aria-label="Search" title="Global search foundation"><Search size={17}/></button><button className="admin-shell-icon" aria-label="AI assistant" title="AI assistant foundation"><Bot size={17}/></button><button className="admin-shell-icon" aria-label="Notifications" title="Notification center foundation"><Bell size={17}/></button><div className="admin-account" ref={menuRef}><button className="admin-account-trigger" onClick={()=>setAccountOpen(x=>!x)} aria-expanded={accountOpen}><span className="admin-account-avatar">{initials(identityName)}</span><span className="admin-account-copy"><b>{identityName}</b><small>{roleSummary}</small></span><ChevronDown size={14}/></button>{accountOpen&&<div className="admin-account-menu"><div className="admin-account-identity"><CircleUserRound size={18}/><span><b>{identityName}</b><small>{access?.email||"Signed in"}</small></span></div>{hasMy&&<a href="/?workspace=self"><CircleUserRound size={15}/>My compensation</a>}{hasTeam&&<a href="/?workspace=team"><Users size={15}/>Team workspace</a>}<a href="/?workspace=administration"><ShieldCheck size={15}/>Administration</a>{(isSystemAdmin||can("settings.manage")||can("notifications.configure_own"))&&<a href="/settings"><Settings size={15}/>Preferences & settings</a>}<button onClick={signOut}><LogOut size={15}/>Log out</button></div>}</div></div></header><div className="admin-shell-mobile-nav"><select aria-label="Administration section" value={current?.href||""} onChange={e=>window.location.href=e.target.value}>{visibleNav.map(item=><option key={item.key} value={item.href}>{item.label}</option>)}</select></div><main className="admin-shell-content">{children}</main></div></div>
}
