create or replace function public.refresh_compensation_management_data(force_refresh boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  hubspot_result jsonb;
  earnings_result jsonb;
begin
  if not private.has_permission('hubspot.refresh') then
    raise exception 'Management permission is required to refresh HubSpot.' using errcode = '42501';
  end if;

  hubspot_result := public.refresh_hubspot_compensation_data(force_refresh);

  if hubspot_result->>'status' in ('completed','skipped') then
    earnings_result := public.apply_comp_deal_earning_refresh();
  else
    earnings_result := jsonb_build_object('status','not_run','reason','HubSpot refresh did not complete.');
  end if;

  insert into public.app_access_audit_events (
    actor_user_id, event_type, event_reason, new_state
  ) values (
    (select auth.uid()),
    'management_compensation_refresh',
    'An authorized management user refreshed HubSpot and compensation earnings.',
    jsonb_build_object('hubspot', hubspot_result, 'earnings', earnings_result)
  );

  return jsonb_build_object(
    'status', 'completed',
    'hubspot', hubspot_result,
    'earnings', earnings_result,
    'completed_at', pg_catalog.now()
  );
end;
$function$;