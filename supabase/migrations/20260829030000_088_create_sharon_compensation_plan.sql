-- 088 - Create Sharon Compensation Plan - April 2023 Modified
-- ALREADY APPLIED MANUALLY TO PRODUCTION.
-- Source-controlled here so database history can be reproduced.

insert into public.comp_plans (
  name,
  plan_code,
  description,
  plan_type,
  is_active
)
select
  'Sharon - April 2023 - Modified',
  'SHARON_2023_04_MODIFIED',
  'Modified version of Sharon Wells variable compensation plan originally effective April 1, 2023. Component-level effective date changes are preserved separately.',
  'variable_compensation',
  true
where not exists (
  select 1
  from public.comp_plans
  where plan_code = 'SHARON_2023_04_MODIFIED'
);

insert into public.comp_plan_versions (
  comp_plan_id,
  version_number,
  status,
  effective_start_date,
  currency_code,
  notes
)
select
  cp.id,
  1,
  'draft',
  '2023-04-01',
  'USD',
  'Modified/current representation of the compensation plan originally effective April 1, 2023.'
from public.comp_plans cp
where cp.plan_code = 'SHARON_2023_04_MODIFIED'
and not exists (
  select 1
  from public.comp_plan_versions cpv
  where cpv.comp_plan_id = cp.id
    and cpv.version_number = 1
);
