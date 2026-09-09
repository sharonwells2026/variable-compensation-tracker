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
  relative_days numeric;
  actual_ts timestamptz;
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
    if operator_key in ('within_last','not_within_last') then
      relative_days := (expected_value#>>'{}')::numeric;
      if relative_days < 0 then return false; end if;
      actual_ts := actual_value::timestamptz;
      if operator_key='within_last' then
        return actual_ts >= current_timestamp - make_interval(secs => (relative_days * 86400)::double precision)
           and actual_ts <= current_timestamp;
      else
        return actual_ts < current_timestamp - make_interval(secs => (relative_days * 86400)::double precision)
            or actual_ts > current_timestamp;
      end if;
    end if;
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
