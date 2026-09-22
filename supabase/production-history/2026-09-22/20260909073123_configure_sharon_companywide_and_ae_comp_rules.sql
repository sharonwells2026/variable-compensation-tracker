alter table public.comp_user_attribution_rules drop constraint if exists comp_user_attribution_rules_match_logic_check;
alter table public.comp_user_attribution_rules add constraint comp_user_attribution_rules_match_logic_check check (match_logic = any (array['any'::text,'all'::text,'none'::text]));

create or replace function private.evaluate_hubspot_user_attribution(selected_employee_id uuid, selected_hubspot_deal_id text, selected_field_keys jsonb, selected_match_logic text default 'any'::text)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  employee_owner_id text;
  selected_fields jsonb := coalesce(selected_field_keys,'[]'::jsonb);
  selected_field_count integer;
  matched_field_count integer := 0;
  field_record record;
  field_value text;
  field_matched boolean;
  associated_company_id text;
  deal_properties jsonb;
  company_properties jsonb;
  field_results jsonb := '[]'::jsonb;
  final_match boolean;
begin
  if selected_match_logic not in ('any','all','none') then
    raise exception 'Unsupported attribution match logic: %', selected_match_logic using errcode='22023';
  end if;
  if jsonb_typeof(selected_fields) <> 'array' then
    raise exception 'HubSpot user field keys must be a JSON array.' using errcode='22023';
  end if;
  select e.hubspot_owner_id into employee_owner_id from public.employees e where e.id=selected_employee_id and e.is_active=true;
  if employee_owner_id is null then
    return jsonb_build_object('matched',false,'status','missing_employee_hubspot_owner','employee_id',selected_employee_id);
  end if;
  select d.raw_hubspot_data->'properties' into deal_properties from public.hubspot_deals d where d.hubspot_deal_id=selected_hubspot_deal_id;
  if deal_properties is null then
    return jsonb_build_object('matched',false,'status','deal_not_found','hubspot_deal_id',selected_hubspot_deal_id);
  end if;
  select association.hubspot_company_id into associated_company_id
  from public.hubspot_deal_company_associations association
  where association.hubspot_deal_id=selected_hubspot_deal_id
  order by association.is_primary desc,association.last_synced_at desc limit 1;
  if associated_company_id is not null then
    select company.raw_hubspot_data->'properties' into company_properties from public.hubspot_companies company where company.hubspot_company_id=associated_company_id;
  end if;
  selected_field_count := jsonb_array_length(selected_fields);
  if selected_field_count=0 then
    return jsonb_build_object('matched',true,'status','no_user_field_requirement','match_logic',selected_match_logic,'employee_hubspot_owner_id',employee_owner_id,'field_results','[]'::jsonb);
  end if;
  for field_record in
    select registry.field_key,registry.display_name,registry.object_type,registry.hubspot_property_name
    from public.comp_hubspot_user_fields registry
    join jsonb_array_elements_text(selected_fields) selected on selected.value=registry.field_key
    where registry.is_active=true
    order by registry.calculation_order
  loop
    if field_record.object_type='deal' then field_value := deal_properties->>field_record.hubspot_property_name;
    elsif field_record.object_type='company' then field_value := company_properties->>field_record.hubspot_property_name;
    else field_value := null;
    end if;
    field_matched := field_value is not null and (field_value=employee_owner_id or employee_owner_id = any(regexp_split_to_array(field_value,'[;,]')));
    if field_matched then matched_field_count := matched_field_count+1; end if;
    field_results := field_results || jsonb_build_array(jsonb_build_object('field_key',field_record.field_key,'display_name',field_record.display_name,'object_type',field_record.object_type,'hubspot_property_name',field_record.hubspot_property_name,'hubspot_value',field_value,'employee_hubspot_owner_id',employee_owner_id,'matched',field_matched));
  end loop;
  if jsonb_array_length(field_results)<>selected_field_count then
    return jsonb_build_object('matched',false,'status','invalid_user_field_configuration','selected_field_count',selected_field_count,'recognized_field_count',jsonb_array_length(field_results),'field_results',field_results);
  end if;
  if selected_match_logic='all' then final_match := matched_field_count=selected_field_count;
  elsif selected_match_logic='none' then final_match := matched_field_count=0;
  else final_match := matched_field_count>0;
  end if;
  return jsonb_build_object('matched',final_match,'status','evaluated','match_logic',selected_match_logic,'selected_field_count',selected_field_count,'matched_field_count',matched_field_count,'employee_hubspot_owner_id',employee_owner_id,'hubspot_deal_id',selected_hubspot_deal_id,'hubspot_company_id',associated_company_id,'field_results',field_results);
end;
$function$;

insert into public.comp_hubspot_user_fields(field_key,display_name,object_type,hubspot_property_name,description,is_active,calculation_order)
values
('solutions_advisor','Solutions Advisor','deal','sales_account_executive__multi_year_deals_','Employee matches the HubSpot Solutions Advisor on the deal.',true,11),
('business_development_owner','Business Development Owner','deal','business_development_owner','Employee matches the HubSpot Business Development Owner on the deal.',true,12)
on conflict (field_key) do update set display_name=excluded.display_name,object_type=excluded.object_type,hubspot_property_name=excluded.hubspot_property_name,description=excluded.description,is_active=excluded.is_active,calculation_order=excluded.calculation_order,updated_at=now();

update public.comp_plan_components
set measurement_source='amount', measurement_label='New sale ARR / deal amount used by the operating compensation history', updated_at=now()
where plan_version_id='8f281e19-db02-43d6-bf4f-7dcc77e9cf05' and component_code in ('SHARON_GA_NEW_LOGO_OVERRIDE','SHARON_MEAMS_NEW_LOGO_OVERRIDE');

update public.comp_plan_components
set name='Renewal ARR Override', description='2% company-wide renewal override based on documented historical compensation records.', rule_configuration=jsonb_build_object('rate',0.02,'deal_type','Renewal','credit_scope','company_wide','earned_condition','closed_won','eligibility_condition','customer_payment_received','effective_start_date','2024-08-01','earning_treatment','normal'), updated_at=now()
where plan_version_id='8f281e19-db02-43d6-bf4f-7dcc77e9cf05' and component_code='SHARON_RENEWAL_OVERRIDE_REVIEW';

insert into public.comp_plan_components(plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active,payout_timing_method,allow_manager_payout_override,measurement_label,additional_eligibility_waiting_days)
select '8f281e19-db02-43d6-bf4f-7dcc77e9cf05','Non-MEams New Sale as AE','SHARON_NON_MEAMS_AE_NEW_LOGO','Full AE commission on Sharon-owned non-MEams new sales. Historical rates: 1 year 10%, 2 years 12%, 3-4 years 14%.','tiered_percentage','amount','deal',15,
jsonb_build_object('tiers',jsonb_build_array(jsonb_build_object('minimum_contract_years',1,'maximum_contract_years',1,'rate',0.10),jsonb_build_object('minimum_contract_years',2,'maximum_contract_years',2,'rate',0.12),jsonb_build_object('minimum_contract_years',3,'maximum_contract_years',4,'rate',0.14)),'deal_type','New Business','pipeline','GovAffairs','credit_scope','deal_owner','effective_start_date','2023-04-01','eligibility_condition','customer_payment_received'),null,true,'annual',true,'ARR / deal amount',0
where not exists (select 1 from public.comp_plan_components where plan_version_id='8f281e19-db02-43d6-bf4f-7dcc77e9cf05' and component_code='SHARON_NON_MEAMS_AE_NEW_LOGO');

with components as (
  select id,component_code from public.comp_plan_components where plan_version_id='8f281e19-db02-43d6-bf4f-7dcc77e9cf05'
), stage_rules as (
  select * from (values
    ('20788895','110553179'),('20788895','110577979'),('20788895','110609073'),('20788895','110691177'),
    ('56062501','111910703'),('56062501','111970621'),('56062501','111910704'),('56062501','111910705')
  ) v(pipeline_id,stage_id)
), desired as (
  select c.id as component_id,s.pipeline_id,s.stage_id,'newbusiness'::text as deal_type,'amount'::text as amount_source,'New Sale ARR / Deal Amount'::text as amount_label,'Company-wide new-sale compensation rule'::text as notes
  from components c join stage_rules s on s.pipeline_id='20788895' where c.component_code='SHARON_GA_NEW_LOGO_OVERRIDE'
  union all
  select c.id,s.pipeline_id,s.stage_id,'newbusiness','amount','New Sale ARR / Deal Amount','MEams company-wide new-sale compensation rule'
  from components c join stage_rules s on s.pipeline_id='56062501' where c.component_code='SHARON_MEAMS_NEW_LOGO_OVERRIDE'
  union all
  select c.id,s.pipeline_id,s.stage_id,'newbusiness','amount','New Sale ARR / Deal Amount','Sharon-owned non-MEams AE new-sale rule'
  from components c join stage_rules s on s.pipeline_id='20788895' where c.component_code='SHARON_NON_MEAMS_AE_NEW_LOGO'
  union all
  select c.id,s.pipeline_id,s.stage_id,'existingbusiness','amount','Expansion Amount','2% company-wide expansion override'
  from components c cross join stage_rules s where c.component_code='SHARON_EXPANSION_OVERRIDE'
  union all
  select c.id,s.pipeline_id,s.stage_id,'One-time Fees','amount','One-Time Fee Amount','3% company-wide one-time-fee override'
  from components c cross join stage_rules s where c.component_code='SHARON_ONE_TIME_FEES'
  union all
  select c.id,s.pipeline_id,s.stage_id,'Renewal','amount','Renewal Amount','2% company-wide renewal override'
  from components c cross join stage_rules s where c.component_code='SHARON_RENEWAL_OVERRIDE_REVIEW'
)
insert into public.comp_component_deal_rules(plan_component_id,hubspot_pipeline_id,hubspot_stage_id,hubspot_deal_type,calculation_action,marks_earned,marks_eligible,marks_paid,amount_source,amount_label,priority,is_active,effective_start_date,rule_notes)
select component_id,pipeline_id,stage_id,deal_type,'include',true,true,false,amount_source,amount_label,100,true,
case when deal_type='Renewal' then '2024-08-01'::date else '2023-04-01'::date end,notes
from desired
on conflict (plan_component_id,hubspot_pipeline_id,hubspot_stage_id,hubspot_deal_type,calculation_action)
do update set marks_earned=excluded.marks_earned,marks_eligible=excluded.marks_eligible,marks_paid=excluded.marks_paid,amount_source=excluded.amount_source,amount_label=excluded.amount_label,is_active=true,effective_start_date=excluded.effective_start_date,rule_notes=excluded.rule_notes,updated_at=now();

with components as (
  select id,component_code from public.comp_plan_components where plan_version_id='8f281e19-db02-43d6-bf4f-7dcc77e9cf05'
)
insert into public.comp_user_attribution_rules(plan_component_id,attribution_purpose,hubspot_user_field_keys,match_logic,credit_percentage,qualifying_pipeline_ids,qualifying_deal_types,priority,allow_stacking,rule_configuration,effective_start_date,is_active)
select id,'earning','["deal_owner"]'::jsonb,'none',100,'["20788895"]'::jsonb,'["newbusiness"]'::jsonb,100,false,jsonb_build_object('scope','company_wide_non_ae','description','Sharon earns the 3% GovAffairs override when she is not the deal owner.'),'2023-04-01'::date,true from components where component_code='SHARON_GA_NEW_LOGO_OVERRIDE'
union all
select id,'earning','["deal_owner"]'::jsonb,'any',100,'["20788895"]'::jsonb,'["newbusiness"]'::jsonb,100,false,jsonb_build_object('scope','sharon_as_ae','description','Sharon-owned non-MEams new sales use AE term-based rates.'),'2023-04-01'::date,true from components where component_code='SHARON_NON_MEAMS_AE_NEW_LOGO'
union all
select id,'earning','[]'::jsonb,'any',100,'["56062501"]'::jsonb,'["newbusiness"]'::jsonb,100,false,jsonb_build_object('scope','company_wide'),'2023-04-01'::date,true from components where component_code='SHARON_MEAMS_NEW_LOGO_OVERRIDE'
union all
select id,'earning','[]'::jsonb,'any',100,'[]'::jsonb,'["existingbusiness"]'::jsonb,100,false,jsonb_build_object('scope','company_wide'),'2023-04-01'::date,true from components where component_code='SHARON_EXPANSION_OVERRIDE'
union all
select id,'earning','[]'::jsonb,'any',100,'[]'::jsonb,'["One-time Fees"]'::jsonb,100,false,jsonb_build_object('scope','company_wide'),'2023-10-01'::date,true from components where component_code='SHARON_ONE_TIME_FEES'
union all
select id,'earning','[]'::jsonb,'any',100,'[]'::jsonb,'["Renewal"]'::jsonb,100,false,jsonb_build_object('scope','company_wide'),'2024-08-01'::date,true from components where component_code='SHARON_RENEWAL_OVERRIDE_REVIEW';