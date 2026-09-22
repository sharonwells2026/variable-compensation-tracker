create or replace function public.get_compensation_plan_admin_data()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare payload jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_app_role('system_administrator') or private.has_permission('plans.view') or private.has_permission('plans.edit')) then raise exception 'Plan access required.' using errcode='42501'; end if;
  select jsonb_build_object(
    'plans',coalesce((select jsonb_agg(jsonb_build_object(
      'plan_id',p.id,'name',p.name,'plan_code',p.plan_code,'description',p.description,'plan_type',p.plan_type,'is_active',p.is_active,
      'versions',coalesce((select jsonb_agg(jsonb_build_object(
        'version_id',v.id,'version_number',v.version_number,'status',v.status,'effective_start_date',v.effective_start_date,'effective_end_date',v.effective_end_date,'currency_code',v.currency_code,'notes',v.notes,'approved_at',v.approved_at,
        'components',coalesce((select jsonb_agg(jsonb_build_object('component_id',c.id,'name',c.name,'component_code',c.component_code,'description',c.description,'calculation_type',c.calculation_type,'measurement_source',c.measurement_source,'measurement_period',c.measurement_period,'calculation_order',c.calculation_order,'rule_configuration',c.rule_configuration,'maximum_payout',c.maximum_payout,'is_active',c.is_active,'payout_timing_method',c.payout_timing_method,'allow_manager_payout_override',c.allow_manager_payout_override,'measurement_label',c.measurement_label,'additional_eligibility_waiting_days',c.additional_eligibility_waiting_days) order by c.calculation_order,c.name) from public.comp_plan_components c where c.plan_version_id=v.id),'[]'::jsonb),
        'assignments',coalesce((select jsonb_agg(jsonb_build_object('assignment_id',a.id,'employee_id',a.employee_id,'employee_name',e.full_name,'allocation_percent',a.allocation_percent,'effective_start_date',a.effective_start_date,'effective_end_date',a.effective_end_date,'earnings_eligibility_date',a.earnings_eligibility_date) order by e.full_name,a.effective_start_date desc) from public.employee_plan_assignments a join public.employees e on e.id=a.employee_id where a.plan_version_id=v.id),'[]'::jsonb),
        'draft_assignments',coalesce((select jsonb_agg(jsonb_build_object('draft_assignment_id',d.id,'employee_id',d.employee_id,'employee_name',e.full_name,'allocation_percent',d.allocation_percent,'effective_start_date',d.effective_start_date,'effective_end_date',d.effective_end_date,'eligibility_waiting_period_days',d.eligibility_waiting_period_days,'earnings_eligibility_date',d.effective_start_date+d.eligibility_waiting_period_days,'assignment_notes',d.assignment_notes) order by e.full_name,d.effective_start_date desc) from public.comp_plan_draft_assignments d join public.employees e on e.id=d.employee_id where d.plan_version_id=v.id),'[]'::jsonb)
      ) order by v.version_number desc) from public.comp_plan_versions v where v.comp_plan_id=p.id),'[]'::jsonb)
    ) order by p.name) from public.comp_plans p),'[]'::jsonb),
    'employees',coalesce((select jsonb_agg(jsonb_build_object('employee_id',e.id,'employee_name',e.full_name,'email',e.email,'job_title',e.job_title,'department',e.department,'hire_date',e.hire_date) order by e.full_name) from public.employees e where e.is_active),'[]'::jsonb)
  ) into payload;
  return payload;
end;
$$;