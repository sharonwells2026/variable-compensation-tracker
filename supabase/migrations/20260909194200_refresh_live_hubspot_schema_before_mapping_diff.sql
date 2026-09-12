do $$
declare def text; newdef text;
begin
 select pg_get_functiondef(p.oid) into def
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='refresh_hubspot_comp_configuration_changes' limit 1;
 newdef:=replace(def,
E'  if not private.can_edit_hubspot_comp_mapping(access) then\n    raise exception ''Not authorized to refresh HubSpot compensation configuration'';\n  end if;',
E'  if not private.can_edit_hubspot_comp_mapping(access) then\n    raise exception ''Not authorized to refresh HubSpot compensation configuration'';\n  end if;\n\n  -- Refresh live pipeline/stage metadata before comparing configuration snapshots.\n  perform public.sync_hubspot_pipelines();');
 if newdef=def then raise exception 'Could not insert live HubSpot schema refresh'; end if;
 execute newdef;
end $$;