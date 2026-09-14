export type SavedPredicate={
  id:string;rule_key:string;display_name:string;object_type:string;property_name:string;operator_key:string;
  comparison_value:unknown;comparison_value_type:string;association_quantifier:string|null;
  case_sensitive:boolean;include_null_as_match:boolean;
};
export type SavedNode={
  id:string;parent_node_id:string|null;node_type:"group"|"predicate";predicate_id:string|null;
  logical_operator:"AND"|"OR"|null;negate:boolean;sort_order:number;label:string|null;
};
export type SavedRuleSet={
  id:string;plan_component_id:string;name:string;purpose:string;description:string|null;evaluation_scope:string;
  version:number;is_active:boolean;predicates:SavedPredicate[];nodes:SavedNode[];
};
export type EditorRule={
  id:string;key:string;name:string;objectType:string;property:string;operator:string;value:string;
  quantifier:"record"|"any"|"all"|"none";caseSensitive:boolean;includeNull:boolean;
};
export type EditorRuleNode={id:string;type:"rule";ruleId:string;negate:boolean};
export type EditorGroupNode={id:string;type:"group";op:"AND"|"OR";negate:boolean;children:(EditorRuleNode|EditorGroupNode)[]};

export function editorValue(value:unknown):string{
  if(value==null)return "";
  if(Array.isArray(value))return value.map(String).join("\u001f");
  if(typeof value==="object"){
    const v=value as Record<string,unknown>;
    if("low" in v||"high" in v)return `${v.low??""}\u001f${v.high??""}`;
    return JSON.stringify(value);
  }
  return String(value);
}

export function hydrateRules(saved:SavedRuleSet):EditorRule[]{
  return (saved.predicates||[]).map(p=>({
    id:p.id,key:p.rule_key,name:p.display_name,objectType:p.object_type,property:p.property_name,
    operator:p.operator_key,value:editorValue(p.comparison_value),
    quantifier:(p.object_type==="deal"?"record":p.association_quantifier||"any") as EditorRule["quantifier"],
    caseSensitive:!!p.case_sensitive,includeNull:!!p.include_null_as_match
  }));
}

export function hydrateExpression(saved:SavedRuleSet):EditorGroupNode{
  const nodes=[...(saved.nodes||[])].sort((a,b)=>(a.sort_order??0)-(b.sort_order??0));
  const childrenByParent=new Map<string|null,SavedNode[]>();
  for(const n of nodes){const key=n.parent_node_id??null;childrenByParent.set(key,[...(childrenByParent.get(key)||[]),n]);}
  const root=nodes.find(n=>n.parent_node_id==null&&n.node_type==="group");
  if(!root)return {id:"root",type:"group",op:"AND",negate:false,children:[]};
  const build=(n:SavedNode):EditorRuleNode|EditorGroupNode=>{
    if(n.node_type==="predicate")return {id:n.id,type:"rule",ruleId:n.predicate_id||"",negate:!!n.negate};
    return {id:n.id,type:"group",op:n.logical_operator==="OR"?"OR":"AND",negate:!!n.negate,children:(childrenByParent.get(n.id)||[]).map(build)};
  };
  return build(root) as EditorGroupNode;
}
