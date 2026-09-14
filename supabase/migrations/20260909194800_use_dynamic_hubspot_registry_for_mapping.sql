create or replace function public.get_hubspot_comp_mapping_admin_data(target_mapping_version_id uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
 access jsonb;
 mv public.comp_hubspot_mapping_versions%rowtype;
begin
 access:=public.get_current_user_access();
 if not private.can_view_hubspot_comp_mapping(access) then raise exception 'Not authorized to view HubSpot compensation mapping'; end if;
 if target_mapping_version_id is null then
   select * into mv from public.comp_hubspot_mapping_versions
   order by case status when 'draft' then 0 when 'active' then 1 else 2 end,version_number desc limit 1;
 else select * into mv from public.comp_hubspot_mapping_versions where id=target_mapping_version_id; end if;
 if mv.id is null then raise exception 'Mapping version not found'; end if;
 return jsonb_build_object(
  'mapping_version',jsonb_build_object('id',mv.id,'version_number',mv.version_number,'status',mv.status,'effective_from',mv.effective_from,'effective_to',mv.effective_to,'notes',mv.notes),
  'objects',coalesce((select jsonb_agg(jsonb_build_object(
    'object_type',o.internal_object_key,'display_name',coalesce(nullif(initcap(replace(o.internal_object_key,'_',' ')),''),o.hubspot_object_type),
    'hubspot_object_type',o.hubspot_object_type,'description',o.description,'discovered_active',o.is_active and o.read_access='AVAILABLE',
    'read_access',o.read_access,'write_access',o.write_access,'object_category',o.object_category,'eligible',coalesce(m.is_eligible,false),
    'property_count',(select count(*) from public.hubspot_property_definitions p where p.hubspot_object_type=o.hubspot_object_type and p.is_active)
  ) order by o.object_category,o.hubspot_object_type)
  from public.hubspot_object_definitions o
  left join public.comp_hubspot_object_mappings m on m.mapping_version_id=mv.id and m.object_type=o.internal_object_key),'[]'::jsonb),
  'fields',coalesce((select jsonb_agg(jsonb_build_object(
    'object_type',f.internal_object_key,'hubspot_object_type',f.hubspot_object_type,'property_name',f.property_name,'display_name',f.display_label,
    'data_type',f.property_type,'field_type',f.field_type,'description',f.description,'group_name',f.group_name,
    'is_multi_value',f.field_type='checkbox','source_system','hubspot','discovered_active',f.is_active and not f.is_archived,
    'hidden',f.is_hidden,'eligible',coalesce(m.is_eligible,false),'value_policy',coalesce(m.value_policy,'all'),
    'selected_value_count',(select count(*) from public.comp_hubspot_value_mappings vm where vm.field_mapping_id=m.id and vm.is_eligible),
    'option_count',jsonb_array_length(coalesce(f.options,'[]'::jsonb))
  ) order by f.internal_object_key,f.display_label)
  from public.hubspot_property_definitions f
  left join public.comp_hubspot_field_mappings m on m.mapping_version_id=mv.id and m.object_type=f.internal_object_key and m.property_name=f.property_name
  where f.is_active and not f.is_archived),'[]'::jsonb),
  'values',coalesce((select jsonb_agg(jsonb_build_object(
    'object_type',v.object_type,'property_name',v.property_name,'hubspot_value',v.hubspot_value,'display_label',v.display_label,
    'context',v.context,'discovered_active',v.is_active,'eligible',coalesce(vm.is_eligible,false)
  ) order by v.object_type,v.property_name,v.context->>'pipeline_name',v.display_label)
  from public.comp_hubspot_discovered_values v
  join public.hubspot_property_definitions f on f.internal_object_key=v.object_type and f.property_name=v.property_name and f.is_active
  left join public.comp_hubspot_field_mappings fm on fm.mapping_version_id=mv.id and fm.object_type=v.object_type and fm.property_name=v.property_name
  left join public.comp_hubspot_value_mappings vm on vm.field_mapping_id=fm.id and vm.hubspot_value=v.hubspot_value and vm.context=v.context),'[]'::jsonb)
 );
end; $$;
revoke all on function public.get_hubspot_comp_mapping_admin_data(uuid) from public,anon;
grant execute on function public.get_hubspot_comp_mapping_admin_data(uuid) to authenticated;

do $$
declare def text; newdef text;
begin
 select pg_get_functiondef(p.oid) into def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='apply_hubspot_comp_mapping_change' limit 1;
 newdef:=replace(def,
E'  if target_object is null then raise exception ''object_type is required''; end if;\n  if change_level in (''field'',''value'') and target_property is null then raise exception ''property_name is required''; end if;\n  if change_level=''value'' and target_value is null then raise exception ''hubspot_value is required''; end if;',
E'  if target_object is null then raise exception ''object_type is required''; end if;\n  if not exists(select 1 from public.hubspot_object_definitions o where o.internal_object_key=target_object and o.is_active and o.read_access=''AVAILABLE'') then raise exception ''HubSpot object is not currently available to the compensation mapping''; end if;\n  if change_level in (''field'',''value'') and target_property is null then raise exception ''property_name is required''; end if;\n  if change_level in (''field'',''value'') and not exists(select 1 from public.hubspot_property_definitions f where f.internal_object_key=target_object and f.property_name=target_property and f.is_active and not f.is_archived) then raise exception ''HubSpot field is not currently available to the compensation mapping''; end if;\n  if change_level=''value'' and target_value is null then raise exception ''hubspot_value is required''; end if;\n  if change_level=''value'' and not exists(select 1 from public.comp_hubspot_discovered_values v where v.object_type=target_object and v.property_name=target_property and v.hubspot_value=target_value and v.context=target_context and v.is_active) then raise exception ''HubSpot value is not currently available for this field/context''; end if;');
 newdef:=replace(newdef,
E'    insert into public.comp_hubspot_object_mappings(mapping_version_id,object_type,hubspot_object_type,is_eligible)\n    select mv.id,target_object,o.hubspot_object_type,target_eligible\n    from public.comp_rule_object_catalog o where o.object_type=target_object',
E'    insert into public.comp_hubspot_object_mappings(mapping_version_id,object_type,hubspot_object_type,is_eligible)\n    select mv.id,target_object,o.hubspot_object_type,target_eligible\n    from public.hubspot_object_definitions o where o.internal_object_key=target_object');
 if newdef=def then raise exception 'Could not rewrite mapping write path to dynamic HubSpot registry'; end if;
 execute newdef;
end $$;