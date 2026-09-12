-- Compensation rule saves must never activate logic implicitly.
-- New rule sets are drafts; active versions are immutable and require a successor version for changes.
create or replace function public.save_comp_rule_set(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  set_id uuid;
  pred jsonb;
  node jsonb;
  generated_id uuid;
  existing public.comp_rule_sets%rowtype;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to edit compensation plan rules';
  end if;
  if payload->>'plan_component_id' is null or payload->>'name' is null or payload->>'purpose' is null then
    raise exception 'plan_component_id, name and purpose are required';
  end if;

  if payload->>'id' is null then
    insert into public.comp_rule_sets(
      plan_component_id,name,purpose,description,evaluation_scope,version,is_active,
      stop_on_match,outcome_configuration,created_by,updated_by
    ) values (
      (payload->>'plan_component_id')::uuid,payload->>'name',payload->>'purpose',payload->>'description',
      coalesce(payload->>'evaluation_scope','record'),coalesce((payload->>'version')::int,1),false,
      coalesce((payload->>'stop_on_match')::boolean,false),coalesce(payload->'outcome_configuration','{}'::jsonb),
      (select auth.uid()),(select auth.uid())
    ) returning id into set_id;
  else
    set_id:=(payload->>'id')::uuid;
    select * into existing from public.comp_rule_sets where id=set_id for update;
    if existing.id is null then raise exception 'Rule set not found'; end if;
    if existing.is_active then raise exception 'Active rule versions are immutable. Create a new inactive version before editing.'; end if;
    if existing.plan_component_id<>(payload->>'plan_component_id')::uuid then raise exception 'A rule version cannot be moved to another plan component'; end if;

    update public.comp_rule_sets
      set name=payload->>'name',purpose=payload->>'purpose',description=payload->>'description',
          evaluation_scope=coalesce(payload->>'evaluation_scope','record'),is_active=false,
          stop_on_match=coalesce((payload->>'stop_on_match')::boolean,false),
          outcome_configuration=coalesce(payload->'outcome_configuration','{}'::jsonb),
          updated_by=(select auth.uid()),updated_at=now()
    where id=set_id;

    delete from public.comp_rule_expression_nodes where rule_set_id=set_id;
    delete from public.comp_rule_predicates where rule_set_id=set_id;
  end if;

  create temporary table if not exists _rule_pred_map(client_key text primary key,predicate_id uuid) on commit drop;
  truncate _rule_pred_map;
  for pred in select * from jsonb_array_elements(coalesce(payload->'predicates','[]'::jsonb)) loop
    insert into public.comp_rule_predicates(
      rule_set_id,rule_key,display_name,object_type,association_path,association_quantifier,
      aggregate_function,aggregate_window,property_name,operator_key,comparison_value,
      comparison_value_type,case_sensitive,include_null_as_match,notes
    ) values (
      set_id,pred->>'rule_key',coalesce(pred->>'display_name',pred->>'rule_key'),pred->>'object_type',
      coalesce(pred->'association_path','[]'::jsonb),coalesce(pred->>'association_quantifier','record'),
      pred->>'aggregate_function',pred->'aggregate_window',pred->>'property_name',pred->>'operator_key',
      pred->'comparison_value',pred->>'comparison_value_type',coalesce((pred->>'case_sensitive')::boolean,false),
      coalesce((pred->>'include_null_as_match')::boolean,false),pred->>'notes'
    ) returning id into generated_id;
    insert into _rule_pred_map(client_key,predicate_id) values (pred->>'client_key',generated_id);
  end loop;

  create temporary table if not exists _rule_node_map(client_key text primary key,node_id uuid) on commit drop;
  truncate _rule_node_map;
  for node in select * from jsonb_array_elements(coalesce(payload->'nodes','[]'::jsonb)) loop
    insert into public.comp_rule_expression_nodes(
      rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label
    ) values (
      set_id,(select node_id from _rule_node_map where client_key=node->>'parent_client_key'),node->>'node_type',
      (select predicate_id from _rule_pred_map where client_key=node->>'predicate_client_key'),node->>'logical_operator',
      coalesce((node->>'negate')::boolean,false),coalesce((node->>'sort_order')::int,0),node->>'label'
    ) returning id into generated_id;
    insert into _rule_node_map(client_key,node_id) values (node->>'client_key',generated_id);
  end loop;

  if (select count(*) from public.comp_rule_expression_nodes where rule_set_id=set_id and parent_node_id is null)<>1 then
    raise exception 'A rule set must contain exactly one root expression node';
  end if;
  return set_id;
end;
$$;

revoke all on function public.save_comp_rule_set(jsonb) from public,anon;
grant execute on function public.save_comp_rule_set(jsonb) to authenticated;
