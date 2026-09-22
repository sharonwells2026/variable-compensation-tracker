create or replace function private.compute_comp_component_attainment(target_component_id uuid,target_employee_id uuid,target_year integer)
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  c public.comp_plan_components%rowtype;
  cfg jsonb;
  component_codes text[];
  source_total numeric:=0;
  uplift numeric:=0;
  total_value numeric:=0;
  threshold_value numeric:=0;
  bonus_value numeric:=0;
  attainment numeric:=0;
  met boolean:=false;
  plan_version uuid;
begin
  select * into c from public.comp_plan_components where id=target_component_id;
  if c.id is null then raise exception 'Earning Type not found'; end if;
  cfg:=coalesce(c.rule_configuration,'{}'::jsonb);
  plan_version:=c.plan_version_id;
  select coalesce(array_agg(value),array[]::text[]) into component_codes
  from jsonb_array_elements_text(coalesce(cfg->'aggregate_component_codes','[]'::jsonb));
  uplift:=coalesce(nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
  threshold_value:=coalesce(nullif(cfg->>'threshold_amount','')::numeric,0);
  bonus_value:=coalesce(nullif(cfg->>'bonus_amount','')::numeric,0);

  select coalesce(sum(x.source_amount),0) into source_total
  from (
    select candidate.plan_component_id,candidate.hubspot_deal_id,max(candidate.source_amount) source_amount
    from public.comp_deal_earning_candidates_v2 candidate
    join public.comp_plan_components source_component on source_component.id=candidate.plan_component_id
    where candidate.employee_id=target_employee_id
      and candidate.plan_version_id=plan_version
      and extract(year from candidate.earned_date)::int=target_year
      and source_component.component_code=any(component_codes)
      and candidate.calculation_status='ready'
      and candidate.source_amount is not null
    group by candidate.plan_component_id,candidate.hubspot_deal_id
  ) x;
  total_value:=source_total+uplift;
  attainment:=case when threshold_value>0 then round((total_value/threshold_value)*100,2) else 0 end;
  met:=threshold_value>0 and total_value>threshold_value;
  return jsonb_build_object(
    'component_id',target_component_id,'employee_id',target_employee_id,'year',target_year,
    'source_component_codes',to_jsonb(component_codes),'source_total',source_total,
    'fixed_uplift',uplift,'measurement_value',total_value,'threshold',threshold_value,
    'attainment_percent',attainment,'threshold_met',met,'bonus_amount',bonus_value
  );
end;
$$;

create or replace function public.get_comp_component_attainment(target_component_id uuid,target_employee_id uuid,target_year integer default extract(year from current_date)::integer)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare access jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ?| array['plans.view','plans.edit','earnings.view_all']) then
    raise exception 'Not authorized to view compensation attainment';
  end if;
  return private.compute_comp_component_attainment(target_component_id,target_employee_id,target_year);
end;
$$;

grant execute on function public.get_comp_component_attainment(uuid,uuid,integer) to authenticated;

create or replace function public.refresh_comp_aggregate_earnings(target_year integer default extract(year from current_date)::integer)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  r record;
  a jsonb;
  measurement_date date;
  period_id uuid;
  calc_id uuid;
  created_count int:=0;
  updated_count int:=0;
  existing_id uuid;
  source_key text;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ?| array['earnings.manage','plans.edit']) then
    raise exception 'Not authorized to refresh aggregate compensation';
  end if;
  measurement_date:=make_date(target_year,12,31);
  for r in
    select c.id component_id,c.name component_name,c.rule_configuration,a.employee_id,a.id assignment_id
    from public.comp_plan_components c
    join public.comp_plan_versions pv on pv.id=c.plan_version_id and pv.status='active'
    join public.employee_plan_assignments a on a.plan_version_id=pv.id
    where c.is_active=true and c.calculation_type='threshold_bonus' and c.measurement_source='book_of_business'
      and measurement_date between a.effective_start_date and coalesce(a.effective_end_date,'infinity'::date)
  loop
    a:=private.compute_comp_component_attainment(r.component_id,r.employee_id,target_year);
    source_key:=r.component_id::text||':'||target_year::text;
    select id into existing_id from public.comp_earnings where employee_id=r.employee_id and plan_component_id=r.component_id and source_type='aggregate_metric' and source_external_id=source_key and is_current=true limit 1;
    if current_date<measurement_date or coalesce((a->>'threshold_met')::boolean,false) is not true then
      if existing_id is not null then
        update public.comp_earnings set is_current=false,eligibility_status='ineligible',eligible_amount=0,payment_status='not_payable',updated_at=now() where id=existing_id;
        updated_count:=updated_count+1;
      end if;
      continue;
    end if;
    select id into period_id from public.comp_periods where measurement_date between start_date and end_date order by start_date desc limit 1;
    if period_id is null then continue; end if;
    insert into public.comp_calculations(employee_id,comp_period_id,calculation_version,calculated_at,total_earned,total_eligible,total_approved,total_paid,notes)
    values(r.employee_id,period_id,1,now(),0,0,0,0,'Created by aggregate compensation engine.')
    on conflict(employee_id,comp_period_id,calculation_version) do update set calculated_at=excluded.calculated_at,updated_at=now()
    returning id into calc_id;
    if existing_id is null then
      insert into public.comp_earnings(calculation_id,employee_id,plan_assignment_id,plan_component_id,earning_name,earning_description,source_type,source_external_id,source_snapshot,earned_date,earned_amount,eligibility_status,eligibility_condition_type,eligibility_condition_description,eligible_date,eligible_amount,eligibility_evidence,approved_amount,payment_status,paid_amount,is_current,earning_origin,reconciliation_status,source_match_status)
      values(calc_id,r.employee_id,r.assignment_id,r.component_id,r.component_name,r.component_name||' for '||target_year,'aggregate_metric',source_key,a,measurement_date,(a->>'bonus_amount')::numeric,'eligible','aggregate_threshold','Eligible when annual aggregate benchmark is exceeded.',measurement_date,(a->>'bonus_amount')::numeric,a,0,'not_payable',0,true,'system_calculated','not_reviewed','confirmed');
      created_count:=created_count+1;
    else
      update public.comp_earnings set calculation_id=calc_id,plan_assignment_id=r.assignment_id,earned_date=measurement_date,earned_amount=(a->>'bonus_amount')::numeric,eligibility_status='eligible',eligible_date=measurement_date,eligible_amount=(a->>'bonus_amount')::numeric,source_snapshot=a,eligibility_evidence=a,updated_at=now() where id=existing_id;
      updated_count:=updated_count+1;
    end if;
  end loop;
  return jsonb_build_object('status','completed','year',target_year,'created',created_count,'updated',updated_count,'measurement_date',measurement_date);
end;
$$;

grant execute on function public.refresh_comp_aggregate_earnings(integer) to authenticated;

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
begin
  base:=public.validate_compensation_plan_version_readiness_core(selected_plan_version_id);
  blockers:=coalesce(base->'blockers','[]'::jsonb);
  warnings:=coalesce(base->'warnings','[]'::jsonb);
  select count(*) into approval_step_count from public.comp_plan_approval_steps where plan_version_id=selected_plan_version_id and is_required=true;
  if approval_step_count=0 then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_approval_steps','section','approvals','message','Configure at least one required approval step for this plan.')); end if;
  for c in select id,name,measurement_source,calculation_type,rule_configuration from public.comp_plan_components where plan_version_id=selected_plan_version_id and is_active=true order by calculation_order,name loop
    if c.measurement_source in ('amount','average_arr','first_year_arr','one_time_fee','total_contract_value') then
      if not exists(select 1 from public.comp_component_deal_rules dr where dr.plan_component_id=c.id and dr.is_active=true and dr.marks_earned=true) then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_deal_source_rules','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs both Deal Type and Deal Stage in its Earned conditions before it can generate earnings.',c.name))); end if;
      if not exists(select 1 from public.comp_user_attribution_rules ar where ar.plan_component_id=c.id and ar.attribution_purpose='earning' and ar.is_active=true) then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_credit_attribution','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs a HubSpot owner/CEM field so the system knows which employee gets credit.',c.name))); end if;
    elsif c.measurement_source='book_of_business' and c.calculation_type='threshold_bonus' then
      if jsonb_array_length(coalesce(c.rule_configuration->'aggregate_component_codes','[]'::jsonb))=0 then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_aggregate_sources','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs the Earning Types that count toward its running total.',c.name))); end if;
      if nullif(c.rule_configuration->>'threshold_amount','') is null then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_quota','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a quota or benchmark threshold.',c.name))); end if;
      if nullif(c.rule_configuration->>'bonus_amount','') is null then blockers:=blockers||jsonb_build_array(jsonb_build_object('code','missing_threshold_bonus','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs the bonus paid when the benchmark is exceeded.',c.name))); end if;
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