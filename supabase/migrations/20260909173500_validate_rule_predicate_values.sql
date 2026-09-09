-- Prevent incomplete or type-incompatible rule predicates from being saved or activated.

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
  op_arity text;
  field_type text;
  field_active boolean;
  operator_active boolean;
  supported_types text[];
  cmp jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to edit compensation plan rules';
  end if;

  if payload->>'plan_component_id' is null or nullif(btrim(payload->>'name'),'') is null or nullif(btrim(payload->>'purpose'),'') is null then
    raise exception 'plan_component_id, name and purpose are required';
  end if;
  if jsonb_array_length(coalesce(payload->'predicates','[]'::jsonb))=0 then
    raise exception 'At least one rule is required';
  end if;

  for pred in select * from jsonb_array_elements(coalesce(payload->'predicates','[]'::jsonb)) loop
    if nullif(btrim(pred->>'client_key'),'') is null or nullif(btrim(pred->>'rule_key'),'') is null then
      raise exception 'Every rule needs an internal key';
    end if;
    if nullif(btrim(pred->>'object_type'),'') is null or nullif(btrim(pred->>'property_name'),'') is null or nullif(btrim(pred->>'operator_key'),'') is null then
      raise exception '% needs an object, field and operator', coalesce(nullif(pred->>'display_name',''),pred->>'rule_key','Rule');
    end if;

    select f.data_type,f.is_active into field_type,field_active
    from public.comp_rule_field_catalog f
    where f.object_type=pred->>'object_type' and f.property_name=pred->>'property_name'
    limit 1;
    if field_type is null or field_active is not true then
      raise exception '% uses an unavailable field', coalesce(nullif(pred->>'display_name',''),pred->>'rule_key','Rule');
    end if;

    select o.value_arity,o.is_active,o.supported_data_types into op_arity,operator_active,supported_types
    from public.comp_rule_operator_catalog o
    where o.operator_key=pred->>'operator_key'
    limit 1;
    if op_arity is null or operator_active is not true then
      raise exception '% uses an unavailable operator', coalesce(nullif(pred->>'display_name',''),pred->>'rule_key','Rule');
    end if;
    if not (field_type = any(supported_types)) then
      raise exception '% uses an operator that is not valid for % fields', coalesce(nullif(pred->>'display_name',''),pred->>'rule_key','Rule'), field_type;
    end if;

    cmp:=pred->'comparison_value';
    if op_arity='single' then
      if cmp is null or cmp='null'::jsonb or nullif(btrim(cmp#>>'{}'),'') is null then
        raise exception '% needs a comparison value', coalesce(nullif(pred->>'display_name',''),pred->>'rule_key','Rule');
      end if;
      if pred->>'operator_key' in ('within_last','not_within_last') then
        begin
          if (cmp#>>'{}')::numeric < 0 then raise exception 'negative'; end if;
        exception when others then
          raise exception '% needs a non-negative number of days', coalesce(nullif(pred->>'display_name',''),pred->>'rule_key','Rule');
        end;
      end if;
    elsif op_arity='multiple' then
      if cmp is null or jsonb_typeof(cmp)<>'array' or jsonb_array_length(cmp)=0 then
        raise exception '% needs at least one comparison value', coalesce(nullif(pred->>'display_name',''),pred->>'rule_key','Rule');
      end if;
    elsif op_arity='range' then
      if cmp is null or jsonb_typeof(cmp)<>'object'
         or nullif(btrim(cmp->>'low'),'') is null
         or nullif(btrim(cmp->>'high'),'') is null then
        raise exception '% needs both From and To values', coalesce(nullif(pred->>'display_name',''),pred->>'rule_key','Rule');
      end if;
    end if;
  end loop;

  if payload->>'id' is null then
    insert into public.comp_rule_sets(plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,outcome_configuration,created_by,updated_by)
    values ((payload->>'plan_component_id')::uuid,payload->>'name',payload->>'purpose',payload->>'description',coalesce(payload->>'evaluation_scope','record'),coalesce((payload->>'version')::int,1),false,coalesce((payload->>'stop_on_match')::boolean,false),coalesce(payload->'outcome_configuration','{}'::jsonb),(select auth.uid()),(select auth.uid()))
    returning id into set_id;
  else
    set_id:=(payload->>'id')::uuid;
    select * into existing from public.comp_rule_sets where id=set_id for update;
    if existing.id is null then raise exception 'Rule set not found'; end if;
    if existing.is_active then raise exception 'Active rule versions are immutable. Create a new inactive version before editing.'; end if;
    if existing.plan_component_id<>(payload->>'plan_component_id')::uuid then raise exception 'A rule version cannot be moved to another plan component'; end if;
    update public.comp_rule_sets set name=payload->>'name',purpose=payload->>'purpose',description=payload->>'description',evaluation_scope=coalesce(payload->>'evaluation_scope','record'),is_active=false,stop_on_match=coalesce((payload->>'stop_on_match')::boolean,false),outcome_configuration=coalesce(payload->'outcome_configuration','{}'::jsonb),updated_by=(select auth.uid()),updated_at=now() where id=set_id;
    delete from public.comp_rule_expression_nodes where rule_set_id=set_id;
    delete from public.comp_rule_predicates where rule_set_id=set_id;
  end if;

  create temporary table if not exists _rule_pred_map(client_key text primary key,predicate_id uuid) on commit drop;
  truncate _rule_pred_map;
  for pred in select * from jsonb_array_elements(coalesce(payload->'predicates','[]'::jsonb)) loop
    insert into public.comp_rule_predicates(rule_set_id,rule_key,display_name,object_type,association_path,association_quantifier,aggregate_function,aggregate_window,property_name,operator_key,comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes)
    values (set_id,pred->>'rule_key',coalesce(pred->>'display_name',pred->>'rule_key'),pred->>'object_type',coalesce(pred->'association_path','[]'::jsonb),coalesce(pred->>'association_quantifier','record'),pred->>'aggregate_function',pred->'aggregate_window',pred->>'property_name',pred->>'operator_key',pred->'comparison_value',pred->>'comparison_value_type',coalesce((pred->>'case_sensitive')::boolean,false),coalesce((pred->>'include_null_as_match')::boolean,false),pred->>'notes')
    returning id into generated_id;
    insert into _rule_pred_map(client_key,predicate_id) values (pred->>'client_key',generated_id);
  end loop;

  create temporary table if not exists _rule_node_map(client_key text primary key,node_id uuid) on commit drop;
  truncate _rule_node_map;
  for node in select * from jsonb_array_elements(coalesce(payload->'nodes','[]'::jsonb)) loop
    insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
    values (set_id,(select node_id from _rule_node_map where client_key=node->>'parent_client_key'),node->>'node_type',(select predicate_id from _rule_pred_map where client_key=node->>'predicate_client_key'),node->>'logical_operator',coalesce((node->>'negate')::boolean,false),coalesce((node->>'sort_order')::int,0),node->>'label')
    returning id into generated_id;
    insert into _rule_node_map(client_key,node_id) values (node->>'client_key',generated_id);
  end loop;

  if (select count(*) from public.comp_rule_expression_nodes where rule_set_id=set_id and parent_node_id is null)<>1 then
    raise exception 'A rule set must contain exactly one root expression node';
  end if;
  return set_id;
end;
$$;

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
  invalid_value_count integer;
  incompatible_operator_count integer;
  latest_preview public.comp_rule_set_preview_runs%rowtype;
  preview_ready boolean:=false;
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
    from public.comp_rule_predicates p left join public.comp_rule_field_catalog f on f.object_type=p.object_type and f.property_name=p.property_name and f.is_active
    where p.rule_set_id=s.id and f.id is null;
  select count(*) into invalid_operator_count
    from public.comp_rule_predicates p left join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
    where p.rule_set_id=s.id and o.operator_key is null;
  select count(*) into incompatible_operator_count
    from public.comp_rule_predicates p
    join public.comp_rule_field_catalog f on f.object_type=p.object_type and f.property_name=p.property_name and f.is_active
    join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
    where p.rule_set_id=s.id and not (f.data_type = any(o.supported_data_types));
  select count(*) into invalid_value_count
    from public.comp_rule_predicates p
    join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
    where p.rule_set_id=s.id and (
      (o.value_arity='single' and (p.comparison_value is null or p.comparison_value='null'::jsonb or nullif(btrim(p.comparison_value#>>'{}'),'') is null))
      or (o.value_arity='multiple' and (p.comparison_value is null or jsonb_typeof(p.comparison_value)<>'array' or jsonb_array_length(coalesce(p.comparison_value,'[]'::jsonb))=0))
      or (o.value_arity='range' and (p.comparison_value is null or jsonb_typeof(p.comparison_value)<>'object' or nullif(btrim(p.comparison_value->>'low'),'') is null or nullif(btrim(p.comparison_value->>'high'),'') is null))
    );

  if predicate_count=0 then issues:=issues||jsonb_build_array('At least one predicate is required.'); end if;
  if root_count<>1 then issues:=issues||jsonb_build_array('Exactly one root expression group is required.'); end if;
  if referenced_count=0 then issues:=issues||jsonb_build_array('The expression must reference at least one predicate.'); end if;
  if referenced_count<predicate_count then issues:=issues||jsonb_build_array('Every defined predicate must be referenced by the expression.'); end if;
  if invalid_field_count>0 then issues:=issues||jsonb_build_array(invalid_field_count||' predicate(s) use an unavailable field.'); end if;
  if invalid_operator_count>0 then issues:=issues||jsonb_build_array(invalid_operator_count||' predicate(s) use an unavailable operator.'); end if;
  if incompatible_operator_count>0 then issues:=issues||jsonb_build_array(incompatible_operator_count||' predicate(s) use an operator that is incompatible with the field type.'); end if;
  if invalid_value_count>0 then issues:=issues||jsonb_build_array(invalid_value_count||' predicate(s) are missing a required comparison value.'); end if;

  select * into latest_preview from public.comp_rule_set_preview_runs where rule_set_id=s.id order by previewed_at desc limit 1;
  if latest_preview.id is null or latest_preview.rule_updated_at < s.updated_at then
    issues:=issues||jsonb_build_array('Preview this version against current HubSpot data after the latest edit.');
  elsif latest_preview.supported is not true then
    issues:=issues||jsonb_build_array('The latest preview cannot evaluate all predicates yet.');
  elsif coalesce(latest_preview.scanned_count,0)=0 then
    issues:=issues||jsonb_build_array('The latest preview scanned no synced HubSpot deals.');
  else
    preview_ready:=true;
  end if;

  return jsonb_build_object(
    'rule_set_id',s.id,'version',s.version,'is_active',s.is_active,
    'ready',jsonb_array_length(issues)=0,'issues',issues,
    'predicate_count',predicate_count,'referenced_predicate_count',referenced_count,'root_count',root_count,
    'preview_ready',preview_ready,
    'previewed_at',case when latest_preview.id is null then null else latest_preview.previewed_at end,
    'preview_scanned_count',case when latest_preview.id is null then null else latest_preview.scanned_count end,
    'preview_matched_count',case when latest_preview.id is null then null else latest_preview.matched_count end
  );
end;
$$;
