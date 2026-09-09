create or replace function public.validate_hubspot_comp_mapping_version(target_mapping_version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  access jsonb;
  mv public.comp_hubspot_mapping_versions%rowtype;
  eligible_objects integer:=0;
  eligible_fields integer:=0;
  selected_value_fields integer:=0;
  selected_values integer:=0;
  unavailable_objects integer:=0;
  unavailable_fields integer:=0;
  unavailable_values integer:=0;
  empty_selected_fields integer:=0;
  blocking_changes integer:=0;
  blockers jsonb:='[]'::jsonb;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then
    raise exception 'Not authorized to validate HubSpot compensation mapping';
  end if;

  select * into mv
  from public.comp_hubspot_mapping_versions
  where id=target_mapping_version_id;
  if mv.id is null then raise exception 'Mapping version not found'; end if;

  select count(*) into eligible_objects
  from public.comp_hubspot_object_mappings om
  where om.mapping_version_id=mv.id and om.is_eligible;

  select count(*) into eligible_fields
  from public.comp_hubspot_field_mappings fm
  where fm.mapping_version_id=mv.id and fm.is_eligible;

  select count(*) into selected_value_fields
  from public.comp_hubspot_field_mappings fm
  where fm.mapping_version_id=mv.id and fm.is_eligible and fm.value_policy='selected';

  select count(*) into selected_values
  from public.comp_hubspot_value_mappings vm
  join public.comp_hubspot_field_mappings fm on fm.id=vm.field_mapping_id
  where fm.mapping_version_id=mv.id and fm.is_eligible and fm.value_policy='selected' and vm.is_eligible;

  select count(*) into unavailable_objects
  from public.comp_hubspot_object_mappings om
  where om.mapping_version_id=mv.id and om.is_eligible
    and not exists(
      select 1 from public.hubspot_object_definitions d
      where d.internal_object_key=om.object_type
        and d.hubspot_object_type=om.hubspot_object_type
        and d.is_active
        and d.read_access='AVAILABLE'
    );

  select count(*) into unavailable_fields
  from public.comp_hubspot_field_mappings fm
  where fm.mapping_version_id=mv.id and fm.is_eligible
    and not exists(
      select 1 from public.hubspot_property_definitions p
      where p.internal_object_key=fm.object_type
        and p.property_name=fm.property_name
        and p.is_active
        and not p.is_archived
    );

  select count(*) into unavailable_values
  from public.comp_hubspot_value_mappings vm
  join public.comp_hubspot_field_mappings fm on fm.id=vm.field_mapping_id
  where fm.mapping_version_id=mv.id
    and fm.is_eligible
    and fm.value_policy='selected'
    and vm.is_eligible
    and not exists(
      select 1 from public.comp_hubspot_discovered_values dv
      where dv.object_type=fm.object_type
        and dv.property_name=fm.property_name
        and dv.hubspot_value=vm.hubspot_value
        and dv.context=vm.context
        and dv.is_active
    );

  select count(*) into empty_selected_fields
  from public.comp_hubspot_field_mappings fm
  where fm.mapping_version_id=mv.id
    and fm.is_eligible
    and fm.value_policy='selected'
    and not exists(
      select 1 from public.comp_hubspot_value_mappings vm
      where vm.field_mapping_id=fm.id and vm.is_eligible
    );

  select count(*) into blocking_changes
  from public.comp_hubspot_config_changes
  where review_status='open' and severity in ('critical','action_required');

  if mv.status<>'draft' then blockers:=blockers||jsonb_build_array('Mapping version is not a draft'); end if;
  if eligible_objects=0 then blockers:=blockers||jsonb_build_array('Select at least one eligible HubSpot object'); end if;
  if eligible_fields=0 then blockers:=blockers||jsonb_build_array('Select at least one eligible HubSpot field'); end if;
  if unavailable_objects>0 then blockers:=blockers||jsonb_build_array(format('%s eligible object(s) are no longer readable in HubSpot',unavailable_objects)); end if;
  if unavailable_fields>0 then blockers:=blockers||jsonb_build_array(format('%s eligible field(s) are no longer available in HubSpot',unavailable_fields)); end if;
  if unavailable_values>0 then blockers:=blockers||jsonb_build_array(format('%s selected exact value(s) are no longer available in HubSpot',unavailable_values)); end if;
  if empty_selected_fields>0 then blockers:=blockers||jsonb_build_array(format('%s field(s) use selected-value mode but have no eligible values selected',empty_selected_fields)); end if;
  if blocking_changes>0 then blockers:=blockers||jsonb_build_array(format('%s critical/action-required HubSpot configuration change(s) must be resolved',blocking_changes)); end if;

  return jsonb_build_object(
    'mapping_version_id',mv.id,
    'version_number',mv.version_number,
    'status',mv.status,
    'ready',jsonb_array_length(blockers)=0,
    'eligible_objects',eligible_objects,
    'eligible_fields',eligible_fields,
    'selected_value_fields',selected_value_fields,
    'selected_values',selected_values,
    'unavailable_objects',unavailable_objects,
    'unavailable_fields',unavailable_fields,
    'unavailable_values',unavailable_values,
    'empty_selected_value_fields',empty_selected_fields,
    'blocking_configuration_changes',blocking_changes,
    'blockers',blockers
  );
end;
$function$;

revoke all on function public.validate_hubspot_comp_mapping_version(uuid) from public, anon;
grant execute on function public.validate_hubspot_comp_mapping_version(uuid) to authenticated;

create or replace function public.activate_hubspot_comp_mapping_version(target_mapping_version_id uuid, effective_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
 access jsonb;
 target public.comp_hubspot_mapping_versions%rowtype;
 prior public.comp_hubspot_mapping_versions%rowtype;
 readiness jsonb;
begin
 access:=public.get_current_user_access();
 if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized'; end if;

 select * into target from public.comp_hubspot_mapping_versions where id=target_mapping_version_id for update;
 if target.id is null then raise exception 'Mapping version not found'; end if;
 if target.status<>'draft' then raise exception 'Only draft mapping versions can be activated'; end if;

 readiness:=public.validate_hubspot_comp_mapping_version(target.id);
 if coalesce((readiness->>'ready')::boolean,false) is not true then
   raise exception 'Mapping version is not ready to activate: %', coalesce(readiness->'blockers','[]'::jsonb)::text;
 end if;

 select * into prior from public.comp_hubspot_mapping_versions where status='active' order by version_number desc limit 1 for update;
 if prior.id is not null then
   update public.comp_hubspot_mapping_versions set status='retired',effective_to=effective_at where id=prior.id;
 end if;
 update public.comp_hubspot_mapping_versions
 set status='active',effective_from=effective_at,effective_to=null,activated_by=(select auth.uid()),activated_at=now()
 where id=target.id;

 return jsonb_build_object(
   'activated_mapping_version_id',target.id,
   'version_number',target.version_number,
   'effective_from',effective_at,
   'retired_mapping_version_id',prior.id,
   'readiness',readiness
 );
end;
$function$;

revoke all on function public.activate_hubspot_comp_mapping_version(uuid,timestamptz) from public, anon;
grant execute on function public.activate_hubspot_comp_mapping_version(uuid,timestamptz) to authenticated;
