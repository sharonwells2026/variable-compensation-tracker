do $$
declare
  draft_id uuid;
begin
  select id into draft_id
  from public.comp_hubspot_mapping_versions
  where status='draft'
  order by version_number desc
  limit 1;

  if draft_id is not null then
    insert into public.comp_hubspot_object_mappings(mapping_version_id,object_type,hubspot_object_type,is_eligible)
    select draft_id,o.object_type,d.hubspot_object_type,true
    from public.comp_rule_object_catalog o
    join public.hubspot_object_definitions d on d.internal_object_key=o.object_type and d.is_active
    where o.is_active
    on conflict(mapping_version_id,object_type)
    do update set hubspot_object_type=excluded.hubspot_object_type,
                  is_eligible=true,
                  updated_at=now();

    insert into public.comp_hubspot_field_mappings(mapping_version_id,object_type,property_name,is_eligible,value_policy)
    select draft_id,f.object_type,f.property_name,true,'all'
    from public.comp_rule_field_catalog f
    join public.hubspot_property_definitions p
      on p.internal_object_key=f.object_type
     and p.property_name=f.property_name
     and p.is_active
    where f.is_active
    on conflict(mapping_version_id,object_type,property_name)
    do update set is_eligible=true,updated_at=now();
  end if;
end $$;

create or replace function public.get_comp_rule_builder_catalog(target_plan_component_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  access jsonb;
  mapping_id uuid;
  mapping_status text;
  mapping_version integer;
  bootstrap boolean:=false;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to view compensation plan rules';
  end if;

  select id,status,version_number into mapping_id,mapping_status,mapping_version
  from public.comp_hubspot_mapping_versions
  where status='active'
  order by version_number desc
  limit 1;

  if mapping_id is null and private.can_edit_hubspot_comp_mapping(access) then
    select id,status,version_number into mapping_id,mapping_status,mapping_version
    from public.comp_hubspot_mapping_versions
    where status='draft'
    order by version_number desc
    limit 1;
    bootstrap:=mapping_id is not null;
  end if;

  return jsonb_build_object(
    'mapping',jsonb_build_object(
      'id',mapping_id,
      'status',mapping_status,
      'version_number',mapping_version,
      'bootstrap_mode',bootstrap,
      'activation_required',not exists(select 1 from public.comp_hubspot_mapping_versions where status='active')
    ),
    'objects',case when mapping_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'object_type',m.object_type,
        'display_name',coalesce(c.display_name,initcap(replace(m.object_type,'_',' '))),
        'description',coalesce(c.description,d.description),
        'hubspot_object_type',m.hubspot_object_type
      ) order by coalesce(c.sort_order,999),coalesce(c.display_name,m.object_type))
      from public.comp_hubspot_object_mappings m
      join public.hubspot_object_definitions d
        on d.internal_object_key=m.object_type
       and d.hubspot_object_type=m.hubspot_object_type
       and d.is_active
      join public.comp_rule_object_catalog c
        on c.object_type=m.object_type and c.is_active
      where m.mapping_version_id=mapping_id and m.is_eligible
    ),'[]'::jsonb) end,
    'fields',case when mapping_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'object_type',fm.object_type,
        'property_name',fm.property_name,
        'display_name',coalesce(cf.display_name,p.display_label,fm.property_name),
        'data_type',coalesce(cf.data_type,
          case p.property_type
            when 'bool' then 'boolean'
            when 'date' then 'date'
            when 'datetime' then 'datetime'
            when 'number' then 'number'
            when 'enumeration' then case when p.field_type in ('checkbox','multiplecheckbox') then 'multi_enumeration' else 'enumeration' end
            else 'string'
          end),
        'description',coalesce(cf.description,p.description),
        'is_multi_value',coalesce(cf.is_multi_value,p.field_type in ('checkbox','multiplecheckbox'),false),
        'source_system','hubspot',
        'mapping_value_policy',fm.value_policy,
        'options',coalesce((
          select jsonb_agg(jsonb_build_object(
            'value',dv.hubspot_value,
            'label',case
              when nullif(dv.context->>'pipeline_name','') is not null
                then dv.display_label||' — '||(dv.context->>'pipeline_name')
              else dv.display_label
            end
          ) order by coalesce(dv.context->>'pipeline_name',''),dv.display_label,dv.hubspot_value)
          from public.comp_hubspot_discovered_values dv
          where dv.object_type=fm.object_type
            and dv.property_name=fm.property_name
            and dv.is_active
            and (
              fm.value_policy='all'
              or exists(
                select 1
                from public.comp_hubspot_value_mappings vm
                where vm.field_mapping_id=fm.id
                  and vm.hubspot_value=dv.hubspot_value
                  and vm.context=dv.context
                  and vm.is_eligible
              )
            )
        ),'[]'::jsonb)
      ) order by fm.object_type,coalesce(cf.display_name,p.display_label,fm.property_name))
      from public.comp_hubspot_field_mappings fm
      join public.comp_hubspot_object_mappings om
        on om.mapping_version_id=fm.mapping_version_id
       and om.object_type=fm.object_type
       and om.is_eligible
      join public.hubspot_property_definitions p
        on p.internal_object_key=fm.object_type
       and p.property_name=fm.property_name
       and p.is_active
      left join public.comp_rule_field_catalog cf
        on cf.object_type=fm.object_type
       and cf.property_name=fm.property_name
       and cf.is_active
      where fm.mapping_version_id=mapping_id
        and fm.is_eligible
    ),'[]'::jsonb) end,
    'operators',coalesce((select jsonb_agg(to_jsonb(o) order by o.sort_order) from public.comp_rule_operator_catalog o where o.is_active),'[]'::jsonb),
    'rule_sets',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'plan_component_id',s.plan_component_id,'name',s.name,'purpose',s.purpose,'description',s.description,
      'evaluation_scope',s.evaluation_scope,'version',s.version,'is_active',s.is_active,'stop_on_match',s.stop_on_match,
      'outcome_configuration',s.outcome_configuration,
      'predicates',coalesce((select jsonb_agg(to_jsonb(p) order by p.rule_key) from public.comp_rule_predicates p where p.rule_set_id=s.id),'[]'::jsonb),
      'nodes',coalesce((select jsonb_agg(to_jsonb(n) order by n.parent_node_id nulls first,n.sort_order,n.created_at) from public.comp_rule_expression_nodes n where n.rule_set_id=s.id),'[]'::jsonb)
    ) order by s.purpose,s.name) from public.comp_rule_sets s where target_plan_component_id is null or s.plan_component_id=target_plan_component_id),'[]'::jsonb)
  );
end;
$$;

create or replace function public.validate_comp_rule_set_for_activation(target_rule_set_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  access jsonb;
  s public.comp_rule_sets%rowtype;
  issues jsonb := '[]'::jsonb;
  root_count integer;
  predicate_count integer;
  referenced_count integer;
  invalid_field_count integer:=0;
  invalid_operator_count integer;
  invalid_value_count integer;
  incompatible_operator_count integer;
  latest_preview public.comp_rule_set_preview_runs%rowtype;
  preview_ready boolean:=false;
  active_mapping_id uuid;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to validate compensation plan rules';
  end if;

  select * into s from public.comp_rule_sets where id=target_rule_set_id;
  if s.id is null then raise exception 'Rule set not found'; end if;

  select id into active_mapping_id
  from public.comp_hubspot_mapping_versions
  where status='active'
  order by version_number desc
  limit 1;

  select count(*) into predicate_count from public.comp_rule_predicates where rule_set_id=s.id;
  select count(*) into root_count from public.comp_rule_expression_nodes where rule_set_id=s.id and parent_node_id is null;
  select count(distinct predicate_id) into referenced_count from public.comp_rule_expression_nodes where rule_set_id=s.id and node_type='predicate';

  if active_mapping_id is null then
    issues:=issues||jsonb_build_array('Activate a HubSpot Compensation Mapping before activating compensation rules.');
  else
    select count(*) into invalid_field_count
    from public.comp_rule_predicates p
    left join public.comp_hubspot_field_mappings fm
      on fm.mapping_version_id=active_mapping_id
     and fm.object_type=p.object_type
     and fm.property_name=p.property_name
     and fm.is_eligible
    left join public.comp_hubspot_object_mappings om
      on om.mapping_version_id=active_mapping_id
     and om.object_type=p.object_type
     and om.is_eligible
    left join public.hubspot_property_definitions hp
      on hp.internal_object_key=p.object_type
     and hp.property_name=p.property_name
     and hp.is_active
    where p.rule_set_id=s.id
      and (fm.id is null or om.id is null or hp.id is null);
  end if;

  select count(*) into invalid_operator_count
  from public.comp_rule_predicates p
  left join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
  where p.rule_set_id=s.id and o.operator_key is null;

  select count(*) into incompatible_operator_count
  from public.comp_rule_predicates p
  join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
  where p.rule_set_id=s.id
    and not (o.supported_data_types ? coalesce(p.comparison_value_type,'string'));

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
  if invalid_field_count>0 then issues:=issues||jsonb_build_array(invalid_field_count||' predicate(s) use a field that is not allowed by the active HubSpot Compensation Mapping.'); end if;
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
    'active_mapping_id',active_mapping_id,
    'previewed_at',case when latest_preview.id is null then null else latest_preview.previewed_at end,
    'preview_scanned_count',case when latest_preview.id is null then null else latest_preview.scanned_count end,
    'preview_matched_count',case when latest_preview.id is null then null else latest_preview.matched_count end
  );
end;
$$;