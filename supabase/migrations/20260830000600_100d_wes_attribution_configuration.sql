-- 100D - Wes Attribution Configuration
-- Configuration only. Does not modify comp_earnings.

with wes as (
  select id from public.employees where lower(email)='wesmorris@engagifii.com'
), components as (
  select c.id,c.component_code
  from public.comp_plan_components c
  join public.comp_plan_versions pv on pv.id=c.plan_version_id
  join public.comp_plans p on p.id=pv.comp_plan_id
  where p.plan_code='WES_2026'
)
delete from public.comp_user_attribution_rules r
using components c
where r.plan_component_id=c.id
  and r.rule_configuration->>'configuration_source'='100D';

with components as (
  select c.id,c.component_code
  from public.comp_plan_components c
  join public.comp_plan_versions pv on pv.id=c.plan_version_id
  join public.comp_plans p on p.id=pv.comp_plan_id
  where p.plan_code='WES_2026'
)
insert into public.comp_user_attribution_rules(
  plan_component_id,attribution_purpose,metric_key,hubspot_user_field_keys,match_logic,credit_percentage,
  qualifying_pipeline_ids,qualifying_deal_types,priority,allow_stacking,rule_configuration,effective_start_date,is_active
)
select c.id,'earning',null,'["company_cem"]'::jsonb,'any',100,'["20788895","56062501"]'::jsonb,'["Renewal"]'::jsonb,100,false,
       '{"configuration_source":"100D"}'::jsonb,date '2025-12-12',true
from components c where c.component_code='WES_2026_RETENTION'
union all
select c.id,'earning',null,'["deal_owner"]'::jsonb,'any',100,'[]'::jsonb,'[]'::jsonb,100,false,
       '{"configuration_source":"100D"}'::jsonb,date '2025-12-12',true
from components c where c.component_code='WES_2026_EXPANSION'
union all
select c.id,'earning',null,'["deal_owner"]'::jsonb,'any',100,'[]'::jsonb,'[]'::jsonb,100,false,
       '{"configuration_source":"100D"}'::jsonb,date '2025-12-12',true
from components c where c.component_code='WES_2026_GA_NEW_SALES'
union all
select c.id,'metric','book_of_business','["company_cem"]'::jsonb,'any',100,'[]'::jsonb,'[]'::jsonb,100,false,
       '{"configuration_source":"100D"}'::jsonb,date '2025-12-12',true
from components c where c.component_code='WES_2026_EXPANSION';
