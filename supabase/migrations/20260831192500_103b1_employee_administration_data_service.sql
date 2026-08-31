create or replace function public.get_employee_administration_data()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare result jsonb;
begin
  if not private.has_permission('users.manage') then raise exception 'User administration is not permitted.' using errcode='42501'; end if;
  select jsonb_build_object('employees',coalesce(jsonb_agg(row_data order by row_data->>'full_name'),'[]'::jsonb)) into result from (
    select jsonb_build_object('employee_id',e.id,'full_name',e.full_name,'email',e.email,'title',e.job_title,'department',e.department,'manager_name',mgr.full_name,'is_active',e.is_active,'profile_status',case when pr.id is null then 'not_provisioned' when pr.is_active then 'active' else 'inactive' end,'has_app_access',coalesce(pr.is_active,false),'plan_name',cp.name,'plan_status',pv.status::text,'plan_effective_start_date',pa.effective_start_date,'plan_effective_end_date',pa.effective_end_date,'earnings_eligibility_date',pa.earnings_eligibility_date,'workflow_name',wv.workflow_name,'workflow_status',wv.status,'readiness',case when pr.is_active and pa.id is not null and pa.earnings_eligibility_date is not null and wv.id is not null then 'ready' else 'needs_setup' end,'readiness_reasons',to_jsonb(array_remove(array[case when pr.id is null then 'Application access has not been provisioned.' when not pr.is_active then 'Application access is inactive.' end,case when pa.id is null then 'No compensation plan is assigned for today.' end,case when pa.id is not null and pa.earnings_eligibility_date is null then 'Earnings eligibility date is missing.' end,case when wv.id is null then 'No active approval workflow is configured for today.' end],null))) row_data
    from public.employees e left join public.employees mgr on mgr.id=e.manager_id
    left join lateral (select p.* from public.profiles p where p.employee_id=e.id order by p.is_active desc,p.updated_at desc limit 1) pr on true
    left join lateral (select a.* from public.employee_plan_assignments a where a.employee_id=e.id and a.effective_start_date<=current_date and (a.effective_end_date is null or a.effective_end_date>=current_date) order by a.effective_start_date desc limit 1) pa on true
    left join public.comp_plan_versions pv on pv.id=pa.plan_version_id left join public.comp_plans cp on cp.id=pv.comp_plan_id
    left join lateral (select v.* from public.employee_approval_workflow_versions v where v.employee_id=e.id and v.status='active' and v.effective_start_date<=current_date and (v.effective_end_date is null or v.effective_end_date>=current_date) order by v.effective_start_date desc limit 1) wv on true where e.is_active
  ) q;
  return coalesce(result,jsonb_build_object('employees','[]'::jsonb));
end;$function$;
revoke all on function public.get_employee_administration_data() from public,anon;
grant execute on function public.get_employee_administration_data() to authenticated;
