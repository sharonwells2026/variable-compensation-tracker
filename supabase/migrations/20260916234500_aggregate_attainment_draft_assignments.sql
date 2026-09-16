create or replace function private.compute_comp_component_attainment(target_component_id uuid,target_employee_id uuid,target_year integer)
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  c public.comp_plan_components%rowtype; cfg jsonb; agg jsonb; component_codes text[];
  source_total numeric:=0; baseline numeric:=0; total_value numeric:=0; threshold_value numeric:=0; bonus_value numeric:=0; attainment numeric:=0;
  met boolean:=false; comparison_key text; plan_version uuid; version_status text;
begin
  select * into c from public.comp_plan_components where id=target_component_id;
  if c.id is null then raise exception 'Earning Type not found'; end if;
  cfg:=coalesce(c.rule_configuration,'{}'::jsonb); agg:=coalesce(cfg->'aggregate','{}'::jsonb); plan_version:=c.plan_version_id;
  select pv.status::text into version_status from public.comp_plan_versions pv where pv.id=plan_version;
  select coalesce(array_agg(value),array[]::text[]) into component_codes from jsonb_array_elements_text(coalesce(agg->'source_component_codes',cfg->'aggregate_component_codes','[]'::jsonb));
  baseline:=coalesce(nullif(agg->>'baseline_amount','')::numeric,nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
  threshold_value:=coalesce(nullif(agg->>'benchmark_amount','')::numeric,nullif(cfg->>'threshold_amount','')::numeric,0);
  bonus_value:=coalesce(nullif(agg->>'payout_amount','')::numeric,nullif(cfg->>'bonus_amount','')::numeric,0);
  comparison_key:=coalesce(nullif(agg->>'comparison',''),nullif(cfg->>'comparison',''),'greater_than');
  with assignment as (
    select da.effective_start_date,da.effective_end_date from public.comp_plan_draft_assignments da where version_status='draft' and da.employee_id=target_employee_id and da.plan_version_id=plan_version
    union all
    select epa.effective_start_date,epa.effective_end_date from public.employee_plan_assignments epa where version_status<>'draft' and epa.employee_id=target_employee_id and epa.plan_version_id=plan_version
  ), source_components as (
    select sc.id,sc.component_code,sc.measurement_source from public.comp_plan_components sc where sc.plan_version_id=plan_version and sc.is_active=true and sc.id<>target_component_id and sc.component_code=any(component_codes)
  ), raw as (
    select sc.id source_component_id,d.hubspot_deal_id,
      case sc.measurement_source when 'average_arr' then d.average_arr when 'first_year_arr' then d.first_year_arr when 'one_time_fee' then d.one_time_fee when 'total_contract_value' then d.total_contract_value else d.amount end source_amount,
      case when exists(select 1 from public.comp_user_attribution_rules mr where mr.plan_component_id=sc.id and mr.attribution_purpose='metric' and mr.metric_key='book_of_business' and mr.is_active=true)
        then private.resolve_comp_user_attribution(target_employee_id,sc.id,d.hubspot_deal_id,'metric','book_of_business')
        else private.resolve_comp_user_attribution(target_employee_id,sc.id,d.hubspot_deal_id,'earning',null) end attribution
    from assignment a join source_components sc on true
    join public.comp_component_deal_rules dr on dr.plan_component_id=sc.id and dr.is_active=true and dr.calculation_action='include' and dr.marks_earned=true
    join public.hubspot_deals d on d.hubspot_pipeline_id=dr.hubspot_pipeline_id and d.hubspot_stage_id=dr.hubspot_stage_id and d.hubspot_deal_type=dr.hubspot_deal_type
    join public.comp_plan_versions pv on pv.id=plan_version
    where extract(year from d.close_date)::int=target_year and d.close_date between greatest(a.effective_start_date,pv.effective_start_date,dr.effective_start_date) and least(coalesce(a.effective_end_date,'infinity'::date),coalesce(pv.effective_end_date,'infinity'::date),coalesce(dr.effective_end_date,'infinity'::date))
  ), deduped as (
    select source_component_id,hubspot_deal_id,max(source_amount*coalesce(nullif(attribution->>'resolved_credit_percentage','')::numeric,100)/100) credited_source_amount
    from raw where coalesce((attribution->>'matched')::boolean,false)=true and source_amount is not null group by source_component_id,hubspot_deal_id
  ) select coalesce(sum(credited_source_amount),0) into source_total from deduped;
  total_value:=source_total+baseline; attainment:=case when threshold_value>0 then round((total_value/threshold_value)*100,2) else 0 end;
  met:=case comparison_key when 'greater_than_or_equal' then total_value>=threshold_value when 'equal' then total_value=threshold_value else total_value>threshold_value end;
  return jsonb_build_object('component_id',target_component_id,'employee_id',target_employee_id,'year',target_year,'source_component_codes',to_jsonb(component_codes),'source_total',source_total,'baseline_amount',baseline,'measurement_value',total_value,'threshold',threshold_value,'attainment_percent',attainment,'threshold_met',met,'bonus_amount',bonus_value,'comparison',comparison_key,'metric_key','book_of_business');
end;
$$;
revoke all on function private.compute_comp_component_attainment(uuid,uuid,integer) from public,anon,authenticated;
