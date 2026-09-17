-- Rule-builder option values are the union of values seen in synced records
-- and values defined by HubSpot, so mapped fields never hide valid choices.

create or replace function private.comp_rule_builder_field_options(
  target_object_type text,
  target_property_name text,
  definition_options jsonb
)
returns jsonb
language sql
stable
set search_path=''
as $$
  with discovered as (
    select
      dv.hubspot_value as value,
      coalesce(nullif(dv.display_label,''),dv.hubspot_value) as label,
      nullif(dv.context->>'pipeline_name','') as option_group,
      0 as priority
    from public.comp_hubspot_discovered_values dv
    where dv.object_type=target_object_type
      and dv.property_name=target_property_name
      and dv.is_active
      and nullif(dv.hubspot_value,'') is not null
  ), defined as (
    select
      opt->>'value' as value,
      coalesce(nullif(opt->>'label',''),opt->>'value') as label,
      null::text as option_group,
      1 as priority
    from jsonb_array_elements(coalesce(definition_options,'[]'::jsonb)) opt
    where coalesce((opt->>'hidden')::boolean,false)=false
      and nullif(opt->>'value','') is not null
  ), combined as (
    select * from discovered
    union all
    select * from defined
  ), deduped as (
    select distinct on(value)
      value,label,option_group
    from combined
    order by value,priority,option_group nulls last,label
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object('value',value,'label',label,'group',option_group)
      order by coalesce(option_group,''),label,value
    ),
    '[]'::jsonb
  )
  from deduped;
$$;

revoke all on function private.comp_rule_builder_field_options(text,text,jsonb) from public,anon,authenticated;

create or replace function public.get_comp_rule_builder_catalog(target_plan_component_id uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
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
        'object_type',p.internal_object_key,
        'property_name',p.property_name,
        'display_name',coalesce(cf.display_name,p.display_label,p.property_name),
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
        'mapping_value_policy','all',
        'hubspot_group',p.group_name,
        'hubspot_field_type',p.field_type,
        'external_options',p.external_options,
        'options',private.comp_rule_builder_field_options(p.internal_object_key,p.property_name,p.options)
      ) order by p.internal_object_key,coalesce(p.group_name,''),coalesce(cf.display_name,p.display_label,p.property_name),p.property_name)
      from public.comp_hubspot_object_mappings om
      join public.hubspot_property_definitions p
        on p.internal_object_key=om.object_type
       and p.hubspot_object_type=om.hubspot_object_type
       and p.is_active
      left join public.comp_rule_field_catalog cf
        on cf.object_type=p.internal_object_key
       and cf.property_name=p.property_name
       and cf.is_active
      where om.mapping_version_id=mapping_id
        and om.is_eligible
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

grant execute on function public.get_comp_rule_builder_catalog(uuid) to authenticated;
