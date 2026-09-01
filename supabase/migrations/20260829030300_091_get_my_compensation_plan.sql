-- 091 - Dynamic My Compensation Plan RPC
-- ALREADY APPLIED MANUALLY TO PRODUCTION.
-- Returns the signed-in employee's assigned plan and active components.

create or replace function public.get_my_compensation_plan()
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  resolved_employee_id uuid;
  result jsonb;
begin
  select p.employee_id into resolved_employee_id
  from public.profiles p
  where p.id = auth.uid();

  if resolved_employee_id is null then
    return jsonb_build_object('employee',null,'plan',null,'components','[]'::jsonb);
  end if;

  select jsonb_build_object(
    'employee', jsonb_build_object('id',e.id,'full_name',e.full_name,'email',e.email,'job_title',e.job_title,'department',e.department),
    'plan', jsonb_build_object('id',cp.id,'name',cp.name,'plan_code',cp.plan_code,'plan_type',cp.plan_type,'version_id',cpv.id,'version_number',cpv.version_number,'status',cpv.status,'effective_start_date',cpv.effective_start_date,'effective_end_date',cpv.effective_end_date,'currency_code',cpv.currency_code),
    'components', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'component_code',c.component_code,'description',c.description,'calculation_type',c.calculation_type,'measurement_source',c.measurement_source,'measurement_period',c.measurement_period,'calculation_order',c.calculation_order,'rule_configuration',c.rule_configuration,'maximum_payout',c.maximum_payout,'is_active',c.is_active) order by c.calculation_order,c.name) from public.comp_plan_components c where c.plan_version_id=cpv.id and c.is_active=true),'[]'::jsonb)
  ) into result
  from public.employees e
  join public.employee_plan_assignments epa on epa.employee_id=e.id
  join public.comp_plan_versions cpv on cpv.id=epa.plan_version_id
  join public.comp_plans cp on cp.id=cpv.comp_plan_id
  where e.id=resolved_employee_id
    and epa.effective_start_date <= current_date
    and (epa.effective_end_date is null or epa.effective_end_date >= current_date)
  order by epa.effective_start_date desc, cpv.version_number desc
  limit 1;

  return coalesce(result,jsonb_build_object('employee',null,'plan',null,'components','[]'::jsonb));
end;
$$;

grant execute on function public.get_my_compensation_plan() to authenticated;
