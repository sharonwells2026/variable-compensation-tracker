-- 090 - Assign Sharon Compensation Plan
-- ALREADY APPLIED MANUALLY TO PRODUCTION.
-- Uses natural keys rather than hard-coded UUIDs.

insert into public.employee_plan_assignments (
  employee_id,
  plan_version_id,
  allocation_percent,
  effective_start_date,
  eligibility_waiting_period_days,
  earnings_eligibility_date,
  assignment_notes
)
select
  e.id,
  cpv.id,
  100,
  '2023-04-01',
  0,
  '2023-04-01',
  'Assignment of Sharon Wells to modified compensation plan originally effective April 1, 2023.'
from public.employees e
join public.comp_plans cp on cp.plan_code='SHARON_2023_04_MODIFIED'
join public.comp_plan_versions cpv on cpv.comp_plan_id=cp.id and cpv.version_number=1
where lower(e.email)=lower('sharonwells@engagifii.com')
and not exists (
  select 1 from public.employee_plan_assignments epa
  where epa.employee_id=e.id and epa.plan_version_id=cpv.id
);
