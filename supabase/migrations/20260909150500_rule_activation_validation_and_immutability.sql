-- Protect historical compensation logic and require activation readiness.
-- save_comp_rule_set remains defined by the existing rule-builder migration.
-- Active-version immutability is enforced independently by the database triggers
-- in 20260909151000_guard_active_rule_version_edits.sql.

create or replace function public.validate_comp_rule_set_for_activation(target_rule_set_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  access jsonb;
  s public.comp_rule_sets%rowtype;
  issues jsonb := '[]'::jsonb;
  root_count integer;
  predicate_count integer;
  referenced_count integer;
  invalid_field_count integer;
  invalid_operator_count integer;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to validate compensation plan rules';
  end if;

  select * into s from public.comp_rule_sets where id=target_rule_set_id;
  if s.id is null then raise exception 'Rule set not found'; end if;

  select count(*) into predicate_count from public.comp_rule_predicates where rule_set_id=s.id;
  select count(*) into root_count from public.comp_rule_expression_nodes where rule_set_id=s.id and parent_node_id is null;
  select count(distinct predicate_id) into referenced_count from public.comp_rule_expression_nodes where rule_set_id=s.id and node_type='predicate';
  select count(*) into invalid_field_count
    from public.comp_rule_predicates p
    left join public.comp_rule_field_catalog f on f.object_type=p.object_type and f.property_name=p.property_name and f.is_active
    where p.rule_set_id=s.id and f.id is null;
  select count(*) into invalid_operator_count
    from public.comp_rule_predicates p
    left join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
    where p.rule_set_id=s.id and o.operator_key is null;

  if predicate_count=0 then issues:=issues||jsonb_build_array('At least one predicate is required.'); end if;
  if root_count<>1 then issues:=issues||jsonb_build_array('Exactly one root expression group is required.'); end if;
  if referenced_count=0 then issues:=issues||jsonb_build_array('The expression must reference at least one predicate.'); end if;
  if referenced_count<predicate_count then issues:=issues||jsonb_build_array('Every defined predicate must be referenced by the expression.'); end if;
  if invalid_field_count>0 then issues:=issues||jsonb_build_array(invalid_field_count||' predicate(s) use an unavailable field.'); end if;
  if invalid_operator_count>0 then issues:=issues||jsonb_build_array(invalid_operator_count||' predicate(s) use an unavailable operator.'); end if;

  return jsonb_build_object(
    'rule_set_id',s.id,'version',s.version,'is_active',s.is_active,
    'ready',jsonb_array_length(issues)=0,'issues',issues,
    'predicate_count',predicate_count,'referenced_predicate_count',referenced_count,'root_count',root_count
  );
end;
$$;

create or replace function public.set_comp_rule_set_active(target_rule_set_id uuid,target_active boolean)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare access jsonb; target public.comp_rule_sets%rowtype; validation jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then raise exception 'Not authorized to activate compensation plan rules'; end if;
  select * into target from public.comp_rule_sets where id=target_rule_set_id for update;
  if target.id is null then raise exception 'Rule set not found'; end if;
  if target_active then
    validation:=public.validate_comp_rule_set_for_activation(target.id);
    if coalesce((validation->>'ready')::boolean,false) is not true then raise exception 'Rule version is not ready for activation: %',validation->'issues'; end if;
    update public.comp_rule_sets set is_active=false,updated_at=now(),updated_by=(select auth.uid()) where plan_component_id=target.plan_component_id and name=target.name and id<>target.id;
  end if;
  update public.comp_rule_sets set is_active=target_active,updated_at=now(),updated_by=(select auth.uid()) where id=target.id;
end;
$$;

revoke all on function public.validate_comp_rule_set_for_activation(uuid) from public,anon;
grant execute on function public.validate_comp_rule_set_for_activation(uuid) to authenticated;
