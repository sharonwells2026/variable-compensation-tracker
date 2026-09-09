-- Compensation rule evaluation + safe preview against the local HubSpot deal snapshot.
-- Preview is read-only and exists so plan authors can validate logic before activation.

create or replace function public.comp_rule_deal_property(target_deal_record_id uuid, target_property_name text)
returns text
language sql
stable security definer
set search_path=''
as $$
  select case target_property_name
    when 'hs_object_id' then d.hubspot_deal_id
    when 'dealname' then d.deal_name
    when 'hubspot_owner_id' then d.hubspot_owner_id
    when 'pipeline' then d.hubspot_pipeline_id
    when 'dealstage' then d.hubspot_stage_id
    when 'dealtype' then d.hubspot_deal_type
    when 'amount' then d.amount::text
    when 'average_arr' then d.average_arr::text
    when 'first_year_arr' then d.first_year_arr::text
    when 'new_business_arr' then d.new_business_arr::text
    when 'expansion_arr' then d.expansion_arr::text
    when 'renewal_arr' then d.renewal_arr::text
    when 'nrr__non_recurring_revenue_' then d.non_recurring_revenue::text
    when 'one_time_fee' then d.one_time_fee::text
    when 'current_tcv' then d.total_contract_value::text
    when 'contract_term_deal' then d.contract_term_label
    when 'term_length__in_years_' then d.contract_term_years::text
    when 'contract_term_months' then d.contract_term_months::text
    when 'contract_term' then d.payment_frequency
    when 'contract_term_start_date' then d.contract_start_date::text
    when 'contract_term_end_dates' then d.contract_end_date::text
    when 'subscription_updated_date' then d.subscription_updated_date::text
    when 'invoice_paid_date' then d.invoice_paid_date::text
    when 'closedate' then d.close_date::text
    when 'engagifii_modules_of_interest' then d.purchased_modules
    when 'sales_account_executive__multi_year_deals_' then d.solutions_advisor_id
    when 'business_development_owner' then d.business_development_owner_id
    when 'qdc_completed_date' then d.qdc_completed_date::text
    when 'hs_is_closed_won' then d.is_closed_won::text
    else d.raw_hubspot_data->'properties'->>target_property_name
  end
  from public.hubspot_deals d
  where d.id=target_deal_record_id;
$$;

create or replace function public.comp_rule_compare_value(
  actual_value text,
  data_type text,
  operator_key text,
  expected_value jsonb,
  case_sensitive boolean default false,
  include_null_as_match boolean default false
)
returns boolean
language plpgsql
immutable
set search_path=''
as $$
declare
  actual_cmp text;
  expected_cmp text;
  low_cmp text;
  high_cmp text;
  result boolean := false;
  item text;
  matched_count integer := 0;
  total_count integer := 0;
begin
  if operator_key='is_unknown' then return actual_value is null or btrim(actual_value)=''; end if;
  if operator_key='is_known' then return actual_value is not null and btrim(actual_value)<>''; end if;
  if actual_value is null or btrim(actual_value)='' then return include_null_as_match; end if;

  actual_cmp := case when case_sensitive then actual_value else lower(actual_value) end;
  expected_cmp := case when expected_value is null then null when case_sensitive then expected_value#>>'{}' else lower(expected_value#>>'{}') end;

  if operator_key='is' then return actual_cmp=expected_cmp; end if;
  if operator_key='is_not' then return actual_cmp<>expected_cmp; end if;
  if operator_key='contains' then return position(expected_cmp in actual_cmp)>0; end if;
  if operator_key='does_not_contain' then return position(expected_cmp in actual_cmp)=0; end if;
  if operator_key='starts_with' then return actual_cmp like expected_cmp||'%'; end if;
  if operator_key='ends_with' then return actual_cmp like '%'||expected_cmp; end if;

  if operator_key in ('is_any_of','is_none_of','contains_any_of','contains_all_of') then
    if jsonb_typeof(expected_value)<>'array' then return false; end if;
    for item in select jsonb_array_elements_text(expected_value) loop
      total_count := total_count + 1;
      item := case when case_sensitive then item else lower(item) end;
      if operator_key in ('is_any_of','is_none_of') then
        if actual_cmp=item then matched_count:=matched_count+1; end if;
      else
        if position(item in actual_cmp)>0 then matched_count:=matched_count+1; end if;
      end if;
    end loop;
    if operator_key='is_any_of' then return matched_count>0; end if;
    if operator_key='is_none_of' then return matched_count=0; end if;
    if operator_key='contains_any_of' then return matched_count>0; end if;
    if operator_key='contains_all_of' then return total_count>0 and matched_count=total_count; end if;
  end if;

  if operator_key='matches_regex' then return actual_value ~ (expected_value#>>'{}'); end if;
  if operator_key='does_not_match_regex' then return not (actual_value ~ (expected_value#>>'{}')); end if;

  if operator_key='between' then
    low_cmp:=expected_value->>'low'; high_cmp:=expected_value->>'high';
    if data_type='number' then return actual_value::numeric between low_cmp::numeric and high_cmp::numeric; end if;
    if data_type in ('date','datetime') then return actual_value::timestamptz between low_cmp::timestamptz and high_cmp::timestamptz; end if;
    return actual_cmp between lower(low_cmp) and lower(high_cmp);
  end if;

  if data_type='number' then
    if operator_key='greater_than' then return actual_value::numeric>(expected_value#>>'{}')::numeric; end if;
    if operator_key='greater_than_or_equal' then return actual_value::numeric>=(expected_value#>>'{}')::numeric; end if;
    if operator_key='less_than' then return actual_value::numeric<(expected_value#>>'{}')::numeric; end if;
    if operator_key='less_than_or_equal' then return actual_value::numeric<=(expected_value#>>'{}')::numeric; end if;
  end if;

  if data_type in ('date','datetime') then
    if operator_key in ('after','greater_than') then return actual_value::timestamptz>(expected_value#>>'{}')::timestamptz; end if;
    if operator_key='greater_than_or_equal' then return actual_value::timestamptz>=(expected_value#>>'{}')::timestamptz; end if;
    if operator_key in ('before','less_than') then return actual_value::timestamptz<(expected_value#>>'{}')::timestamptz; end if;
    if operator_key='less_than_or_equal' then return actual_value::timestamptz<=(expected_value#>>'{}')::timestamptz; end if;
  end if;

  return result;
exception when others then
  return false;
end;
$$;

create or replace function public.comp_rule_evaluate_deal_node(target_node_id uuid,target_deal_record_id uuid)
returns boolean
language plpgsql
stable security definer
set search_path=''
as $$
declare
  n public.comp_rule_expression_nodes%rowtype;
  p public.comp_rule_predicates%rowtype;
  child record;
  result boolean;
  child_result boolean;
  actual_value text;
begin
  select * into n from public.comp_rule_expression_nodes where id=target_node_id;
  if n.id is null then return false; end if;

  if n.node_type='predicate' then
    select * into p from public.comp_rule_predicates where id=n.predicate_id;
    if p.object_type<>'deal' or jsonb_array_length(coalesce(p.association_path,'[]'::jsonb))>0 then return false; end if;
    actual_value:=public.comp_rule_deal_property(target_deal_record_id,p.property_name);
    result:=public.comp_rule_compare_value(actual_value,p.comparison_value_type,p.operator_key,p.comparison_value,p.case_sensitive,p.include_null_as_match);
  else
    if n.logical_operator='AND' then
      result:=true;
      for child in select id from public.comp_rule_expression_nodes where parent_node_id=n.id order by sort_order,created_at loop
        child_result:=public.comp_rule_evaluate_deal_node(child.id,target_deal_record_id);
        if not child_result then result:=false; exit; end if;
      end loop;
    else
      result:=false;
      for child in select id from public.comp_rule_expression_nodes where parent_node_id=n.id order by sort_order,created_at loop
        child_result:=public.comp_rule_evaluate_deal_node(child.id,target_deal_record_id);
        if child_result then result:=true; exit; end if;
      end loop;
    end if;
  end if;

  if n.negate then return not coalesce(result,false); end if;
  return coalesce(result,false);
end;
$$;

create or replace function public.preview_comp_rule_set(target_rule_set_id uuid,max_results integer default 25)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  access jsonb;
  root_id uuid;
  unsupported integer;
  d record;
  scanned integer:=0;
  matched integer:=0;
  samples jsonb:='[]'::jsonb;
  limit_count integer:=greatest(1,least(coalesce(max_results,25),100));
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to preview compensation plan rules';
  end if;

  select count(*) into unsupported from public.comp_rule_predicates
  where rule_set_id=target_rule_set_id
    and (object_type<>'deal' or jsonb_array_length(coalesce(association_path,'[]'::jsonb))>0);
  if unsupported>0 then
    return jsonb_build_object('supported',false,'reason','This preview currently supports Deal predicates only. Associated-object predicates are saved correctly but require the association evaluator.','unsupported_predicates',unsupported);
  end if;

  select id into root_id from public.comp_rule_expression_nodes
  where rule_set_id=target_rule_set_id and parent_node_id is null limit 1;
  if root_id is null then raise exception 'Rule set has no root expression'; end if;

  for d in select id,hubspot_deal_id,deal_name,close_date,hubspot_deal_type,amount,hubspot_stage_id,hubspot_owner_id,hubspot_record_url from public.hubspot_deals order by close_date desc nulls last,deal_name loop
    scanned:=scanned+1;
    if public.comp_rule_evaluate_deal_node(root_id,d.id) then
      matched:=matched+1;
      if jsonb_array_length(samples)<limit_count then
        samples:=samples||jsonb_build_array(jsonb_build_object(
          'hubspot_deal_id',d.hubspot_deal_id,'deal_name',d.deal_name,'close_date',d.close_date,
          'deal_type',d.hubspot_deal_type,'amount',d.amount,'stage_id',d.hubspot_stage_id,
          'owner_id',d.hubspot_owner_id,'record_url',d.hubspot_record_url
        ));
      end if;
    end if;
  end loop;

  return jsonb_build_object('supported',true,'scanned_count',scanned,'matched_count',matched,'sample_count',jsonb_array_length(samples),'samples',samples);
end;
$$;

-- Preserve association semantics when saving predicates. The original save RPC predated these columns.
create or replace function public.save_comp_rule_set(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  set_id uuid;
  pred jsonb;
  node jsonb;
  generated_id uuid;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to edit compensation plan rules';
  end if;
  if payload->>'plan_component_id' is null or payload->>'name' is null or payload->>'purpose' is null then
    raise exception 'plan_component_id, name and purpose are required';
  end if;

  if payload->>'id' is null then
    insert into public.comp_rule_sets(plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,outcome_configuration,created_by,updated_by)
    values ((payload->>'plan_component_id')::uuid,payload->>'name',payload->>'purpose',payload->>'description',coalesce(payload->>'evaluation_scope','record'),coalesce((payload->>'version')::int,1),coalesce((payload->>'is_active')::boolean,true),coalesce((payload->>'stop_on_match')::boolean,false),coalesce(payload->'outcome_configuration','{}'::jsonb),(select auth.uid()),(select auth.uid()))
    returning id into set_id;
  else
    set_id:=(payload->>'id')::uuid;
    update public.comp_rule_sets set name=payload->>'name',purpose=payload->>'purpose',description=payload->>'description',evaluation_scope=coalesce(payload->>'evaluation_scope','record'),is_active=coalesce((payload->>'is_active')::boolean,true),stop_on_match=coalesce((payload->>'stop_on_match')::boolean,false),outcome_configuration=coalesce(payload->'outcome_configuration','{}'::jsonb),updated_by=(select auth.uid()),updated_at=now() where id=set_id;
    delete from public.comp_rule_expression_nodes where rule_set_id=set_id;
    delete from public.comp_rule_predicates where rule_set_id=set_id;
  end if;

  create temporary table if not exists _rule_pred_map(client_key text primary key,predicate_id uuid) on commit drop;
  truncate _rule_pred_map;
  for pred in select * from jsonb_array_elements(coalesce(payload->'predicates','[]'::jsonb)) loop
    insert into public.comp_rule_predicates(rule_set_id,rule_key,display_name,object_type,association_path,association_quantifier,aggregate_function,aggregate_window,property_name,operator_key,comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes)
    values (set_id,pred->>'rule_key',coalesce(pred->>'display_name',pred->>'rule_key'),pred->>'object_type',coalesce(pred->'association_path','[]'::jsonb),coalesce(pred->>'association_quantifier','any'),pred->>'aggregate_function',pred->'aggregate_window',pred->>'property_name',pred->>'operator_key',pred->'comparison_value',pred->>'comparison_value_type',coalesce((pred->>'case_sensitive')::boolean,false),coalesce((pred->>'include_null_as_match')::boolean,false),pred->>'notes')
    returning id into generated_id;
    insert into _rule_pred_map(client_key,predicate_id) values (pred->>'client_key',generated_id);
  end loop;

  create temporary table if not exists _rule_node_map(client_key text primary key,node_id uuid) on commit drop;
  truncate _rule_node_map;
  for node in select * from jsonb_array_elements(coalesce(payload->'nodes','[]'::jsonb)) loop
    insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
    values (set_id,(select node_id from _rule_node_map where client_key=node->>'parent_client_key'),node->>'node_type',(select predicate_id from _rule_pred_map where client_key=node->>'predicate_client_key'),node->>'logical_operator',coalesce((node->>'negate')::boolean,false),coalesce((node->>'sort_order')::int,0),node->>'label') returning id into generated_id;
    insert into _rule_node_map(client_key,node_id) values (node->>'client_key',generated_id);
  end loop;

  if (select count(*) from public.comp_rule_expression_nodes where rule_set_id=set_id and parent_node_id is null)<>1 then
    raise exception 'A rule set must contain exactly one root expression node';
  end if;
  return set_id;
end;
$$;

revoke all on function public.comp_rule_deal_property(uuid,text) from public,anon;
revoke all on function public.comp_rule_compare_value(text,text,text,jsonb,boolean,boolean) from public,anon;
revoke all on function public.comp_rule_evaluate_deal_node(uuid,uuid) from public,anon;
revoke all on function public.preview_comp_rule_set(uuid,integer) from public,anon;
grant execute on function public.preview_comp_rule_set(uuid,integer) to authenticated,service_role;
