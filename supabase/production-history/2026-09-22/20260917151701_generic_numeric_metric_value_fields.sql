create or replace function private.compute_comp_metric_rule_summary(
  target_rule_set_id uuid,
  selected_value_field text,
  selected_start_date date,
  selected_end_date date
)
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  root_id uuid;
  total_value numeric:=0;
  matched_count integer:=0;
  d record;
  raw_value text;
  row_value numeric;
begin
  if target_rule_set_id is null then
    return jsonb_build_object('total',0,'matched_count',0,'value_field',selected_value_field);
  end if;
  if selected_start_date is null or selected_end_date is null or selected_end_date<selected_start_date then
    return jsonb_build_object('total',0,'matched_count',0,'value_field',selected_value_field);
  end if;

  if not exists(
    select 1
    from public.comp_rule_field_catalog f
    join public.comp_hubspot_object_mappings om
      on om.object_type=f.object_type
     and om.is_eligible=true
    where f.object_type='deal'
      and f.property_name=selected_value_field
      and f.data_type='number'
      and f.is_active=true
  ) then
    raise exception 'Aggregate value field % is not an available mapped numeric Deal field',selected_value_field using errcode='22023';
  end if;

  select n.id into root_id
  from public.comp_rule_expression_nodes n
  where n.rule_set_id=target_rule_set_id and n.parent_node_id is null
  limit 1;
  if root_id is null then
    raise exception 'Metric qualification rule has no root expression' using errcode='22023';
  end if;

  for d in
    select id
    from public.hubspot_deals
    where close_date between selected_start_date and selected_end_date
  loop
    if public.comp_rule_evaluate_deal_node(root_id,d.id) then
      raw_value:=public.comp_rule_deal_property(d.id,selected_value_field);
      if raw_value is not null and btrim(raw_value)<>'' then
        begin
          row_value:=raw_value::numeric;
        exception when invalid_text_representation or numeric_value_out_of_range then
          raise exception 'Deal % has non-numeric value % for aggregate field %',d.id,raw_value,selected_value_field using errcode='22023';
        end;
        total_value:=total_value+coalesce(row_value,0);
      end if;
      matched_count:=matched_count+1;
    end if;
  end loop;

  return jsonb_build_object(
    'total',total_value,
    'matched_count',matched_count,
    'value_field',selected_value_field
  );
end;
$$;

revoke all on function private.compute_comp_metric_rule_summary(uuid,text,date,date) from public,anon,authenticated;

create or replace function public.is_comp_metric_numeric_value_field(selected_value_field text)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.comp_rule_field_catalog f
    join public.comp_hubspot_object_mappings om
      on om.object_type=f.object_type
     and om.is_eligible=true
    where f.object_type='deal'
      and f.property_name=selected_value_field
      and f.data_type='number'
      and f.is_active=true
  );
$$;

revoke all on function public.is_comp_metric_numeric_value_field(text) from public,anon;
grant execute on function public.is_comp_metric_numeric_value_field(text) to authenticated;