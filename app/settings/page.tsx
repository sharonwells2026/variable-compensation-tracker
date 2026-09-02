"use client";

import { useEffect, useMemo, useState } from "react";
import { Bell, Building2, CalendarDays, Database, Eye, LockKeyhole, Palette, ShieldCheck, SlidersHorizontal, Users, WalletCards } from "lucide-react";
import { createClient } from "@supabase/supabase-js";
import AdminShell from "../components/admin-shell";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY||"";
const supabase=supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type AccessSummary={roles:string[];permissions:string[];full_name?:string;email?:string};
type SettingSection={id:string;title:string;description:string;icon:any;items:string[]};
const sections:SettingSection[]=[
 {id:"organization",title:"Organization",description:"Company-wide structure and defaults that shape compensation administration.",icon:Building2,items:["Organization and business-unit defaults","Localization, currency, and time zone","Company-level compensation defaults"]},
 {id:"access",title:"Roles, permissions & scope",description:"Define access models here; assign them to individual people in People & Access.",icon:ShieldCheck,items:["System role definitions","Permission matrix and defaults","Employee/data scope models","Explicit permission override policy"]},
 {id:"payroll",title:"Compensation & payroll configuration",description:"Defaults used by earnings, approvals, eligibility, and finance processing.",icon:WalletCards,items:["Payroll periods and payment-date defaults","Approval deadlines and escalation defaults","Eligibility/payment rule defaults","Correction and hold policies"]},
 {id:"notifications",title:"Notifications",description:"Organization delivery policies and role defaults. Personal delivery choices belong to each user.",icon:Bell,items:["Role notification defaults","In-app and email delivery policies","Escalation/reminder defaults","Digest policy"]},
 {id:"calendar",title:"Calendars & periods",description:"Plan years, measurement periods, close windows, and administrative deadlines.",icon:CalendarDays,items:["Plan and calendar years","Measurement periods","Submission/approval deadlines","Payroll cutoffs"]},
 {id:"integrations",title:"Integration configuration",description:"System-level connection settings. Day-to-day sync work belongs in Data & Integrations.",icon:Database,items:["HubSpot refresh schedule","Source mapping policy","Integration health thresholds","Data-change review defaults"]},
 {id:"security",title:"Security & domains",description:"Authentication and access-governance settings for the application.",icon:LockKeyhole,items:["Allowed email domains","Invitation-only access policy","Session/security policy","Privileged access review policy"]},
 {id:"governance",title:"Audit, retention & governance",description:"Retention and audit rules that preserve compensation history and accountability.",icon:Eye,items:["Audit retention","Compensation-history preservation","Configuration-change history","Access-review retention"]},
 {id:"appearance",title:"Appearance & display",description:"Organization-wide presentation defaults without changing compensation logic.",icon:Palette,items:["Branding and labels","Default display density","Organization display defaults"]},
 {id:"personal",title:"My preferences",description:"Personal display and notification preferences for the signed-in user.",icon:SlidersHorizontal,items:["Display time zone and date format","Default dashboard period and landing view","Digest timing","Personal notification delivery"]},
];

export default function SettingsPage(){
 const[access,setAccess]=useState<AccessSummary|null>(null);const[loading,setLoading]=useState(true);
 useEffect(()=>{const load=async()=>{if(!supabase){setLoading(false);return}const{data}=await supabase.rpc("get_current_user_access");if(data)setAccess(data as AccessSummary);setLoading(false)};load()},[]);
 const isSystemAdmin=Boolean(access?.roles?.includes("system_administrator"));
 const canManage=Boolean(isSystemAdmin||access?.permissions?.includes("settings.manage"));
 const visible=useMemo(()=>canManage?sections:sections.filter(s=>s.id==="personal"||s.id==="notifications"),[canManage]);
 return <AdminShell section="settings" title="Settings" description="System configuration, governance, and personal preferences — separated from operational administration.">
  <div className="settings-ia-page">
   {!loading&&!canManage&&<div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900"><b>Limited settings access.</b> You can manage only settings permitted for your account. Organization and security configuration require administrative permission.</div>}
   <section className="mt-4 rounded-xl border bg-white p-5 shadow-sm">
    <div><p className="text-[10px] font-extrabold tracking-[.11em] text-[#2095f3]">SETTINGS ARCHITECTURE</p><h2 className="mt-1 text-lg font-bold">Configuration lives here. Operational work does not.</h2><p className="mt-1 max-w-3xl text-xs leading-5 text-[#66717f]">Employees, invitations, compensation plans, approval workflows, payroll work, reconciliation, integration operations, and audit investigation remain first-class Administration destinations rather than being stacked into one Settings page.</p></div>
    <div className="mt-4 flex flex-wrap gap-2"><a href="/employee-administration" className="rounded-lg border px-3 py-2 text-xs font-bold text-[#0879d5]"><Users size={14} className="mr-1 inline"/>People & Access</a><a href="/approval-workflows" className="rounded-lg border px-3 py-2 text-xs font-bold text-[#0879d5]">Approval Workflows</a><a href="/?workspace=administration&screen=plans" className="rounded-lg border px-3 py-2 text-xs font-bold text-[#0879d5]">Plans & Programs</a><a href="/?workspace=administration&screen=hubspot" className="rounded-lg border px-3 py-2 text-xs font-bold text-[#0879d5]">Data & Integrations</a></div>
   </section>
   <div className="mt-5 grid gap-5 lg:grid-cols-[230px_minmax(0,1fr)]">
    <aside className="settings-ia-subnav self-start rounded-xl border bg-white p-3 shadow-sm"><p className="px-2 pb-2 text-[9px] font-extrabold tracking-[.1em] text-[#8b94a0]">SETTINGS</p>{visible.map(s=>{const Icon=s.icon;return <a key={s.id} href={`#${s.id}`} className="flex items-center gap-2 rounded-lg px-2 py-2 text-xs font-semibold text-[#566170] hover:bg-[#f3f6fb] hover:text-[#0879d5]"><Icon size={15}/>{s.title}</a>})}</aside>
    <div className="space-y-4">{visible.map(s=>{const Icon=s.icon;return <section id={s.id} key={s.id} className="scroll-mt-24 rounded-xl border bg-white p-5 shadow-sm"><div className="flex items-start gap-3"><span className="grid h-9 w-9 place-items-center rounded-lg bg-[#edf6ff] text-[#2095f3]"><Icon size={18}/></span><div><h3 className="text-sm font-bold">{s.title}</h3><p className="mt-1 text-xs leading-5 text-[#77808e]">{s.description}</p></div></div><div className="mt-4 grid gap-2 md:grid-cols-2">{s.items.map(item=><div key={item} className="rounded-lg border bg-[#fafbfd] px-3 py-3 text-xs font-semibold text-[#4e5967]">{item}</div>)}</div>{s.id==="access"&&<div className="mt-3 rounded-lg bg-[#f7f9fc] p-3 text-xs text-[#66717f]">Individual role assignment, employee/data scope, invitations, and user-specific permission overrides are managed from <a href="/employee-administration" className="font-bold text-[#0879d5]">People & Access</a>.</div>}{s.id==="notifications"&&<div className="mt-3 rounded-lg bg-[#f7f9fc] p-3 text-xs text-[#66717f]">Organization defaults belong here; each person's own delivery preferences will remain available from the account/profile experience.</div>}</section>})}</div>
   </div>
  </div>
 </AdminShell>
}
