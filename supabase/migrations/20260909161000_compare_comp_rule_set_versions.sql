create or replace function public.compare_comp_rule_set_versions(left_rule_set_id uuid,right_rule_set_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  access jsonb;
  l public.comp_rule_sets%rowtype;
  r public.comp_rule_sets%rowtype;
  result jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to compare compensation plan rules';
  end if;
  select * into l from public.comp_rule_sets where id=left_rule_set_id;
  select * into r from public.comp_rule_sets where id=right_rule_set_id;
  if l.id is null or r.id is null then raise exception 'Rule set version not found'; end if;
  if l.plan_component_id<>r.plan_component_id or l.name<>r.name then
    raise exception 'Only versions of the same logical rule set can be compared';
  end if;

  with lp as (
    select rule_key,jsonb_build_object('name',display_name,'object_type',object_type,'property_name',property_name,'operator_key',operator_key,'comparison_value',comparison_value,'comparison_value_type',comparison_value_type,'association_path',association_path,'association_quantifier',association_quantifier,'case_sensitive',case_sensitive,'include_null_as_match',include_null_as_match) body
    from public.comp_rule_predicates where rule_set_id=l.id
  ), rp as (
    select rule_key,jsonb_build_object('name',display_name,'object_type',object_type,'property_name',property_name,'operator_key',operator_key,'comparison_value',comparison_value,'comparison_value_type',comparison_value_type,'association_path',association_path,'association_quantifier',association_quantifier,'case_sensitive',case_sensitive,'include_null_as_match',include_null_as_match) body
    from public.comp_rule_predicates where rule_set_id=r.id
  ), keys as (select rule_key from lp union select rule_key from rp), pd as (
    select k.rule_key,lp.body left_body,rp.body right_body,
      case when lp.rule_key is null then 'added' when rp.rule_key is null then 'removed' when lp.body is distinct from rp.body then 'changed' else 'unchanged' end change_type
    from keys k left join lp using(rule_key) left join rp using(rule_key)
  ), ln as (
    select coalesce(jsonb_agg(jsonb_build_object('node_type',node_type,'predicate_rule_key',p.rule_key,'logical_operator',logical_operator,'negate',negate,'sort_order',sort_order,'label',label,'parent_sort_order',pn.sort_order) order by n.sort_order,n.id),'[]'::jsonb) body
    from public.comp_rule_expression_nodes n left join public.comp_rule_predicates p on p.id=n.predicate_id left join public.comp_rule_expression_nodes pn on pn.id=n.parent_node_id where n.rule_set_id=l.id
  ), rn as (
    select coalesce(jsonb_agg(jsonb_build_object('node_type',node_type,'predicate_rule_key',p.rule_key,'logical_operator',logical_operator,'negate',negate,'sort_order',sort_order,'label',label,'parent_sort_order',pn.sort_order) order by n.sort_order,n.id),'[]'::jsonb) body
    from public.comp_rule_expression_nodes n left join public.comp_rule_predicates p on p.id=n.predicate_id left join public.comp_rule_expression_nodes pn on pn.id=n.parent_node_id where n.rule_set_id=r.id
  )
  select jsonb_build_object(
    'left',jsonb_build_object('id',l.id,'version',l.version,'active',l.is_active),
    'right',jsonb_build_object('id',r.id,'version',r.version,'active',r.is_active),
    'metadata_changed',jsonb_build_object('purpose',l.purpose is distinct from r.purpose,'description',l.description is distinct from r.description,'evaluation_scope',l.evaluation_scope is distinct from r.evaluation_scope,'stop_on_match',l.stop_on_match is distinct from r.stop_on_match,'outcome_configuration',l.outcome_configuration is distinct from r.outcome_configuration),
    'predicate_changes',coalesce((select jsonb_agg(jsonb_build_object('rule_key',rule_key,'change_type',change_type,'left',left_body,'right',right_body) order by rule_key) from pd where change_type<>'unchanged'),'[]'::jsonb),
    'expression_changed',(select body from ln) is distinct from (select body from rn)
  ) into result;
  return result;
end;
$$;
revoke all on function public.compare_comp_rule_set_versions(uuid,uuid) from public,anon;
grant execute on function public.compare_comp_rule_set_versions(uuid,uuid) to authenticated;
