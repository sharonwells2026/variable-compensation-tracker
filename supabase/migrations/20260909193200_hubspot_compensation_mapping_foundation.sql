-- Dynamic, versioned HubSpot compensation mapping foundation.

create table if not exists public.comp_hubspot_discovered_values (
  id uuid primary key default gen_random_uuid(),
  object_type text not null,
  property_name text not null,
  hubspot_value text not null,
  display_label text not null,
  context jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique(object_type, property_name, hubspot_value, context)
);

create table if not exists public.comp_hubspot_mapping_versions (
  id uuid primary key default gen_random_uuid(),
  version_number integer not null unique,
  status text not null default 'draft' check(status in ('draft','active','retired')),
  effective_from timestamptz,
  effective_to timestamptz,
  notes text,
  created_by uuid,
  activated_by uuid,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  check(effective_to is null or effective_from is null or effective_to > effective_from)
);

create table if not exists public.comp_hubspot_object_mappings (
  id uuid primary key default gen_random_uuid(),
  mapping_version_id uuid not null references public.comp_hubspot_mapping_versions(id) on delete cascade,
  object_type text not null,
  hubspot_object_type text,
  is_eligible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(mapping_version_id, object_type)
);

create table if not exists public.comp_hubspot_field_mappings (
  id uuid primary key default gen_random_uuid(),
  mapping_version_id uuid not null references public.comp_hubspot_mapping_versions(id) on delete cascade,
  object_type text not null,
  property_name text not null,
  is_eligible boolean not null default false,
  value_policy text not null default 'all' check(value_policy in ('all','selected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(mapping_version_id, object_type, property_name)
);

create table if not exists public.comp_hubspot_value_mappings (
  id uuid primary key default gen_random_uuid(),
  field_mapping_id uuid not null references public.comp_hubspot_field_mappings(id) on delete cascade,
  hubspot_value text not null,
  context jsonb not null default '{}'::jsonb,
  is_eligible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(field_mapping_id, hubspot_value, context)
);

create table if not exists public.comp_hubspot_mapping_change_log (
  id uuid primary key default gen_random_uuid(),
  mapping_version_id uuid not null references public.comp_hubspot_mapping_versions(id) on delete cascade,
  change_request jsonb not null,
  impact_snapshot jsonb not null,
  resolution_action text,
  changed_by uuid,
  changed_at timestamptz not null default now()
);

alter table public.comp_hubspot_discovered_values enable row level security;
alter table public.comp_hubspot_mapping_versions enable row level security;
alter table public.comp_hubspot_object_mappings enable row level security;
alter table public.comp_hubspot_field_mappings enable row level security;
alter table public.comp_hubspot_value_mappings enable row level security;
alter table public.comp_hubspot_mapping_change_log enable row level security;
revoke all on public.comp_hubspot_discovered_values, public.comp_hubspot_mapping_versions,
  public.comp_hubspot_object_mappings, public.comp_hubspot_field_mappings,
  public.comp_hubspot_value_mappings, public.comp_hubspot_mapping_change_log
  from public,anon,authenticated;

insert into public.comp_hubspot_discovered_values(object_type,property_name,hubspot_value,display_label,context,last_seen_at)
select f.object_type,f.property_name,opt->>'value',coalesce(opt->>'label',opt->>'value'),'{}'::jsonb,now()
from public.comp_rule_field_catalog f
cross join lateral jsonb_array_elements(coalesce(f.options,'[]'::jsonb)) opt
where nullif(opt->>'value','') is not null
on conflict(object_type,property_name,hubspot_value,context)
do update set display_label=excluded.display_label,is_active=true,last_seen_at=now();

insert into public.comp_hubspot_discovered_values(object_type,property_name,hubspot_value,display_label,context,last_seen_at)
select 'deal','dealstage',s.hubspot_stage_id,s.stage_name,
       jsonb_build_object('pipeline_id',s.hubspot_pipeline_id,'pipeline_name',p.pipeline_name),now()
from public.hubspot_pipeline_stages s
left join public.hubspot_pipelines p on p.hubspot_pipeline_id=s.hubspot_pipeline_id
on conflict(object_type,property_name,hubspot_value,context)
do update set display_label=excluded.display_label,is_active=true,last_seen_at=now();

insert into public.comp_hubspot_mapping_versions(version_number,status,created_by)
select 1,'draft',auth.uid()
where not exists(select 1 from public.comp_hubspot_mapping_versions);

create or replace function public.get_hubspot_comp_mapping_admin_data(target_mapping_version_id uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  access jsonb;
  mv public.comp_hubspot_mapping_versions%rowtype;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to view HubSpot compensation mapping';
  end if;
  if target_mapping_version_id is null then
    select * into mv from public.comp_hubspot_mapping_versions
    order by case status when 'draft' then 0 when 'active' then 1 else 2 end, version_number desc limit 1;
  else
    select * into mv from public.comp_hubspot_mapping_versions where id=target_mapping_version_id;
  end if;
  if mv.id is null then raise exception 'Mapping version not found'; end if;
  return jsonb_build_object(
    'mapping_version',jsonb_build_object('id',mv.id,'version_number',mv.version_number,'status',mv.status,'effective_from',mv.effective_from,'effective_to',mv.effective_to,'notes',mv.notes),
    'objects',coalesce((select jsonb_agg(jsonb_build_object('object_type',o.object_type,'display_name',o.display_name,'hubspot_object_type',o.hubspot_object_type,'description',o.description,'discovered_active',o.is_active,'eligible',coalesce(m.is_eligible,false)) order by o.sort_order,o.display_name) from public.comp_rule_object_catalog o left join public.comp_hubspot_object_mappings m on m.mapping_version_id=mv.id and m.object_type=o.object_type),'[]'::jsonb),
    'fields',coalesce((select jsonb_agg(jsonb_build_object('object_type',f.object_type,'property_name',f.property_name,'display_name',f.display_name,'data_type',f.data_type,'description',f.description,'is_multi_value',f.is_multi_value,'source_system',f.source_system,'discovered_active',f.is_active,'eligible',coalesce(m.is_eligible,false),'value_policy',coalesce(m.value_policy,'all'),'selected_value_count',(select count(*) from public.comp_hubspot_value_mappings vm where vm.field_mapping_id=m.id and vm.is_eligible)) order by f.object_type,f.display_name) from public.comp_rule_field_catalog f left join public.comp_hubspot_field_mappings m on m.mapping_version_id=mv.id and m.object_type=f.object_type and m.property_name=f.property_name where f.source_system like 'hubspot%'),'[]'::jsonb),
    'values',coalesce((select jsonb_agg(jsonb_build_object('object_type',v.object_type,'property_name',v.property_name,'hubspot_value',v.hubspot_value,'display_label',v.display_label,'context',v.context,'discovered_active',v.is_active,'eligible',coalesce(vm.is_eligible,false)) order by v.object_type,v.property_name,v.context->>'pipeline_name',v.display_label) from public.comp_hubspot_discovered_values v left join public.comp_hubspot_field_mappings fm on fm.mapping_version_id=mv.id and fm.object_type=v.object_type and fm.property_name=v.property_name left join public.comp_hubspot_value_mappings vm on vm.field_mapping_id=fm.id and vm.hubspot_value=v.hubspot_value and vm.context=v.context),'[]'::jsonb)
  );
end;
$$;
revoke all on function public.get_hubspot_comp_mapping_admin_data(uuid) from public,anon;
grant execute on function public.get_hubspot_comp_mapping_admin_data(uuid) to authenticated;

create or replace function public.analyze_hubspot_comp_mapping_change(change_request jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  access jsonb;
  target_object text:=nullif(change_request->>'object_type','');
  target_property text:=nullif(change_request->>'property_name','');
  target_value text:=nullif(change_request->>'hubspot_value','');
  affected_rules integer:=0; affected_active_rules integer:=0; affected_draft_rules integer:=0;
  affected_components integer:=0; affected_earnings integer:=0; paid_earnings integer:=0; approved_unpaid integer:=0;
  rule_ids uuid[]; component_ids uuid[]; risk text:='low'; options jsonb:='[]'::jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to analyze HubSpot compensation mapping changes';
  end if;
  if target_object is null then raise exception 'object_type is required'; end if;
  select coalesce(array_agg(distinct s.id),'{}'::uuid[]),count(distinct s.id),count(distinct s.id) filter(where s.is_active),count(distinct s.id) filter(where not s.is_active)
  into rule_ids,affected_rules,affected_active_rules,affected_draft_rules
  from public.comp_rule_sets s join public.comp_rule_predicates p on p.rule_set_id=s.id
  where p.object_type=target_object and (target_property is null or p.property_name=target_property)
    and (target_value is null or p.comparison_value=to_jsonb(target_value) or p.comparison_value @> jsonb_build_array(target_value));
  select coalesce(array_agg(distinct s.plan_component_id),'{}'::uuid[]),count(distinct s.plan_component_id)
  into component_ids,affected_components from public.comp_rule_sets s where s.id=any(rule_ids);
  if cardinality(component_ids)>0 then
    select count(*) filter(where e.is_current),count(*) filter(where e.is_current and coalesce(e.paid_amount,0)>0),count(*) filter(where e.is_current and coalesce(e.approved_amount,0)>0 and coalesce(e.paid_amount,0)=0)
    into affected_earnings,paid_earnings,approved_unpaid from public.comp_earnings e where e.plan_component_id=any(component_ids);
  end if;
  if paid_earnings>0 then risk:='critical'; elsif affected_active_rules>0 or approved_unpaid>0 then risk:='high'; elsif affected_rules>0 or affected_earnings>0 then risk:='medium'; end if;
  options:=jsonb_build_array('cancel_change','apply_future_only');
  if affected_rules>0 then options:=options||jsonb_build_array('create_successor_rule_versions'); end if;
  if affected_earnings>0 then options:=options||jsonb_build_array('grandfather_existing_earnings','dry_run_recalculation'); end if;
  if approved_unpaid>0 then options:=options||jsonb_build_array('send_unpaid_to_review'); end if;
  if paid_earnings>0 then options:=options||jsonb_build_array('preserve_paid_and_use_correction_workflow'); end if;
  return jsonb_build_object('risk',risk,'target',jsonb_build_object('object_type',target_object,'property_name',target_property,'hubspot_value',target_value,'context',coalesce(change_request->'context','{}'::jsonb)),'affected_rule_sets',affected_rules,'affected_active_rule_sets',affected_active_rules,'affected_draft_rule_sets',affected_draft_rules,'affected_plan_components',affected_components,'affected_current_earnings',affected_earnings,'approved_unpaid_earnings',approved_unpaid,'paid_earnings',paid_earnings,'requires_explicit_resolution',(affected_rules>0 or affected_earnings>0),'resolution_options',options);
end;
$$;
revoke all on function public.analyze_hubspot_comp_mapping_change(jsonb) from public,anon;
grant execute on function public.analyze_hubspot_comp_mapping_change(jsonb) to authenticated;

create or replace function public.apply_hubspot_comp_mapping_change(change_request jsonb)
returns jsonb
language plpgsql
volatile security definer
set search_path=''
as $$
declare
  access jsonb; mv public.comp_hubspot_mapping_versions%rowtype; impact jsonb;
  change_level text:=nullif(change_request->>'level',''); target_object text:=nullif(change_request->>'object_type',''); target_property text:=nullif(change_request->>'property_name',''); target_value text:=nullif(change_request->>'hubspot_value','');
  target_context jsonb:=coalesce(change_request->'context','{}'::jsonb); target_eligible boolean:=coalesce((change_request->>'is_eligible')::boolean,false); value_policy text:=coalesce(nullif(change_request->>'value_policy',''),'all'); resolution text:=nullif(change_request->>'resolution_action',''); fm_id uuid;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then raise exception 'Not authorized to change HubSpot compensation mapping'; end if;
  select * into mv from public.comp_hubspot_mapping_versions where id=(change_request->>'mapping_version_id')::uuid for update;
  if mv.id is null then raise exception 'Mapping version not found'; end if;
  if mv.status<>'draft' then raise exception 'Only draft mapping versions can be edited'; end if;
  if change_level not in ('object','field','value') then raise exception 'level must be object, field, or value'; end if;
  if target_object is null then raise exception 'object_type is required'; end if;
  if change_level in ('field','value') and target_property is null then raise exception 'property_name is required'; end if;
  if change_level='value' and target_value is null then raise exception 'hubspot_value is required'; end if;
  if value_policy not in ('all','selected') then raise exception 'value_policy must be all or selected'; end if;
  impact:=public.analyze_hubspot_comp_mapping_change(change_request);
  if coalesce((impact->>'requires_explicit_resolution')::boolean,false) and resolution is null then return jsonb_build_object('applied',false,'requires_resolution',true,'impact',impact); end if;
  if resolution is not null and not (coalesce(impact->'resolution_options','[]'::jsonb) ? resolution) then raise exception 'Invalid resolution_action for this change'; end if;
  if change_level='object' then
    insert into public.comp_hubspot_object_mappings(mapping_version_id,object_type,hubspot_object_type,is_eligible)
    select mv.id,target_object,o.hubspot_object_type,target_eligible from public.comp_rule_object_catalog o where o.object_type=target_object
    on conflict(mapping_version_id,object_type) do update set is_eligible=excluded.is_eligible,hubspot_object_type=excluded.hubspot_object_type,updated_at=now();
  elsif change_level='field' then
    insert into public.comp_hubspot_field_mappings(mapping_version_id,object_type,property_name,is_eligible,value_policy)
    values(mv.id,target_object,target_property,target_eligible,value_policy)
    on conflict(mapping_version_id,object_type,property_name) do update set is_eligible=excluded.is_eligible,value_policy=excluded.value_policy,updated_at=now();
  else
    select id into fm_id from public.comp_hubspot_field_mappings where mapping_version_id=mv.id and object_type=target_object and property_name=target_property;
    if fm_id is null then insert into public.comp_hubspot_field_mappings(mapping_version_id,object_type,property_name,is_eligible,value_policy) values(mv.id,target_object,target_property,true,'selected') returning id into fm_id; else update public.comp_hubspot_field_mappings set value_policy='selected',updated_at=now() where id=fm_id; end if;
    insert into public.comp_hubspot_value_mappings(field_mapping_id,hubspot_value,context,is_eligible)
    values(fm_id,target_value,target_context,target_eligible)
    on conflict(field_mapping_id,hubspot_value,context) do update set is_eligible=excluded.is_eligible,updated_at=now();
  end if;
  insert into public.comp_hubspot_mapping_change_log(mapping_version_id,change_request,impact_snapshot,resolution_action,changed_by) values(mv.id,change_request,impact,resolution,auth.uid());
  return jsonb_build_object('applied',true,'requires_resolution',false,'impact',impact,'mapping_version_id',mv.id);
end;
$$;
revoke all on function public.apply_hubspot_comp_mapping_change(jsonb) from public,anon;
grant execute on function public.apply_hubspot_comp_mapping_change(jsonb) to authenticated;
