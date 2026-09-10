"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {
  AlertTriangle, BarChart3, BriefcaseBusiness, ChevronLeft, ChevronRight,
  ClipboardCheck, CreditCard, History, Home, Menu, RefreshCw, Settings,
  ShieldCheck, SlidersHorizontal, Users, WalletCards, X
} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;

type Access={full_name?:string;email?:string;roles?:string[];permissions?:string[]};
type Item={href:string;label:string;icon:React.ReactNode;show:boolean};
type Group={label:string;items:Item[]};

export default function AppNav(){
  const pathname=usePathname();
  const[access,setAccess]=useState<Access|null>(null);
  const[collapsed,setCollapsed]=useState(false);
  const[mobileOpen,setMobileOpen]=useState(false);
  const[refreshing,setRefreshing]=useState(false);

  useEffect(()=>{let live=true;(async()=>{if(!supabase)return;const{data}=await supabase.rpc("get_current_user_access");if(live&&data)setAccess(data as Access)})();return()=>{live=false}},[]);
  useEffect(()=>setMobileOpen(false),[pathname]);

  const groups=useMemo<Group[]>(()=>{
    if(!access)return[];
    const roles=access.roles||[],perms=access.permissions||[];
    const admin=roles.includes("system_administrator");
    const has=(p:string)=>admin||perms.includes(p);
    const g=(label:string,items:Item[])=>({label,items:items.filter(x=>x.show)});
    return [
      g("WORK",[
        {href:"/manage",label:"Control Center",icon:<Home size={18}/>,show:admin||has("workspace.view_administration")},
        {href:"/attention",label:"Needs Attention",icon:<AlertTriangle size={18}/>,show:admin||has("workspace.view_administration")||has("earnings.view")||has("payments.view")},
        {href:"/me",label:"My Compensation",icon:<BriefcaseBusiness size={18}/>,show:has("workspace.view_self")},
      ]),
      g("APPROVE & PAY",[
        {href:"/submissions",label:"Approvals",icon:<ClipboardCheck size={18}/>,show:has("earnings.approve")||roles.includes("executive_administrator")},
        {href:"/payments",label:"Payments",icon:<WalletCards size={18}/>,show:has("payments.view")},
        {href:"/corrections",label:"Corrections",icon:<RefreshCw size={18}/>,show:has("earnings.edit")||has("earnings.override")},
      ]),
      g("RECORDS",[
        {href:"/earnings",label:"Earnings & Credits",icon:<CreditCard size={18}/>,show:has("earnings.view")},
        {href:"/employees",label:"Employees",icon:<Users size={18}/>,show:has("users.manage")||has("users.act_as")},
        {href:"/plans",label:"Plans & Rules",icon:<BarChart3 size={18}/>,show:has("plans.view")},
        {href:"/reconciliation",label:"Reconciliation",icon:<SlidersHorizontal size={18}/>,show:has("reconciliation.view")||has("reconciliation.manage")},
      ]),
      g("SYSTEM",[
        {href:"/workflow",label:"Workflow",icon:<SlidersHorizontal size={18}/>,show:has("settings.manage")||has("plans.view")},
        {href:"/hubspot",label:"HubSpot",icon:<RefreshCw size={18}/>,show:has("integrations.view")||has("integrations.configure")||has("hubspot.refresh")},
        {href:"/users",label:"Users & Permissions",icon:<ShieldCheck size={18}/>,show:has("users.manage")||has("permissions.view")},
        {href:"/audit",label:"Audit Log",icon:<History size={18}/>,show:has("audit.view_all")||has("audit.view_assigned")},
        {href:"/settings",label:"Settings",icon:<Settings size={18}/>,show:has("settings.manage")||has("settings.hubspot_mapping.view")||has("settings.hubspot_mapping.edit")},
      ]),
    ].filter(group=>group.items.length>0);
  },[access]);

  if(pathname==="/"||!access)return null;
  const active=(href:string)=>pathname===href||pathname.startsWith(`${href}/`);
  const initials=(access.full_name||access.email||"U").split(/\s+/).map(x=>x[0]).join("").slice(0,2).toUpperCase();

  const nav=<>
    <div className="app-sidebar-brand">
      <Link href="/manage" aria-label="Engagifii Compensation home">
        <b>ENGAGIFII</b><span>Compensation</span>
      </Link>
      <button className="app-sidebar-collapse" onClick={()=>setCollapsed(x=>!x)} aria-label={collapsed?"Expand navigation":"Collapse navigation"}>{collapsed?<ChevronRight size={17}/>:<ChevronLeft size={17}/>}</button>
    </div>
    <nav className="app-sidebar-nav">
      {groups.map(group=><div className="app-sidebar-group" key={group.label}>
        <div className="app-sidebar-group-label">{group.label}</div>
        {group.items.map(i=><Link key={i.href} href={i.href} className={active(i.href)?"active":""} title={collapsed?i.label:undefined}>{i.icon}<span>{i.label}</span></Link>)}
      </div>)}
    </nav>
    <div className="app-sidebar-user">
      <div className="app-user-avatar">{initials}</div>
      <div className="app-user-copy"><b>{access.full_name||"Signed in"}</b><span>{access.email||""}</span></div>
    </div>
  </>;

  return <>
    <aside className={`app-sidebar ${collapsed?"collapsed":""}`}>{nav}</aside>
    <header className="app-mobile-header">
      <Link href="/manage" className="app-mobile-brand"><b>ENGAGIFII</b><span>Compensation</span></Link>
      <button onClick={()=>setMobileOpen(x=>!x)} aria-label="Open navigation">{mobileOpen?<X size={22}/>:<Menu size={22}/>}</button>
    </header>
    {mobileOpen&&<div className="app-mobile-drawer"><div className="app-mobile-drawer-nav">{groups.map(group=><div key={group.label}><div className="app-sidebar-group-label">{group.label}</div>{group.items.map(i=><Link key={i.href} href={i.href} className={active(i.href)?"active":""}>{i.icon}<span>{i.label}</span></Link>)}</div>)}</div><div className="app-sidebar-user"><div className="app-user-avatar">{initials}</div><div className="app-user-copy"><b>{access.full_name||"Signed in"}</b><span>{access.email||""}</span></div></div></div>}
  </>;
}
