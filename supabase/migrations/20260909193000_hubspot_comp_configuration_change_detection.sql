create table if not exists public.comp_hubspot_config_snapshots (
  id uuid primary key default gen_random_uuid(),
  snapshot_type text not null check (snapshot_type in ('field','value','object')),
  object_type text not null,
  property_name text,
  hubspot_value text,
  display_label text,
  data_type text,
  context jsonb not null default '{}'::jsonb,
  source_fingerprint text not null,
  captured_at timestamptz not null default now(),
  is_current boolean not null default true
);
create unique index if not exists comp_hubspot_config_snapshots_current_uq
  on public.comp_hubspot_config_snapshots(snapshot_type,object_type,coalesce(property_name,''),coalesce(hubspot_value,''),md5(context::text)) where is_current;

create table if not exists public.comp_hubspot_config_changes (
  id uuid primary key default gen_random_uuid(),
  change_type text not null check (change_type in ('added','removed','renamed','type_changed','context_changed','reactivated','deactivated')),
  entity_type text not null check (entity_type in ('object','field','value')),
  object_type text not null,
  property_name text,
  hubspot_value text,
  old_state jsonb,
  new_state jsonb,
  severity text not null default 'informational' check (severity in ('informational','review_recommended','action_required','critical')),
  review_status text not null default 'open' check (review_status in ('open','acknowledged','resolved','ignored')),
  mapping_impact jsonb not null default '{}'::jsonb,
  detected_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid,
  resolution_action text,
  notes text,
  fingerprint text not null unique
);
create index if not exists comp_hubspot_config_changes_open_idx on public.comp_hubspot_config_changes(review_status,severity,detected_at desc);

alter table public.comp_hubspot_config_snapshots enable row level security;
alter table public.comp_hubspot_config_changes enable row level security;
revoke all on public.comp_hubspot_config_snapshots from public,anon,authenticated;
revoke all on public.comp_hubspot_config_changes from public,anon,authenticated;

create or replace function public.refresh_hubspot_comp_configuration_changes()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  now_ts timestamptz:=now();
  added_count integer:=0;
  removed_count integer:=0;
  changed_count integer:=0;
  r record;
  oldr record;
  fp text;
  impact jsonb;
  sev text;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to refresh HubSpot compensation configuration';
  end if;

  create temporary table if not exists _current_hs_config(
    snapshot_type text, object_type text, property_name text, hubspot_value text,
    display_label text, data_type text, context jsonb, source_fingerprint text
  ) on commit drop;
  truncate _current_hs_config;

  insert into _current_hs_config
  select 'object',o.object_type,null,null,o.display_name,null,
         jsonb_build_object('hubspot_object_type',o.hubspot_object_type,'supports_associations',o.supports_associations,'is_active',o.is_active),
         md5(concat_ws('|',o.object_type,o.display_name,o.hubspot_object_type,o.supports_associations::text,o.is_active::text))
  from public.comp_rule_object_catalog o;

  insert into _current_hs_config
  select 'field',f.object_type,f.property_name,null,f.display_name,f.data_type,
         jsonb_build_object('is_multi_value',f.is_multi_value,'is_active',f.is_active,'source_system',f.source_system),
         md5(concat_ws('|',f.object_type,f.property_name,f.display_name,f.data_type,f.is_multi_value::text,f.is_active::text,coalesce(f.source_system,'')))
  from public.comp_rule_field_catalog f
  where f.source_system like 'hubspot%';

  insert into _current_hs_config
  select 'value',v.object_type,v.property_name,v.hubspot_value,v.display_label,null,
         coalesce(v.context,'{}'::jsonb)||jsonb_build_object('is_active',v.is_active),
         md5(concat_ws('|',v.object_type,v.property_name,v.hubspot_value,v.display_label,coalesce(v.context,'{}'::jsonb)::text,v.is_active::text))
  from public.comp_hubspot_discovered_values v;

  if not exists(select 1 from public.comp_hubspot_config_snapshots where is_current) then
    insert into public.comp_hubspot_config_snapshots(snapshot_type,object_type,property_name,hubspot_value,display_label,data_type,context,source_fingerprint,captured_at,is_current)
    select snapshot_type,object_type,property_name,hubspot_value,display_label,data_type,context,source_fingerprint,now_ts,true from _current_hs_config;
    return jsonb_build_object('baseline_created',true,'snapshot_count',(select count(*) from _current_hs_config),'added',0,'removed',0,'changed',0);
  end if;

  for r in select * from _current_hs_config loop
    select * into oldr from public.comp_hubspot_config_snapshots s
    where s.is_current and s.snapshot_type=r.snapshot_type and s.object_type=r.object_type
      and coalesce(s.property_name,'')=coalesce(r.property_name,'')
      and coalesce(s.hubspot_value,'')=coalesce(r.hubspot_value,'')
      and md5(coalesce(s.context,'{}'::jsonb)::text)=md5(coalesce(r.context,'{}'::jsonb)::text)
    limit 1;

    if oldr.id is null then
      select * into oldr from public.comp_hubspot_config_snapshots s
      where s.is_current and s.snapshot_type=r.snapshot_type and s.object_type=r.object_type
        and coalesce(s.property_name,'')=coalesce(r.property_name,'')
        and coalesce(s.hubspot_value,'')=coalesce(r.hubspot_value,'')
      limit 1;
    end if;

    if oldr.id is null then
      impact:=public.analyze_hubspot_comp_mapping_change(jsonb_build_object('object_type',r.object_type,'property_name',r.property_name,'hubspot_value',r.hubspot_value,'change','added'));
      sev:=case when coalesce((impact->>'affected_active_rules')::int,0)>0 then 'action_required' else 'informational' end;
      fp:=md5(concat_ws('|','added',r.snapshot_type,r.object_type,coalesce(r.property_name,''),coalesce(r.hubspot_value,''),r.source_fingerprint));
      insert into public.comp_hubspot_config_changes(change_type,entity_type,object_type,property_name,hubspot_value,new_state,severity,mapping_impact,fingerprint)
      values('added',r.snapshot_type,r.object_type,r.property_name,r.hubspot_value,to_jsonb(r),sev,coalesce(impact,'{}'::jsonb),fp)
      on conflict(fingerprint) do nothing;
      added_count:=added_count+1;
    elsif oldr.source_fingerprint<>r.source_fingerprint then
      impact:=public.analyze_hubspot_comp_mapping_change(jsonb_build_object('object_type',r.object_type,'property_name',r.property_name,'hubspot_value',r.hubspot_value,'change','modified'));
      sev:=case when coalesce((impact->>'paid_earnings')::int,0)>0 then 'critical' when coalesce((impact->>'affected_active_rules')::int,0)>0 then 'action_required' else 'review_recommended' end;
      fp:=md5(concat_ws('|','changed',r.snapshot_type,r.object_type,coalesce(r.property_name,''),coalesce(r.hubspot_value,''),oldr.source_fingerprint,r.source_fingerprint));
      insert into public.comp_hubspot_config_changes(change_type,entity_type,object_type,property_name,hubspot_value,old_state,new_state,severity,mapping_impact,fingerprint)
      values(case when coalesce(oldr.display_label,'')<>coalesce(r.display_label,'') then 'renamed' when coalesce(oldr.data_type,'')<>coalesce(r.data_type,'') then 'type_changed' else 'context_changed' end,
             r.snapshot_type,r.object_type,r.property_name,r.hubspot_value,to_jsonb(oldr),to_jsonb(r),sev,coalesce(impact,'{}'::jsonb),fp)
      on conflict(fingerprint) do nothing;
      changed_count:=changed_count+1;
    end if;
  end loop;

  for oldr in
    select s.* from public.comp_hubspot_config_snapshots s
    where s.is_current and not exists(
      select 1 from _current_hs_config c
      where c.snapshot_type=s.snapshot_type and c.object_type=s.object_type
        and coalesce(c.property_name,'')=coalesce(s.property_name,'')
        and coalesce(c.hubspot_value,'')=coalesce(s.hubspot_value,'')
    )
  loop
    impact:=public.analyze_hubspot_comp_mapping_change(jsonb_build_object('object_type',oldr.object_type,'property_name',oldr.property_name,'hubspot_value',oldr.hubspot_value,'change','removed'));
    sev:=case when coalesce((impact->>'paid_earnings')::int,0)>0 then 'critical' when coalesce((impact->>'affected_active_rules')::int,0)>0 then 'action_required' else 'review_recommended' end;
    fp:=md5(concat_ws('|','removed',oldr.snapshot_type,oldr.object_type,coalesce(oldr.property_name,''),coalesce(oldr.hubspot_value,''),oldr.source_fingerprint));
    insert into public.comp_hubspot_config_changes(change_type,entity_type,object_type,property_name,hubspot_value,old_state,severity,mapping_impact,fingerprint)
    values('removed',oldr.snapshot_type,oldr.object_type,oldr.property_name,oldr.hubspot_value,to_jsonb(oldr),sev,coalesce(impact,'{}'::jsonb),fp)
    on conflict(fingerprint) do nothing;
    removed_count:=removed_count+1;
  end loop;

  update public.comp_hubspot_config_snapshots set is_current=false where is_current;
  insert into public.comp_hubspot_config_snapshots(snapshot_type,object_type,property_name,hubspot_value,display_label,data_type,context,source_fingerprint,captured_at,is_current)
  select snapshot_type,object_type,property_name,hubspot_value,display_label,data_type,context,source_fingerprint,now_ts,true from _current_hs_config;

  return jsonb_build_object('baseline_created',false,'snapshot_count',(select count(*) from _current_hs_config),'added',added_count,'removed',removed_count,'changed',changed_count,
    'open_changes',(select count(*) from public.comp_hubspot_config_changes where review_status='open'));
end;
$$;
revoke all on function public.refresh_hubspot_comp_configuration_changes() from public,anon;
grant execute on function public.refresh_hubspot_comp_configuration_changes() to authenticated;

create or replace function public.get_hubspot_comp_configuration_changes()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare access jsonb; begin
 access:=public.get_current_user_access();
 if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then raise exception 'Not authorized'; end if;
 return jsonb_build_object(
  'summary',jsonb_build_object(
   'open',(select count(*) from public.comp_hubspot_config_changes where review_status='open'),
   'critical',(select count(*) from public.comp_hubspot_config_changes where review_status='open' and severity='critical'),
   'action_required',(select count(*) from public.comp_hubspot_config_changes where review_status='open' and severity='action_required'),
   'review_recommended',(select count(*) from public.comp_hubspot_config_changes where review_status='open' and severity='review_recommended')
  ),
  'changes',coalesce((select jsonb_agg(to_jsonb(c) order by case c.severity when 'critical' then 1 when 'action_required' then 2 when 'review_recommended' then 3 else 4 end,c.detected_at desc) from public.comp_hubspot_config_changes c where c.review_status='open'),'[]'::jsonb)
 );
end; $$;
revoke all on function public.get_hubspot_comp_configuration_changes() from public,anon;
grant execute on function public.get_hubspot_comp_configuration_changes() to authenticated;

create or replace function public.resolve_hubspot_comp_configuration_change(target_change_id uuid, resolution text, note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare access jsonb; c public.comp_hubspot_config_changes%rowtype; begin
 access:=public.get_current_user_access();
 if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then raise exception 'Not authorized'; end if;
 if resolution not in ('acknowledge','update_mapping','create_successor_mapping','future_only','grandfather_existing','send_to_review','ignore') then raise exception 'Unsupported resolution'; end if;
 select * into c from public.comp_hubspot_config_changes where id=target_change_id for update;
 if c.id is null then raise exception 'Configuration change not found'; end if;
 update public.comp_hubspot_config_changes set review_status=case when resolution='acknowledge' then 'acknowledged' when resolution='ignore' then 'ignored' else 'resolved' end,
   resolution_action=resolution,notes=note,reviewed_at=now(),reviewed_by=(select auth.uid()) where id=target_change_id;
 return jsonb_build_object('id',target_change_id,'status',case when resolution='acknowledge' then 'acknowledged' when resolution='ignore' then 'ignored' else 'resolved' end,'resolution',resolution);
end; $$;
revoke all on function public.resolve_hubspot_comp_configuration_change(uuid,text,text) from public,anon;
grant execute on function public.resolve_hubspot_comp_configuration_change(uuid,text,text) to authenticated;
