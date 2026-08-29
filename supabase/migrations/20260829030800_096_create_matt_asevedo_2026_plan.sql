-- 096 - Create Matt Asevedo 2026 Compensation Plan
-- ALREADY APPLIED MANUALLY TO PRODUCTION.
-- Creates the plan container and Version 1. Components are added separately.

insert into public.comp_plans (name,plan_code,description,plan_type,is_active)
select 'Matt Asevedo - July 2026','MATT_2026_07','2026 Variable Compensation Plan for Matt Asevedo, Senior Solutions Advisor. Effective July 15, 2026.','variable_compensation',true
where not exists (select 1 from public.comp_plans where plan_code='MATT_2026_07');

insert into public.comp_plan_versions (comp_plan_id,version_number,status,effective_start_date,currency_code,notes)
select p.id,1,'draft','2026-07-15','USD','2026 plan effective July 15, 2026. Variable at target: $41,820. No draw or guarantee. Uncapped commissions. Earnings governed by collected-cash rules and six-month chargeback protection.'
from public.comp_plans p
where p.plan_code='MATT_2026_07'
and not exists (select 1 from public.comp_plan_versions pv where pv.comp_plan_id=p.id and pv.version_number=1);
