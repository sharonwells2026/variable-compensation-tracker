create or replace function public.preview_hubspot_object_record_filter(
  target_hubspot_object_type text,
  filter_definition jsonb default '{"filterGroups":[]}'::jsonb,
  max_results integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $$
declare
  access jsonb;
  obj public.hubspot_object_definitions%rowtype;
  hubspot_key text;
  r extensions.http_response;
  body jsonb;
  group_item jsonb;
  filter_item jsonb;
  prop text;
  op text;
  props_json jsonb:='[]'::jsonb;
  props_seen text[]:=array[]::text[];
  request_body jsonb;
  requested_limit integer:=greatest(1,least(coalesce(max_results,25),100));
  current_scope integer:=0;
  current_stored integer:=0;
  samples jsonb:='[]'::jsonb;
  setting public.hubspot_object_sync_settings%rowtype;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then
    raise exception 'Not authorized to preview HubSpot record filters';
  end if;

  select * into obj
  from public.hubspot_object_definitions
  where hubspot_object_type=target_hubspot_object_type and is_active;
  if obj.hubspot_object_type is null then raise exception 'Unknown HubSpot object type %',target_hubspot_object_type; end if;
  if obj.read_access<>'AVAILABLE' then raise exception 'HubSpot object % is not readable with the current connection',target_hubspot_object_type; end if;

  if jsonb_typeof(coalesce(filter_definition->'filterGroups','null'::jsonb))<>'array' then
    raise exception 'filterGroups must be an array';
  end if;

  for group_item in select value from jsonb_array_elements(coalesce(filter_definition->'filterGroups','[]'::jsonb)) loop
    if jsonb_typeof(coalesce(group_item->'filters','null'::jsonb))<>'array' or jsonb_array_length(group_item->'filters')=0 then
      raise exception 'Each filter group requires at least one filter';
    end if;
    for filter_item in select value from jsonb_array_elements(group_item->'filters') loop
      prop:=nullif(filter_item->>'propertyName','');
      op:=upper(coalesce(nullif(filter_item->>'operator',''),'EQ'));
      if prop is null then raise exception 'Each filter requires propertyName'; end if;
      if not exists(
        select 1 from public.hubspot_property_definitions p
        where p.hubspot_object_type=target_hubspot_object_type
          and p.property_name=prop and p.is_active and not p.is_archived
      ) then raise exception 'HubSpot field % is not available on %',prop,target_hubspot_object_type; end if;
      if op not in ('EQ','NEQ','IN','NOT_IN','GT','GTE','LT','LTE','BETWEEN','HAS_PROPERTY','NOT_HAS_PROPERTY') then
        raise exception 'Unsupported HubSpot sync filter operator %',op;
      end if;
      if op in ('EQ','NEQ','GT','GTE','LT','LTE') and nullif(filter_item->>'value','') is null then raise exception '% requires value',op; end if;
      if op in ('IN','NOT_IN') and (jsonb_typeof(coalesce(filter_item->'values','null'::jsonb))<>'array' or jsonb_array_length(filter_item->'values')=0) then
        raise exception '% requires values',op;
      end if;
      if op='BETWEEN' and (nullif(filter_item->>'highValue','') is null or nullif(filter_item->>'value','') is null) then
        raise exception 'BETWEEN requires value and highValue';
      end if;
      if not (prop=any(props_seen)) then
        props_seen:=array_append(props_seen,prop);
        props_json:=props_json||jsonb_build_array(prop);
      end if;
    end loop;
  end loop;

  for prop in
    select p.property_name
    from public.hubspot_property_definitions p
    where p.hubspot_object_type=target_hubspot_object_type
      and p.is_active and not p.is_archived and not p.is_hidden
      and p.property_name in ('hs_object_id','hs_createdate','hs_lastmodifieddate','hs_timestamp','hs_meeting_title','hs_activity_type','dealname','name')
    order by case p.property_name
      when 'hs_object_id' then 1 when 'name' then 2 when 'dealname' then 3 when 'hs_meeting_title' then 4 when 'hs_activity_type' then 5 else 10 end
  loop
    if not (prop=any(props_seen)) then
      props_seen:=array_append(props_seen,prop);
      props_json:=props_json||jsonb_build_array(prop);
    end if;
  end loop;

  select decrypted_secret into hubspot_key from vault.decrypted_secrets where name='hubspot_service_key' limit 1;
  if hubspot_key is null then raise exception 'The HubSpot service key was not found in Vault.'; end if;

  request_body:=jsonb_build_object(
    'filterGroups',coalesce(filter_definition->'filterGroups','[]'::jsonb),
    'properties',props_json,
    'limit',requested_limit
  );

  r:=extensions.http((
    'POST',
    'https://api.hubapi.com/crm/v3/objects/'||target_hubspot_object_type||'/search',
    array[
      extensions.http_header('Authorization','Bearer '||hubspot_key),
      extensions.http_header('Content-Type','application/json')
    ],
    'application/json',
    request_body::text
  )::extensions.http_request);

  if r.status<>200 then
    return jsonb_build_object(
      'supported',false,
      'hubspot_object_type',target_hubspot_object_type,
      'http_status',r.status,
      'reason',left(r.content,500)
    );
  end if;

  body:=r.content::jsonb;
  samples:=coalesce(body->'results','[]'::jsonb);

  select count(*),count(*) filter(where in_sync_scope)
    into current_stored,current_scope
  from public.hubspot_generic_records
  where hubspot_object_type=target_hubspot_object_type;

  select * into setting from public.hubspot_object_sync_settings where hubspot_object_type=target_hubspot_object_type;

  return jsonb_build_object(
    'supported',true,
    'hubspot_object_type',target_hubspot_object_type,
    'internal_object_key',obj.internal_object_key,
    'total_matches',coalesce((body->>'total')::integer,jsonb_array_length(samples)),
    'sample_count',jsonb_array_length(samples),
    'samples',samples,
    'properties_requested',props_json,
    'current_record_filter_mode',coalesce(setting.record_filter_mode,'all'),
    'current_record_filter',coalesce(setting.record_filter,'{"filterGroups":[]}'::jsonb),
    'current_stored_records',current_stored,
    'current_in_scope_records',current_scope
  );
end;$$;

revoke all on function public.preview_hubspot_object_record_filter(text,jsonb,integer) from public,anon;
grant execute on function public.preview_hubspot_object_record_filter(text,jsonb,integer) to authenticated;

create or replace function public.analyze_hubspot_object_record_filter_change(
  target_hubspot_object_type text,
  proposed_filter_mode text,
  proposed_filter_definition jsonb default '{"filterGroups":[]}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  access jsonb;
  obj public.hubspot_object_definitions%rowtype;
  preview jsonb;
  setting public.hubspot_object_sync_settings%rowtype;
  current_scope integer:=0;
  proposed_total integer:=0;
  direction text;
  active_mapping_refs integer:=0;
  draft_mapping_refs integer:=0;
  active_rule_refs integer:=0;
  draft_rule_refs integer:=0;
  requires_review boolean:=false;
  warnings jsonb:='[]'::jsonb;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then
    raise exception 'Not authorized to analyze HubSpot record filter changes';
  end if;
  if proposed_filter_mode not in ('all','filtered') then raise exception 'proposed_filter_mode must be all or filtered'; end if;

  select * into obj from public.hubspot_object_definitions where hubspot_object_type=target_hubspot_object_type and is_active;
  if obj.hubspot_object_type is null then raise exception 'Unknown HubSpot object type %',target_hubspot_object_type; end if;
  select * into setting from public.hubspot_object_sync_settings where hubspot_object_type=target_hubspot_object_type;

  preview:=public.preview_hubspot_object_record_filter(
    target_hubspot_object_type,
    case when proposed_filter_mode='all' then '{"filterGroups":[]}'::jsonb else proposed_filter_definition end,
    5
  );
  if coalesce((preview->>'supported')::boolean,false) is not true then return preview; end if;

  proposed_total:=coalesce((preview->>'total_matches')::integer,0);
  current_scope:=coalesce((preview->>'current_in_scope_records')::integer,0);
  direction:=case when proposed_total<current_scope then 'narrowing' when proposed_total>current_scope then 'widening' else 'same_count' end;

  select count(*) into active_mapping_refs
  from public.comp_hubspot_object_mappings om
  join public.comp_hubspot_mapping_versions mv on mv.id=om.mapping_version_id
  where om.hubspot_object_type=target_hubspot_object_type and om.is_eligible and mv.status='active';

  select count(*) into draft_mapping_refs
  from public.comp_hubspot_object_mappings om
  join public.comp_hubspot_mapping_versions mv on mv.id=om.mapping_version_id
  where om.hubspot_object_type=target_hubspot_object_type and om.is_eligible and mv.status='draft';

  select count(*) filter(where s.is_active),count(*) filter(where not s.is_active)
    into active_rule_refs,draft_rule_refs
  from public.comp_rule_predicates p
  join public.comp_rule_sets s on s.id=p.rule_set_id
  where p.object_type=obj.internal_object_key;

  if direction='narrowing' and current_scope>proposed_total then
    warnings:=warnings||jsonb_build_array(jsonb_build_object(
      'type','records_leave_scope',
      'severity','warning',
      'message',(current_scope-proposed_total)||' currently in-scope record(s) may become historical/out of scope after the next sync.'
    ));
  end if;
  if active_mapping_refs>0 then
    warnings:=warnings||jsonb_build_array(jsonb_build_object(
      'type','active_mapping_dependency','severity','warning',
      'message','This object is enabled in an active HubSpot Compensation Mapping.'
    ));
  end if;
  if active_rule_refs>0 then
    warnings:=warnings||jsonb_build_array(jsonb_build_object(
      'type','active_rule_dependency','severity','warning',
      'message',active_rule_refs||' active compensation rule predicate(s) use this object.'
    ));
  end if;

  requires_review:=jsonb_array_length(warnings)>0;

  return jsonb_build_object(
    'supported',true,
    'hubspot_object_type',target_hubspot_object_type,
    'internal_object_key',obj.internal_object_key,
    'current',jsonb_build_object(
      'filter_mode',coalesce(setting.record_filter_mode,'all'),
      'filter',coalesce(setting.record_filter,'{"filterGroups":[]}'::jsonb),
      'in_scope_records',current_scope
    ),
    'proposed',jsonb_build_object(
      'filter_mode',proposed_filter_mode,
      'filter',case when proposed_filter_mode='all' then '{"filterGroups":[]}'::jsonb else proposed_filter_definition end,
      'estimated_matching_records',proposed_total,
      'sample_records',preview->'samples'
    ),
    'direction',direction,
    'dependencies',jsonb_build_object(
      'active_mapping_references',active_mapping_refs,
      'draft_mapping_references',draft_mapping_refs,
      'active_rule_predicates',active_rule_refs,
      'draft_rule_predicates',draft_rule_refs
    ),
    'requires_review',requires_review,
    'warnings',warnings,
    'historical_behavior',jsonb_build_object(
      'delete_historical_records',false,
      'recalculate_paid_compensation',false,
      'future_evaluation_uses_current_scope',true
    ),
    'recommended_action','apply_future_only'
  );
end;$$;

revoke all on function public.analyze_hubspot_object_record_filter_change(text,text,jsonb) from public,anon;
grant execute on function public.analyze_hubspot_object_record_filter_change(text,text,jsonb) to authenticated;
