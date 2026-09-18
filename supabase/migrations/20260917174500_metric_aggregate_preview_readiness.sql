-- Align aggregate preview and readiness with Metric Qualification as the primary source model.

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
  qualification_rule_set_id uuid;
  value_field text;
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
  from public.comp_plan_components c
  join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where c.id=target_component_id;
  if component_row.id is null then raise exception 'Earning Type not found' using errcode='P0002'; end if;

  aggregate_config:=coalesce(component_row.rule_configuration->'aggregate','{}'::jsonb);
  source_codes:=coalesce(aggregate_config->'source_component_codes','[]'::jsonb);
  period_key:=coalesce(nullif(aggregate_config->>'period',''),nullif(component_row.measurement_period,''),'annual');
  baseline_amount:=coalesce(nullif(aggregate_config->>'baseline_amount','')::numeric,0);
  benchmark_amount:=coalesce(nullif(aggregate_config->>'benchmark_amount','')::numeric,nullif(component_row.rule_configuration->>'threshold_amount','')::numeric);
  qualification_rule_set_id:=nullif(aggregate_config->>'qualification_rule_set_id','')::uuid;
  value_field:=coalesce(nullif(aggregate_config->>'value_field',''),'amount');

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

  if qualification_rule_set_id is not null then
    if not exists(
      select 1 from public.comp_rule_sets rs
      where rs.id=qualification_rule_set_id
        and rs.plan_component_id=target_component_id
        and rs.purpose='metric_qualification'
    ) then
      raise exception 'Metric qualification rule is missing or belongs to another Earning Type' using errcode='22023';
    end if;

    with assigned as (
      select da.employee_id,e.full_name,da.effective_start_date,da.effective_end_date
      from public.comp_plan_draft_assignments da
      join public.employees e on e.id=da.employee_id
      where component_row.version_status='draft' and da.plan_version_id=component_row.plan_version_id
      union all
      select a.employee_id,e.full_name,a.effective_start_date,a.effective_end_date
      from public.employee_plan_assignments a
      join public.employees e on e.id=a.employee_id
      where component_row.version_status<>'draft' and a.plan_version_id=component_row.plan_version_id
        and period_end>=a.effective_start_date
        and period_start<=coalesce(a.effective_end_date,'infinity'::date)
    ), measured as (
      select a.employee_id,a.full_name,
             greatest(period_start,component_row.effective_start_date,a.effective_start_date) as employee_period_start,
             least(period_end,coalesce(component_row.effective_end_date,'infinity'::date),coalesce(a.effective_end_date,'infinity'::date)) as employee_period_end
      from assigned a
    ), summarized as (
      select m.*,
             private.compute_comp_metric_rule_summary(
               qualification_rule_set_id,
               value_field,
               m.employee_period_start,
               m.employee_period_end
             ) as metric_summary
      from measured m
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'employee_id',s.employee_id,
      'employee_name',s.full_name,
      'period_start',s.employee_period_start,
      'period_end',s.employee_period_end,
      'qualifying_total',coalesce((s.metric_summary->>'total')::numeric,0),
      'baseline_amount',baseline_amount,
      'attainment_value',coalesce((s.metric_summary->>'total')::numeric,0)+baseline_amount,
      'benchmark_amount',benchmark_amount,
      'attainment_percent',case when benchmark_amount is null or benchmark_amount=0 then null else round(((coalesce((s.metric_summary->>'total')::numeric,0)+baseline_amount)/benchmark_amount)*100,2) end,
      'qualifying_record_count',coalesce((s.metric_summary->>'matched_count')::integer,0),
      'metric_key','book_of_business',
      'source_mode','metric_rule',
      'qualification_rule_set_id',qualification_rule_set_id,
      'value_field',value_field,
      'calculation',public.evaluate_compensation_rule(component_row.calculation_type,component_row.rule_configuration,coalesce((s.metric_summary->>'total')::numeric,0)+baseline_amount,null,null,selected_measurement_date)
    ) order by s.full_name),'[]'::jsonb)
    into rows_json
    from summarized s;

    return jsonb_build_object(
      'component_id',component_row.id,'component_name',component_row.name,'component_code',component_row.component_code,
      'plan_version_id',component_row.plan_version_id,'plan_status',component_row.version_status,
      'period',period_key,'period_start',period_start,'period_end',period_end,'measurement_date',selected_measurement_date,
      'source_mode','metric_rule','qualification_rule_set_id',qualification_rule_set_id,'value_field',value_field,
      'source_component_codes',source_codes,'baseline_amount',baseline_amount,'benchmark_amount',benchmark_amount,
      'metric_key','book_of_business','rows',rows_json
    );
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
      'metric_key','book_of_business','source_mode','legacy_components',
      'calculation',public.evaluate_compensation_rule(component_row.calculation_type,component_row.rule_configuration,t.qualifying_total+baseline_amount,null,null,selected_measurement_date)
    ) order by t.full_name),'[]'::jsonb)
  into rows_json from totals t;

  return jsonb_build_object(
    'component_id',component_row.id,'component_name',component_row.name,'component_code',component_row.component_code,
    'plan_version_id',component_row.plan_version_id,'plan_status',component_row.version_status,
    'period',period_key,'period_start',period_start,'period_end',period_end,'measurement_date',selected_measurement_date,
    'source_mode','legacy_components','source_component_codes',source_codes,'baseline_amount',baseline_amount,'benchmark_amount',benchmark_amount,
    'metric_key','book_of_business','rows',rows_json
  );
end;
$$;

grant execute on function public.preview_comp_component_aggregate(uuid,date) to authenticated;

create or replace function public.validate_compensation_plan_version_readiness(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  base jsonb;
  approval_step_count integer;
  c record;
  blockers jsonb;
  warnings jsonb;
  agg jsonb;
  source_codes jsonb;
  metric_rule_id uuid;
  metric_value_field text;
begin
  base:=public.validate_compensation_plan_version_readiness_core(selected_plan_version_id);

  select coalesce(jsonb_agg(b),'[]'::jsonb) into blockers
  from jsonb_array_elements(coalesce(base->'blockers','[]'::jsonb)) b
  where not (
    (
      b->>'code' in ('missing_earned_rule','earned_rule_needs_preview')
      and exists(
        select 1 from public.comp_plan_components pc
        where pc.id=nullif(b->>'component_id','')::uuid
          and (
            (pc.measurement_source='book_of_business' and pc.calculation_type='threshold_bonus')
            or exists(select 1 from public.comp_component_deal_rules dr where dr.plan_component_id=pc.id and dr.is_active=true and dr.marks_earned=true)
          )
      )
    )
    or
    (
      b->>'code'='missing_eligibility'
      and exists(
        select 1 from public.comp_plan_components pc
        where pc.id=nullif(b->>'component_id','')::uuid
          and (
            (pc.measurement_source='book_of_business' and pc.calculation_type='threshold_bonus')
            or coalesce((pc.rule_configuration->>'requires_invoice_paid_date')::boolean,false)=true
            or pc.rule_configuration->>'eligibility_condition' in ('paid_stage_and_invoice_paid_date','invoice_paid_date','customer_payment_received')
          )
      )
    )
  );

  warnings:=coalesce(base->'warnings','[]'::jsonb);

  select count(*) into approval_step_count
  from public.comp_plan_approval_steps
  where plan_version_id=selected_plan_version_id and is_required=true;
  if approval_step_count=0 then
    blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_approval_steps','section','approvals','message','Configure at least one required approval step for this plan.'));
  end if;

  for c in
    select id,name,measurement_source,calculation_type,rule_configuration
    from public.comp_plan_components
    where plan_version_id=selected_plan_version_id and is_active=true
    order by calculation_order,name
  loop
    if c.measurement_source in ('amount','average_arr','first_year_arr','one_time_fee','total_contract_value') then
      if not exists(select 1 from public.comp_component_deal_rules dr where dr.plan_component_id=c.id and dr.is_active=true and dr.marks_earned=true) then
        blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_deal_source_rules','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs both Deal Type and Deal Stage in its Earned conditions before it can generate earnings.',c.name)));
      elsif not exists(select 1 from public.comp_rule_sets rs where rs.plan_component_id=c.id and rs.purpose='qualification') then
        warnings:=warnings||jsonb_build_array(jsonb_build_object('code','legacy_earned_rules','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s is using valid legacy Earned rules. You can keep them for this plan or open Earned conditions to migrate them to the advanced rule model.',c.name)));
      end if;

      if not exists(select 1 from public.comp_user_attribution_rules ar where ar.plan_component_id=c.id and ar.attribution_purpose='earning' and ar.is_active=true) then
        blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_credit_attribution','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs a HubSpot owner/CEM field so the system knows which employee gets credit.',c.name)));
      end if;

      if coalesce(c.rule_configuration->'eligibility','{}'::jsonb)='{}'::jsonb
         and (coalesce((c.rule_configuration->>'requires_invoice_paid_date')::boolean,false)=true
           or c.rule_configuration->>'eligibility_condition' in ('paid_stage_and_invoice_paid_date','invoice_paid_date','customer_payment_received')) then
        warnings:=warnings||jsonb_build_array(jsonb_build_object('code','legacy_payment_eligibility','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s is using the existing customer-payment eligibility rule. Open payment conditions if you want to migrate it to the configurable business-condition model.',c.name)));
      end if;

    elsif c.measurement_source='book_of_business' and c.calculation_type='threshold_bonus' then
      agg:=coalesce(c.rule_configuration->'aggregate','{}'::jsonb);
      source_codes:=coalesce(agg->'source_component_codes',c.rule_configuration->'aggregate_component_codes','[]'::jsonb);
      metric_rule_id:=nullif(agg->>'qualification_rule_set_id','')::uuid;
      metric_value_field:=coalesce(nullif(agg->>'value_field',''),'amount');

      if metric_rule_id is not null then
        if not exists(
          select 1 from public.comp_rule_sets rs
          where rs.id=metric_rule_id and rs.plan_component_id=c.id and rs.purpose='metric_qualification'
        ) then
          blockers:=blockers||jsonb_build_array(jsonb_build_object('code','invalid_metric_qualification_rule','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s references a Metric Qualification rule that is missing or belongs elsewhere.',c.name)));
        elsif not exists(
          select 1 from public.comp_rule_expression_nodes n
          where n.rule_set_id=metric_rule_id and n.parent_node_id is null
        ) then
          blockers:=blockers||jsonb_build_array(jsonb_build_object('code','empty_metric_qualification_rule','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs at least one Metric Qualification condition.',c.name)));
        end if;

        if metric_value_field not in ('amount','average_arr','first_year_arr','total_contract_value','one_time_fee','new_business_arr','expansion_arr','renewal_arr','non_recurring_revenue') then
          blockers:=blockers||jsonb_build_array(jsonb_build_object('code','invalid_metric_value_field','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s has an unsupported value field for its running total.',c.name)));
        end if;
      elsif jsonb_array_length(source_codes)=0 then
        blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_metric_qualification','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs Metric Qualification conditions that define which HubSpot records count toward the running total.',c.name)));
      else
        warnings:=warnings||jsonb_build_array(jsonb_build_object('code','legacy_aggregate_sources','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s is still using legacy source Earning Types. Open Metric Qualification to migrate it to the configurable HubSpot rule model.',c.name)));
      end if;

      if coalesce(nullif(agg->>'benchmark_amount',''),nullif(c.rule_configuration->>'threshold_amount','')) is null then
        blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_quota','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a quota or benchmark threshold.',c.name)));
      end if;
      if coalesce(nullif(agg->>'payout_amount',''),nullif(c.rule_configuration->>'bonus_amount','')) is null then
        blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_threshold_bonus','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs the bonus paid when the benchmark is exceeded.',c.name)));
      end if;
      warnings:=warnings||jsonb_build_array(jsonb_build_object('code','aggregate_year_end','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s tracks attainment during the year and creates the bonus earning at year end if the benchmark is exceeded.',c.name)));
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
