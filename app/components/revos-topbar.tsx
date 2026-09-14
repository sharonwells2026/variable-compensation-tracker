"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {BarChart3,ChevronDown,CircleDollarSign,FileSignature,Menu,Presentation,RefreshCw,BookOpen,Handshake} from "lucide-react";
import {createClient} from "@supabase/supabase-js";

const supabase=createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type Access={full_name?:string;email?:string};
type Module={id:string;label:string;note:string;status:"active"|"pilot"|"soon";href?:string;icon:React.ReactNode};

export default function RevOSTopBar(){
  const pathname=usePathname();
  const[open,setOpen]=useState(false);
  const[access,setAccess]=useState<Access>({});
  const growthUrl=process.env.NEXT_PUBLIC_REVOS_GROWTH_URL||"";
  useEffect(()=>{let live=true;(async()=>{const{data}=await supabase.rpc("get_current_user_access");if(live&&data)setAccess(data as Access)})();return()=>{live=false}},[]);
  useEffect(()=>setOpen(false),[pathname]);
  const modules=useMemo<Module[]>(()=>[
    {id:"growth",label:"Growth Analytics",note:"Pipeline, forecast and growth performance",status:growthUrl?"active":"soon",href:growthUrl||undefined,icon:<BarChart3 size={16}/>},
    {id:"meeting",label:"Sales Meeting Hub",note:"QDCs, demos and meeting outcomes",status:"soon",icon:<Handshake size={16}/>},
    {id:"compensation",label:"Compensation",note:"Plans, earnings, approvals and payments",status:"pilot",href:"/manage",icon:<CircleDollarSign size={16}/>},
    {id:"cpq",label:"Proposals & CPQ",note:"Quoting, proposals and approvals",status:"soon",icon:<FileSignature size={16}/>},
    {id:"subscriptions",label:"Subscriptions & Expansion",note:"Renewals, dues and installed-base expansion",status:"soon",icon:<RefreshCw size={16}/>},
    {id:"content",label:"Playbooks & Content",note:"Sales plays, enablement and collateral",status:"soon",icon:<BookOpen size={16}/>},
  ],[growthUrl]);
  const initials=(access.full_name||access.email||"SW").split(/\s+/).map(x=>x[0]).join("").slice(0,2).toUpperCase();
  if(pathname==="/")return null;
  return <header className="revos-topbar">
    <div className="revos-topbar__left">
      <button className="revos-icon-button revos-topbar__menu" aria-label="Open module navigation"><Menu size={18}/></button>
      <Link href="/manage" className="revos-brand" aria-label="Engagifii Compensation home"><img src="/engagifii-logo.png" alt="Engagifii"/></Link>
      <span className="revos-divider"/>
      <div className="revos-module-switcher">
        <button className="revos-module-button" onClick={()=>setOpen(v=>!v)} aria-expanded={open} aria-haspopup="menu"><CircleDollarSign size={15}/><span>Compensation</span><ChevronDown size={14} className={open?"rotated":""}/></button>
        {open&&<div className="revos-module-menu" role="menu">
          <div className="revos-module-menu__heading">ENGAGIFII REVOS MODULES</div>
          {modules.map(m=>{
            const content=<><span className="revos-module-icon">{m.icon}</span><span className="revos-module-copy"><b>{m.label}</b><small>{m.note}</small></span><span className={`revos-module-status ${m.status}`}>{m.status==="soon"?"COMING SOON":m.status.toUpperCase()}</span></>;
            if(m.href&&m.id!=="compensation")return <a key={m.id} className="revos-module-row" href={m.href} role="menuitem">{content}</a>;
            if(m.id==="compensation")return <Link key={m.id} className="revos-module-row active" href="/manage" role="menuitem">{content}</Link>;
            return <div key={m.id} className="revos-module-row disabled" aria-disabled="true">{content}</div>;
          })}
        </div>}
      </div>
    </div>
    <div className="revos-topbar__right">
      <span className="revos-shell-label">RevOS</span>
      <button className="revos-action-button" type="button" disabled title="Presentation controls are available in Growth Analytics"><Presentation size={15}/> Presentation</button>
      <div className="revos-user"><span>{initials}</span><div><b>{access.full_name||"Engagifii user"}</b><small>Crescerance · Engagifii</small></div></div>
    </div>
    <div className="revos-accent-bar"/>
  </header>;
}