alter table public.hubspot_object_sync_settings
  add column if not exists record_filter_mode text not null default 'all',
  add column if not exists record_filter jsonb not null default '{"filterGroups":[]}'::jsonb;

alter table public.hubspot_object_sync_settings
  drop constraint if exists hubspot_object_sync_settings_filter_mode_check;
alter table public.hubspot_object_sync_settings
  add constraint hubspot_object_sync_settings_filter_mode_check check (record_filter_mode in ('all','filtered'));

create or replace function public.set_hubspot_object_record_filter(
  target_hubspot_object_type text,
  filter_mode text,
  filter_definition jsonb default '{"filterGroups":[]}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  access jsonb;
  obj public.hubspot_object_definitions%rowtype;
  group_item jsonb;
  filter_item jsonb;
  prop text;
  op text;
  vals jsonb;
  v text;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to configure HubSpot record filters'; end if;
  if filter_mode not in ('all','filtered') then raise exception 'filter_mode must be all or filtered'; end if;
  select * into obj from public.hubspot_object_definitions where hubspot_object_type=target_hubspot_object_type and is_active;
  if obj.hubspot_object_type is null then raise exception 'Unknown HubSpot object type %',target_hubspot_object_type; end if;

  if filter_mode='filtered' then
    if jsonb_typeof(coalesce(filter_definition->'filterGroups','null'::jsonb))<>'array' or jsonb_array_length(filter_definition->'filterGroups')=0 then
      raise exception 'Filtered mode requires at least one filter group';
    end if;
    for group_item in select value from jsonb_array_elements(filter_definition->'filterGroups') loop
      if jsonb_typeof(coalesce(group_item->'filters','null'::jsonb))<>'array' or jsonb_array_length(group_item->'filters')=0 then
        raise exception 'Each filter group requires at least one filter';
      end if;
      for filter_item in select value from jsonb_array_elements(group_item->'filters') loop
        prop:=nullif(filter_item->>'propertyName','');
        op:=upper(coalesce(nullif(filter_item->>'operator',''),'EQ'));
        if prop is null then raise exception 'Each filter requires propertyName'; end if;
        if not exists(select 1 from public.hubspot_property_definitions p where p.hubspot_object_type=target_hubspot_object_type and p.property_name=prop and p.is_active and not p.is_archived) then
          raise exception 'HubSpot field % is not available on %',prop,target_hubspot_object_type;
        end if;
        if op not in ('EQ','NEQ','IN','NOT_IN','GT','GTE','LT','LTE','BETWEEN','HAS_PROPERTY','NOT_HAS_PROPERTY') then
          raise exception 'Unsupported HubSpot sync filter operator %',op;
        end if;
        if op in ('EQ','NEQ','GT','GTE','LT','LTE') and nullif(filter_item->>'value','') is null then raise exception '% requires value',op; end if;
        if op in ('IN','NOT_IN') and (jsonb_typeof(coalesce(filter_item->'values','null'::jsonb))<>'array' or jsonb_array_length(filter_item->'values')=0) then raise exception '% requires values',op; end if;
        if op='BETWEEN' and (nullif(filter_item->>'highValue','') is null or nullif(filter_item->>'value','') is null) then raise exception 'BETWEEN requires value and highValue'; end if;

        if exists(select 1 from public.hubspot_property_definitions p where p.hubspot_object_type=target_hubspot_object_type and p.property_name=prop and p.property_type='enumeration') then
          vals:=case when op in ('IN','NOT_IN') then filter_item->'values' when op in ('EQ','NEQ') then jsonb_build_array(filter_item->>'value') else '[]'::jsonb end;
          for v in select value #>> '{}' from jsonb_array_elements(vals) loop
            if not exists(select 1 from public.comp_hubspot_discovered_values dv where dv.object_type=obj.internal_object_key and dv.property_name=prop and dv.hubspot_value=v and dv.is_active) then
              raise exception 'HubSpot value % is not currently available for %.%',v,obj.internal_object_key,prop;
            end if;
          end loop;
        end if;
      end loop;
    end loop;
  end if;

  insert into public.hubspot_object_sync_settings(hubspot_object_type,record_sync_enabled,sync_reason,updated_by,updated_at,record_filter_mode,record_filter)
  values(target_hubspot_object_type,false,'Available for future opt-in',auth.uid(),now(),filter_mode,case when filter_mode='all' then '{"filterGroups":[]}'::jsonb else filter_definition end)
  on conflict(hubspot_object_type) do update set
    record_filter_mode=excluded.record_filter_mode,
    record_filter=excluded.record_filter,
    updated_by=auth.uid(),
    updated_at=now();

  return jsonb_build_object('hubspot_object_type',target_hubspot_object_type,'filter_mode',filter_mode,'filter',case when filter_mode='all' then '{"filterGroups":[]}'::jsonb else filter_definition end);
end;$function$;

revoke execute on function public.set_hubspot_object_record_filter(text,text,jsonb) from public, anon;
grant execute on function public.set_hubspot_object_record_filter(text,text,jsonb) to authenticated;

create or replace function public.get_hubspot_object_sync_settings()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare access jsonb; begin
  access:=public.get_current_user_access();
  if not private.can_view_hubspot_comp_mapping(access) then raise exception 'Not authorized'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'hubspot_object_type',o.hubspot_object_type,
    'internal_object_key',o.internal_object_key,
    'object_category',o.object_category,
    'description',o.description,
    'read_access',o.read_access,
    'record_sync_enabled',coalesce(s.record_sync_enabled,false),
    'sync_reason',s.sync_reason,
    'record_filter_mode',coalesce(s.record_filter_mode,'all'),
    'record_filter',coalesce(s.record_filter,'{"filterGroups":[]}'::jsonb),
    'updated_at',s.updated_at
  ) order by o.object_category,o.internal_object_key) from public.hubspot_object_definitions o left join public.hubspot_object_sync_settings s on s.hubspot_object_type=o.hubspot_object_type where o.is_active),'[]'::jsonb);
end;$function$;

revoke execute on function public.get_hubspot_object_sync_settings() from public, anon;
grant execute on function public.get_hubspot_object_sync_settings() to authenticated;