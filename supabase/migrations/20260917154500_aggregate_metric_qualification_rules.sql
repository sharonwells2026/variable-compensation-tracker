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
  row_value numeric;
begin
  if target_rule_set_id is null then
    return jsonb_build_object('total',0,'matched_count',0,'value_field',selected_value_field);
  end if;
  if selected_start_date is null or selected_end_date is null or selected_end_date<selected_start_date then
    return jsonb_build_object('total',0,'matched_count',0,'value_field',selected_value_field);
  end if;
  if selected_value_field not in ('amount','average_arr','first_year_arr','total_contract_value','one_time_fee','new_business_arr','expansion_arr','renewal_arr','non_recurring_revenue') then
    raise exception 'Unsupported aggregate value field: %',selected_value_field using errcode='22023';
  end if;

  select n.id into root_id
  from public.comp_rule_expression_nodes n
  where n.rule_set_id=target_rule_set_id and n.parent_node_id is null
  limit 1;
  if root_id is null then raise exception 'Metric qualification rule has no root expression' using errcode='22023'; end if;

  for d in
    select id,amount,average_arr,first_year_arr,total_contract_value,one_time_fee,
           new_business_arr,expansion_arr,renewal_arr,non_recurring_revenue
    from public.hubspot_deals
    where close_date between selected_start_date and selected_end_date
  loop
    if public.comp_rule_evaluate_deal_node(root_id,d.id) then
      row_value:=case selected_value_field
        when 'average_arr' then d.average_arr
        when 'first_year_arr' then d.first_year_arr
        when 'total_contract_value' then d.total_contract_value
        when 'one_time_fee' then d.one_time_fee
        when 'new_business_arr' then d.new_business_arr
        when 'expansion_arr' then d.expansion_arr
        when 'renewal_arr' then d.renewal_arr
        when 'non_recurring_revenue' then d.non_recurring_revenue
        else d.amount
      end;
      total_value:=total_value+coalesce(row_value,0);
      matched_count:=matched_count+1;
    end if;
  end loop;

  return jsonb_build_object('total',total_value,'matched_count',matched_count,'value_field',selected_value_field);
end;
$$;

revoke all on function private.compute_comp_metric_rule_summary(uuid,text,date,date) from public,anon,authenticated;

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

  if use_legacy then
    sources:=coalesce(cfg->'aggregate_component_codes','[]'::jsonb);
    baseline:=coalesce(nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
    benchmark:=nullif(cfg->>'threshold_amount','')::numeric;
    payout:=nullif(cfg->>'bonus_amount','')::numeric;
    comparison_key:=coalesce(nullif(cfg->>'comparison',''),'greater_than');
    period_key:=coalesce(nullif(new.measurement_period,''),'annual');
    qualification_rule_set_id:=nullif(incoming_agg->>'qualification_rule_set_id','');
    value_field:=coalesce(nullif(incoming_agg->>'value_field',''),'amount');
  else
    sources:=coalesce(incoming_agg->'source_component_codes',cfg->'aggregate_component_codes','[]'::jsonb);
    baseline:=coalesce(nullif(incoming_agg->>'baseline_amount','')::numeric,nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
    benchmark:=coalesce(nullif(incoming_agg->>'benchmark_amount','')::numeric,nullif(cfg->>'threshold_amount','')::numeric);
    payout:=coalesce(nullif(incoming_agg->>'payout_amount','')::numeric,nullif(cfg->>'bonus_amount','')::numeric);
    comparison_key:=coalesce(nullif(incoming_agg->>'comparison',''),nullif(cfg->>'comparison',''),'greater_than');
    period_key:=coalesce(nullif(incoming_agg->>'period',''),nullif(new.measurement_period,''),'annual');
    qualification_rule_set_id:=nullif(incoming_agg->>'qualification_rule_set_id','');
    value_field:=coalesce(nullif(incoming_agg->>'value_field',''),'amount');
  end if;

  cfg:=jsonb_set(cfg,'{aggregate_component_codes}',coalesce(sources,'[]'::jsonb),true);
  cfg:=jsonb_set(cfg,'{aggregate_fixed_uplift}',to_jsonb(coalesce(baseline,0)),true);
  if benchmark is not null then cfg:=jsonb_set(cfg,'{threshold_amount}',to_jsonb(benchmark),true); end if;
  if payout is not null then cfg:=jsonb_set(cfg,'{bonus_amount}',to_jsonb(payout),true); end if;
  cfg:=jsonb_set(cfg,'{comparison}',to_jsonb(comparison_key),true);
  cfg:=jsonb_set(cfg,'{aggregate}',jsonb_build_object(
    'function','sum','period',period_key,'source_component_codes',coalesce(sources,'[]'::jsonb),
    'baseline_amount',coalesce(baseline,0),'benchmark_amount',benchmark,'comparison',comparison_key,'payout_amount',payout,
    'qualification_rule_set_id',qualification_rule_set_id,'value_field',value_field
  ),true);
  new.rule_configuration:=cfg;
  new.measurement_period:=period_key;
  return new;
end;
$$;

revoke all on function private.normalize_comp_aggregate_configuration() from public,anon,authenticated;

create or replace function private.compute_comp_component_attainment(target_component_id uuid,target_employee_id uuid,target_year integer)
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  c public.comp_plan_components%rowtype;
  cfg jsonb; agg jsonb; component_codes text[];
  source_total numeric:=0; baseline numeric:=0; total_value numeric:=0; threshold_value numeric:=0; bonus_value numeric:=0; attainment numeric:=0;
  met boolean:=false; comparison_key text; plan_version uuid; version_status text;
  plan_start date; plan_end date; assignment_start date; assignment_end date; period_start date; period_end date;
  qualification_rule_set_id uuid; value_field text; metric_summary jsonb;
begin
  select * into c from public.comp_plan_components where id=target_component_id;
  if c.id is null then raise exception 'Earning Type not found'; end if;
  cfg:=coalesce(c.rule_configuration,'{}'::jsonb); agg:=coalesce(cfg->'aggregate','{}'::jsonb); plan_version:=c.plan_version_id;
  select pv.status::text,pv.effective_start_date,pv.effective_end_date into version_status,plan_start,plan_end from public.comp_plan_versions pv where pv.id=plan_version;
  select coalesce(array_agg(value),array[]::text[]) into component_codes from jsonb_array_elements_text(coalesce(agg->'source_component_codes',cfg->'aggregate_component_codes','[]'::jsonb));
  baseline:=coalesce(nullif(agg->>'baseline_amount','')::numeric,nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
  threshold_value:=coalesce(nullif(agg->>'benchmark_amount','')::numeric,nullif(cfg->>'threshold_amount','')::numeric,0);
  bonus_value:=coalesce(nullif(agg->>'payout_amount','')::numeric,nullif(cfg->>'bonus_amount','')::numeric,0);
  comparison_key:=coalesce(nullif(agg->>'comparison',''),nullif(cfg->>'comparison',''),'greater_than');
  qualification_rule_set_id:=nullif(agg->>'qualification_rule_set_id','')::uuid;
  value_field:=coalesce(nullif(agg->>'value_field',''),'amount');

  if version_status='draft' then
    select effective_start_date,effective_end_date into assignment_start,assignment_end from public.comp_plan_draft_assignments where plan_version_id=plan_version and employee_id=target_employee_id limit 1;
  else
    select effective_start_date,effective_end_date into assignment_start,assignment_end from public.employee_plan_assignments where plan_version_id=plan_version and employee_id=target_employee_id limit 1;
  end if;

  if qualification_rule_set_id is not null then
    if not exists(select 1 from public.comp_rule_sets rs where rs.id=qualification_rule_set_id and rs.plan_component_id=target_component_id and rs.purpose='metric_qualification') then
      raise exception 'Metric qualification rule is not attached to this Earning Type' using errcode='22023';
    end if;
    if assignment_start is not null then
      period_start:=greatest(make_date(target_year,1,1),coalesce(plan_start,make_date(target_year,1,1)),assignment_start);
      period_end:=least(make_date(target_year,12,31),coalesce(plan_end,make_date(target_year,12,31)),coalesce(assignment_end,make_date(target_year,12,31)));
      metric_summary:=private.compute_comp_metric_rule_summary(qualification_rule_set_id,value_field,period_start,period_end);
      source_total:=coalesce((metric_summary->>'total')::numeric,0);
    end if;
  else
    with assignment as (
      select da.effective_start_date,da.effective_end_date from public.comp_plan_draft_assignments da where version_status='draft' and da.employee_id=target_employee_id and da.plan_version_id=plan_version
      union all
      select epa.effective_start_date,epa.effective_end_date from public.employee_plan_assignments epa where version_status<>'draft' and epa.employee_id=target_employee_id and epa.plan_version_id=plan_version
    ), source_components as (
      select sc.id,sc.component_code,sc.measurement_source from public.comp_plan_components sc where sc.plan_version_id=plan_version and sc.is_active=true and sc.id<>target_component_id and sc.component_code=any(component_codes)
    ), raw as (
      select sc.id source_component_id,d.hubspot_deal_id,
        case sc.measurement_source when 'average_arr' then d.average_arr when 'first_year_arr' then d.first_year_arr when 'one_time_fee' then d.one_time_fee when 'total_contract_value' then d.total_contract_value else d.amount end as source_amount,
        case when exists(select 1 from public.comp_user_attribution_rules mr where mr.plan_component_id=sc.id and mr.attribution_purpose='metric' and mr.metric_key='book_of_business' and mr.is_active=true)
          then private.resolve_comp_user_attribution(target_employee_id,sc.id,d.hubspot_deal_id,'metric','book_of_business') else private.resolve_comp_user_attribution(target_employee_id,sc.id,d.hubspot_deal_id,'earning',null) end as attribution
      from assignment a join source_components sc on true
      join public.comp_component_deal_rules dr on dr.plan_component_id=sc.id and dr.is_active=true and dr.calculation_action='include' and dr.marks_earned=true
      join public.hubspot_deals d on d.hubspot_pipeline_id=dr.hubspot_pipeline_id and d.hubspot_stage_id=dr.hubspot_stage_id and d.hubspot_deal_type=dr.hubspot_deal_type
      join public.comp_plan_versions pv on pv.id=plan_version
      where extract(year from d.close_date)::int=target_year and d.close_date between greatest(a.effective_start_date,pv.effective_start_date,dr.effective_start_date) and least(coalesce(a.effective_end_date,'infinity'::date),coalesce(pv.effective_end_date,'infinity'::date),coalesce(dr.effective_end_date,'infinity'::date))
    ), deduped as (
      select source_component_id,hubspot_deal_id,max(source_amount*coalesce(nullif(attribution->>'resolved_credit_percentage','')::numeric,100)/100) credited_source_amount from raw where coalesce((attribution->>'matched')::boolean,false)=true and source_amount is not null group by source_component_id,hubspot_deal_id
    ) select coalesce(sum(credited_source_amount),0) into source_total from deduped;
  end if;

  total_value:=source_total+baseline; attainment:=case when threshold_value>0 then round((total_value/threshold_value)*100,2) else 0 end;
  met:=case comparison_key when 'greater_than_or_equal' then total_value>=threshold_value when 'equal' then total_value=threshold_value else total_value>threshold_value end;
  return jsonb_build_object('component_id',target_component_id,'employee_id',target_employee_id,'year',target_year,'source_component_codes',to_jsonb(component_codes),'qualification_rule_set_id',qualification_rule_set_id,'value_field',value_field,'source_mode',case when qualification_rule_set_id is null then 'legacy_components' else 'metric_rule' end,'source_total',source_total,'baseline_amount',baseline,'measurement_value',total_value,'threshold',threshold_value,'attainment_percent',attainment,'threshold_met',met,'bonus_amount',bonus_value,'comparison',comparison_key,'metric_key','book_of_business');
end;
$$;

revoke all on function private.compute_comp_component_attainment(uuid,uuid,integer) from public,anon,authenticated;

create or replace function public.preview_comp_component_aggregate(target_component_id uuid,selected_measurement_date date default current_date)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb; component_row record; aggregate_config jsonb; source_codes jsonb; period_key text; period_start date; period_end date;
  baseline_amount numeric; benchmark_amount numeric; rows_json jsonb; qualification_rule_set_id uuid; value_field text;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true or not ((coalesce(access->'permissions','[]'::jsonb)?'plans.view') or (coalesce(access->'permissions','[]'::jsonb)?'plans.edit')) then raise exception 'Not authorized to preview compensation aggregates' using errcode='42501'; end if;
  select c.id,c.plan_version_id,c.name,c.component_code,c.calculation_type,c.measurement_period,c.rule_configuration,pv.status::text version_status,pv.effective_start_date,pv.effective_end_date into component_row from public.comp_plan_components c join public.comp_plan_versions pv on pv.id=c.plan_version_id where c.id=target_component_id;
  if component_row.id is null then raise exception 'Earning Type not found' using errcode='P0002'; end if;
  aggregate_config:=coalesce(component_row.rule_configuration->'aggregate','{}'::jsonb); source_codes:=coalesce(aggregate_config->'source_component_codes','[]'::jsonb);
  period_key:=coalesce(nullif(aggregate_config->>'period',''),nullif(component_row.measurement_period,''),'annual'); baseline_amount:=coalesce(nullif(aggregate_config->>'baseline_amount','')::numeric,0); benchmark_amount:=coalesce(nullif(aggregate_config->>'benchmark_amount','')::numeric,nullif(component_row.rule_configuration->>'threshold_amount','')::numeric);
  qualification_rule_set_id:=nullif(aggregate_config->>'qualification_rule_set_id','')::uuid; value_field:=coalesce(nullif(aggregate_config->>'value_field',''),'amount');
  if period_key='monthly' then period_start:=date_trunc('month',selected_measurement_date)::date;period_end:=(date_trunc('month',selected_measurement_date)+interval '1 month-1 day')::date;
  elsif period_key='quarterly' then period_start:=date_trunc('quarter',selected_measurement_date)::date;period_end:=(date_trunc('quarter',selected_measurement_date)+interval '3 months-1 day')::date;
  else period_key:='annual';period_start:=date_trunc('year',selected_measurement_date)::date;period_end:=(date_trunc('year',selected_measurement_date)+interval '1 year-1 day')::date; end if;

  if qualification_rule_set_id is not null then
    if not exists(select 1 from public.comp_rule_sets rs where rs.id=qualification_rule_set_id and rs.plan_component_id=target_component_id and rs.purpose='metric_qualification') then raise exception 'Metric qualification rule is not attached to this Earning Type' using errcode='22023'; end if;
    with assigned as (
      select da.employee_id,e.full_name,da.effective_start_date,da.effective_end_date from public.comp_plan_draft_assignments da join public.employees e on e.id=da.employee_id where component_row.version_status='draft' and da.plan_version_id=component_row.plan_version_id
      union all
      select a.employee_id,e.full_name,a.effective_start_date,a.effective_end_date from public.employee_plan_assignments a join public.employees e on e.id=a.employee_id where component_row.version_status<>'draft' and a.plan_version_id=component_row.plan_version_id and selected_measurement_date between a.effective_start_date and coalesce(a.effective_end_date,'infinity'::date)
    ), summarized as (
      select a.*,private.compute_comp_metric_rule_summary(qualification_rule_set_id,value_field,greatest(period_start,component_row.effective_start_date,a.effective_start_date),least(period_end,coalesce(component_row.effective_end_date,period_end),coalesce(a.effective_end_date,period_end))) summary from assigned a
    )
    select coalesce(jsonb_agg(jsonb_build_object('employee_id',s.employee_id,'employee_name',s.full_name,'period_start',period_start,'period_end',period_end,'qualifying_total',coalesce((s.summary->>'total')::numeric,0),'baseline_amount',baseline_amount,'attainment_value',coalesce((s.summary->>'total')::numeric,0)+baseline_amount,'benchmark_amount',benchmark_amount,'attainment_percent',case when benchmark_amount is null or benchmark_amount=0 then null else round(((coalesce((s.summary->>'total')::numeric,0)+baseline_amount)/benchmark_amount)*100,2) end,'qualifying_record_count',coalesce((s.summary->>'matched_count')::int,0),'metric_key','book_of_business','source_mode','metric_rule','qualification_rule_set_id',qualification_rule_set_id,'value_field',value_field,'calculation',public.evaluate_compensation_rule(component_row.calculation_type,component_row.rule_configuration,coalesce((s.summary->>'total')::numeric,0)+baseline_amount,null,null,selected_measurement_date)) order by s.full_name),'[]'::jsonb) into rows_json from summarized s;
  else
    with assigned as (
      select da.employee_id,e.full_name,da.effective_start_date,da.effective_end_date from public.comp_plan_draft_assignments da join public.employees e on e.id=da.employee_id where component_row.version_status='draft' and da.plan_version_id=component_row.plan_version_id
      union all
      select a.employee_id,e.full_name,a.effective_start_date,a.effective_end_date from public.employee_plan_assignments a join public.employees e on e.id=a.employee_id where component_row.version_status<>'draft' and a.plan_version_id=component_row.plan_version_id and selected_measurement_date between a.effective_start_date and coalesce(a.effective_end_date,'infinity'::date)
    ), source_components as (
      select c.id,c.component_code,c.name,c.measurement_source from public.comp_plan_components c where c.plan_version_id=component_row.plan_version_id and c.is_active and c.id<>target_component_id and source_codes?c.component_code
    ), raw_matches as (
      select a.employee_id,a.full_name,sc.id source_component_id,sc.component_code,sc.name source_component_name,d.hubspot_deal_id,d.deal_name,d.close_date,
        case sc.measurement_source when 'average_arr' then d.average_arr when 'first_year_arr' then d.first_year_arr when 'one_time_fee' then d.one_time_fee when 'total_contract_value' then d.total_contract_value else d.amount end source_amount,
        case when exists(select 1 from public.comp_user_attribution_rules mr where mr.plan_component_id=sc.id and mr.attribution_purpose='metric' and mr.metric_key='book_of_business' and mr.is_active=true) then private.resolve_comp_user_attribution(a.employee_id,sc.id,d.hubspot_deal_id,'metric','book_of_business') else private.resolve_comp_user_attribution(a.employee_id,sc.id,d.hubspot_deal_id,'earning',null) end attribution
      from assigned a join source_components sc on true join public.comp_component_deal_rules dr on dr.plan_component_id=sc.id and dr.is_active and dr.calculation_action='include' and dr.marks_earned join public.hubspot_deals d on d.hubspot_pipeline_id=dr.hubspot_pipeline_id and d.hubspot_stage_id=dr.hubspot_stage_id and d.hubspot_deal_type=dr.hubspot_deal_type
      where d.close_date between greatest(period_start,component_row.effective_start_date,a.effective_start_date,coalesce(dr.effective_start_date,period_start)) and least(period_end,coalesce(component_row.effective_end_date,'infinity'::date),coalesce(a.effective_end_date,'infinity'::date),coalesce(dr.effective_end_date,'infinity'::date))
    ), deduped as (
      select distinct on(employee_id,source_component_id,hubspot_deal_id) employee_id,full_name,source_component_id,component_code,source_component_name,hubspot_deal_id,deal_name,close_date,source_amount*coalesce(nullif(attribution->>'resolved_credit_percentage','')::numeric,100)/100 source_amount from raw_matches where coalesce((attribution->>'matched')::boolean,false)=true order by employee_id,source_component_id,hubspot_deal_id,close_date desc
    ), totals as (
      select a.employee_id,a.full_name,coalesce(sum(d.source_amount),0) qualifying_total,count(d.hubspot_deal_id) qualifying_record_count from assigned a left join deduped d on d.employee_id=a.employee_id group by a.employee_id,a.full_name
    )
    select coalesce(jsonb_agg(jsonb_build_object('employee_id',t.employee_id,'employee_name',t.full_name,'period_start',period_start,'period_end',period_end,'qualifying_total',t.qualifying_total,'baseline_amount',baseline_amount,'attainment_value',t.qualifying_total+baseline_amount,'benchmark_amount',benchmark_amount,'attainment_percent',case when benchmark_amount is null or benchmark_amount=0 then null else round(((t.qualifying_total+baseline_amount)/benchmark_amount)*100,2) end,'qualifying_record_count',t.qualifying_record_count,'metric_key','book_of_business','source_mode','legacy_components','qualification_rule_set_id',null,'value_field',null,'calculation',public.evaluate_compensation_rule(component_row.calculation_type,component_row.rule_configuration,t.qualifying_total+baseline_amount,null,null,selected_measurement_date)) order by t.full_name),'[]'::jsonb) into rows_json from totals t;
  end if;

  return jsonb_build_object('component_id',component_row.id,'component_name',component_row.name,'component_code',component_row.component_code,'plan_version_id',component_row.plan_version_id,'plan_status',component_row.version_status,'period',period_key,'period_start',period_start,'period_end',period_end,'measurement_date',selected_measurement_date,'source_component_codes',source_codes,'qualification_rule_set_id',qualification_rule_set_id,'value_field',value_field,'source_mode',case when qualification_rule_set_id is null then 'legacy_components' else 'metric_rule' end,'baseline_amount',baseline_amount,'benchmark_amount',benchmark_amount,'metric_key','book_of_business','rows',rows_json);
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
  base jsonb; approval_step_count integer; c record; blockers jsonb; warnings jsonb; agg jsonb; source_codes jsonb; metric_rule_id uuid;
begin
  base:=public.validate_compensation_plan_version_readiness_core(selected_plan_version_id);
  select coalesce(jsonb_agg(b),'[]'::jsonb) into blockers from jsonb_array_elements(coalesce(base->'blockers','[]'::jsonb)) b where not (((b->>'code' in ('missing_earned_rule','earned_rule_needs_preview')) and exists(select 1 from public.comp_plan_components pc where pc.id=nullif(b->>'component_id','')::uuid and ((pc.measurement_source='book_of_business' and pc.calculation_type='threshold_bonus') or exists(select 1 from public.comp_component_deal_rules dr where dr.plan_component_id=pc.id and dr.is_active=true and dr.marks_earned=true)))) or ((b->>'code'='missing_eligibility') and exists(select 1 from public.comp_plan_components pc where pc.id=nullif(b->>'component_id','')::uuid and ((pc.measurement_source='book_of_business' and pc.calculation_type='threshold_bonus') or coalesce((pc.rule_configuration->>'requires_invoice_paid_date')::boolean,false)=true or pc.rule_configuration->>'eligibility_condition' in ('paid_stage_and_invoice_paid_date','invoice_paid_date','customer_payment_received')))));
  warnings:=coalesce(base->'warnings','[]'::jsonb);
  select count(*) into approval_step_count from public.comp_plan_approval_steps where plan_version_id=selected_plan_version_id and is_required=true;
  if approval_step_count=0 then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_approval_steps','section','approvals','message','Configure at least one required approval step for this plan.')); end if;

  for c in select id,name,measurement_source,calculation_type,rule_configuration from public.comp_plan_components where plan_version_id=selected_plan_version_id and is_active=true order by calculation_order,name loop
    if c.measurement_source in ('amount','average_arr','first_year_arr','one_time_fee','total_contract_value') then
      if not exists(select 1 from public.comp_component_deal_rules dr where dr.plan_component_id=c.id and dr.is_active=true and dr.marks_earned=true) then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_deal_source_rules','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs both Deal Type and Deal Stage in its Earned conditions before it can generate earnings.',c.name)));
      elsif not exists(select 1 from public.comp_rule_sets rs where rs.plan_component_id=c.id and rs.purpose='qualification') then warnings:=warnings||jsonb_build_array(jsonb_build_object('code','legacy_earned_rules','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s is using valid legacy Earned rules. You can keep them for this plan or open Earned conditions to migrate them to the advanced rule model.',c.name))); end if;
      if not exists(select 1 from public.comp_user_attribution_rules ar where ar.plan_component_id=c.id and ar.attribution_purpose='earning' and ar.is_active=true) then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_credit_attribution','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs a HubSpot owner/CEM field so the system knows which employee gets credit.',c.name))); end if;
      if coalesce(c.rule_configuration->'eligibility','{}'::jsonb)='{}'::jsonb and (coalesce((c.rule_configuration->>'requires_invoice_paid_date')::boolean,false)=true or c.rule_configuration->>'eligibility_condition' in ('paid_stage_and_invoice_paid_date','invoice_paid_date','customer_payment_received')) then warnings:=warnings||jsonb_build_array(jsonb_build_object('code','legacy_payment_eligibility','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s is using the existing customer-payment eligibility rule. Open payment conditions if you want to migrate it to the configurable business-condition model.',c.name))); end if;
    elsif c.measurement_source='book_of_business' and c.calculation_type='threshold_bonus' then
      agg:=coalesce(c.rule_configuration->'aggregate','{}'::jsonb); source_codes:=coalesce(agg->'source_component_codes',c.rule_configuration->'aggregate_component_codes','[]'::jsonb); metric_rule_id:=nullif(agg->>'qualification_rule_set_id','')::uuid;
      if metric_rule_id is null and jsonb_array_length(source_codes)=0 then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_aggregate_qualification','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a Metric Qualification rule (preferred) or legacy source Earning Types.',c.name))); end if;
      if metric_rule_id is not null and not exists(select 1 from public.comp_rule_sets rs where rs.id=metric_rule_id and rs.plan_component_id=c.id and rs.purpose='metric_qualification') then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','invalid_metric_qualification','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s has a Metric Qualification rule that no longer belongs to this Earning Type.',c.name))); end if;
      if metric_rule_id is not null and exists(select 1 from public.comp_rule_sets rs where rs.id=metric_rule_id and rs.plan_component_id=c.id) and not exists(select 1 from public.comp_rule_set_preview_runs pr join public.comp_rule_sets rs on rs.id=pr.rule_set_id where pr.rule_set_id=metric_rule_id and pr.supported=true and pr.rule_updated_at=rs.updated_at) then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','metric_rule_needs_preview','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('Preview %s''s Metric Qualification rule against current HubSpot data before approval.',c.name))); end if;
      if coalesce(nullif(agg->>'benchmark_amount',''),nullif(c.rule_configuration->>'threshold_amount','')) is null then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_quota','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a quota or benchmark threshold.',c.name))); end if;
      if coalesce(nullif(agg->>'payout_amount',''),nullif(c.rule_configuration->>'bonus_amount','')) is null then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_threshold_bonus','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs the bonus paid when the benchmark is exceeded.',c.name))); end if;
      warnings:=warnings||jsonb_build_array(jsonb_build_object('code','aggregate_year_end','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s tracks attainment during the year and creates the bonus earning at year end if the benchmark is exceeded.',c.name)));
    end if;
  end loop;
  base:=jsonb_set(base,'{blockers}',blockers);base:=jsonb_set(base,'{warnings}',warnings);base:=jsonb_set(base,'{blocker_count}',to_jsonb(jsonb_array_length(blockers)));base:=jsonb_set(base,'{warning_count}',to_jsonb(jsonb_array_length(warnings)));base:=jsonb_set(base,'{ready}',to_jsonb(jsonb_array_length(blockers)=0));return base;
end;
$$;
