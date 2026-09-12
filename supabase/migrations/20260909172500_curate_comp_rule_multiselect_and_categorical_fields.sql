update public.comp_rule_field_catalog
set data_type='multi_enumeration',
    is_multi_value=true,
    options=(
      select coalesce(jsonb_agg(jsonb_build_object('label',v,'value',v) order by v),'[]'::jsonb)
      from (
        select distinct btrim(token) v
        from public.hubspot_deals d
        cross join lateral regexp_split_to_table(coalesce(public.comp_rule_deal_property(d.id,'product_line'),''),';') token
        where btrim(token)<>''
      ) x
    ),
    source_system='hubspot_curated',
    description='Product line(s) on the HubSpot deal. Multi-select values are matched as exact selections.',
    updated_at=now()
where object_type='deal' and property_name='product_line';

update public.comp_rule_field_catalog
set data_type='multi_enumeration',
    is_multi_value=true,
    options=(
      select coalesce(jsonb_agg(jsonb_build_object('label',v,'value',v) order by v),'[]'::jsonb)
      from (
        select distinct btrim(token) v
        from public.hubspot_deals d
        cross join lateral regexp_split_to_table(coalesce(public.comp_rule_deal_property(d.id,'engagifii_modules_of_interest'),''),';') token
        where btrim(token)<>''
      ) x
    ),
    source_system='hubspot_curated',
    description='Products, modules, integrations, or services selected on the HubSpot deal. Multi-select values are matched as exact selections.',
    updated_at=now()
where object_type='deal' and property_name='engagifii_modules_of_interest';

update public.comp_rule_field_catalog
set data_type='enumeration',
    options=(select coalesce(jsonb_agg(jsonb_build_object('label',v,'value',v) order by v),'[]'::jsonb) from (select distinct public.comp_rule_deal_property(id,'contract_term') v from public.hubspot_deals where nullif(btrim(public.comp_rule_deal_property(id,'contract_term')),'') is not null) x),
    source_system='hubspot_curated',
    updated_at=now()
where object_type='deal' and property_name='contract_term';

update public.comp_rule_field_catalog
set data_type='enumeration',
    options=(select coalesce(jsonb_agg(jsonb_build_object('label',v,'value',v) order by v),'[]'::jsonb) from (select distinct public.comp_rule_deal_property(id,'contract_term_deal') v from public.hubspot_deals where nullif(btrim(public.comp_rule_deal_property(id,'contract_term_deal')),'') is not null) x),
    source_system='hubspot_curated',
    updated_at=now()
where object_type='deal' and property_name='contract_term_deal';

update public.comp_rule_field_catalog
set data_type='enumeration',
    options=(select coalesce(jsonb_agg(jsonb_build_object('label',v,'value',v) order by v),'[]'::jsonb) from (select distinct public.comp_rule_company_property(id,'customer_status') v from public.hubspot_companies where nullif(btrim(public.comp_rule_company_property(id,'customer_status')),'') is not null) x),
    source_system='hubspot_curated',
    updated_at=now()
where object_type='company' and property_name='customer_status';

update public.comp_rule_field_catalog
set data_type='enumeration',
    options='[{"label":"Yes","value":"yes"},{"label":"No","value":"no"}]'::jsonb,
    source_system='hubspot_curated',
    updated_at=now()
where object_type='company' and property_name='current_customer';

create or replace function public.comp_rule_compare_value(actual_value text, data_type text, operator_key text, expected_value jsonb, case_sensitive boolean default false, include_null_as_match boolean default false)
returns boolean
language plpgsql
stable
set search_path=''
as $$
declare
  actual_cmp text; expected_cmp text; low_cmp text; high_cmp text; result boolean := false; item text; matched_count integer := 0; total_count integer := 0;
  actual_tokens text[];
begin
  if operator_key='is_unknown' then return actual_value is null or btrim(actual_value)=''; end if;
  if operator_key='is_known' then return actual_value is not null and btrim(actual_value)<>''; end if;
  if actual_value is null or btrim(actual_value)='' then return include_null_as_match; end if;

  actual_cmp := case when case_sensitive then actual_value else lower(actual_value) end;
  expected_cmp := case when expected_value is null then null when case_sensitive then expected_value#>>'{}' else lower(expected_value#>>'{}') end;

  if data_type='multi_enumeration' then
    select array_agg(case when case_sensitive then btrim(v) else lower(btrim(v)) end)
    into actual_tokens
    from regexp_split_to_table(actual_value,';') v
    where btrim(v)<>'';

    if operator_key='contains' then return expected_cmp = any(coalesce(actual_tokens,array[]::text[])); end if;
    if operator_key='does_not_contain' then return not (expected_cmp = any(coalesce(actual_tokens,array[]::text[]))); end if;
    if operator_key in ('contains_any_of','contains_all_of') then
      if jsonb_typeof(expected_value)<>'array' then return false; end if;
      for item in select jsonb_array_elements_text(expected_value) loop
        total_count:=total_count+1;
        item:=case when case_sensitive then btrim(item) else lower(btrim(item)) end;
        if item = any(coalesce(actual_tokens,array[]::text[])) then matched_count:=matched_count+1; end if;
      end loop;
      if operator_key='contains_any_of' then return matched_count>0; end if;
      return total_count>0 and matched_count=total_count;
    end if;
  end if;

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

  if operator_key in ('within_last','not_within_last') and data_type in ('date','datetime') then
    if expected_value is null or (expected_value#>>'{}') !~ '^[0-9]+([.][0-9]+)?$' then return false; end if;
    result := actual_value::timestamptz >= now() - make_interval(days => (expected_value#>>'{}')::integer)
              and actual_value::timestamptz <= now();
    if operator_key='not_within_last' then return not result; end if;
    return result;
  end if;

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
exception when others then return false;
end;
$$;

revoke all on function public.comp_rule_compare_value(text,text,text,jsonb,boolean,boolean) from public,anon,authenticated;
