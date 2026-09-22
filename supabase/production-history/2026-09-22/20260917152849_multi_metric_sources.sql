-- Support aggregate metrics composed from multiple independently qualified HubSpot metric sources.
-- Each source owns a Metric Qualification rule and the numeric HubSpot field whose values should be summed.
-- Existing single-rule and legacy source-Earning-Type configurations remain supported.

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
  matched_ids uuid[]:=array[]::uuid[];
begin
  if target_rule_set_id is null then
    return jsonb_build_object('total',0,'matched_count',0,'value_field',selected_value_field,'matched_record_ids','[]'::jsonb);
  end if;
  if selected_start_date is null or selected_end_date is null or selected_end_date<selected_start_date then
    return jsonb_build_object('total',0,'matched_count',0,'value_field',selected_value_field,'matched_record_ids','[]'::jsonb);
  end if;

  if not public.is_comp_metric_numeric_value_field(selected_value_field) then
    raise exception 'Aggregate value field % is not an available mapped numeric Deal field',selected_value_field using errcode='22023';
  end if;

  select n.id into root_id
  from public.comp_rule_expression_nodes n
  where n.rule_set_id=target_rule_set_id and n.parent_node_id is null
  limit 1;
  if root_id is null then raise exception 'Metric qualification rule has no root expression' using errcode='22023'; end if;

  for d in
    select id from public.hubspot_deals
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
      matched_ids:=array_append(matched_ids,d.id);
    end if;
  end loop;

  return jsonb_build_object(
    'total',total_value,
    'matched_count',matched_count,
    'value_field',selected_value_field,
    'matched_record_ids',to_jsonb(matched_ids)
  );
end;
$$;

revoke all on function private.compute_comp_metric_rule_summary(uuid,text,date,date) from public,anon,authenticated;

create or replace function private.compute_comp_metric_sources_summary(
  target_component_id uuid,
  selected_sources jsonb,
  selected_start_date date,
  selected_end_date date
)
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  source jsonb;
  source_index integer:=0;
  source_rule_set_id uuid;
  source_value_field text;
  source_label text;
  source_summary jsonb;
  source_ids uuid[];
  seen_ids uuid[]:=array[]::uuid[];
  total_value numeric:=0;
  matched_count integer:=0;
  source_results jsonb:='[]'::jsonb;
begin
  if selected_sources is null or jsonb_typeof(selected_sources)<>'array' or jsonb_array_length(selected_sources)=0 then
    return jsonb_build_object('total',0,'matched_count',0,'sources','[]'::jsonb);
  end if;

  for source in select value from jsonb_array_elements(selected_sources)
  loop
    source_index:=source_index+1;
    source_rule_set_id:=nullif(source->>'rule_set_id','')::uuid;
    source_value_field:=coalesce(nullif(source->>'value_field',''),'amount');
    source_label:=coalesce(nullif(source->>'label',''),format('Metric source %s',source_index));

    if source_rule_set_id is null then
      raise exception '% needs a Metric Qualification rule',source_label using errcode='22023';
    end if;
    if not exists(
      select 1 from public.comp_rule_sets rs
      where rs.id=source_rule_set_id
        and rs.plan_component_id=target_component_id
        and rs.purpose='metric_qualification'
    ) then
      raise exception '% references a Metric Qualification rule that does not belong to this Earning Type',source_label using errcode='22023';
    end if;
    if not public.is_comp_metric_numeric_value_field(source_value_field) then
      raise exception '% uses an unavailable or nonnumeric Deal value field: %',source_label,source_value_field using errcode='22023';
    end if;

    source_summary:=private.compute_comp_metric_rule_summary(source_rule_set_id,source_value_field,selected_start_date,selected_end_date);
    select coalesce(array_agg(value::uuid),array[]::uuid[])
    into source_ids
    from jsonb_array_elements_text(coalesce(source_summary->'matched_record_ids','[]'::jsonb));

    if cardinality(source_ids)>0 and seen_ids && source_ids then
      raise exception 'Metric sources overlap on one or more HubSpot deals. Make source qualification rules mutually exclusive to avoid double counting.' using errcode='22023';
    end if;

    if cardinality(source_ids)>0 then
      select coalesce(array_agg(distinct x),array[]::uuid[])
      into seen_ids
      from unnest(seen_ids||source_ids) x;
    end if;

    total_value:=total_value+coalesce((source_summary->>'total')::numeric,0);
    matched_count:=matched_count+coalesce((source_summary->>'matched_count')::integer,0);
    source_results:=source_results||jsonb_build_array(jsonb_build_object(
      'label',source_label,
      'rule_set_id',source_rule_set_id,
      'value_field',source_value_field,
      'total',coalesce((source_summary->>'total')::numeric,0),
      'matched_count',coalesce((source_summary->>'matched_count')::integer,0)
    ));
  end loop;

  return jsonb_build_object('total',total_value,'matched_count',matched_count,'sources',source_results);
end;
$$;

revoke all on function private.compute_comp_metric_sources_summary(uuid,jsonb,date,date) from public,anon,authenticated;

create or replace function private.normalize_comp_aggregate_configuration()
returns trigger
language plpgsql
set search_path=''
as $$
declare
  cfg jsonb:=coalesce(new.rule_configuration,'{}'::jsonb);
  old_cfg jsonb:='{}'::jsonb;
  incoming_agg jsonb:=coalesce(cfg->'aggregate','{}'::jsonb);
  old_agg jsonb:='{}'::jsonb;
  use_legacy boolean:=false;
  sources jsonb;
  metric_sources jsonb:='[]'::jsonb;
  baseline numeric;
  benchmark numeric;
  payout numeric;
  comparison_key text;
  period_key text;
  qualification_rule_set_id text;
  value_field text;
begin
  if tg_op='UPDATE' then
    old_cfg:=coalesce(old.rule_configuration,'{}'::jsonb);
    old_agg:=coalesce(old_cfg->'aggregate','{}'::jsonb);
  end if;

  if new.measurement_source<>'book_of_business' or new.calculation_type<>'threshold_bonus' then return new; end if;

  if tg_op='UPDATE' then
    use_legacy:=incoming_agg=old_agg and (
      cfg->'aggregate_component_codes' is distinct from old_cfg->'aggregate_component_codes'
      or cfg->>'aggregate_fixed_uplift' is distinct from old_cfg->>'aggregate_fixed_uplift'
      or cfg->>'threshold_amount' is distinct from old_cfg->>'threshold_amount'
      or cfg->>'bonus_amount' is distinct from old_cfg->>'bonus_amount'
      or cfg->>'comparison' is distinct from old_cfg->>'comparison'
      or new.measurement_period is distinct from old.measurement_period
    );
  end if;

  metric_sources:=case
    when jsonb_typeof(incoming_agg->'metric_sources')='array' then incoming_agg->'metric_sources'
    when jsonb_typeof(old_agg->'metric_sources')='array' then old_agg->'metric_sources'
    else '[]'::jsonb
  end;
  qualification_rule_set_id:=coalesce(nullif(incoming_agg->>'qualification_rule_set_id',''),nullif(old_agg->>'qualification_rule_set_id',''));
  value_field:=coalesce(nullif(incoming_agg->>'value_field',''),nullif(old_agg->>'value_field',''),'amount');

  if use_legacy then
    sources:=coalesce(cfg->'aggregate_component_codes','[]'::jsonb);
    baseline:=coalesce(nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
    benchmark:=nullif(cfg->>'threshold_amount','')::numeric;
    payout:=nullif(cfg->>'bonus_amount','')::numeric;
    comparison_key:=coalesce(nullif(cfg->>'comparison',''),'greater_than');
    period_key:=coalesce(nullif(new.measurement_period,''),'annual');
  else
    sources:=coalesce(incoming_agg->'source_component_codes',cfg->'aggregate_component_codes','[]'::jsonb);
    baseline:=coalesce(nullif(incoming_agg->>'baseline_amount','')::numeric,nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
    benchmark:=coalesce(nullif(incoming_agg->>'benchmark_amount','')::numeric,nullif(cfg->>'threshold_amount','')::numeric);
    payout:=coalesce(nullif(incoming_agg->>'payout_amount','')::numeric,nullif(cfg->>'bonus_amount','')::numeric);
    comparison_key:=coalesce(nullif(incoming_agg->>'comparison',''),nullif(cfg->>'comparison',''),'greater_than');
    period_key:=coalesce(nullif(incoming_agg->>'period',''),nullif(new.measurement_period,''),'annual');
  end if;

  cfg:=jsonb_set(cfg,'{aggregate_component_codes}',coalesce(sources,'[]'::jsonb),true);
  cfg:=jsonb_set(cfg,'{aggregate_fixed_uplift}',to_jsonb(coalesce(baseline,0)),true);
  if benchmark is not null then cfg:=jsonb_set(cfg,'{threshold_amount}',to_jsonb(benchmark),true); end if;
  if payout is not null then cfg:=jsonb_set(cfg,'{bonus_amount}',to_jsonb(payout),true); end if;
  cfg:=jsonb_set(cfg,'{comparison}',to_jsonb(comparison_key),true);
  cfg:=jsonb_set(cfg,'{aggregate}',jsonb_build_object(
    'function','sum',
    'period',period_key,
    'source_component_codes',coalesce(sources,'[]'::jsonb),
    'metric_sources',metric_sources,
    'baseline_amount',coalesce(baseline,0),
    'benchmark_amount',benchmark,
    'comparison',comparison_key,
    'payout_amount',payout,
    'qualification_rule_set_id',qualification_rule_set_id,
    'value_field',value_field
  ),true);

  new.rule_configuration:=cfg;
  new.measurement_period:=period_key;
  return new;
end;
$$;

revoke all on function private.normalize_comp_aggregate_configuration() from public,anon,authenticated;

alter function private.compute_comp_component_attainment(uuid,uuid,integer)
  rename to compute_comp_component_attainment_pre_multi_metric_sources;

create or replace function private.compute_comp_component_attainment(target_component_id uuid,target_employee_id uuid,target_year integer)
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  c public.comp_plan_components%rowtype;
  cfg jsonb;
  agg jsonb;
  metric_sources jsonb;
  source_summary jsonb;
  baseline numeric:=0;
  threshold_value numeric:=0;
  bonus_value numeric:=0;
  source_total numeric:=0;
  total_value numeric:=0;
  attainment numeric:=0;
  comparison_key text;
  met boolean:=false;
  version_status text;
  plan_start date;
  plan_end date;
  assignment_start date;
  assignment_end date;
  period_start date;
  period_end date;
begin
  select * into c from public.comp_plan_components where id=target_component_id;
  if c.id is null then raise exception 'Earning Type not found'; end if;
  cfg:=coalesce(c.rule_configuration,'{}'::jsonb);
  agg:=coalesce(cfg->'aggregate','{}'::jsonb);
  metric_sources:=case when jsonb_typeof(agg->'metric_sources')='array' then agg->'metric_sources' else '[]'::jsonb end;

  if jsonb_array_length(metric_sources)=0 then
    return private.compute_comp_component_attainment_pre_multi_metric_sources(target_component_id,target_employee_id,target_year);
  end if;

  select pv.status::text,pv.effective_start_date,pv.effective_end_date
  into version_status,plan_start,plan_end
  from public.comp_plan_versions pv where pv.id=c.plan_version_id;

  if version_status='draft' then
    select effective_start_date,effective_end_date into assignment_start,assignment_end
    from public.comp_plan_draft_assignments
    where plan_version_id=c.plan_version_id and employee_id=target_employee_id limit 1;
  else
    select effective_start_date,effective_end_date into assignment_start,assignment_end
    from public.employee_plan_assignments
    where plan_version_id=c.plan_version_id and employee_id=target_employee_id limit 1;
  end if;

  period_start:=greatest(make_date(target_year,1,1),coalesce(plan_start,make_date(target_year,1,1)),coalesce(assignment_start,make_date(target_year,1,1)));
  period_end:=least(make_date(target_year,12,31),coalesce(plan_end,make_date(target_year,12,31)),coalesce(assignment_end,make_date(target_year,12,31)));

  source_summary:=private.compute_comp_metric_sources_summary(target_component_id,metric_sources,period_start,period_end);
  source_total:=coalesce((source_summary->>'total')::numeric,0);
  baseline:=coalesce(nullif(agg->>'baseline_amount','')::numeric,nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
  threshold_value:=coalesce(nullif(agg->>'benchmark_amount','')::numeric,nullif(cfg->>'threshold_amount','')::numeric,0);
  bonus_value:=coalesce(nullif(agg->>'payout_amount','')::numeric,nullif(cfg->>'bonus_amount','')::numeric,0);
  comparison_key:=coalesce(nullif(agg->>'comparison',''),nullif(cfg->>'comparison',''),'greater_than');
  total_value:=source_total+baseline;
  attainment:=case when threshold_value>0 then round((total_value/threshold_value)*100,2) else 0 end;
  met:=case comparison_key when 'greater_than_or_equal' then total_value>=threshold_value when 'equal' then total_value=threshold_value else total_value>threshold_value end;

  return jsonb_build_object(
    'component_id',target_component_id,'employee_id',target_employee_id,'year',target_year,
    'source_mode','metric_sources','metric_sources',coalesce(source_summary->'sources','[]'::jsonb),
    'source_total',source_total,'baseline_amount',baseline,'measurement_value',total_value,
    'threshold',threshold_value,'attainment_percent',attainment,'threshold_met',met,
    'bonus_amount',bonus_value,'comparison',comparison_key,'metric_key','book_of_business',
    'period_start',period_start,'period_end',period_end
  );
end;
$$;

revoke all on function private.compute_comp_component_attainment(uuid,uuid,integer) from public,anon,authenticated;

alter function public.preview_comp_component_aggregate(uuid,date)
  rename to preview_comp_component_aggregate_pre_multi_metric_sources;

create or replace function public.preview_comp_component_aggregate(target_component_id uuid,selected_measurement_date date default current_date)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  component_row record;
  agg jsonb;
  metric_sources jsonb;
  period_key text;
  period_start date;
  period_end date;
  baseline numeric;
  benchmark numeric;
  rows_json jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not ((coalesce(access->'permissions','[]'::jsonb)?'plans.view') or (coalesce(access->'permissions','[]'::jsonb)?'plans.edit')) then
    raise exception 'Not authorized to preview compensation aggregates' using errcode='42501';
  end if;

  select c.id,c.plan_version_id,c.name,c.component_code,c.calculation_type,c.measurement_period,c.rule_configuration,
         pv.status::text version_status,pv.effective_start_date,pv.effective_end_date
  into component_row
  from public.comp_plan_components c join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where c.id=target_component_id;
  if component_row.id is null then raise exception 'Earning Type not found' using errcode='P0002'; end if;

  agg:=coalesce(component_row.rule_configuration->'aggregate','{}'::jsonb);
  metric_sources:=case when jsonb_typeof(agg->'metric_sources')='array' then agg->'metric_sources' else '[]'::jsonb end;
  if jsonb_array_length(metric_sources)=0 then
    return public.preview_comp_component_aggregate_pre_multi_metric_sources(target_component_id,selected_measurement_date);
  end if;

  period_key:=coalesce(nullif(agg->>'period',''),nullif(component_row.measurement_period,''),'annual');
  baseline:=coalesce(nullif(agg->>'baseline_amount','')::numeric,0);
  benchmark:=coalesce(nullif(agg->>'benchmark_amount','')::numeric,nullif(component_row.rule_configuration->>'threshold_amount','')::numeric);
  if period_key='monthly' then
    period_start:=date_trunc('month',selected_measurement_date)::date;
    period_end:=(date_trunc('month',selected_measurement_date)+interval '1 month-1 day')::date;
  elsif period_key='quarterly' then
    period_start:=date_trunc('quarter',selected_measurement_date)::date;
    period_end:=(date_trunc('quarter',selected_measurement_date)+interval '3 months-1 day')::date;
  else
    period_key:='annual';
    period_start:=date_trunc('year',selected_measurement_date)::date;
    period_end:=(date_trunc('year',selected_measurement_date)+interval '1 year-1 day')::date;
  end if;

  with assigned as (
    select da.employee_id,e.full_name,da.effective_start_date,da.effective_end_date
    from public.comp_plan_draft_assignments da join public.employees e on e.id=da.employee_id
    where component_row.version_status='draft' and da.plan_version_id=component_row.plan_version_id
    union all
    select a.employee_id,e.full_name,a.effective_start_date,a.effective_end_date
    from public.employee_plan_assignments a join public.employees e on e.id=a.employee_id
    where component_row.version_status<>'draft' and a.plan_version_id=component_row.plan_version_id
      and period_end>=a.effective_start_date and period_start<=coalesce(a.effective_end_date,'infinity'::date)
  ), measured as (
    select a.*,
      greatest(period_start,component_row.effective_start_date,a.effective_start_date) employee_period_start,
      least(period_end,coalesce(component_row.effective_end_date,period_end),coalesce(a.effective_end_date,period_end)) employee_period_end
    from assigned a
  ), summarized as (
    select m.*,private.compute_comp_metric_sources_summary(target_component_id,metric_sources,m.employee_period_start,m.employee_period_end) source_summary
    from measured m
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'employee_id',s.employee_id,'employee_name',s.full_name,
    'period_start',s.employee_period_start,'period_end',s.employee_period_end,
    'qualifying_total',coalesce((s.source_summary->>'total')::numeric,0),
    'qualifying_record_count',coalesce((s.source_summary->>'matched_count')::integer,0),
    'metric_sources',coalesce(s.source_summary->'sources','[]'::jsonb),
    'baseline_amount',baseline,
    'attainment_value',coalesce((s.source_summary->>'total')::numeric,0)+baseline,
    'benchmark_amount',benchmark,
    'attainment_percent',case when benchmark is null or benchmark=0 then null else round(((coalesce((s.source_summary->>'total')::numeric,0)+baseline)/benchmark)*100,2) end,
    'metric_key','book_of_business','source_mode','metric_sources',
    'calculation',public.evaluate_compensation_rule(component_row.calculation_type,component_row.rule_configuration,coalesce((s.source_summary->>'total')::numeric,0)+baseline,null,null,selected_measurement_date)
  ) order by s.full_name),'[]'::jsonb)
  into rows_json from summarized s;

  return jsonb_build_object(
    'component_id',component_row.id,'component_name',component_row.name,'component_code',component_row.component_code,
    'plan_version_id',component_row.plan_version_id,'plan_status',component_row.version_status,
    'period',period_key,'period_start',period_start,'period_end',period_end,'measurement_date',selected_measurement_date,
    'source_mode','metric_sources','metric_sources',metric_sources,
    'baseline_amount',baseline,'benchmark_amount',benchmark,'metric_key','book_of_business','rows',rows_json
  );
end;
$$;

grant execute on function public.preview_comp_component_aggregate(uuid,date) to authenticated;
revoke all on function public.preview_comp_component_aggregate(uuid,date) from public,anon;

alter function public.validate_compensation_plan_version_readiness(uuid)
  rename to validate_compensation_plan_version_readiness_pre_multi_metric_sources;

create or replace function public.validate_compensation_plan_version_readiness(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  base jsonb;
  blockers jsonb;
  warnings jsonb;
  c record;
  agg jsonb;
  metric_sources jsonb;
  source jsonb;
  source_rule_set_id uuid;
  source_value_field text;
  source_label text;
begin
  base:=public.validate_compensation_plan_version_readiness_pre_multi_metric_sources(selected_plan_version_id);

  select coalesce(jsonb_agg(b),'[]'::jsonb)
  into blockers
  from jsonb_array_elements(coalesce(base->'blockers','[]'::jsonb)) b
  where not (
    b->>'code' in ('missing_metric_qualification','invalid_metric_value_field')
    and exists(
      select 1 from public.comp_plan_components pc
      where pc.id=nullif(b->>'component_id','')::uuid
        and jsonb_typeof(pc.rule_configuration->'aggregate'->'metric_sources')='array'
        and jsonb_array_length(pc.rule_configuration->'aggregate'->'metric_sources')>0
    )
  );

  select coalesce(jsonb_agg(w),'[]'::jsonb)
  into warnings
  from jsonb_array_elements(coalesce(base->'warnings','[]'::jsonb)) w
  where not (
    w->>'code'='legacy_aggregate_sources'
    and exists(
      select 1 from public.comp_plan_components pc
      where pc.id=nullif(w->>'component_id','')::uuid
        and jsonb_typeof(pc.rule_configuration->'aggregate'->'metric_sources')='array'
        and jsonb_array_length(pc.rule_configuration->'aggregate'->'metric_sources')>0
    )
  );

  for c in
    select id,name,rule_configuration
    from public.comp_plan_components
    where plan_version_id=selected_plan_version_id
      and is_active=true
      and measurement_source='book_of_business'
      and calculation_type='threshold_bonus'
  loop
    agg:=coalesce(c.rule_configuration->'aggregate','{}'::jsonb);
    metric_sources:=case when jsonb_typeof(agg->'metric_sources')='array' then agg->'metric_sources' else '[]'::jsonb end;
    if jsonb_array_length(metric_sources)>0 then
      for source in select value from jsonb_array_elements(metric_sources)
      loop
        source_rule_set_id:=nullif(source->>'rule_set_id','')::uuid;
        source_value_field:=coalesce(nullif(source->>'value_field',''),'amount');
        source_label:=coalesce(nullif(source->>'label',''),'Metric source');

        if source_rule_set_id is null or not exists(
          select 1 from public.comp_rule_sets rs
          where rs.id=source_rule_set_id and rs.plan_component_id=c.id and rs.purpose='metric_qualification'
        ) then
          blockers:=blockers||jsonb_build_array(jsonb_build_object(
            'code','invalid_metric_source_rule','section','earned','component_id',c.id,'component_name',c.name,
            'message',format('%s: %s needs a Metric Qualification rule that belongs to this Earning Type.',c.name,source_label)
          ));
        elsif not exists(select 1 from public.comp_rule_expression_nodes n where n.rule_set_id=source_rule_set_id and n.parent_node_id is null) then
          blockers:=blockers||jsonb_build_array(jsonb_build_object(
            'code','empty_metric_source_rule','section','earned','component_id',c.id,'component_name',c.name,
            'message',format('%s: %s needs at least one qualification condition.',c.name,source_label)
          ));
        elsif not exists(
          select 1 from public.comp_rule_set_preview_runs pr
          join public.comp_rule_sets rs on rs.id=pr.rule_set_id
          where pr.rule_set_id=source_rule_set_id and pr.supported=true and pr.rule_updated_at=rs.updated_at
        ) then
          blockers:=blockers||jsonb_build_array(jsonb_build_object(
            'code','metric_source_needs_preview','section','earned','component_id',c.id,'component_name',c.name,
            'message',format('Preview %s: %s against current HubSpot data before approval.',c.name,source_label)
          ));
        end if;

        if not public.is_comp_metric_numeric_value_field(source_value_field) then
          blockers:=blockers||jsonb_build_array(jsonb_build_object(
            'code','invalid_metric_source_value_field','section','earning_types','component_id',c.id,'component_name',c.name,
            'message',format('%s: %s needs an available numeric Deal field to sum.',c.name,source_label)
          ));
        end if;
      end loop;
    end if;
  end loop;

  base:=jsonb_set(base,'{blockers}',blockers);
  base:=jsonb_set(base,'{warnings}',warnings);
  base:=jsonb_set(base,'{blocker_count}',to_jsonb(jsonb_array_length(blockers)));
  base:=jsonb_set(base,'{warning_count}',to_jsonb(jsonb_array_length(warnings)));
  base:=jsonb_set(base,'{ready}',to_jsonb(jsonb_array_length(blockers)=0));
  return base;
end;
$$;

revoke all on function public.validate_compensation_plan_version_readiness(uuid) from public,anon;
grant execute on function public.validate_compensation_plan_version_readiness(uuid) to authenticated;
