create or replace function public.apply_comp_business_condition_to_eligibility(selected_component_id uuid, selected_business_concept text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  access jsonb;
  cfg jsonb;
  display_name text;
  condition_description text;
  signal jsonb;
  rs_id uuid;
  root_id uuid;
  pred_id uuid;
  next_version integer;
  sort_n integer:=0;
  component_version_status public.plan_version_status;
  field_type text;
  logic_operator text;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to configure compensation plan conditions';
  end if;

  select pv.status into component_version_status
  from public.comp_plan_components c
  join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where c.id=selected_component_id;
  if component_version_status is null then raise exception 'Earning Type does not exist.'; end if;
  if component_version_status<>'draft' then raise exception 'Only Earning Types in draft plan versions can be edited.'; end if;

  select b.configuration,b.display_name,b.description
    into cfg,display_name,condition_description
  from public.comp_business_condition_settings b
  where b.business_concept=selected_business_concept and b.is_active;
  if cfg is null then raise exception 'Business condition % is not configured or active.', selected_business_concept; end if;
  if jsonb_array_length(coalesce(cfg->'signals','[]'::jsonb))=0 then raise exception 'Business condition % has no configured signals.', selected_business_concept; end if;

  logic_operator:=upper(coalesce(nullif(cfg->>'logic',''),'AND'));
  if logic_operator not in ('AND','OR') then raise exception 'Business condition logic must be AND or OR.'; end if;

  select s.id into rs_id
  from public.comp_rule_sets s
  where s.plan_component_id=selected_component_id
    and s.purpose='eligibility'
    and s.name=display_name
    and not s.is_active
  order by s.version desc
  limit 1;

  if rs_id is null then
    select coalesce(max(s.version),0)+1 into next_version
    from public.comp_rule_sets s
    where s.plan_component_id=selected_component_id and s.name=display_name;
    insert into public.comp_rule_sets(plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,outcome_configuration,created_by,updated_by)
    values(selected_component_id,display_name,'eligibility',condition_description,'record',next_version,false,false,jsonb_build_object('business_concept',selected_business_concept),(select auth.uid()),(select auth.uid()))
    returning id into rs_id;
  else
    update public.comp_rule_sets
    set description=condition_description,
        outcome_configuration=jsonb_build_object('business_concept',selected_business_concept),
        updated_by=(select auth.uid()),updated_at=now()
    where id=rs_id;
    delete from public.comp_rule_expression_nodes where rule_set_id=rs_id;
    delete from public.comp_rule_predicates where rule_set_id=rs_id;
  end if;

  insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
  values(rs_id,null,'group',null,logic_operator,false,0,display_name)
  returning id into root_id;

  for signal in select * from jsonb_array_elements(cfg->'signals') loop
    select f.data_type into field_type
    from public.comp_rule_field_catalog f
    where f.object_type=signal->>'object_type'
      and f.property_name=signal->>'property_name'
      and f.is_active
    limit 1;
    if field_type is null then
      raise exception 'Configured field %.% is not available to compensation rules.',signal->>'object_type',signal->>'property_name';
    end if;
    if not exists(select 1 from public.comp_rule_operator_catalog o where o.operator_key=signal->>'operator_key' and o.is_active and o.supported_data_types ? field_type) then
      raise exception 'Configured operator % is not valid for %.%.',signal->>'operator_key',signal->>'object_type',signal->>'property_name';
    end if;

    sort_n:=sort_n+1;
    insert into public.comp_rule_predicates(rule_set_id,rule_key,display_name,object_type,association_path,association_quantifier,property_name,operator_key,comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes)
    values(rs_id,'business_condition_'||sort_n,coalesce(signal->>'label','Condition '||sort_n),signal->>'object_type','[]'::jsonb,'record',signal->>'property_name',signal->>'operator_key',case when signal ? 'value' then to_jsonb(signal->>'value') else null end,field_type,false,false,'Generated from workspace business condition: '||selected_business_concept)
    returning id into pred_id;

    insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
    values(rs_id,root_id,'predicate',pred_id,null,false,sort_n,coalesce(signal->>'label','Condition '||sort_n));
  end loop;

  perform public.save_compensation_plan_component_eligibility(selected_component_id,'customer_payment',null,rs_id,display_name);

  return jsonb_build_object('status','configured','component_id',selected_component_id,'business_concept',selected_business_concept,'rule_set_id',rs_id,'display_name',display_name,'signal_count',sort_n);
end;
$function$;
