-- 089 - Sharon Plan Components and Modifications
-- ALREADY APPLIED MANUALLY TO PRODUCTION.
-- This file documents the plan rules represented in production.
-- Component codes are stable identifiers; rule_configuration contains the source terms.

with target_version as (
  select cpv.id
  from public.comp_plan_versions cpv
  join public.comp_plans cp on cp.id = cpv.comp_plan_id
  where cp.plan_code = 'SHARON_2023_04_MODIFIED'
    and cpv.version_number = 1
  limit 1
)
insert into public.comp_plan_components
  (plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active)
select id,'GovAffairs New Logo ARR Override','SHARON_GA_NEW_LOGO_OVERRIDE','3% override on Government Affairs new-logo ARR.','percentage','new_logo_arr','annual',10,
  jsonb_build_object('business_line','government_affairs','deal_type','new_business','rate',0.03,'scope','company_wide','effective_start_date','2023-04-01'),null,true
from target_version
where not exists (select 1 from public.comp_plan_components where component_code='SHARON_GA_NEW_LOGO_OVERRIDE');

with target_version as (
  select cpv.id from public.comp_plan_versions cpv join public.comp_plans cp on cp.id=cpv.comp_plan_id
  where cp.plan_code='SHARON_2023_04_MODIFIED' and cpv.version_number=1 limit 1
)
insert into public.comp_plan_components
  (plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active)
select id,'MEams New Logo ARR Override','SHARON_MEAMS_NEW_LOGO_OVERRIDE','MEams new-logo ARR override with rate history.','percentage','new_logo_arr','annual',20,
  jsonb_build_object('business_line','meams','deal_type','new_business','rate_history',jsonb_build_array(jsonb_build_object('rate',0.03,'start','2023-04-01','end','2024-07-31'),jsonb_build_object('rate',0.06,'start','2024-08-01','end',null))),null,true
from target_version
where not exists (select 1 from public.comp_plan_components where component_code='SHARON_MEAMS_NEW_LOGO_OVERRIDE');

with target_version as (
  select cpv.id from public.comp_plan_versions cpv join public.comp_plans cp on cp.id=cpv.comp_plan_id
  where cp.plan_code='SHARON_2023_04_MODIFIED' and cpv.version_number=1 limit 1
)
insert into public.comp_plan_components
  (plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active)
select id,'Expansion ARR Override','SHARON_EXPANSION_OVERRIDE','2% expansion ARR override.','percentage','expansion_arr','annual',30,jsonb_build_object('deal_type','expansion','rate',0.02,'effective_start_date','2023-04-01'),null,true
from target_version
where not exists (select 1 from public.comp_plan_components where component_code='SHARON_EXPANSION_OVERRIDE');

with target_version as (
  select cpv.id from public.comp_plan_versions cpv join public.comp_plans cp on cp.id=cpv.comp_plan_id
  where cp.plan_code='SHARON_2023_04_MODIFIED' and cpv.version_number=1 limit 1
)
insert into public.comp_plan_components
  (plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active)
select id,'One-Time Fees Override','SHARON_ONE_TIME_FEES','3% override on qualifying one-time fees.','percentage','one_time_fees','annual',40,jsonb_build_object('rate',0.03,'effective_start_date','2023-10-01'),null,true
from target_version
where not exists (select 1 from public.comp_plan_components where component_code='SHARON_ONE_TIME_FEES');

with target_version as (
  select cpv.id from public.comp_plan_versions cpv join public.comp_plans cp on cp.id=cpv.comp_plan_id
  where cp.plan_code='SHARON_2023_04_MODIFIED' and cpv.version_number=1 limit 1
)
insert into public.comp_plan_components
  (plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active)
select id,'Completed QDC Bonus','SHARON_COMPLETED_QDC','$30 per completed QDC.','fixed_amount_per_unit','hubspot_meeting','monthly',50,jsonb_build_object('amount_per_unit',30,'qualifying_status','completed','effective_start_date','2023-04-01'),null,true
from target_version
where not exists (select 1 from public.comp_plan_components where component_code='SHARON_COMPLETED_QDC');

with target_version as (
  select cpv.id from public.comp_plan_versions cpv join public.comp_plans cp on cp.id=cpv.comp_plan_id
  where cp.plan_code='SHARON_2023_04_MODIFIED' and cpv.version_number=1 limit 1
)
insert into public.comp_plan_components
  (plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active)
select id,'New Logo ARR Milestone Bonuses','SHARON_NEW_LOGO_MILESTONES','Annual New Logo ARR milestone bonuses.','milestone_bonus','new_logo_arr','annual',60,
 jsonb_build_object('milestones',jsonb_build_array(
   jsonb_build_object('threshold',100000,'bonus',1000),jsonb_build_object('threshold',150000,'bonus',1000),jsonb_build_object('threshold',200000,'bonus',2000),
   jsonb_build_object('threshold',250000,'bonus',2000),jsonb_build_object('threshold',300000,'bonus',3000),jsonb_build_object('threshold',350000,'bonus',3000),
   jsonb_build_object('threshold',400000,'bonus',4000),jsonb_build_object('threshold',450000,'bonus',4000),jsonb_build_object('threshold',500000,'bonus',5000))),25000,true
from target_version
where not exists (select 1 from public.comp_plan_components where component_code='SHARON_NEW_LOGO_MILESTONES');

with target_version as (
  select cpv.id from public.comp_plan_versions cpv join public.comp_plans cp on cp.id=cpv.comp_plan_id
  where cp.plan_code='SHARON_2023_04_MODIFIED' and cpv.version_number=1 limit 1
)
insert into public.comp_plan_components
  (plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active)
select id,'Renewal ARR Override - Under Review','SHARON_RENEWAL_OVERRIDE_REVIEW','2% renewal ARR override modeled for visibility only; not formally approved.','percentage','renewal_arr','annual',70,
 jsonb_build_object('rate',0.02,'effective_start_date','2024-08-01','earning_treatment','calculate_only_hold','review_status','under_review','counts_as_earned',false,'counts_as_eligible',false,'counts_as_approved',false,'counts_as_payable',false,'calculate_for_visibility',true,'requires_management_release',true,'hold_reason','Discussed but not formally incorporated into the compensation plan.'),null,true
from target_version
where not exists (select 1 from public.comp_plan_components where component_code='SHARON_RENEWAL_OVERRIDE_REVIEW');
