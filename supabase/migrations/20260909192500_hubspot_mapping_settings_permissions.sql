insert into private.app_permissions(permission_key,category,display_name,description)
values
 ('settings.hubspot_mapping.view','Settings','View HubSpot Compensation Mapping','View approved HubSpot objects, fields, values, mapping versions, and configuration-change impacts used by compensation.'),
 ('settings.hubspot_mapping.edit','Settings','Edit HubSpot Compensation Mapping','Create and edit HubSpot compensation mapping drafts, resolve configuration changes, and activate mapping versions.')
on conflict(permission_key) do update set category=excluded.category,display_name=excluded.display_name,description=excluded.description;

create or replace function private.can_view_hubspot_comp_mapping(access jsonb)
returns boolean language sql stable set search_path=''
as $$ select coalesce((access->>'authenticated')::boolean,false) and (
 coalesce(access->'permissions','[]'::jsonb) ? 'settings.manage'
 or coalesce(access->'permissions','[]'::jsonb) ? 'settings.hubspot_mapping.view'
 or coalesce(access->'permissions','[]'::jsonb) ? 'settings.hubspot_mapping.edit'); $$;

create or replace function private.can_edit_hubspot_comp_mapping(access jsonb)
returns boolean language sql stable set search_path=''
as $$ select coalesce((access->>'authenticated')::boolean,false) and (
 coalesce(access->'permissions','[]'::jsonb) ? 'settings.manage'
 or coalesce(access->'permissions','[]'::jsonb) ? 'settings.hubspot_mapping.edit'); $$;

revoke all on function private.can_view_hubspot_comp_mapping(jsonb) from public,anon,authenticated;
revoke all on function private.can_edit_hubspot_comp_mapping(jsonb) from public,anon,authenticated;

do $$
declare r record; def text; newdef text;
begin
 for r in
   select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname in (
    'get_hubspot_comp_mapping_admin_data','get_hubspot_comp_configuration_changes',
    'analyze_hubspot_comp_mapping_change','apply_hubspot_comp_mapping_change',
    'create_hubspot_comp_mapping_version','activate_hubspot_comp_mapping_version',
    'retire_hubspot_comp_mapping_draft','refresh_hubspot_comp_configuration_changes',
    'resolve_hubspot_comp_configuration_change')
 loop
   def:=pg_get_functiondef(r.oid);
   newdef:=replace(def,
     'coalesce((access->>''authenticated'')::boolean,false) is not true or not (coalesce(access->''permissions'',''[]''::jsonb) ? ''plans.view'')',
     'not private.can_view_hubspot_comp_mapping(access)');
   newdef:=replace(newdef,
     E'coalesce((access->>''authenticated'')::boolean,false) is not true\n     or not (coalesce(access->''permissions'',''[]''::jsonb) ? ''plans.view'')',
     'not private.can_view_hubspot_comp_mapping(access)');
   newdef:=replace(newdef,
     'coalesce((access->>''authenticated'')::boolean,false) is not true or not (coalesce(access->''permissions'',''[]''::jsonb) ? ''plans.edit'')',
     'not private.can_edit_hubspot_comp_mapping(access)');
   newdef:=replace(newdef,
     E'coalesce((access->>''authenticated'')::boolean,false) is not true\n     or not (coalesce(access->''permissions'',''[]''::jsonb) ? ''plans.edit'')',
     'not private.can_edit_hubspot_comp_mapping(access)');
   if newdef=def then raise exception 'Permission rewrite did not match function %',r.proname; end if;
   execute newdef;
 end loop;
end $$;