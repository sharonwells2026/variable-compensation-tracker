"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,Banknote,ClipboardCheck,Coins,FileStack,History,LayoutDashboard,Menu,PanelLeftClose,PanelLeftOpen,Plug,Route,RotateCcw,Scale,Settings,ShieldCheck,Users,Wallet,X} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;
type Access={full_name?:string;email?:string;roles?:string[];permissions?:string[]};
type Item={href:string;label:string;icon:React.ReactNode;show:boolean;exact?:boolean;count?:number};
type Group={label:string;items:Item[]};
const COUNTABLE=new Set(["/attention","/submissions","/payments"]);

export default function AppNav(){
  const pathname=usePathname();
  const[access,setAccess]=useState<Access|null>(null);
  const[collapsed,setCollapsed]=useState(false);
  const[mobileOpen,setMobileOpen]=useState(false);
  useEffect(()=>{let live=true;(async()=>{if(!supabase)return;const{data}=await supabase.rpc("get_current_user_access");if(live&&data)setAccess(data as Access)})();return()=>{live=false}},[]);
  useEffect(()=>setMobileOpen(false),[pathname]);
  useEffect(()=>{try{if(window.localStorage.getItem("eng-nav-collapsed")==="1")setCollapsed(true)}catch{}},[]);
  const toggleCollapsed=()=>setCollapsed(x=>{const next=!x;try{window.localStorage.setItem("eng-nav-collapsed",next?"1":"0")}catch{}return next});

  const groups=useMemo<Group[]>(()=>{
    if(!access)return[];
    const roles=access.roles||[],perms=access.permissions||[];
    const admin=roles.includes("system_administrator");
    const has=(p:string)=>admin||perms.includes(p);
    const g=(label:string,items:Item[])=>({label,items:items.filter(x=>x.show)});
    return [
      g("WORK",[
        {href:"/manage",label:"Control Center",icon:<LayoutDashboard size={17}/>,show:admin||has("workspace.view_administration")},
        {href:"/attention",label:"Needs Attention",icon:<AlertTriangle size={17}/>,show:admin||has("workspace.view_administration")||has("earnings.view")||has("payments.view")},
        {href:"/me",label:"My Compensation",icon:<Wallet size={17}/>,show:has("workspace.view_self")},
      ]),
      g("APPROVE & PAY",[
        {href:"/submissions",label:"Pending Actions",icon:<ClipboardCheck size={17}/>,show:has("earnings.approve")||roles.includes("executive_administrator")},
        {href:"/payments",label:"Payments",icon:<Banknote size={17}/>,show:has("payments.view")},
        {href:"/corrections",label:"Corrections",icon:<RotateCcw size={17}/>,show:has("earnings.edit")||has("earnings.override")},
      ]),
      g("RECORDS",[
        {href:"/earnings",label:"Earnings & Credits",icon:<Coins size={17}/>,show:has("earnings.view")},
        {href:"/employees",label:"Employees",icon:<Users size={17}/>,show:has("users.manage")||has("users.act_as")},
        {href:"/plans",label:"Plans",icon:<FileStack size={17}/>,show:has("plans.view"),exact:true},
        {href:"/reconciliation",label:"Reconciliation",icon:<Scale size={17}/>,show:has("reconciliation.view")||has("reconciliation.manage")},
      ]),
      g("SYSTEM",[
        {href:"/workflow",label:"Workflow",icon:<Route size={17}/>,show:has("settings.manage")||has("plans.view")},
        {href:"/hubspot",label:"HubSpot Source Data",icon:<Plug size={17}/>,show:has("integrations.view")||has("integrations.configure")||has("hubspot.refresh")},
        {href:"/users",label:"Users & Permissions",icon:<ShieldCheck size={17}/>,show:has("users.manage")||has("permissions.view")},
        {href:"/audit",label:"Audit Log",icon:<History size={17}/>,show:has("audit.view_all")||has("audit.view_assigned")},
        {href:"/settings",label:"Settings",icon:<Settings size={17}/>,show:has("settings.manage")||has("settings.hubspot_mapping.view")||has("settings.hubspot_mapping.edit")},
      ]),
    ].filter(group=>group.items.length>0);
  },[access]);

  if(pathname==="/"||!access)return null;
  const active=(item:Item)=>item.exact?pathname===item.href:(pathname===item.href||pathname.startsWith(`${item.href}/`));
  const initials=(access.full_name||access.email||"U").split(/\s+/).map(x=>x[0]).join("").slice(0,2).toUpperCase();
  const link=(i:Item,inDrawer=false)=>{const on=active(i);const showCount=COUNTABLE.has(i.href)&&typeof i.count==="number"&&i.count>0;return <Link key={i.href} href={i.href} className={on?"active":""} aria-current={on?"page":undefined} title={collapsed&&!inDrawer?i.label:undefined}><span className="app-nav-icon">{i.icon}{showCount&&collapsed&&!inDrawer?<span className="app-nav-dot" aria-hidden="true"/>:null}</span><span className="app-nav-label">{i.label}</span>{showCount?<span className="app-nav-count">{i.count!>99?"99+":i.count}</span>:null}</Link>};
  const nav=<><div className="app-sidebar-brand"><Link href="/manage" aria-label="Engagifii Compensation home"><span className="app-brand-mark" aria-hidden="true">E</span><span className="app-brand-copy"><b>ENGAGIFII</b><span>Compensation</span></span></Link></div><nav className="app-sidebar-nav" aria-label="Main">{groups.map(group=><div className="app-sidebar-group" key={group.label}><div className="app-sidebar-group-label">{group.label}</div>{group.items.map(i=>link(i))}</div>)}</nav><div className="app-sidebar-foot"><div className="app-sidebar-user"><div className="app-user-avatar">{initials}</div><div className="app-user-copy"><b>{access.full_name||"Signed in"}</b><span>{access.email||""}</span></div></div><button type="button" className="app-sidebar-collapse" onClick={toggleCollapsed} aria-label={collapsed?"Expand navigation":"Collapse navigation"}>{collapsed?<PanelLeftOpen size={16}/>:<PanelLeftClose size={16}/>}<span className="app-nav-label">Collapse</span></button></div></>;
  return <><aside className={`app-sidebar ${collapsed?"collapsed":""}`}>{nav}</aside><header className="app-mobile-header"><Link href="/manage" className="app-mobile-brand"><span className="app-brand-mark" aria-hidden="true">E</span><span className="app-brand-copy"><b>ENGAGIFII</b><span>Compensation</span></span></Link><button onClick={()=>setMobileOpen(x=>!x)} aria-label={mobileOpen?"Close navigation":"Open navigation"} aria-expanded={mobileOpen}>{mobileOpen?<X size={22}/>:<Menu size={22}/>}</button></header>{mobileOpen&&<div className="app-mobile-drawer"><div className="app-mobile-drawer-nav">{groups.map(group=><div className="app-sidebar-group" key={group.label}><div className="app-sidebar-group-label">{group.label}</div>{group.items.map(i=>link(i,true))}</div>)}</div><div className="app-sidebar-user"><div className="app-user-avatar">{initials}</div><div className="app-user-copy"><b>{access.full_name||"Signed in"}</b><span>{access.email||""}</span></div></div></div>}</>;
}
