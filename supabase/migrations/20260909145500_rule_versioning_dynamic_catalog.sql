-- Rule-set lifecycle and dynamic HubSpot deal-property discovery.
-- Existing rule versions are immutable when a new version is created.

create or replace function public.refresh_comp_rule_deal_field_catalog()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  discovered integer := 0;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to refresh compensation rule fields';
  end if;

  with property_values as (
    select e.key as property_name, e.value as property_value
    from public.hubspot_deals d
    cross join lateral jsonb_each_text(coalesce(d.raw_hubspot_data->'properties','{}'::jsonb)) e
    where e.key is not null and btrim(e.key)<>''
  ), inferred as (
    select property_name,
      count(*) filter (where property_value is not null and btrim(property_value)<>'') as populated_count,
      case
        when bool_and(property_value is null or btrim(property_value)='' or property_value ~ '^-?[0-9]+([.][0-9]+)?$') then 'number'
        when bool_and(property_value is null or btrim(property_value)='' or lower(property_value) in ('true','false')) then 'boolean'
        when property_name ilike '%date%' or property_name ilike '%time%' then 'datetime'
        else 'string'
      end as data_type
    from property_values
    group by property_name
  ), inserted as (
    insert into public.comp_rule_field_catalog(object_type,property_name,display_name,data_type,description,is_multi_value,is_active,source_system)
    select 'deal',i.property_name,
      initcap(replace(replace(i.property_name,'__',' '),'_',' ')),
      i.data_type,
      'Discovered from the synchronized HubSpot deal property snapshot. Populated on '||i.populated_count||' local deal records.',
      false,true,'hubspot_snapshot'
    from inferred i
    on conflict (object_type,property_name) do update set
      is_active=true,
      updated_at=now(),
      description=case
        when public.comp_rule_field_catalog.source_system='hubspot_snapshot' then excluded.description
        else public.comp_rule_field_catalog.description
      end
    returning id
  )
  select count(*) into discovered from inserted;

  return jsonb_build_object(
    'catalog_count',(select count(*) from public.comp_rule_field_catalog where object_type='deal' and is_active),
    'discovered_or_refreshed',discovered,
    'source','local synchronized HubSpot deal snapshot'
  );
end;
$$;

create or replace function public.create_comp_rule_set_version(target_rule_set_id uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  source_set public.comp_rule_sets%rowtype;
  new_id uuid;
  new_version integer;
  p record;
  n record;
  new_predicate_id uuid;
  new_node_id uuid;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to version compensation plan rules';
  end if;

  select * into source_set from public.comp_rule_sets where id=target_rule_set_id for update;
  if source_set.id is null then raise exception 'Rule set not found'; end if;

  select coalesce(max(version),0)+1 into new_version
  from public.comp_rule_sets
  where plan_component_id=source_set.plan_component_id and name=source_set.name;

  insert into public.comp_rule_sets(plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,outcome_configuration,created_by,updated_by)
  values(source_set.plan_component_id,source_set.name,source_set.purpose,source_set.description,source_set.evaluation_scope,new_version,false,source_set.stop_on_match,source_set.outcome_configuration,(select auth.uid()),(select auth.uid()))
  returning id into new_id;

  create temporary table if not exists _version_pred_map(old_id uuid primary key,new_id uuid) on commit drop;
  create temporary table if not exists _version_node_map(old_id uuid primary key,new_id uuid) on commit drop;
  truncate _version_pred_map;
  truncate _version_node_map;

  for p in select * from public.comp_rule_predicates where rule_set_id=source_set.id order by created_at,id loop
    insert into public.comp_rule_predicates(rule_set_id,rule_key,display_name,object_type,association_path,association_quantifier,aggregate_function,aggregate_window,property_name,operator_key,comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes)
    values(new_id,p.rule_key,p.display_name,p.object_type,p.association_path,p.association_quantifier,p.aggregate_function,p.aggregate_window,p.property_name,p.operator_key,p.comparison_value,p.comparison_value_type,p.case_sensitive,p.include_null_as_match,p.notes)
    returning id into new_predicate_id;
    insert into _version_pred_map values(p.id,new_predicate_id);
  end loop;

  -- Parent nodes are emitted before descendants by recursive depth.
  for n in
    with recursive tree as (
      select x.*,0 as depth from public.comp_rule_expression_nodes x where x.rule_set_id=source_set.id and x.parent_node_id is null
      union all
      select c.*,t.depth+1 from public.comp_rule_expression_nodes c join tree t on c.parent_node_id=t.id
    ) select * from tree order by depth,sort_order,created_at
  loop
    insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
    values(
      new_id,
      (select m.new_id from _version_node_map m where m.old_id=n.parent_node_id),
      n.node_type,
      (select m.new_id from _version_pred_map m where m.old_id=n.predicate_id),
      n.logical_operator,n.negate,n.sort_order,n.label
    ) returning id into new_node_id;
    insert into _version_node_map values(n.id,new_node_id);
  end loop;

  return new_id;
end;
$$;

create or replace function public.set_comp_rule_set_active(target_rule_set_id uuid,target_active boolean)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  target public.comp_rule_sets%rowtype;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to activate compensation plan rules';
  end if;
  select * into target from public.comp_rule_sets where id=target_rule_set_id for update;
  if target.id is null then raise exception 'Rule set not found'; end if;
  if target_active then
    update public.comp_rule_sets set is_active=false,updated_at=now(),updated_by=(select auth.uid())
    where plan_component_id=target.plan_component_id and name=target.name and id<>target.id;
  end if;
  update public.comp_rule_sets set is_active=target_active,updated_at=now(),updated_by=(select auth.uid()) where id=target.id;
end;
$$;

revoke all on function public.refresh_comp_rule_deal_field_catalog() from public,anon;
revoke all on function public.create_comp_rule_set_version(uuid) from public,anon;
revoke all on function public.set_comp_rule_set_active(uuid,boolean) from public,anon;
grant execute on function public.refresh_comp_rule_deal_field_catalog() to authenticated;
grant execute on function public.create_comp_rule_set_version(uuid) to authenticated;
grant execute on function public.set_comp_rule_set_active(uuid,boolean) to authenticated;
