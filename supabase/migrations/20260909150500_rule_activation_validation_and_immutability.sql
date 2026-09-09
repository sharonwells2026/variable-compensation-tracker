-- Protect historical compensation logic and require activation readiness.

create or replace function public.validate_comp_rule_set_for_activation(target_rule_set_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  access jsonb;
  s public.comp_rule_sets%rowtype;
  issues jsonb := '[]'::jsonb;
  root_count integer;
  predicate_count integer;
  referenced_count integer;
  invalid_field_count integer;
  invalid_operator_count integer;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to validate compensation plan rules';
  end if;

  select * into s from public.comp_rule_sets where id=target_rule_set_id;
  if s.id is null then raise exception 'Rule set not found'; end if;

  select count(*) into predicate_count from public.comp_rule_predicates where rule_set_id=s.id;
  select count(*) into root_count from public.comp_rule_expression_nodes where rule_set_id=s.id and parent_node_id is null;
  select count(distinct predicate_id) into referenced_count from public.comp_rule_expression_nodes where rule_set_id=s.id and node_type='predicate';
  select count(*) into invalid_field_count
    from public.comp_rule_predicates p
    left join public.comp_rule_field_catalog f on f.object_type=p.object_type and f.property_name=p.property_name and f.is_active
    where p.rule_set_id=s.id and f.id is null;
  select count(*) into invalid_operator_count
    from public.comp_rule_predicates p
    left join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
    where p.rule_set_id=s.id and o.operator_key is null;

  if predicate_count=0 then issues:=issues||jsonb_build_array('At least one predicate is required.'); end if;
  if root_count<>1 then issues:=issues||jsonb_build_array('Exactly one root expression group is required.'); end if;
  if referenced_count=0 then issues:=issues||jsonb_build_array('The expression must reference at least one predicate.'); end if;
  if referenced_count<predicate_count then issues:=issues||jsonb_build_array('Every defined predicate must be referenced by the expression.'); end if;
  if invalid_field_count>0 then issues:=issues||jsonb_build_array(invalid_field_count||' predicate(s) use an unavailable field.'); end if;
  if invalid_operator_count>0 then issues:=issues||jsonb_build_array(invalid_operator_count||' predicate(s) use an unavailable operator.'); end if;

  return jsonb_build_object(
    'rule_set_id',s.id,'version',s.version,'is_active',s.is_active,
    'ready',jsonb_array_length(issues)=0,'issues',issues,
    'predicate_count',predicate_count,'referenced_predicate_count',referenced_count,'root_count',root_count
  );
end;
$$;

-- Active versions are immutable. Editing requires creating an inactive successor version first.
create or replace function public.save_comp_rule_set(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb; set_id uuid; pred jsonb; node jsonb; pred_id uuid; existing public.comp_rule_sets%rowtype;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then raise exception 'Not authorized to edit compensation plan rules'; end if;
  if payload->>'plan_component_id' is null or payload->>'name' is null or payload->>'purpose' is null then raise exception 'plan_component_id, name and purpose are required'; end if;

  if payload->>'id' is null then
    insert into public.comp_rule_sets(plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,outcome_configuration,created_by,updated_by)
    values((payload->>'plan_component_id')::uuid,payload->>'name',payload->>'purpose',payload->>'description',coalesce(payload->>'evaluation_scope','record'),coalesce((payload->>'version')::int,1),false,coalesce((payload->>'stop_on_match')::boolean,false),coalesce(payload->'outcome_configuration','{}'::jsonb),(select auth.uid()),(select auth.uid())) returning id into set_id;
  else
    set_id:=(payload->>'id')::uuid;
    select * into existing from public.comp_rule_sets where id=set_id for update;
    if existing.id is null then raise exception 'Rule set not found'; end if;
    if existing.is_active then raise exception 'Active rule versions are immutable. Create a new version before editing.'; end if;
    if existing.plan_component_id<>(payload->>'plan_component_id')::uuid then raise exception 'A rule version cannot be moved to another plan component'; end if;
    update public.comp_rule_sets set name=payload->>'name',purpose=payload->>'purpose',description=payload->>'description',evaluation_scope=coalesce(payload->>'evaluation_scope','record'),stop_on_match=coalesce((payload->>'stop_on_match')::boolean,false),outcome_configuration=coalesce(payload->'outcome_configuration','{}'::jsonb),updated_by=(select auth.uid()),updated_at=now() where id=set_id;
    delete from public.comp_rule_expression_nodes where rule_set_id=set_id;
    delete from public.comp_rule_predicates where rule_set_id=set_id;
  end if;

  for pred in select * from jsonb_array_elements(coalesce(payload->'predicates','[]'::jsonb)) loop
    insert into public.comp_rule_predicates(rule_set_id,rule_key,display_name,object_type,association_path,association_quantifier,aggregate_function,aggregate_window,property_name,operator_key,comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes)
    values(set_id,pred->>'rule_key',pred->>'display_name',pred->>'object_type',coalesce(pred->'association_path','[]'::jsonb),coalesce(pred->>'association_quantifier','record'),pred->>'aggregate_function',pred->'aggregate_window',pred->>'property_name',pred->>'operator_key',pred->'comparison_value',pred->>'comparison_value_type',coalesce((pred->>'case_sensitive')::boolean,false),coalesce((pred->>'include_null_as_match')::boolean,false),pred->>'notes');
  end loop;

  -- Map expression nodes from client keys to stored predicate IDs and parent node IDs.
  create temporary table if not exists _save_pred_map(client_key text primary key,predicate_id uuid) on commit drop;
  create temporary table if not exists _save_node_map(client_key text primary key,node_id uuid) on commit drop;
  truncate _save_pred_map; truncate _save_node_map;
  insert into _save_pred_map(client_key,predicate_id)
    select pld->>'client_key',p.id from jsonb_array_elements(coalesce(payload->'predicates','[]'::jsonb)) pld join public.comp_rule_predicates p on p.rule_set_id=set_id and p.rule_key=pld->>'rule_key';

  for node in select value from jsonb_array_elements(coalesce(payload->'nodes','[]'::jsonb)) loop
    insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
    values(set_id,(select node_id from _save_node_map where client_key=node->>'parent_client_key'),node->>'node_type',(select predicate_id from _save_pred_map where client_key=node->>'predicate_client_key'),node->>'logical_operator',coalesce((node->>'negate')::boolean,false),coalesce((node->>'sort_order')::int,0),node->>'label') returning id into pred_id;
    insert into _save_node_map(client_key,node_id) values(node->>'client_key',pred_id);
  end loop;
  return set_id;
end;
$$;

create or replace function public.set_comp_rule_set_active(target_rule_set_id uuid,target_active boolean)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare access jsonb; target public.comp_rule_sets%rowtype; validation jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then raise exception 'Not authorized to activate compensation plan rules'; end if;
  select * into target from public.comp_rule_sets where id=target_rule_set_id for update;
  if target.id is null then raise exception 'Rule set not found'; end if;
  if target_active then
    validation:=public.validate_comp_rule_set_for_activation(target.id);
    if coalesce((validation->>'ready')::boolean,false) is not true then raise exception 'Rule version is not ready for activation: %',validation->'issues'; end if;
    update public.comp_rule_sets set is_active=false,updated_at=now(),updated_by=(select auth.uid()) where plan_component_id=target.plan_component_id and name=target.name and id<>target.id;
  end if;
  update public.comp_rule_sets set is_active=target_active,updated_at=now(),updated_by=(select auth.uid()) where id=target.id;
end;
$$;

revoke all on function public.validate_comp_rule_set_for_activation(uuid) from public,anon;
grant execute on function public.validate_comp_rule_set_for_activation(uuid) to authenticated;
