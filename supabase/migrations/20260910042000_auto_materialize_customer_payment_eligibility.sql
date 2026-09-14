create or replace function public.apply_comp_business_condition_to_eligibility(selected_component_id uuid, selected_business_concept text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  access jsonb; cfg jsonb; display_name text; condition_description text; signal jsonb;
  rs_id uuid; root_id uuid; pred_id uuid; next_version integer; sort_n integer:=0;
  component_version_status public.plan_version_status; field_type text; logic_operator text;
  old_configuration jsonb; new_eligibility jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then raise exception 'Not authorized to configure compensation plan conditions'; end if;
  select pv.status,c.rule_configuration into component_version_status,old_configuration from public.comp_plan_components c join public.comp_plan_versions pv on pv.id=c.plan_version_id where c.id=selected_component_id for update of c;
  if component_version_status is null then raise exception 'Earning Type does not exist.'; end if;
  if component_version_status<>'draft' then raise exception 'Only Earning Types in draft plan versions can be edited.'; end if;
  select b.configuration,b.display_name,b.description into cfg,display_name,condition_description from public.comp_business_condition_settings b where b.business_concept=selected_business_concept and b.is_active;
  if cfg is null then raise exception 'Business condition % is not configured or active.',selected_business_concept; end if;
  if jsonb_array_length(coalesce(cfg->'signals','[]'::jsonb))=0 then raise exception 'Business condition % has no configured signals.',selected_business_concept; end if;
  logic_operator:=upper(coalesce(nullif(cfg->>'logic',''),'AND'));
  if logic_operator not in ('AND','OR') then raise exception 'Business condition logic must be AND or OR.'; end if;
  select s.id into rs_id from public.comp_rule_sets s where s.plan_component_id=selected_component_id and s.purpose='eligibility' and s.name=display_name and not s.is_active order by s.version desc limit 1;
  if rs_id is null then
    select coalesce(max(s.version),0)+1 into next_version from public.comp_rule_sets s where s.plan_component_id=selected_component_id and s.name=display_name;
    insert into public.comp_rule_sets(plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,outcome_configuration,created_by,updated_by) values(selected_component_id,display_name,'eligibility',condition_description,'record',next_version,false,false,jsonb_build_object('business_concept',selected_business_concept),(select auth.uid()),(select auth.uid())) returning id into rs_id;
  else
    update public.comp_rule_sets set description=condition_description,outcome_configuration=jsonb_build_object('business_concept',selected_business_concept),updated_by=(select auth.uid()),updated_at=now() where id=rs_id;
    delete from public.comp_rule_expression_nodes where rule_set_id=rs_id; delete from public.comp_rule_predicates where rule_set_id=rs_id;
  end if;
  insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label) values(rs_id,null,'group',null,logic_operator,false,0,display_name) returning id into root_id;
  for signal in select * from jsonb_array_elements(cfg->'signals') loop
    select f.data_type into field_type from public.comp_rule_field_catalog f where f.object_type=signal->>'object_type' and f.property_name=signal->>'property_name' and f.is_active limit 1;
    if field_type is null then raise exception 'Configured field %.% is not available to compensation rules.',signal->>'object_type',signal->>'property_name'; end if;
    if not exists(select 1 from public.comp_rule_operator_catalog o where o.operator_key=signal->>'operator_key' and o.is_active and o.supported_data_types ? field_type) then raise exception 'Configured operator % is not valid for %.%.',signal->>'operator_key',signal->>'object_type',signal->>'property_name'; end if;
    sort_n:=sort_n+1;
    insert into public.comp_rule_predicates(rule_set_id,rule_key,display_name,object_type,association_path,association_quantifier,property_name,operator_key,comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes) values(rs_id,'business_condition_'||sort_n,coalesce(signal->>'label','Condition '||sort_n),signal->>'object_type','[]'::jsonb,'record',signal->>'property_name',signal->>'operator_key',case when signal ? 'value' then to_jsonb(signal->>'value') else null end,field_type,false,false,'Generated from workspace business condition: '||selected_business_concept) returning id into pred_id;
    insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label) values(rs_id,root_id,'predicate',pred_id,null,false,sort_n,coalesce(signal->>'label','Condition '||sort_n));
  end loop;
  new_eligibility:=jsonb_build_object('mode','rule','business_concept',selected_business_concept,'rule_set_id',rs_id,'configuration_complete',true,'description',display_name);
  update public.comp_plan_components set additional_eligibility_waiting_days=null,rule_configuration=jsonb_set(coalesce(rule_configuration,'{}'::jsonb),'{eligibility}',new_eligibility,true),updated_at=now() where id=selected_component_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,old_state,new_state) values((select auth.uid()),'comp_plan_business_condition_applied','A workspace business condition was applied to a draft Earning Type.',jsonb_build_object('component_id',selected_component_id,'eligibility',coalesce(old_configuration->'eligibility','null'::jsonb)),jsonb_build_object('component_id',selected_component_id,'eligibility',new_eligibility));
  return jsonb_build_object('status','configured','component_id',selected_component_id,'business_concept',selected_business_concept,'rule_set_id',rs_id,'display_name',display_name,'signal_count',sort_n,'eligibility',new_eligibility);
end;
$function$;

create or replace function public.save_compensation_plan_component_eligibility(selected_component_id uuid, selected_mode text, selected_waiting_days integer default null::integer, selected_rule_set_id uuid default null::uuid, selected_description text default null::text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  normalized_mode text := lower(trim(coalesce(selected_mode,'')));
  stored_mode text; version_status public.plan_version_status; old_configuration jsonb; new_eligibility jsonb; previous_waiting_days integer;
  rule_purpose text; rule_component_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan eligibility editing is not permitted.' using errcode='42501'; end if;
  if normalized_mode='customer_payment' and selected_rule_set_id is null then return public.apply_comp_business_condition_to_eligibility(selected_component_id,'customer_payment_received'); end if;
  select pv.status,c.rule_configuration,c.additional_eligibility_waiting_days into version_status,old_configuration,previous_waiting_days from public.comp_plan_components c join public.comp_plan_versions pv on pv.id=c.plan_version_id where c.id=selected_component_id for update of c;
  if version_status is null then raise exception 'Plan component does not exist.' using errcode='22023'; end if;
  if version_status<>'draft' then raise exception 'Only components in draft plan versions can be edited.' using errcode='42501'; end if;
  if normalized_mode not in ('immediate','waiting_period','rule','customer_payment') then raise exception 'Eligibility mode must be immediate, waiting_period, customer_payment, or rule.' using errcode='22023'; end if;
  stored_mode:=case when normalized_mode='customer_payment' then 'rule' else normalized_mode end;
  if normalized_mode='waiting_period' then
    if selected_waiting_days is null or selected_waiting_days<0 then raise exception 'Waiting-period eligibility requires a non-negative number of days.' using errcode='22023'; end if;
    if selected_rule_set_id is not null then raise exception 'Waiting-period eligibility cannot also reference an eligibility rule set.' using errcode='22023'; end if;
  elsif normalized_mode in ('rule','customer_payment') and selected_rule_set_id is not null then
    select rs.purpose,rs.plan_component_id into rule_purpose,rule_component_id from public.comp_rule_sets rs where rs.id=selected_rule_set_id;
    if rule_purpose is null then raise exception 'Eligibility rule set does not exist.' using errcode='22023'; end if;
    if rule_purpose<>'eligibility' then raise exception 'The selected rule set is not an eligibility rule set.' using errcode='22023'; end if;
    if rule_component_id<>selected_component_id then raise exception 'Eligibility rule set must belong to the same plan component.' using errcode='22023'; end if;
    if selected_waiting_days is not null then raise exception 'Rule-based eligibility cannot also use a waiting-period value.' using errcode='22023'; end if;
  elsif normalized_mode='immediate' then
    if selected_waiting_days is not null or selected_rule_set_id is not null then raise exception 'Immediate eligibility cannot include a waiting period or eligibility rule set.' using errcode='22023'; end if;
  end if;
  new_eligibility:=jsonb_strip_nulls(jsonb_build_object('mode',stored_mode,'business_concept',case when normalized_mode='customer_payment' then 'customer_payment_received' else null end,'waiting_days',case when normalized_mode='waiting_period' then selected_waiting_days else null end,'rule_set_id',case when stored_mode='rule' then selected_rule_set_id else null end,'configuration_complete',case when stored_mode='rule' then selected_rule_set_id is not null else true end,'description',coalesce(nullif(trim(coalesce(selected_description,'')),''),case when normalized_mode='customer_payment' then 'Customer payment received' else null end)));
  update public.comp_plan_components set additional_eligibility_waiting_days=case when normalized_mode='waiting_period' then selected_waiting_days else null end,rule_configuration=jsonb_set(coalesce(rule_configuration,'{}'::jsonb),'{eligibility}',new_eligibility,true),updated_at=now() where id=selected_component_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,old_state,new_state) values((select auth.uid()),'comp_plan_component_eligibility_updated','The Earned-to-Eligible condition for a draft compensation plan component was updated.',jsonb_build_object('component_id',selected_component_id,'eligibility',coalesce(old_configuration->'eligibility','null'::jsonb),'additional_eligibility_waiting_days',previous_waiting_days),jsonb_build_object('component_id',selected_component_id,'eligibility',new_eligibility,'additional_eligibility_waiting_days',case when normalized_mode='waiting_period' then selected_waiting_days else null end));
  return jsonb_build_object('status','saved','component_id',selected_component_id,'eligibility',new_eligibility);
end;
$function$;