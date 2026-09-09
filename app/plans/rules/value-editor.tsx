"use client";

export type RuleFieldOption={value:string;label:string};
export type RuleFieldMeta={data_type:string;options?:RuleFieldOption[];is_multi_value?:boolean};
export type RuleOperatorMeta={operator_key?:string;value_arity:string};

export default function ValueEditor({field,operator,value,onChange}:{field?:RuleFieldMeta;operator?:RuleOperatorMeta;value:string;onChange:(value:string)=>void}){
  const arity=operator?.value_arity||"single";
  const options=field?.options||[];
  const type=field?.data_type||"string";
  const relativeDateOperator=operator?.operator_key==="within_last"||operator?.operator_key==="not_within_last";
  if(arity==="none") return <div style={{padding:"8px",color:"#718096"}}>No value needed</div>;

  if(relativeDateOperator&&(type==="date"||type==="datetime")){
    return <div style={{display:"flex",alignItems:"center",gap:6}}>
      <input type="number" min="0" step="1" value={value} onChange={e=>onChange(e.target.value)} placeholder="30" style={{width:"100%"}}/>
      <span style={{whiteSpace:"nowrap",color:"#647184",fontSize:12}}>days</span>
    </div>;
  }

  if(options.length>0&&arity==="single"){
    return <select value={value} onChange={e=>onChange(e.target.value)} style={{width:"100%"}}>
      <option value="">Choose value…</option>
      {options.map(o=><option key={o.value} value={o.value}>{o.label}</option>)}
    </select>;
  }

  if(options.length>0&&arity==="multiple"){
    const selected=value?value.split("\u001f"):[];
    return <select multiple value={selected} onChange={e=>onChange(Array.from(e.target.selectedOptions).map(o=>o.value).join("\u001f"))} style={{width:"100%",minHeight:92}}>
      {options.map(o=><option key={o.value} value={o.value}>{o.label}</option>)}
    </select>;
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
    return <select value={value} onChange={e=>onChange(e.target.value)} style={{width:"100%"}}><option value="">Choose…</option><option value="true">True</option><option value="false">False</option></select>;
  }
  if(type==="date") return <input type="date" value={value} onChange={e=>onChange(e.target.value)} style={{width:"100%"}}/>;
  if(type==="datetime") return <input type="datetime-local" value={value} onChange={e=>onChange(e.target.value)} style={{width:"100%"}}/>;
  if(type==="number") return <input type="number" step="any" value={value} onChange={e=>onChange(e.target.value)} style={{width:"100%"}}/>;

  return <input value={value} onChange={e=>onChange(e.target.value)} placeholder={arity==="multiple"?"Enter values separated by commas":"Value"} style={{width:"100%"}}/>;
}
