"use client";

import {useMemo,useState} from "react";

export type RuleFieldOption={value:string;label:string};
export type RuleFieldMeta={data_type:string;options?:RuleFieldOption[];is_multi_value?:boolean};
export type RuleOperatorMeta={operator_key?:string;value_arity:string};

const inputStyle={width:"100%",boxSizing:"border-box" as const};

export default function ValueEditor({field,operator,value,onChange}:{field?:RuleFieldMeta;operator?:RuleOperatorMeta;value:string;onChange:(value:string)=>void}){
  const arity=operator?.value_arity||"single";
  const options=field?.options||[];
  const type=field?.data_type||"string";
  const relativeDateOperator=operator?.operator_key==="within_last"||operator?.operator_key==="not_within_last";
  const[search,setSearch]=useState("");
  const selected=value?value.split("\u001f").filter(Boolean):[];
  const filtered=useMemo(()=>{
    const q=search.trim().toLowerCase();
    return q?options.filter(o=>`${o.label} ${o.value}`.toLowerCase().includes(q)):options;
  },[options,search]);

  if(arity==="none") return <div style={{padding:"8px",color:"#718096"}}>No value needed</div>;

  if(relativeDateOperator&&(type==="date"||type==="datetime")){
    return <div style={{display:"flex",alignItems:"center",gap:6}}>
      <input type="number" min="0" step="1" value={value} onChange={e=>onChange(e.target.value)} placeholder="30" style={inputStyle}/>
      <span style={{whiteSpace:"nowrap",color:"#647184",fontSize:12}}>days</span>
    </div>;
  }

  if(options.length>0&&arity==="single"){
    return <select value={value} onChange={e=>onChange(e.target.value)} style={inputStyle}>
      <option value="">Choose value…</option>
      {options.map(o=><option key={o.value} value={o.value}>{o.label}</option>)}
    </select>;
  }

  if(options.length>0&&arity==="multiple"){
    const toggle=(option:string,checked:boolean)=>{
      const next=checked?[...selected,option]:selected.filter(v=>v!==option);
      onChange([...new Set(next)].join("\u001f"));
    };
    return <div style={{border:"1px solid #cad5df",borderRadius:8,background:"white",overflow:"hidden"}}>
      <div style={{padding:8,borderBottom:"1px solid #e7edf3"}}>
        <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search available values…" style={{...inputStyle,padding:"7px 8px",border:"1px solid #d7e1eb",borderRadius:6}}/>
        <div style={{display:"flex",gap:6,flexWrap:"wrap",marginTop:selected.length?7:0}}>
          {selected.map(v=>{const option=options.find(o=>o.value===v);return <button key={v} type="button" onClick={()=>toggle(v,false)} title="Remove" style={{border:"1px solid #b9d8f4",background:"#eef7ff",borderRadius:999,padding:"3px 7px",fontSize:11,color:"#0b5f9f",cursor:"pointer"}}>{option?.label||v} ×</button>})}
        </div>
      </div>
      <div style={{maxHeight:210,overflowY:"auto",padding:6}}>
        {filtered.length===0?<div style={{padding:8,color:"#718096",fontSize:12}}>No matching values.</div>:filtered.map(o=><label key={o.value} style={{display:"flex",gap:8,alignItems:"flex-start",padding:"7px 8px",borderRadius:6,cursor:"pointer"}}>
          <input type="checkbox" checked={selected.includes(o.value)} onChange={e=>toggle(o.value,e.target.checked)}/>
          <span><span style={{display:"block",fontSize:13}}>{o.label}</span>{o.value!==o.label&&<code style={{fontSize:10,color:"#7a8794"}}>{o.value}</code>}</span>
        </label>)}
      </div>
      <div style={{padding:"6px 8px",borderTop:"1px solid #e7edf3",fontSize:11,color:"#647184"}}>{selected.length} selected</div>
    </div>;
  }

  if(arity==="range"){
    const [low="",high=""]=value.split("\u001f");
    const inputType=type==="date"?"date":type==="datetime"?"datetime-local":type==="number"?"number":"text";
    return <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:6}}>
      <input type={inputType} value={low} onChange={e=>onChange(`${e.target.value}\u001f${high}`)} placeholder="From"/>
      <input type={inputType} value={high} onChange={e=>onChange(`${low}\u001f${e.target.value}`)} placeholder="To"/>
    </div>;
  }

  if(type==="boolean"){
    return <select value={value} onChange={e=>onChange(e.target.value)} style={inputStyle}><option value="">Choose…</option><option value="true">True</option><option value="false">False</option></select>;
  }
  if(type==="date") return <input type="date" value={value} onChange={e=>onChange(e.target.value)} style={inputStyle}/>;
  if(type==="datetime") return <input type="datetime-local" value={value} onChange={e=>onChange(e.target.value)} style={inputStyle}/>;
  if(type==="number") return <input type="number" step="any" value={value} onChange={e=>onChange(e.target.value)} style={inputStyle}/>;

  return <input value={value} onChange={e=>onChange(e.target.value)} placeholder={arity==="multiple"?"Enter values separated by commas":"Value"} style={inputStyle}/>;
}