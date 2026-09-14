"use client";

import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@supabase/supabase-js";
import {ArrowLeft,Save} from "lucide-react";

const supabase=createClient(
 process.env.NEXT_PUBLIC_SUPABASE_URL||"https://bwdtbsqojtxfbeyfkang.supabase.co",
 process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"sb_publishable_UEFOn-Rc0sczK9PwqVI91w_IAz95BcH"
);

type HelpItem={title:string;help_text:string;area:string;updated_at?:string};
type HelpMap=Record<string,HelpItem>;

export default function HelpContentSettings(){
 const[data,setData]=useState<HelpMap>({}),[loading,setLoading]=useState(true),[savingKey,setSavingKey]=useState(""),[error,setError]=useState(""),[message,setMessage]=useState("");
 const load=async()=>{setLoading(true);setError("");const{data:result,error:e}=await supabase.rpc("get_app_help_content");if(e)setError(e.message);else setData((result||{}) as HelpMap);setLoading(false)};
 useEffect(()=>{load()},[]);
 const rows=useMemo(()=>Object.entries(data).sort((a,b)=>`${a[1].area} ${a[1].title}`.localeCompare(`${b[1].area} ${b[1].title}`)),[data]);
 const patch=(key:string,field:keyof HelpItem,value:string)=>setData(current=>({...current,[key]:{...current[key],[field]:value}}));
 const save=async(key:string)=>{const item=data[key];if(!item)return;setSavingKey(key);setError("");setMessage("");const{error:e}=await supabase.rpc("save_app_help_content",{selected_help_key:key,selected_title:item.title,selected_help_text:item.help_text,selected_area:item.area});setSavingKey("");if(e)setError(e.message);else setMessage(`Saved help text for ${item.title}.`)};
 if(loading)return <main style={{padding:28}}>Loading help content…</main>;
 return <main style={{minHeight:"100vh",background:"#f5f7fa",padding:28,color:"#051b34"}}><div style={{maxWidth:1100,margin:"0 auto"}}>
  <div style={{marginBottom:18}}><Link href="/settings" style={{display:"inline-flex",alignItems:"center",gap:6,textDecoration:"none",color:"#475467"}}><ArrowLeft size={15}/>Settings</Link></div>
  <header style={{marginBottom:22}}><small style={{fontWeight:900,color:"#2095f3",letterSpacing:1}}>WORKSPACE HELP</small><h1 style={{fontSize:32,margin:"6px 0"}}>Inline help content</h1><p style={{margin:0,color:"#647184",maxWidth:760}}>Edit the plain-language guidance administrators see while configuring plans and rules. Changes do not require a code deployment.</p></header>
  {error&&<div style={{padding:12,border:"1px solid #f0b4b4",background:"#fff6f6",borderRadius:10,marginBottom:12}}>{error}</div>}
  {message&&<div style={{padding:12,border:"1px solid #b8dfc5",background:"#f4fbf6",borderRadius:10,marginBottom:12}}>{message}</div>}
  <div style={{display:"grid",gap:12}}>{rows.map(([key,item])=><section key={key} style={{background:"white",border:"1px solid #e6e8ec",borderRadius:12,padding:16}}>
    <div style={{display:"grid",gridTemplateColumns:"180px 1fr",gap:12,alignItems:"start"}}>
      <div><small style={{display:"block",fontWeight:800,color:"#667085",marginBottom:5}}>{item.area}</small><code style={{fontSize:11,color:"#98a2b3"}}>{key}</code></div>
      <div style={{display:"grid",gap:9}}>
        <label style={{display:"grid",gap:5,fontWeight:700}}>Help title<input value={item.title} onChange={e=>patch(key,"title",e.target.value)} style={{padding:"9px 10px",border:"1px solid #d0d5dd",borderRadius:8}}/></label>
        <label style={{display:"grid",gap:5,fontWeight:700}}>Help text<textarea value={item.help_text} onChange={e=>patch(key,"help_text",e.target.value)} rows={3} style={{padding:"9px 10px",border:"1px solid #d0d5dd",borderRadius:8,resize:"vertical"}}/></label>
        <div style={{display:"flex",justifyContent:"flex-end"}}><button onClick={()=>save(key)} disabled={savingKey===key} style={{display:"inline-flex",alignItems:"center",gap:7,border:0,borderRadius:8,padding:"9px 13px",background:"#2095f3",color:"white",fontWeight:800,cursor:"pointer"}}><Save size={14}/>{savingKey===key?"Saving…":"Save"}</button></div>
      </div>
    </div>
  </section>)}</div>
 </div></main>;
}
