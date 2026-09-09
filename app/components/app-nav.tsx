"use client";

import {useEffect,useState} from "react";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {createClient} from "@supabase/supabase-js";
import {AlertTriangle,BarChart3,BriefcaseBusiness,ChevronDown,ClipboardCheck,History,Home,Menu,Settings,ShieldCheck,Users,WalletCards,X} from "lucide-react";

const supabaseUrl=process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co";
const supabaseKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH";
const supabase=supabaseUrl&&supabaseKey?createClient(supabaseUrl,supabaseKey):null;
type Access={full_name?:string;email?:string;roles?:string[];permissions?:string[]};
type Item={href:string;label:string;icon:React.ReactNode;show:boolean};

export default function AppNav(){
 const pathname=usePathname();
 const[access,setAccess]=useState<Access|null>(null),[open,setOpen]=useState(false),[more,setMore]=useState(false);
 useEffect(()=>{let live=true;(async()=>{if(!supabase)return;const{data}=await supabase.rpc("get_current_user_access");if(live&&data)setAccess(data as Access)})();return()=>{live=false}},[]);
 useEffect(()=>{setOpen(false);setMore(false)},[pathname]);
 if(pathname==="/"||!access)return null;
 const roles=access.roles||[],perms=access.permissions||[];
 const admin=roles.includes("system_administrator"),has=(p:string)=>admin||perms.includes(p);
 const items:Item[]=[
  {href:"/manage",label:"Control Center",icon:<Home size={16}/>,show:admin||has("workspace.view_administration")},
  {href:"/attention",label:"Needs Attention",icon:<AlertTriangle size={16}/>,show:admin||has("workspace.view_administration")||has("earnings.view")||has("payments.view")},
  {href:"/me",label:"My Compensation",icon:<BriefcaseBusiness size={16}/>,show:has("workspace.view_self")},
  {href:"/submissions",label:"Approvals",icon:<ClipboardCheck size={16}/>,show:has("earnings.approve")||roles.includes("executive_administrator")},
  {href:"/payments",label:"Payments",icon:<WalletCards size={16}/>,show:has("payments.view")},
  {href:"/employees",label:"Employees",icon:<Users size={16}/>,show:has("users.manage")||has("users.act_as")},
  {href:"/corrections",label:"Corrections",icon:<AlertTriangle size={16}/>,show:has("earnings.edit")||has("earnings.override")},
  {href:"/plans",label:"Plans",icon:<BarChart3 size={16}/>,show:has("plans.view")},
  {href:"/users",label:"Users & Permissions",icon:<ShieldCheck size={16}/>,show:has("users.manage")||has("permissions.view")},
  {href:"/audit",label:"Audit Log",icon:<History size={16}/>,show:has("audit.view_all")||has("audit.view_assigned")},
  {href:"/settings",label:"Settings",icon:<Settings size={16}/>,show:has("settings.manage")||has("settings.hubspot_mapping.view")||has("settings.hubspot_mapping.edit")},
 ].filter(x=>x.show);
 const primary=items.slice(0,5),secondary=items.slice(5);
 const active=(href:string)=>pathname===href||pathname.startsWith(`${href}/`);
 return <><div className="app-nav-bar"><Link href="/" className="app-nav-brand"><b>ENGAGIFII</b><span>Compensation</span></Link><nav className="app-nav-desktop">{primary.map(i=><Link key={i.href} href={i.href} className={active(i.href)?"active":""}>{i.icon}<span>{i.label}</span></Link>)}{secondary.length>0&&<div className="app-nav-more"><button onClick={()=>setMore(x=>!x)} className={secondary.some(i=>active(i.href))?"active":""}>More <ChevronDown size={14}/></button>{more&&<div className="app-nav-menu">{secondary.map(i=><Link key={i.href} href={i.href} className={active(i.href)?"active":""}>{i.icon}<span>{i.label}</span></Link>)}</div>}</div>}</nav><div className="app-nav-user"><span>{access.full_name||access.email||"Signed in"}</span><button aria-label="Open navigation" onClick={()=>setOpen(x=>!x)} className="app-nav-mobile-button">{open?<X size={20}/>:<Menu size={20}/>}</button></div></div>{open&&<nav className="app-nav-mobile">{items.map(i=><Link key={i.href} href={i.href} className={active(i.href)?"active":""}>{i.icon}<span>{i.label}</span></Link>)}</nav>}</>;
}