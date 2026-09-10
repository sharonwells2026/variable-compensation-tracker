create or replace function public.get_comp_rule_builder_catalog(target_plan_component_id uuid default null::uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
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
            'label',dv.display_label,
            'group',nullif(dv.context->>'pipeline_name','')
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
$function$;
