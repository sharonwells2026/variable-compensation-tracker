-- Keep rule validation, preview freshness, and plan approval aligned with the mapped-object contract.

alter function public.validate_comp_rule_set_for_activation(uuid)
  rename to validate_comp_rule_set_for_activation_pre_mapped_object_contract;

revoke all on function public.validate_comp_rule_set_for_activation_pre_mapped_object_contract(uuid) from public,anon,authenticated;

create or replace function public.validate_comp_rule_set_for_activation(target_rule_set_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  base jsonb;
  issues jsonb;
  active_mapping_id uuid;
  invalid_mapped_field_count integer:=0;
begin
  base:=public.validate_comp_rule_set_for_activation_pre_mapped_object_contract(target_rule_set_id);
  active_mapping_id:=nullif(base->>'active_mapping_id','')::uuid;

  if active_mapping_id is not null then
    select count(*) into invalid_mapped_field_count
    from public.comp_rule_predicates p
    left join public.comp_rule_field_catalog f
      on f.object_type=p.object_type
     and f.property_name=p.property_name
     and f.is_active=true
    left join public.comp_hubspot_object_mappings om
      on om.mapping_version_id=active_mapping_id
     and om.object_type=p.object_type
     and om.is_eligible=true
    where p.rule_set_id=target_rule_set_id
      and (f.property_name is null or om.id is null);
  end if;

  issues:=coalesce(base->'issues','[]'::jsonb);
  if active_mapping_id is not null and invalid_mapped_field_count=0 then
    select coalesce(jsonb_agg(i),'[]'::jsonb)
    into issues
    from jsonb_array_elements(issues) i
    where (i#>>'{}') not like '%predicate(s) use a field that is not allowed by the active HubSpot Compensation Mapping.%';
  end if;

  base:=jsonb_set(base,'{issues}',issues);
  base:=jsonb_set(base,'{ready}',to_jsonb(jsonb_array_length(issues)=0));
  base:=jsonb_set(base,'{mapped_object_contract}',to_jsonb(true));
  return base;
end;
$$;

revoke all on function public.validate_comp_rule_set_for_activation(uuid) from public,anon;
grant execute on function public.validate_comp_rule_set_for_activation(uuid) to authenticated;

-- Activation/deactivation is a lifecycle-state transition, not a rule-content edit.
-- Do not mutate updated_at here: preview freshness uses updated_at as the content revision marker.
create or replace function public.set_comp_rule_set_active(target_rule_set_id uuid,target_active boolean)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  target public.comp_rule_sets%rowtype;
  validation jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to activate compensation plan rules';
  end if;

  select * into target from public.comp_rule_sets where id=target_rule_set_id for update;
  if target.id is null then raise exception 'Rule set not found'; end if;

  if target_active then
    validation:=public.validate_comp_rule_set_for_activation(target.id);
    if coalesce((validation->>'ready')::boolean,false) is not true then
      raise exception 'Rule version is not ready for activation: %',validation->'issues';
    end if;
    update public.comp_rule_sets
    set is_active=false,updated_by=auth.uid()
    where plan_component_id=target.plan_component_id and name=target.name and id<>target.id;
  end if;

  update public.comp_rule_sets
  set is_active=target_active,updated_by=auth.uid()
  where id=target.id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(auth.uid(),'comp_rule_version_state_changed','A compensation rule version active state changed without altering its content revision timestamp.',jsonb_build_object('rule_set_id',target.id,'active',target_active,'content_updated_at',target.updated_at));
end;
$$;

create or replace function private.freeze_comp_plan_referenced_rule_sets(target_plan_version_id uuid)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  target_rule_id uuid;
  target_rule public.comp_rule_sets%rowtype;
  validation jsonb;
  frozen_count integer:=0;
begin
  for target_rule_id in
    with components as (
      select c.id,c.rule_configuration
      from public.comp_plan_components c
      where c.plan_version_id=target_plan_version_id and c.is_active=true
    ), latest_qualification as (
      select q.id
      from components c
      cross join lateral (
        select rs.id
        from public.comp_rule_sets rs
        where rs.plan_component_id=c.id and rs.purpose='qualification'
        order by rs.version desc,rs.updated_at desc
        limit 1
      ) q
    ), eligibility_rules as (
      select nullif(c.rule_configuration->'eligibility'->>'rule_set_id','')::uuid id
      from components c
      where c.rule_configuration->'eligibility'->>'mode'='rule'
        and nullif(c.rule_configuration->'eligibility'->>'rule_set_id','') is not null
    ), aggregate_single_rules as (
      select nullif(c.rule_configuration->'aggregate'->>'qualification_rule_set_id','')::uuid id
      from components c
      where nullif(c.rule_configuration->'aggregate'->>'qualification_rule_set_id','') is not null
    ), aggregate_source_rules as (
      select nullif(s.value->>'rule_set_id','')::uuid id
      from components c
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(c.rule_configuration->'aggregate'->'metric_sources')='array'
             then c.rule_configuration->'aggregate'->'metric_sources' else '[]'::jsonb end
      ) s
      where nullif(s.value->>'rule_set_id','') is not null
    )
    select distinct id from (
      select id from latest_qualification
      union all select id from eligibility_rules
      union all select id from aggregate_single_rules
      union all select id from aggregate_source_rules
    ) x
    where id is not null
  loop
    select * into target_rule from public.comp_rule_sets where id=target_rule_id for update;
    if target_rule.id is null then
      raise exception 'A referenced compensation rule version no longer exists: %',target_rule_id using errcode='23514';
    end if;

    validation:=public.validate_comp_rule_set_for_activation(target_rule.id);
    if coalesce((validation->>'ready')::boolean,false) is not true then
      raise exception 'Referenced rule % is not ready to freeze: %',target_rule.name,validation->'issues' using errcode='23514';
    end if;

    update public.comp_rule_sets
    set is_active=false,updated_by=auth.uid()
    where plan_component_id=target_rule.plan_component_id
      and name=target_rule.name
      and id<>target_rule.id;

    update public.comp_rule_sets
    set is_active=true,updated_by=auth.uid()
    where id=target_rule.id;

    frozen_count:=frozen_count+1;
  end loop;

  if frozen_count>0 then
    insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
    values(auth.uid(),'comp_plan_rule_versions_frozen','Rule versions referenced by an approved compensation plan were frozen as immutable active versions.',jsonb_build_object('plan_version_id',target_plan_version_id,'frozen_rule_count',frozen_count));
  end if;

  return frozen_count;
end;
$$;

revoke all on function private.freeze_comp_plan_referenced_rule_sets(uuid) from public,anon,authenticated;

alter function public.approve_compensation_plan_version(uuid,text)
  rename to approve_compensation_plan_version_pre_rule_freeze;

revoke all on function public.approve_compensation_plan_version_pre_rule_freeze(uuid,text) from public,anon,authenticated;

create or replace function public.approve_compensation_plan_version(selected_plan_version_id uuid,approval_notes text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  result jsonb;
  frozen_rule_count integer;
begin
  -- The pre-freeze function retains the existing permission check, readiness validation,
  -- approval write, and audit event. If freezing fails, the whole transaction rolls back.
  result:=public.approve_compensation_plan_version_pre_rule_freeze(selected_plan_version_id,approval_notes);
  frozen_rule_count:=private.freeze_comp_plan_referenced_rule_sets(selected_plan_version_id);
  result:=jsonb_set(result,'{frozen_rule_count}',to_jsonb(frozen_rule_count),true);
  return result;
end;
$$;

revoke all on function public.approve_compensation_plan_version(uuid,text) from public,anon;
grant execute on function public.approve_compensation_plan_version(uuid,text) to authenticated;
