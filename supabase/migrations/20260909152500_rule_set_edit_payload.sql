create or replace function public.get_comp_rule_set_for_editing(target_rule_set_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  access jsonb;
  s public.comp_rule_sets%rowtype;
  result jsonb;
begin
  access := public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to view compensation plan rules';
  end if;

  select * into s from public.comp_rule_sets where id=target_rule_set_id;
  if s.id is null then raise exception 'Rule set not found'; end if;

  select jsonb_build_object(
    'id',s.id,
    'plan_component_id',s.plan_component_id,
    'name',s.name,
    'purpose',s.purpose,
    'description',s.description,
    'evaluation_scope',s.evaluation_scope,
    'version',s.version,
    'is_active',s.is_active,
    'predicates',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.id,'rule_key',p.rule_key,'display_name',p.display_name,'object_type',p.object_type,
      'property_name',p.property_name,'operator_key',p.operator_key,'comparison_value',p.comparison_value,
      'comparison_value_type',p.comparison_value_type,'association_path',p.association_path,
      'association_quantifier',p.association_quantifier,'case_sensitive',p.case_sensitive,
      'include_null_as_match',p.include_null_as_match
    ) order by p.created_at,p.id) from public.comp_rule_predicates p where p.rule_set_id=s.id),'[]'::jsonb),
    'nodes',coalesce((select jsonb_agg(jsonb_build_object(
      'id',n.id,'parent_node_id',n.parent_node_id,'node_type',n.node_type,'predicate_id',n.predicate_id,
      'logical_operator',n.logical_operator,'negate',n.negate,'sort_order',n.sort_order,'label',n.label
    ) order by n.sort_order,n.created_at,n.id) from public.comp_rule_expression_nodes n where n.rule_set_id=s.id),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.get_comp_rule_set_for_editing(uuid) from public,anon;
grant execute on function public.get_comp_rule_set_for_editing(uuid) to authenticated;
