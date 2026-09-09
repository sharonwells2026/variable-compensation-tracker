create or replace function public.refresh_hubspot_comp_configuration_changes()
returns jsonb
language plpgsql
security definer
set search_path to ''
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
  if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to refresh HubSpot compensation configuration'; end if;

  create temporary table if not exists _current_hs_config(
    snapshot_type text, object_type text, property_name text, hubspot_value text,
    display_label text, data_type text, context jsonb, source_fingerprint text
  ) on commit drop;
  truncate _current_hs_config;

  insert into _current_hs_config
  select 'object',o.internal_object_key,null,null,
         coalesce(nullif(initcap(replace(o.internal_object_key,'_',' ')),''),o.hubspot_object_type),null,
         jsonb_build_object('hubspot_object_type',o.hubspot_object_type,'object_category',o.object_category,'read_access',o.read_access,'write_access',o.write_access,'is_active',o.is_active),
         md5(concat_ws('|',o.internal_object_key,o.hubspot_object_type,o.object_category,o.read_access,o.write_access,o.is_active::text,coalesce(o.description,'')))
  from public.hubspot_object_definitions o;

  insert into _current_hs_config
  select 'field',f.internal_object_key,f.property_name,null,f.display_label,f.property_type,
         jsonb_build_object('hubspot_object_type',f.hubspot_object_type,'field_type',f.field_type,'group_name',f.group_name,'hidden',f.is_hidden,'archived',f.is_archived,'calculated',f.is_calculated,'external_options',f.external_options,'is_active',f.is_active),
         md5(concat_ws('|',f.internal_object_key,f.property_name,f.display_label,f.property_type,coalesce(f.field_type,''),coalesce(f.group_name,''),f.is_hidden::text,f.is_archived::text,f.is_calculated::text,f.external_options::text,f.is_active::text,coalesce(f.description,'')))
  from public.hubspot_property_definitions f;

  insert into _current_hs_config
  select 'value',v.object_type,v.property_name,v.hubspot_value,v.display_label,null,
         coalesce(v.context,'{}'::jsonb)||jsonb_build_object('is_active',v.is_active),
         md5(concat_ws('|',v.object_type,v.property_name,v.hubspot_value,v.display_label,coalesce(v.context,'{}'::jsonb)::text,v.is_active::text))
  from public.comp_hubspot_discovered_values v;

  if not exists(select 1 from public.comp_hubspot_config_snapshots where is_current) then
    insert into public.comp_hubspot_config_snapshots(snapshot_type,object_type,property_name,hubspot_value,display_label,data_type,context,source_fingerprint,captured_at,is_current)
    select snapshot_type,object_type,property_name,hubspot_value,display_label,data_type,context,source_fingerprint,now_ts,true from _current_hs_config;
    return jsonb_build_object('baseline_created',true,'snapshot_count',(select count(*) from _current_hs_config),'added',0,'removed',0,'changed',0,'open_changes',(select count(*) from public.comp_hubspot_config_changes where review_status='open'));
  end if;

  for r in select * from _current_hs_config loop
    select * into oldr from public.comp_hubspot_config_snapshots s
    where s.is_current and s.snapshot_type=r.snapshot_type and s.object_type=r.object_type
      and coalesce(s.property_name,'')=coalesce(r.property_name,'') and coalesce(s.hubspot_value,'')=coalesce(r.hubspot_value,'')
      and coalesce(s.context,'{}'::jsonb)=coalesce(r.context,'{}'::jsonb)
    limit 1;
    if oldr.id is null then
      select * into oldr from public.comp_hubspot_config_snapshots s
      where s.is_current and s.snapshot_type=r.snapshot_type and s.object_type=r.object_type
        and coalesce(s.property_name,'')=coalesce(r.property_name,'') and coalesce(s.hubspot_value,'')=coalesce(r.hubspot_value,'') limit 1;
    end if;
    if oldr.id is null then
      impact:=public.analyze_hubspot_comp_mapping_change(jsonb_build_object('object_type',r.object_type,'property_name',r.property_name,'hubspot_value',r.hubspot_value,'change','added'));
      sev:=case when coalesce((impact->>'affected_active_rule_sets')::int,0)>0 then 'action_required' else 'informational' end;
      fp:=md5(concat_ws('|','added',r.snapshot_type,r.object_type,coalesce(r.property_name,''),coalesce(r.hubspot_value,''),r.source_fingerprint));
      insert into public.comp_hubspot_config_changes(change_type,entity_type,object_type,property_name,hubspot_value,new_state,severity,mapping_impact,fingerprint)
      values('added',r.snapshot_type,r.object_type,r.property_name,r.hubspot_value,to_jsonb(r),sev,coalesce(impact,'{}'::jsonb),fp) on conflict(fingerprint) do nothing;
      added_count:=added_count+1;
    elsif oldr.source_fingerprint<>r.source_fingerprint then
      impact:=public.analyze_hubspot_comp_mapping_change(jsonb_build_object('object_type',r.object_type,'property_name',r.property_name,'hubspot_value',r.hubspot_value,'change','modified'));
      sev:=case when coalesce((impact->>'paid_earnings')::int,0)>0 then 'critical' when coalesce((impact->>'affected_active_rule_sets')::int,0)>0 then 'action_required' else 'review_recommended' end;
      fp:=md5(concat_ws('|','changed',r.snapshot_type,r.object_type,coalesce(r.property_name,''),coalesce(r.hubspot_value,''),oldr.source_fingerprint,r.source_fingerprint));
      insert into public.comp_hubspot_config_changes(change_type,entity_type,object_type,property_name,hubspot_value,old_state,new_state,severity,mapping_impact,fingerprint)
      values(case when coalesce(oldr.display_label,'')<>coalesce(r.display_label,'') then 'renamed' when coalesce(oldr.data_type,'')<>coalesce(r.data_type,'') then 'type_changed' else 'context_changed' end,
             r.snapshot_type,r.object_type,r.property_name,r.hubspot_value,to_jsonb(oldr),to_jsonb(r),sev,coalesce(impact,'{}'::jsonb),fp) on conflict(fingerprint) do nothing;
      changed_count:=changed_count+1;
    end if;
  end loop;

  for oldr in select s.* from public.comp_hubspot_config_snapshots s where s.is_current and not exists(
      select 1 from _current_hs_config c where c.snapshot_type=s.snapshot_type and c.object_type=s.object_type
        and coalesce(c.property_name,'')=coalesce(s.property_name,'') and coalesce(c.hubspot_value,'')=coalesce(s.hubspot_value,''))
  loop
    impact:=public.analyze_hubspot_comp_mapping_change(jsonb_build_object('object_type',oldr.object_type,'property_name',oldr.property_name,'hubspot_value',oldr.hubspot_value,'change','removed'));
    sev:=case when coalesce((impact->>'paid_earnings')::int,0)>0 then 'critical' when coalesce((impact->>'affected_active_rule_sets')::int,0)>0 then 'action_required' else 'review_recommended' end;
    fp:=md5(concat_ws('|','removed',oldr.snapshot_type,oldr.object_type,coalesce(oldr.property_name,''),coalesce(oldr.hubspot_value,''),oldr.source_fingerprint));
    insert into public.comp_hubspot_config_changes(change_type,entity_type,object_type,property_name,hubspot_value,old_state,severity,mapping_impact,fingerprint)
    values('removed',oldr.snapshot_type,oldr.object_type,oldr.property_name,oldr.hubspot_value,to_jsonb(oldr),sev,coalesce(impact,'{}'::jsonb),fp) on conflict(fingerprint) do nothing;
    removed_count:=removed_count+1;
  end loop;

  update public.comp_hubspot_config_snapshots set is_current=false where is_current;
  insert into public.comp_hubspot_config_snapshots(snapshot_type,object_type,property_name,hubspot_value,display_label,data_type,context,source_fingerprint,captured_at,is_current)
  select snapshot_type,object_type,property_name,hubspot_value,display_label,data_type,context,source_fingerprint,now_ts,true from _current_hs_config;

  return jsonb_build_object('baseline_created',false,'snapshot_count',(select count(*) from _current_hs_config),'added',added_count,'removed',removed_count,'changed',changed_count,'open_changes',(select count(*) from public.comp_hubspot_config_changes where review_status='open'));
end;$$;
revoke all on function public.refresh_hubspot_comp_configuration_changes() from public, anon;
grant execute on function public.refresh_hubspot_comp_configuration_changes() to authenticated;