"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {CircleHelp,RefreshCw,Save,Search} from "lucide-react";

const supabase=createClient(
 process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type HelpItem={title:string;help_text:string;area:string;updated_at?:string};
type HelpMap=Record<string,HelpItem>;

export default function HelpContentSettings(){
 const[data,setData]=useState<HelpMap>({}),[loading,setLoading]=useState(true),[savingKey,setSavingKey]=useState(""),[error,setError]=useState(""),[message,setMessage]=useState(""),[query,setQuery]=useState("");
 const load=async()=>{setLoading(true);setError("");const{data:result,error:e}=await supabase.rpc("get_app_help_content");if(e)setError("Inline help could not be loaded. Try again, or check Settings access if the problem continues.");else setData((result||{}) as HelpMap);setLoading(false)};
 useEffect(()=>{load()},[]);
 const rows=useMemo(()=>Object.entries(data).sort((a,b)=>`${a[1].area} ${a[1].title}`.localeCompare(`${b[1].area} ${b[1].title}`)),[data]);
 const filtered=useMemo(()=>{const q=query.trim().toLowerCase();return q?rows.filter(([key,item])=>`${key} ${item.area} ${item.title} ${item.help_text}`.toLowerCase().includes(q)):rows},[rows,query]);
 const areas=useMemo(()=>new Set(rows.map(([,item])=>item.area)).size,[rows]);
 const patch=(key:string,field:keyof HelpItem,value:string)=>setData(current=>({...current,[key]:{...current[key],[field]:value}}));
 const save=async(key:string)=>{const item=data[key];if(!item)return;setSavingKey(key);setError("");setMessage("");const{error:e}=await supabase.rpc("save_app_help_content",{selected_help_key:key,selected_title:item.title,selected_help_text:item.help_text,selected_area:item.area});setSavingKey("");if(e)setError(`Help text for ${item.title} could not be saved. No other help content was changed.`);else setMessage(`Saved help text for ${item.title}.`)};

 return <main className="eng-page"><div className="eng-page__shell">
  <nav className="eng-breadcrumb" aria-label="Breadcrumb"><Link href="/manage">Control Center</Link><span className="eng-breadcrumb__sep">/</span><Link href="/settings">Settings</Link><span className="eng-breadcrumb__sep">/</span><span className="eng-breadcrumb__current">Inline Help</span></nav>
  <header className="eng-page-header"><div className="eng-page-header__main"><span className="eng-page-header__eyebrow">WORKSPACE HELP</span><div className="eng-page-header__titlerow"><h1>Inline help content</h1></div><p className="eng-page-header__lede">Edit the plain-language guidance administrators see while configuring compensation. Changes take effect without a code deployment.</p></div><div className="eng-page-header__actions"><button className="eng-btn" onClick={load} disabled={loading}><RefreshCw size={15}/>{loading?"Refreshing…":"Refresh"}</button></div></header>

  {error&&<div className="eng-callout eng-callout--danger"><div className="eng-callout__body"><b>Help content unavailable</b>{error}</div></div>}
  {message&&<div className="eng-callout eng-callout--success" style={{marginTop:10}}><div className="eng-callout__body"><b>Saved</b>{message}</div></div>}

  <section style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(190px,1fr))",gap:10,margin:"16px 0"}}>
   <div className="eng-card"><div className="eng-card__body"><small>Total help items</small><b className="eng-figure eng-figure--strong" style={{display:"block",fontSize:26,marginTop:4}}>{loading?"—":rows.length}</b></div></div>
   <div className="eng-card"><div className="eng-card__body"><small>Configuration areas</small><b className="eng-figure eng-figure--strong" style={{display:"block",fontSize:26,marginTop:4}}>{loading?"—":areas}</b></div></div>
   <div className="eng-card"><div className="eng-card__body"><small>Visible in this view</small><b className="eng-figure eng-figure--strong" style={{display:"block",fontSize:26,marginTop:4}}>{loading?"—":filtered.length}</b></div></div>
  </section>

  <section className="eng-card" style={{marginBottom:14}}><div className="eng-card__body" style={{display:"flex",gap:10,alignItems:"center",flexWrap:"wrap"}}><Search size={16}/><input className="eng-input" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search help title, area, text, or key" style={{flex:"1 1 320px"}}/></div></section>

  {loading?<section className="eng-card"><div className="eng-card__body">Loading help content…</div></section>:filtered.length===0?<section className="eng-empty"><div className="eng-empty__icon"><CircleHelp size={22}/></div><h2>No help content matches</h2><p>Try a broader search. Existing help entries have not been changed.</p></section>:<div style={{display:"grid",gap:12}}>{filtered.map(([key,item])=><section key={key} className="eng-card">
    <div className="eng-card__body" style={{display:"grid",gridTemplateColumns:"minmax(150px,190px) minmax(0,1fr)",gap:16,alignItems:"start"}}>
      <div><span className="eng-badge eng-badge--info">{item.area}</span><code className="eng-ident" style={{display:"block",marginTop:8}}>{key}</code>{item.updated_at&&<small style={{display:"block",marginTop:8,color:"var(--eng-ink-faint)"}}>Updated {new Date(item.updated_at).toLocaleString()}</small>}</div>
      <div style={{display:"grid",gap:10}}>
        <label style={{display:"grid",gap:5,fontWeight:700}}>Help title<input className="eng-input" value={item.title} onChange={e=>patch(key,"title",e.target.value)}/></label>
        <label style={{display:"grid",gap:5,fontWeight:700}}>Help text<textarea className="eng-input" value={item.help_text} onChange={e=>patch(key,"help_text",e.target.value)} rows={3} style={{resize:"vertical",minHeight:88}}/></label>
        <div style={{display:"flex",justifyContent:"flex-end"}}><button className="eng-btn eng-btn--primary" onClick={()=>save(key)} disabled={Boolean(savingKey)}><Save size={14}/>{savingKey===key?"Saving…":"Save help text"}</button></div>
      </div>
    </div>
  </section>)}</div>}
 </div></main>;
}
