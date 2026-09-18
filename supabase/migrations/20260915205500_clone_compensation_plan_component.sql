create or replace function public.clone_compensation_plan_component(
  source_component_id uuid,
  target_plan_version_id uuid,
  selected_name text,
  selected_component_code text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := auth.uid();
  source public.comp_plan_components%rowtype;
  target_status public.plan_version_status;
  new_component_id uuid := gen_random_uuid();
  copied_rule_sets integer := 0;
  copied_deal_rules integer := 0;
  copied_attribution_rules integer := 0;
  copied_credit_rules integer := 0;
  old_eligibility_rule_id uuid;
  new_eligibility_rule_id uuid;
begin
  if actor is null or not private.has_permission('plans.edit') then
    raise exception 'Plan editing is not permitted.' using errcode='42501';
  end if;
  select * into source from public.comp_plan_components where id=source_component_id;
  if source.id is null then raise exception 'Source Earning Type does not exist.' using errcode='22023'; end if;
  select status into target_status from public.comp_plan_versions where id=target_plan_version_id for update;
  if target_status is null then raise exception 'Target plan version does not exist.' using errcode='22023'; end if;
  if target_status<>'draft' then raise exception 'Earning Types can only be cloned into a draft plan version.' using errcode='42501'; end if;
  if nullif(trim(coalesce(selected_name,'')),'') is null then raise exception 'Earning Type name is required.' using errcode='22023'; end if;
  if nullif(trim(coalesce(selected_component_code,'')),'') is null then raise exception 'Earning Type code is required.' using errcode='22023'; end if;
  if exists(select 1 from public.comp_plan_components where plan_version_id=target_plan_version_id and upper(component_code)=upper(trim(selected_component_code))) then
    raise exception 'Another Earning Type in this draft already uses that code.' using errcode='23505';
  end if;

  begin
    old_eligibility_rule_id := nullif(source.rule_configuration#>>'{eligibility,rule_set_id}','')::uuid;
  exception when others then
    old_eligibility_rule_id := null;
  end;

  insert into public.comp_plan_components(
    id,plan_version_id,name,component_code,description,calculation_type,measurement_source,
    measurement_period,calculation_order,rule_configuration,maximum_payout,is_active,
    payout_timing_method,allow_manager_payout_override,measurement_label,
    additional_eligibility_waiting_days
  ) values (
    new_component_id,target_plan_version_id,trim(selected_name),upper(trim(selected_component_code)),
    source.description,source.calculation_type,source.measurement_source,source.measurement_period,
    coalesce((select max(calculation_order)+1 from public.comp_plan_components where plan_version_id=target_plan_version_id),1),
    source.rule_configuration,source.maximum_payout,source.is_active,source.payout_timing_method,
    source.allow_manager_payout_override,source.measurement_label,source.additional_eligibility_waiting_days
  );

  insert into public.comp_component_deal_rules(
    plan_component_id,hubspot_pipeline_id,hubspot_stage_id,hubspot_deal_type,calculation_action,
    marks_earned,marks_eligible,marks_paid,amount_source,amount_label,priority,is_active,
    effective_start_date,effective_end_date,rule_notes
  )
  select new_component_id,hubspot_pipeline_id,hubspot_stage_id,hubspot_deal_type,calculation_action,
    marks_earned,marks_eligible,marks_paid,amount_source,amount_label,priority,is_active,
    effective_start_date,effective_end_date,rule_notes
  from public.comp_component_deal_rules where plan_component_id=source_component_id;
  get diagnostics copied_deal_rules=row_count;

  insert into public.comp_user_attribution_rules(
    plan_component_id,attribution_purpose,metric_key,hubspot_user_field_keys,match_logic,
    credit_percentage,qualifying_pipeline_ids,qualifying_deal_types,priority,allow_stacking,
    rule_configuration,effective_start_date,effective_end_date,is_active
  )
  select new_component_id,attribution_purpose,metric_key,hubspot_user_field_keys,match_logic,
    credit_percentage,qualifying_pipeline_ids,qualifying_deal_types,priority,allow_stacking,
    rule_configuration,effective_start_date,effective_end_date,is_active
  from public.comp_user_attribution_rules where plan_component_id=source_component_id;
  get diagnostics copied_attribution_rules=row_count;

  insert into public.comp_credit_rules(
    plan_component_id,credit_method,named_employee_id,qualifying_pipeline_ids,qualifying_deal_types,
    credit_percentage,priority,allow_stacking,rule_configuration,effective_start_date,effective_end_date
  )
  select new_component_id,credit_method,named_employee_id,qualifying_pipeline_ids,qualifying_deal_types,
    credit_percentage,priority,allow_stacking,rule_configuration,effective_start_date,effective_end_date
  from public.comp_credit_rules where plan_component_id=source_component_id;
  get diagnostics copied_credit_rules=row_count;

  create temporary table if not exists clone_component_rule_set_map(old_id uuid primary key,new_id uuid not null unique) on commit drop;
  create temporary table if not exists clone_component_predicate_map(old_id uuid primary key,new_id uuid not null unique) on commit drop;
  create temporary table if not exists clone_component_node_map(old_id uuid primary key,new_id uuid not null unique) on commit drop;
  truncate clone_component_rule_set_map,clone_component_predicate_map,clone_component_node_map;

  insert into clone_component_rule_set_map(old_id,new_id)
  select id,gen_random_uuid() from public.comp_rule_sets where plan_component_id=source_component_id;

  insert into public.comp_rule_sets(
    id,plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,
    outcome_configuration,created_by,updated_by
  )
  select m.new_id,new_component_id,rs.name,rs.purpose,rs.description,rs.evaluation_scope,rs.version,
    false,rs.stop_on_match,rs.outcome_configuration,actor,actor
  from public.comp_rule_sets rs join clone_component_rule_set_map m on m.old_id=rs.id;
  get diagnostics copied_rule_sets=row_count;

  insert into clone_component_predicate_map(old_id,new_id)
  select p.id,gen_random_uuid() from public.comp_rule_predicates p join clone_component_rule_set_map m on m.old_id=p.rule_set_id;

  insert into public.comp_rule_predicates(
    id,rule_set_id,rule_key,display_name,object_type,association_path,property_name,operator_key,
    comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes,
    association_quantifier,aggregate_function,aggregate_window
  )
  select pm.new_id,rsm.new_id,p.rule_key,p.display_name,p.object_type,p.association_path,p.property_name,
    p.operator_key,p.comparison_value,p.comparison_value_type,p.case_sensitive,p.include_null_as_match,
    p.notes,p.association_quantifier,p.aggregate_function,p.aggregate_window
  from public.comp_rule_predicates p
  join clone_component_predicate_map pm on pm.old_id=p.id
  join clone_component_rule_set_map rsm on rsm.old_id=p.rule_set_id;

  insert into clone_component_node_map(old_id,new_id)
  select n.id,gen_random_uuid() from public.comp_rule_expression_nodes n join clone_component_rule_set_map rsm on rsm.old_id=n.rule_set_id;

  insert into public.comp_rule_expression_nodes(
    id,rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label
  )
  select nm.new_id,rsm.new_id,null,n.node_type,pm.new_id,n.logical_operator,n.negate,n.sort_order,n.label
  from public.comp_rule_expression_nodes n
  join clone_component_node_map nm on nm.old_id=n.id
  join clone_component_rule_set_map rsm on rsm.old_id=n.rule_set_id
  left join clone_component_predicate_map pm on pm.old_id=n.predicate_id;

  update public.comp_rule_expression_nodes new_node
  set parent_node_id=parent_map.new_id
  from clone_component_node_map node_map
  join public.comp_rule_expression_nodes old_node on old_node.id=node_map.old_id
  join clone_component_node_map parent_map on parent_map.old_id=old_node.parent_node_id
  where new_node.id=node_map.new_id;

  if old_eligibility_rule_id is not null then
    select new_id into new_eligibility_rule_id from clone_component_rule_set_map where old_id=old_eligibility_rule_id;
    if new_eligibility_rule_id is not null then
      update public.comp_plan_components
      set rule_configuration=jsonb_set(rule_configuration,'{eligibility,rule_set_id}',to_jsonb(new_eligibility_rule_id::text),true),updated_at=now()
      where id=new_component_id;
    end if;
  end if;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(actor,'comp_plan_component_cloned','A draft Earning Type was cloned so an administrator can edit only the differences.',
    jsonb_build_object('source_component_id',source_component_id,'target_plan_version_id',target_plan_version_id,
      'new_component_id',new_component_id,'component_code',upper(trim(selected_component_code)),
      'rule_set_count',copied_rule_sets,'deal_rule_count',copied_deal_rules,
      'attribution_rule_count',copied_attribution_rules,'credit_rule_count',copied_credit_rules));

  return jsonb_build_object('status','cloned','component_id',new_component_id,'rule_set_count',copied_rule_sets,
    'deal_rule_count',copied_deal_rules,'attribution_rule_count',copied_attribution_rules,'credit_rule_count',copied_credit_rules);
end;
$function$;

revoke all on function public.clone_compensation_plan_component(uuid,uuid,text,text) from public;
grant execute on function public.clone_compensation_plan_component(uuid,uuid,text,text) to authenticated;
