create or replace function public.comp_rule_generic_property(target_internal_object_key text, target_hubspot_record_id text, target_property_name text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select g.properties ->> target_property_name
  from public.hubspot_generic_records g
  where g.internal_object_key = target_internal_object_key
    and g.hubspot_record_id = target_hubspot_record_id
    and g.in_sync_scope
    and not g.is_archived
  limit 1;
$$;

create or replace function public.comp_rule_evaluate_generic_node(
  target_node_id uuid,
  root_internal_object_key text,
  root_hubspot_record_id text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  n public.comp_rule_expression_nodes%rowtype;
  p public.comp_rule_predicates%rowtype;
  child record;
  related record;
  result boolean;
  child_result boolean;
  actual_value text;
  total_related integer := 0;
  matched_related integer := 0;
begin
  select * into n from public.comp_rule_expression_nodes where id = target_node_id;
  if n.id is null then return false; end if;

  if n.node_type = 'predicate' then
    select * into p from public.comp_rule_predicates where id = n.predicate_id;
    if p.id is null then return false; end if;

    if p.object_type = root_internal_object_key
       and jsonb_array_length(coalesce(p.association_path, '[]'::jsonb)) = 0 then
      actual_value := public.comp_rule_generic_property(root_internal_object_key, root_hubspot_record_id, p.property_name);
      result := public.comp_rule_compare_value(actual_value, p.comparison_value_type, p.operator_key, p.comparison_value, p.case_sensitive, p.include_null_as_match);

    elsif p.object_type = 'company' then
      for related in
        select c.id
        from public.hubspot_generic_associations a
        join public.hubspot_companies c on c.hubspot_company_id = a.target_hubspot_record_id
        where a.source_internal_object_key = root_internal_object_key
          and a.source_hubspot_record_id = root_hubspot_record_id
          and a.target_object_type = 'company'
      loop
        total_related := total_related + 1;
        actual_value := public.comp_rule_company_property(related.id, p.property_name);
        if public.comp_rule_compare_value(actual_value, p.comparison_value_type, p.operator_key, p.comparison_value, p.case_sensitive, p.include_null_as_match) then
          matched_related := matched_related + 1;
        end if;
      end loop;
      result := case coalesce(p.association_quantifier, 'any')
        when 'all' then total_related > 0 and matched_related = total_related
        when 'none' then matched_related = 0
        else matched_related > 0
      end;

    elsif p.object_type = 'deal' then
      for related in
        select d.id
        from public.hubspot_generic_associations a
        join public.hubspot_deals d on d.hubspot_deal_id = a.target_hubspot_record_id
        where a.source_internal_object_key = root_internal_object_key
          and a.source_hubspot_record_id = root_hubspot_record_id
          and a.target_object_type = 'deal'
      loop
        total_related := total_related + 1;
        actual_value := public.comp_rule_deal_property(related.id, p.property_name);
        if public.comp_rule_compare_value(actual_value, p.comparison_value_type, p.operator_key, p.comparison_value, p.case_sensitive, p.include_null_as_match) then
          matched_related := matched_related + 1;
        end if;
      end loop;
      result := case coalesce(p.association_quantifier, 'any')
        when 'all' then total_related > 0 and matched_related = total_related
        when 'none' then matched_related = 0
        else matched_related > 0
      end;
    else
      result := false;
    end if;
  else
    if n.logical_operator = 'AND' then
      result := true;
      for child in select id from public.comp_rule_expression_nodes where parent_node_id = n.id order by sort_order, created_at loop
        child_result := public.comp_rule_evaluate_generic_node(child.id, root_internal_object_key, root_hubspot_record_id);
        if not child_result then result := false; exit; end if;
      end loop;
    else
      result := false;
      for child in select id from public.comp_rule_expression_nodes where parent_node_id = n.id order by sort_order, created_at loop
        child_result := public.comp_rule_evaluate_generic_node(child.id, root_internal_object_key, root_hubspot_record_id);
        if child_result then result := true; exit; end if;
      end loop;
    end if;
  end if;

  if n.negate then return not coalesce(result, false); end if;
  return coalesce(result, false);
end;
$$;

create or replace function public.preview_comp_rule_set(target_rule_set_id uuid, max_results integer default 25)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  access jsonb;
  s public.comp_rule_sets%rowtype;
  root_id uuid;
  unsupported integer;
  generic_roots text[];
  generic_root text;
  d record;
  g record;
  scanned integer := 0;
  matched integer := 0;
  samples jsonb := '[]'::jsonb;
  result jsonb;
  limit_count integer := greatest(1, least(coalesce(max_results, 25), 100));
begin
  access := public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean, false) is not true
     or not (coalesce(access->'permissions', '[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to preview compensation plan rules';
  end if;

  select * into s from public.comp_rule_sets where id = target_rule_set_id;
  if s.id is null then raise exception 'Rule set not found'; end if;

  select array_agg(distinct p.object_type order by p.object_type)
  into generic_roots
  from public.comp_rule_predicates p
  where p.rule_set_id = target_rule_set_id
    and p.object_type not in ('deal', 'company')
    and exists (
      select 1 from public.hubspot_object_definitions o
      where o.internal_object_key = p.object_type and o.is_active and o.read_access = 'AVAILABLE'
    );

  if coalesce(array_length(generic_roots, 1), 0) > 1 then
    result := jsonb_build_object('supported', false, 'reason', 'Preview currently supports one primary generic HubSpot object per rule set, with associated Deal and Company predicates.', 'generic_primary_objects', to_jsonb(generic_roots));
    insert into public.comp_rule_set_preview_runs(rule_set_id, previewed_by, rule_updated_at, supported, result)
    values(s.id, (select auth.uid()), s.updated_at, false, result);
    return result;
  end if;

  generic_root := case when coalesce(array_length(generic_roots,1),0)=1 then generic_roots[1] else null end;

  select count(*) into unsupported
  from public.comp_rule_predicates p
  where p.rule_set_id = target_rule_set_id
    and (
      (generic_root is null and p.object_type not in ('deal','company'))
      or (generic_root is not null and p.object_type not in (generic_root,'deal','company'))
      or jsonb_array_length(coalesce(p.association_path,'[]'::jsonb)) > 1
    );

  if unsupported > 0 then
    result := jsonb_build_object(
      'supported', false,
      'reason', case when generic_root is null
        then 'This preview supports Deal predicates and directly associated Company predicates.'
        else 'This preview supports the primary '||generic_root||' record plus directly associated Deal and Company predicates.'
      end,
      'unsupported_predicates', unsupported
    );
    insert into public.comp_rule_set_preview_runs(rule_set_id, previewed_by, rule_updated_at, supported, result)
    values(s.id, (select auth.uid()), s.updated_at, false, result);
    return result;
  end if;

  select id into root_id from public.comp_rule_expression_nodes where rule_set_id = target_rule_set_id and parent_node_id is null limit 1;
  if root_id is null then raise exception 'Rule set has no root expression'; end if;

  if generic_root is null then
    for d in
      select id, hubspot_deal_id, deal_name, close_date, hubspot_deal_type, amount, hubspot_stage_id, hubspot_owner_id, hubspot_record_url
      from public.hubspot_deals
      order by close_date desc nulls last, deal_name
    loop
      scanned := scanned + 1;
      if public.comp_rule_evaluate_deal_node(root_id, d.id) then
        matched := matched + 1;
        if jsonb_array_length(samples) < limit_count then
          samples := samples || jsonb_build_array(jsonb_build_object('hubspot_deal_id', d.hubspot_deal_id, 'deal_name', d.deal_name, 'close_date', d.close_date, 'deal_type', d.hubspot_deal_type, 'amount', d.amount, 'stage_id', d.hubspot_stage_id, 'owner_id', d.hubspot_owner_id, 'record_url', d.hubspot_record_url));
        end if;
      end if;
    end loop;
  else
    for g in
      select hubspot_record_id, properties, hubspot_created_at, hubspot_updated_at
      from public.hubspot_generic_records
      where internal_object_key = generic_root and in_sync_scope and not is_archived
      order by hubspot_updated_at desc nulls last, hubspot_created_at desc nulls last
    loop
      scanned := scanned + 1;
      if public.comp_rule_evaluate_generic_node(root_id, generic_root, g.hubspot_record_id) then
        matched := matched + 1;
        if jsonb_array_length(samples) < limit_count then
          samples := samples || jsonb_build_array(jsonb_build_object('object_type', generic_root, 'hubspot_record_id', g.hubspot_record_id, 'properties', g.properties, 'created_at', g.hubspot_created_at, 'updated_at', g.hubspot_updated_at));
        end if;
      end if;
    end loop;
  end if;

  result := jsonb_build_object('supported', true, 'primary_object_type', coalesce(generic_root, 'deal'), 'scanned_count', scanned, 'matched_count', matched, 'sample_count', jsonb_array_length(samples), 'samples', samples);
  insert into public.comp_rule_set_preview_runs(rule_set_id, previewed_by, rule_updated_at, supported, scanned_count, matched_count, sample_count, result)
  values(s.id, (select auth.uid()), s.updated_at, true, scanned, matched, jsonb_array_length(samples), result);
  return result;
end;
$$;

revoke all on function public.comp_rule_generic_property(text,text,text) from public, anon, authenticated;
revoke all on function public.comp_rule_evaluate_generic_node(uuid,text,text) from public, anon, authenticated;
