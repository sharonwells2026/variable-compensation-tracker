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
  component_codes text[];
  source_total numeric:=0;
  baseline numeric:=0;
  total_value numeric:=0;
  threshold_value numeric:=0;
  bonus_value numeric:=0;
  attainment numeric:=0;
  met boolean:=false;
  comparison_key text;
  plan_version uuid;
begin
  select * into c from public.comp_plan_components where id=target_component_id;
  if c.id is null then raise exception 'Earning Type not found'; end if;
  cfg:=coalesce(c.rule_configuration,'{}'::jsonb);
  agg:=coalesce(cfg->'aggregate','{}'::jsonb);
  plan_version:=c.plan_version_id;
  select coalesce(array_agg(value),array[]::text[]) into component_codes
  from jsonb_array_elements_text(coalesce(agg->'source_component_codes',cfg->'aggregate_component_codes','[]'::jsonb));
  baseline:=coalesce(nullif(agg->>'baseline_amount','')::numeric,nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
  threshold_value:=coalesce(nullif(agg->>'benchmark_amount','')::numeric,nullif(cfg->>'threshold_amount','')::numeric,0);
  bonus_value:=coalesce(nullif(agg->>'payout_amount','')::numeric,nullif(cfg->>'bonus_amount','')::numeric,0);
  comparison_key:=coalesce(nullif(agg->>'comparison',''),nullif(cfg->>'comparison',''),'greater_than');

  with source_components as (
    select sc.id,sc.component_code,sc.measurement_source
    from public.comp_plan_components sc
    where sc.plan_version_id=plan_version
      and sc.is_active=true
      and sc.id<>target_component_id
      and sc.component_code=any(component_codes)
  ), raw as (
    select sc.id source_component_id,sc.component_code,d.hubspot_deal_id,
      case sc.measurement_source
        when 'average_arr' then d.average_arr
        when 'first_year_arr' then d.first_year_arr
        when 'one_time_fee' then d.one_time_fee
        when 'total_contract_value' then d.total_contract_value
        else d.amount
      end as source_amount,
      case when exists(
        select 1 from public.comp_user_attribution_rules mr
        where mr.plan_component_id=sc.id and mr.attribution_purpose='metric'
          and mr.metric_key='book_of_business' and mr.is_active=true
      ) then private.resolve_comp_user_attribution(target_employee_id,sc.id,d.hubspot_deal_id,'metric','book_of_business')
      else private.resolve_comp_user_attribution(target_employee_id,sc.id,d.hubspot_deal_id,'earning',null)
      end as attribution
    from source_components sc
    join public.comp_component_deal_rules dr on dr.plan_component_id=sc.id and dr.is_active=true and dr.calculation_action='include' and dr.marks_earned=true
    join public.hubspot_deals d on d.hubspot_pipeline_id=dr.hubspot_pipeline_id and d.hubspot_stage_id=dr.hubspot_stage_id and d.hubspot_deal_type=dr.hubspot_deal_type
    join public.employee_plan_assignments epa on epa.employee_id=target_employee_id and epa.plan_version_id=plan_version
    join public.comp_plan_versions pv on pv.id=plan_version
    where extract(year from d.close_date)::int=target_year
      and d.close_date between greatest(epa.effective_start_date,pv.effective_start_date,dr.effective_start_date)
      and least(coalesce(epa.effective_end_date,'infinity'::date),coalesce(pv.effective_end_date,'infinity'::date),coalesce(dr.effective_end_date,'infinity'::date))
  ), deduped as (
    select source_component_id,hubspot_deal_id,
      max(source_amount * coalesce(nullif(attribution->>'resolved_credit_percentage','')::numeric,100)/100) as credited_source_amount
    from raw
    where coalesce((attribution->>'matched')::boolean,false)=true and source_amount is not null
    group by source_component_id,hubspot_deal_id
  )
  select coalesce(sum(credited_source_amount),0) into source_total from deduped;

  total_value:=source_total+baseline;
  attainment:=case when threshold_value>0 then round((total_value/threshold_value)*100,2) else 0 end;
  met:=case comparison_key when 'greater_than_or_equal' then total_value>=threshold_value when 'equal' then total_value=threshold_value else total_value>threshold_value end;
  return jsonb_build_object('component_id',target_component_id,'employee_id',target_employee_id,'year',target_year,'source_component_codes',to_jsonb(component_codes),'source_total',source_total,'baseline_amount',baseline,'measurement_value',total_value,'threshold',threshold_value,'attainment_percent',attainment,'threshold_met',met,'bonus_amount',bonus_value,'comparison',comparison_key,'metric_key','book_of_business');
end;
$$;

revoke all on function private.compute_comp_component_attainment(uuid,uuid,integer) from public,anon,authenticated;

create or replace function public.preview_comp_component_aggregate(
  target_component_id uuid,
  selected_measurement_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  access jsonb;
  component_row record;
  aggregate_config jsonb;
  source_codes jsonb;
  period_key text;
  period_start date;
  period_end date;
  baseline_amount numeric;
  benchmark_amount numeric;
  rows_json jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not ((coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') or (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit')) then
    raise exception 'Not authorized to preview compensation aggregates' using errcode='42501';
  end if;

  select c.id,c.plan_version_id,c.name,c.component_code,c.calculation_type,c.measurement_period,c.rule_configuration,
         pv.status::text as version_status,pv.effective_start_date,pv.effective_end_date
  into component_row
  from public.comp_plan_components c join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where c.id=target_component_id;
  if component_row.id is null then raise exception 'Earning Type not found' using errcode='P0002'; end if;

  aggregate_config:=coalesce(component_row.rule_configuration->'aggregate','{}'::jsonb);
  source_codes:=coalesce(aggregate_config->'source_component_codes','[]'::jsonb);
  period_key:=coalesce(nullif(aggregate_config->>'period',''),nullif(component_row.measurement_period,''),'annual');
  baseline_amount:=coalesce(nullif(aggregate_config->>'baseline_amount','')::numeric,0);
  benchmark_amount:=coalesce(nullif(aggregate_config->>'benchmark_amount','')::numeric,nullif(component_row.rule_configuration->>'threshold_amount','')::numeric);

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
      and selected_measurement_date between a.effective_start_date and coalesce(a.effective_end_date,'infinity'::date)
  ), source_components as (
    select c.id,c.component_code,c.name,c.measurement_source
    from public.comp_plan_components c
    where c.plan_version_id=component_row.plan_version_id and c.is_active and c.id<>target_component_id
      and source_codes ? c.component_code
  ), raw_matches as (
    select a.employee_id,a.full_name,sc.id as source_component_id,sc.component_code,sc.name as source_component_name,
           d.hubspot_deal_id,d.deal_name,d.close_date,
           case sc.measurement_source
             when 'average_arr' then d.average_arr
             when 'first_year_arr' then d.first_year_arr
             when 'one_time_fee' then d.one_time_fee
             when 'total_contract_value' then d.total_contract_value
             else d.amount
           end as source_amount,
           case when exists(
             select 1 from public.comp_user_attribution_rules mr
             where mr.plan_component_id=sc.id and mr.attribution_purpose='metric'
               and mr.metric_key='book_of_business' and mr.is_active=true
           ) then private.resolve_comp_user_attribution(a.employee_id,sc.id,d.hubspot_deal_id,'metric','book_of_business')
           else private.resolve_comp_user_attribution(a.employee_id,sc.id,d.hubspot_deal_id,'earning',null)
           end as attribution
    from assigned a
    join source_components sc on true
    join public.comp_component_deal_rules dr on dr.plan_component_id=sc.id and dr.is_active and dr.calculation_action='include' and dr.marks_earned
    join public.hubspot_deals d on d.hubspot_pipeline_id=dr.hubspot_pipeline_id and d.hubspot_stage_id=dr.hubspot_stage_id and d.hubspot_deal_type=dr.hubspot_deal_type
    where d.close_date between greatest(period_start,component_row.effective_start_date,a.effective_start_date,coalesce(dr.effective_start_date,period_start))
      and least(period_end,coalesce(component_row.effective_end_date,'infinity'::date),coalesce(a.effective_end_date,'infinity'::date),coalesce(dr.effective_end_date,'infinity'::date))
  ), deduped as (
    select distinct on(employee_id,source_component_id,hubspot_deal_id)
      employee_id,full_name,source_component_id,component_code,source_component_name,hubspot_deal_id,deal_name,close_date,
      source_amount * coalesce(nullif(attribution->>'resolved_credit_percentage','')::numeric,100)/100 as source_amount
    from raw_matches
    where coalesce((attribution->>'matched')::boolean,false)=true
    order by employee_id,source_component_id,hubspot_deal_id,close_date desc
  ), totals as (
    select a.employee_id,a.full_name,
           coalesce(sum(d.source_amount),0) as qualifying_total,
           count(d.hubspot_deal_id) as qualifying_record_count
    from assigned a left join deduped d on d.employee_id=a.employee_id
    group by a.employee_id,a.full_name
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'employee_id',t.employee_id,'employee_name',t.full_name,'period_start',period_start,'period_end',period_end,
      'qualifying_total',t.qualifying_total,'baseline_amount',baseline_amount,
      'attainment_value',t.qualifying_total+baseline_amount,'benchmark_amount',benchmark_amount,
      'attainment_percent',case when benchmark_amount is null or benchmark_amount=0 then null else round(((t.qualifying_total+baseline_amount)/benchmark_amount)*100,2) end,
      'qualifying_record_count',t.qualifying_record_count,
      'metric_key','book_of_business',
      'calculation',public.evaluate_compensation_rule(component_row.calculation_type,component_row.rule_configuration,t.qualifying_total+baseline_amount,null,null,selected_measurement_date)
    ) order by t.full_name),'[]'::jsonb)
  into rows_json from totals t;

  return jsonb_build_object(
    'component_id',component_row.id,'component_name',component_row.name,'component_code',component_row.component_code,
    'plan_version_id',component_row.plan_version_id,'plan_status',component_row.version_status,
    'period',period_key,'period_start',period_start,'period_end',period_end,'measurement_date',selected_measurement_date,
    'source_component_codes',source_codes,'baseline_amount',baseline_amount,'benchmark_amount',benchmark_amount,
    'metric_key','book_of_business','rows',rows_json
  );
end;
$$;

grant execute on function public.preview_comp_component_aggregate(uuid,date) to authenticated;
