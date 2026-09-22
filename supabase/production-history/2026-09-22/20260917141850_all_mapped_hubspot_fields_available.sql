-- Mapped HubSpot objects expose every active synced field and every synced/discovered value.
-- Curated catalog rows remain authoritative for business-friendly labels/types (for example Deal Owner = user).

create or replace function private.sync_comp_rule_field_from_hubspot_property()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  inferred_type text;
  inferred_multi boolean;
begin
  if not exists(
    select 1
    from public.comp_hubspot_object_mappings om
    where om.object_type=new.internal_object_key
      and om.hubspot_object_type=new.hubspot_object_type
      and om.is_eligible=true
  ) then
    return new;
  end if;

  inferred_multi:=new.field_type in ('checkbox','multiplecheckbox');
  inferred_type:=case new.property_type
    when 'bool' then 'boolean'
    when 'date' then 'date'
    when 'datetime' then 'datetime'
    when 'number' then 'number'
    when 'enumeration' then case when inferred_multi then 'multi_enumeration' else 'enumeration' end
    else 'string'
  end;

  insert into public.comp_rule_field_catalog(
    object_type,property_name,display_name,data_type,description,options,is_multi_value,is_active,source_system
  ) values(
    new.internal_object_key,
    new.property_name,
    coalesce(nullif(new.display_label,''),initcap(replace(new.property_name,'_',' '))),
    inferred_type,
    new.description,
    coalesce(new.options,'[]'::jsonb),
    inferred_multi,
    new.is_active,
    'hubspot_sync_auto'
  )
  on conflict(object_type,property_name) do update
  set
    display_name=case when public.comp_rule_field_catalog.source_system in ('hubspot','hubspot_curated') then public.comp_rule_field_catalog.display_name else excluded.display_name end,
    data_type=case when public.comp_rule_field_catalog.source_system in ('hubspot','hubspot_curated') then public.comp_rule_field_catalog.data_type else excluded.data_type end,
    description=case when public.comp_rule_field_catalog.source_system in ('hubspot','hubspot_curated') and public.comp_rule_field_catalog.description is not null then public.comp_rule_field_catalog.description else excluded.description end,
    options=case when public.comp_rule_field_catalog.source_system in ('hubspot','hubspot_curated') and jsonb_array_length(public.comp_rule_field_catalog.options)>0 then public.comp_rule_field_catalog.options else excluded.options end,
    is_multi_value=case when public.comp_rule_field_catalog.source_system in ('hubspot','hubspot_curated') then public.comp_rule_field_catalog.is_multi_value else excluded.is_multi_value end,
    is_active=excluded.is_active,
    updated_at=now();

  return new;
end;
$$;

revoke all on function private.sync_comp_rule_field_from_hubspot_property() from public,anon,authenticated;

drop trigger if exists sync_comp_rule_field_from_hubspot_property on public.hubspot_property_definitions;
create trigger sync_comp_rule_field_from_hubspot_property
after insert or update of display_label,property_type,field_type,description,options,is_active
on public.hubspot_property_definitions
for each row execute function private.sync_comp_rule_field_from_hubspot_property();

insert into public.comp_rule_field_catalog(
  object_type,property_name,display_name,data_type,description,options,is_multi_value,is_active,source_system
)
select distinct on (p.internal_object_key,p.property_name)
  p.internal_object_key,
  p.property_name,
  coalesce(nullif(p.display_label,''),initcap(replace(p.property_name,'_',' '))),
  case p.property_type
    when 'bool' then 'boolean'
    when 'date' then 'date'
    when 'datetime' then 'datetime'
    when 'number' then 'number'
    when 'enumeration' then case when p.field_type in ('checkbox','multiplecheckbox') then 'multi_enumeration' else 'enumeration' end
    else 'string'
  end,
  p.description,
  coalesce(p.options,'[]'::jsonb),
  p.field_type in ('checkbox','multiplecheckbox'),
  p.is_active,
  'hubspot_sync_auto'
from public.hubspot_property_definitions p
join public.comp_hubspot_object_mappings om
  on om.object_type=p.internal_object_key
 and om.hubspot_object_type=p.hubspot_object_type
 and om.is_eligible=true
where p.is_active=true
order by p.internal_object_key,p.property_name,p.updated_at desc
on conflict(object_type,property_name) do update
set
  is_active=true,
  updated_at=now();

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
        'options',case
          when exists(
            select 1 from public.comp_hubspot_discovered_values dv
            where dv.object_type=p.internal_object_key
              and dv.property_name=p.property_name
              and dv.is_active
          ) then coalesce((
            select jsonb_agg(jsonb_build_object(
              'value',dv.hubspot_value,
              'label',dv.display_label,
              'group',nullif(dv.context->>'pipeline_name','')
            ) order by coalesce(dv.context->>'pipeline_name',''),dv.display_label,dv.hubspot_value)
            from public.comp_hubspot_discovered_values dv
            where dv.object_type=p.internal_object_key
              and dv.property_name=p.property_name
              and dv.is_active
          ),'[]'::jsonb)
          else coalesce((
            select jsonb_agg(jsonb_build_object(
              'value',opt->>'value',
              'label',coalesce(nullif(opt->>'label',''),opt->>'value'),
              'group',null
            ) order by coalesce((opt->>'displayOrder')::integer,2147483647),coalesce(opt->>'label',opt->>'value'))
            from jsonb_array_elements(coalesce(p.options,'[]'::jsonb)) opt
            where coalesce((opt->>'hidden')::boolean,false)=false
              and nullif(opt->>'value','') is not null
          ),'[]'::jsonb)
        end
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