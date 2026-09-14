-- Require impact review before consequential HubSpot record-filter changes.
-- The low-level setter remains available to privileged internal callers only.

create or replace function public.apply_hubspot_object_record_filter_change(
  target_hubspot_object_type text,
  proposed_filter_mode text,
  proposed_filter_definition jsonb default '{"filterGroups":[]}'::jsonb,
  resolution_action text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  access jsonb;
  impact jsonb;
  result jsonb;
  actor uuid := (select auth.uid());
  needs_review boolean;
begin
  access := public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then
    raise exception 'Not authorized to change HubSpot record filters' using errcode = '42501';
  end if;

  impact := public.analyze_hubspot_object_record_filter_change(
    target_hubspot_object_type,
    proposed_filter_mode,
    proposed_filter_definition
  );

  if coalesce((impact->>'supported')::boolean,false) is not true then
    return jsonb_build_object('applied',false,'requires_resolution',false,'impact',impact);
  end if;

  needs_review := coalesce((impact->>'requires_review')::boolean,false);

  if needs_review and resolution_action is null then
    return jsonb_build_object(
      'applied',false,
      'requires_resolution',true,
      'resolution_options',jsonb_build_array('future_only'),
      'impact',impact
    );
  end if;

  if resolution_action is not null and resolution_action <> 'future_only' then
    raise exception 'Unsupported resolution_action %. Current supported option is future_only.', resolution_action using errcode='22023';
  end if;

  result := public.set_hubspot_object_record_filter(
    target_hubspot_object_type,
    proposed_filter_mode,
    proposed_filter_definition
  );

  insert into public.app_access_audit_events(
    actor_user_id,
    event_type,
    event_reason,
    new_state
  ) values (
    actor,
    'hubspot_record_filter_changed',
    'HubSpot record synchronization scope changed.',
    jsonb_build_object(
      'hubspot_object_type',target_hubspot_object_type,
      'filter_mode',proposed_filter_mode,
      'filter',case when proposed_filter_mode='all' then '{"filterGroups":[]}'::jsonb else proposed_filter_definition end,
      'resolution_action',resolution_action,
      'impact',impact
    )
  );

  return jsonb_build_object(
    'applied',true,
    'requires_resolution',false,
    'resolution_action',resolution_action,
    'impact',impact,
    'configuration',result
  );
end;
$function$;

revoke execute on function public.set_hubspot_object_record_filter(text,text,jsonb) from public, anon, authenticated;
revoke execute on function public.apply_hubspot_object_record_filter_change(text,text,jsonb,text) from public, anon;
grant execute on function public.apply_hubspot_object_record_filter_change(text,text,jsonb,text) to authenticated;
