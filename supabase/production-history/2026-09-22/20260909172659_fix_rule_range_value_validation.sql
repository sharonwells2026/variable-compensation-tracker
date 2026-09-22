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
  invalid_value_count integer;
  incompatible_operator_count integer;
  latest_preview public.comp_rule_set_preview_runs%rowtype;
  preview_ready boolean:=false;
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
  select count(*) into incompatible_operator_count
    from public.comp_rule_predicates p
    join public.comp_rule_field_catalog f on f.object_type=p.object_type and f.property_name=p.property_name and f.is_active
    join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
    where p.rule_set_id=s.id and not (f.data_type = any(o.supported_data_types));
  select count(*) into invalid_value_count
    from public.comp_rule_predicates p
    join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
    where p.rule_set_id=s.id and (
      (o.value_arity='single' and (p.comparison_value is null or p.comparison_value='null'::jsonb or nullif(btrim(p.comparison_value#>>'{}'),'') is null))
      or (o.value_arity='multiple' and (p.comparison_value is null or jsonb_typeof(p.comparison_value)<>'array' or jsonb_array_length(coalesce(p.comparison_value,'[]'::jsonb))=0))
      or (o.value_arity='range' and (p.comparison_value is null or jsonb_typeof(p.comparison_value)<>'object' or nullif(btrim(p.comparison_value->>'low'),'') is null or nullif(btrim(p.comparison_value->>'high'),'') is null))
    );

  if predicate_count=0 then issues:=issues||jsonb_build_array('At least one predicate is required.'); end if;
  if root_count<>1 then issues:=issues||jsonb_build_array('Exactly one root expression group is required.'); end if;
  if referenced_count=0 then issues:=issues||jsonb_build_array('The expression must reference at least one predicate.'); end if;
  if referenced_count<predicate_count then issues:=issues||jsonb_build_array('Every defined predicate must be referenced by the expression.'); end if;
  if invalid_field_count>0 then issues:=issues||jsonb_build_array(invalid_field_count||' predicate(s) use an unavailable field.'); end if;
  if invalid_operator_count>0 then issues:=issues||jsonb_build_array(invalid_operator_count||' predicate(s) use an unavailable operator.'); end if;
  if incompatible_operator_count>0 then issues:=issues||jsonb_build_array(incompatible_operator_count||' predicate(s) use an operator that is incompatible with the field type.'); end if;
  if invalid_value_count>0 then issues:=issues||jsonb_build_array(invalid_value_count||' predicate(s) are missing a required comparison value.'); end if;

  select * into latest_preview from public.comp_rule_set_preview_runs where rule_set_id=s.id order by previewed_at desc limit 1;
  if latest_preview.id is null or latest_preview.rule_updated_at < s.updated_at then
    issues:=issues||jsonb_build_array('Preview this version against current HubSpot data after the latest edit.');
  elsif latest_preview.supported is not true then
    issues:=issues||jsonb_build_array('The latest preview cannot evaluate all predicates yet.');
  elsif coalesce(latest_preview.scanned_count,0)=0 then
    issues:=issues||jsonb_build_array('The latest preview scanned no synced HubSpot deals.');
  else
    preview_ready:=true;
  end if;

  return jsonb_build_object(
    'rule_set_id',s.id,'version',s.version,'is_active',s.is_active,
    'ready',jsonb_array_length(issues)=0,'issues',issues,
    'predicate_count',predicate_count,'referenced_predicate_count',referenced_count,'root_count',root_count,
    'preview_ready',preview_ready,
    'previewed_at',case when latest_preview.id is null then null else latest_preview.previewed_at end,
    'preview_scanned_count',case when latest_preview.id is null then null else latest_preview.scanned_count end,
    'preview_matched_count',case when latest_preview.id is null then null else latest_preview.matched_count end
  );
end;
$$;