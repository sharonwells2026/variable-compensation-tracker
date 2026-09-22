create or replace function public.delete_comp_plan_draft_assignment(selected_draft_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target public.comp_plan_draft_assignments%rowtype;
  version_status public.plan_version_status;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan applicability editing is not permitted.' using errcode='42501'; end if;

  select d.* into target from public.comp_plan_draft_assignments d where d.id=selected_draft_assignment_id for update;
  if target.id is null then raise exception 'Draft assignment does not exist.' using errcode='22023'; end if;
  select pv.status into version_status from public.comp_plan_versions pv where pv.id=target.plan_version_id;
  if version_status <> 'draft' then raise exception 'Only draft plan applicability can be changed.' using errcode='42501'; end if;

  delete from public.comp_plan_draft_assignments where id=target.id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,related_employee_id)
  values((select auth.uid()),'comp_plan_draft_assignment_deleted','A draft plan applicability assignment was removed.',jsonb_build_object('draft_assignment_id',target.id,'plan_version_id',target.plan_version_id,'employee_id',target.employee_id),target.employee_id);
  return jsonb_build_object('status','deleted','draft_assignment_id',target.id);
end;
$function$;

create or replace function public.save_comp_business_condition_setting(selected_business_concept text, selected_display_name text, selected_description text, selected_configuration jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare access jsonb; oldrow jsonb;
begin
 access:=public.get_current_user_access();
 if coalesce((access->>'authenticated')::boolean,false) is not true
    or not (coalesce(access->'permissions','[]'::jsonb) ? 'settings.manage') then
   raise exception 'Not authorized to edit compensation business conditions' using errcode='42501';
 end if;
 select to_jsonb(s) into oldrow from public.comp_business_condition_settings s where s.business_concept=selected_business_concept;
 insert into public.comp_business_condition_settings(business_concept,display_name,description,configuration,updated_by,updated_at)
 values (selected_business_concept,btrim(selected_display_name),nullif(btrim(coalesce(selected_description,'')),''),coalesce(selected_configuration,'{}'::jsonb),(select auth.uid()),now())
 on conflict(business_concept) do update set display_name=excluded.display_name,description=excluded.description,configuration=excluded.configuration,updated_by=excluded.updated_by,updated_at=now();
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state)
 values ((select auth.uid()),'comp_business_condition_setting_updated','Workspace compensation business-condition guidance/configuration was updated.',oldrow,(select to_jsonb(s) from public.comp_business_condition_settings s where s.business_concept=selected_business_concept));
 return (select to_jsonb(s) from public.comp_business_condition_settings s where s.business_concept=selected_business_concept);
end;
$function$;

create or replace function public.apply_comp_business_condition_to_eligibility(selected_component_id uuid, selected_business_concept text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  access jsonb; cfg jsonb; display_name text; condition_description text; signal jsonb;
  rs_id uuid; root_id uuid; pred_id uuid; next_version integer; sort_n integer:=0;
  component_version_status public.plan_version_status; field_type text; logic_operator text;
  old_configuration jsonb; new_eligibility jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to configure compensation plan conditions';
  end if;
  select pv.status,c.rule_configuration into component_version_status,old_configuration
  from public.comp_plan_components c join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where c.id=selected_component_id for update of c;
  if component_version_status is null then raise exception 'Earning Type does not exist.'; end if;
  if component_version_status<>'draft' then raise exception 'Only Earning Types in draft plan versions can be edited.'; end if;

  select b.configuration,b.display_name,b.description into cfg,display_name,condition_description
  from public.comp_business_condition_settings b where b.business_concept=selected_business_concept and b.is_active;
  if cfg is null then raise exception 'Business condition % is not configured or active.',selected_business_concept; end if;
  if jsonb_array_length(coalesce(cfg->'signals','[]'::jsonb))=0 then raise exception 'Business condition % has no configured signals.',selected_business_concept; end if;
  logic_operator:=upper(coalesce(nullif(cfg->>'logic',''),'AND'));
  if logic_operator not in ('AND','OR') then raise exception 'Business condition logic must be AND or OR.'; end if;

  select s.id into rs_id from public.comp_rule_sets s
  where s.plan_component_id=selected_component_id and s.purpose='eligibility' and s.name=display_name and not s.is_active
  order by s.version desc limit 1;
  if rs_id is null then
    select coalesce(max(s.version),0)+1 into next_version from public.comp_rule_sets s where s.plan_component_id=selected_component_id and s.name=display_name;
    insert into public.comp_rule_sets(plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,outcome_configuration,created_by,updated_by)
    values(selected_component_id,display_name,'eligibility',condition_description,'record',next_version,false,false,jsonb_build_object('business_concept',selected_business_concept),(select auth.uid()),(select auth.uid())) returning id into rs_id;
  else
    update public.comp_rule_sets set description=condition_description,outcome_configuration=jsonb_build_object('business_concept',selected_business_concept),updated_by=(select auth.uid()),updated_at=now() where id=rs_id;
    delete from public.comp_rule_expression_nodes where rule_set_id=rs_id;
    delete from public.comp_rule_predicates where rule_set_id=rs_id;
  end if;

  insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
  values(rs_id,null,'group',null,logic_operator,false,0,display_name) returning id into root_id;
  for signal in select * from jsonb_array_elements(cfg->'signals') loop
    select f.data_type into field_type from public.comp_rule_field_catalog f
    where f.object_type=signal->>'object_type' and f.property_name=signal->>'property_name' and f.is_active limit 1;
    if field_type is null then raise exception 'Configured field %.% is not available to compensation rules.',signal->>'object_type',signal->>'property_name'; end if;
    if not exists(select 1 from public.comp_rule_operator_catalog o where o.operator_key=signal->>'operator_key' and o.is_active and o.supported_data_types ? field_type) then
      raise exception 'Configured operator % is not valid for %.%.',signal->>'operator_key',signal->>'object_type',signal->>'property_name';
    end if;
    sort_n:=sort_n+1;
    insert into public.comp_rule_predicates(rule_set_id,rule_key,display_name,object_type,association_path,association_quantifier,property_name,operator_key,comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes)
    values(rs_id,'business_condition_'||sort_n,coalesce(signal->>'label','Condition '||sort_n),signal->>'object_type','[]'::jsonb,'record',signal->>'property_name',signal->>'operator_key',case when signal ? 'value' then to_jsonb(signal->>'value') else null end,field_type,false,false,'Generated from workspace business condition: '||selected_business_concept) returning id into pred_id;
    insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
    values(rs_id,root_id,'predicate',pred_id,null,false,sort_n,coalesce(signal->>'label','Condition '||sort_n));
  end loop;

  new_eligibility:=jsonb_build_object('mode','rule','business_concept',selected_business_concept,'rule_set_id',rs_id,'configuration_complete',true,'description',display_name);
  update public.comp_plan_components set additional_eligibility_waiting_days=null,rule_configuration=jsonb_set(coalesce(rule_configuration,'{}'::jsonb),'{eligibility}',new_eligibility,true),updated_at=now() where id=selected_component_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state)
  values((select auth.uid()),'comp_plan_business_condition_applied','A workspace business condition was applied to a draft Earning Type.',jsonb_build_object('component_id',selected_component_id,'eligibility',coalesce(old_configuration->'eligibility','null'::jsonb)),jsonb_build_object('component_id',selected_component_id,'eligibility',new_eligibility));
  return jsonb_build_object('status','configured','component_id',selected_component_id,'business_concept',selected_business_concept,'rule_set_id',rs_id,'display_name',display_name,'signal_count',sort_n,'eligibility',new_eligibility);
end;
$function$;