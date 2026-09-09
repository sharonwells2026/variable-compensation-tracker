alter table public.hubspot_pipeline_stages add column if not exists is_active boolean not null default true;

create or replace function public.sync_hubspot_pipelines()
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $$
declare
  access jsonb;
  hubspot_key text;
  hubspot_response extensions.http_response;
  response_body jsonb;
  p jsonb;
  s jsonb;
  pipeline_count integer:=0;
  stage_count integer:=0;
  pipeline_id text;
  pipeline_name text;
  stage_id text;
  stage_name text;
  stage_closed boolean;
  stage_probability numeric;
begin
  access:=public.get_current_user_access();
  if not private.can_edit_hubspot_comp_mapping(access) then
    raise exception 'Not authorized to refresh HubSpot pipeline configuration';
  end if;

  select decrypted_secret into hubspot_key
  from vault.decrypted_secrets where name='hubspot_service_key' limit 1;
  if hubspot_key is null then raise exception 'The HubSpot service key was not found in Vault.'; end if;

  hubspot_response:=extensions.http((
    'GET','https://api.hubapi.com/crm/v3/pipelines/deals?archived=false',
    array[
      extensions.http_header('Authorization','Bearer '||hubspot_key),
      extensions.http_header('Accept','application/json')
    ],null,null
  )::extensions.http_request);
  if hubspot_response.status<>200 then
    raise exception 'HubSpot returned HTTP % while reading pipelines: %',hubspot_response.status,left(hubspot_response.content,500);
  end if;
  response_body:=hubspot_response.content::jsonb;

  update public.hubspot_pipelines set is_active=false,updated_at=now();
  update public.hubspot_pipeline_stages set is_active=false,updated_at=now();
  update public.comp_hubspot_discovered_values
     set is_active=false,last_seen_at=now()
   where object_type='deal' and property_name in ('pipeline','dealstage');

  for p in select value from jsonb_array_elements(coalesce(response_body->'results','[]'::jsonb)) loop
    pipeline_id:=p->>'id';
    pipeline_name:=coalesce(nullif(p->>'label',''),pipeline_id);
    insert into public.hubspot_pipelines(hubspot_pipeline_id,pipeline_name,is_active,last_synced_at)
    values(pipeline_id,pipeline_name,not coalesce((p->>'archived')::boolean,false),now())
    on conflict(hubspot_pipeline_id) do update set
      pipeline_name=excluded.pipeline_name,is_active=excluded.is_active,last_synced_at=excluded.last_synced_at,updated_at=now();

    insert into public.comp_hubspot_discovered_values(object_type,property_name,hubspot_value,display_label,context,is_active,first_seen_at,last_seen_at)
    values('deal','pipeline',pipeline_id,pipeline_name,'{}'::jsonb,true,now(),now())
    on conflict(object_type,property_name,hubspot_value,context) do update set
      display_label=excluded.display_label,is_active=true,last_seen_at=now();
    pipeline_count:=pipeline_count+1;

    for s in select value from jsonb_array_elements(coalesce(p->'stages','[]'::jsonb)) loop
      stage_id:=s->>'id';
      stage_name:=coalesce(nullif(s->>'label',''),stage_id);
      stage_closed:=lower(coalesce(s->'metadata'->>'isClosed','false'))='true';
      begin stage_probability:=nullif(s->'metadata'->>'probability','')::numeric; exception when others then stage_probability:=null; end;
      insert into public.hubspot_pipeline_stages(hubspot_stage_id,hubspot_pipeline_id,stage_name,display_order,is_closed_won,is_closed_lost,is_active)
      values(stage_id,pipeline_id,stage_name,nullif(s->>'displayOrder','')::integer,
             stage_closed and stage_probability=1,
             stage_closed and stage_probability=0,
             not coalesce((s->>'archived')::boolean,false))
      on conflict(hubspot_stage_id) do update set
        hubspot_pipeline_id=excluded.hubspot_pipeline_id,
        stage_name=excluded.stage_name,
        display_order=excluded.display_order,
        is_closed_won=excluded.is_closed_won,
        is_closed_lost=excluded.is_closed_lost,
        is_active=excluded.is_active,
        updated_at=now();

      insert into public.comp_hubspot_discovered_values(object_type,property_name,hubspot_value,display_label,context,is_active,first_seen_at,last_seen_at)
      values('deal','dealstage',stage_id,stage_name,jsonb_build_object('pipeline_id',pipeline_id,'pipeline_name',pipeline_name),true,now(),now())
      on conflict(object_type,property_name,hubspot_value,context) do update set
        display_label=excluded.display_label,is_active=true,last_seen_at=now();
      stage_count:=stage_count+1;
    end loop;
  end loop;

  return jsonb_build_object('pipelines',pipeline_count,'stages',stage_count,'synced_at',now());
end;
$$;
revoke all on function public.sync_hubspot_pipelines() from public,anon;
grant execute on function public.sync_hubspot_pipelines() to authenticated;

do $$
declare def text; newdef text; oidv oid;
begin
 select p.oid,pg_get_functiondef(p.oid) into oidv,def
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='sync_hubspot_deals' limit 1;
 newdef:=replace(def,
E'    select pipeline_id,deal_year,make_date(deal_year,1,1) as start_date,make_date(deal_year+1,1,1) as end_date\n    from (\n      select pipeline_id,deal_year\n      from (values (''20788895''),(''56062501'')) as pipelines(pipeline_id)\n      cross join generate_series(2025,extract(year from current_date)::integer) as years(deal_year)\n    ) combinations',
E'    select pipeline_id,deal_year,make_date(deal_year,1,1) as start_date,make_date(deal_year+1,1,1) as end_date\n    from (\n      select p.hubspot_pipeline_id as pipeline_id,years.deal_year\n      from public.hubspot_pipelines p\n      cross join generate_series(2025,extract(year from current_date)::integer) as years(deal_year)\n      where p.is_active\n    ) combinations');
 if newdef=def then raise exception 'Could not replace hardcoded deal pipeline loop'; end if;
 execute newdef;
end $$;