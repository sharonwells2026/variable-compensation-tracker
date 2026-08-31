-- 103A User Administration Read Model
-- Provides one permission-protected RPC for the employee/user provisioning workspace.

create or replace function public.get_user_administration_data()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare result jsonb;
begin
  if not private.has_permission('users.manage') then
    raise exception 'User administration is not permitted.' using errcode='42501';
  end if;

  select jsonb_build_object(
    'employees', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id',e.id,'full_name',e.full_name,'email',e.email,'job_title',e.job_title,'department',e.department,
      'manager_employee_id',e.manager_id,'hire_date',e.hire_date,'is_active',e.is_active,
      'profile_user_id',p.id,'app_access_active',coalesce(p.is_active,false),
      'current_plan_version_id',pa.plan_version_id,'current_plan_name',cp.name,
      'earnings_eligibility_date',pa.earnings_eligibility_date,
      'current_workflow_id',wv.workflow_version_id,'current_workflow_name',wv.workflow_name
    ) order by e.full_name) from public.employees e
      left join public.profiles p on p.employee_id=e.id
      left join lateral (select a.plan_version_id,a.earnings_eligibility_date from public.employee_plan_assignments a where a.employee_id=e.id and a.effective_start_date<=current_date and (a.effective_end_date is null or a.effective_end_date>=current_date) order by a.effective_start_date desc limit 1) pa on true
      left join public.comp_plan_versions pv on pv.id=pa.plan_version_id
      left join public.comp_plans cp on cp.id=pv.comp_plan_id
      left join lateral (select v.id workflow_version_id,v.workflow_name from public.employee_approval_workflow_versions v where v.employee_id=e.id and v.status='active' and v.effective_start_date<=current_date and (v.effective_end_date is null or v.effective_end_date>=current_date) order by v.effective_start_date desc limit 1) wv on true
    ),'[]'::jsonb),
    'drafts', coalesce((select jsonb_agg(jsonb_build_object(
      'draft_user_id',d.id,'email',d.email,'full_name',d.full_name,'employee_id',d.employee_id,'status',d.status,
      'job_title',d.job_title,'department',d.department,'manager_employee_id',d.manager_employee_id,
      'primary_org_unit_id',d.primary_org_unit_id,'plan_version_id',d.plan_version_id,
      'employee_effective_start_date',d.employee_effective_start_date,'earnings_eligibility_date',d.earnings_eligibility_date,
      'roles',coalesce((select jsonb_agg(r.role_key order by r.role_key) from private.draft_user_roles r where r.draft_user_id=d.id),'[]'::jsonb)
    ) order by d.created_at desc) from public.app_user_drafts d where d.status<>'cancelled'),'[]'::jsonb),
    'managers', coalesce((select jsonb_agg(jsonb_build_object('employee_id',e.id,'full_name',e.full_name,'job_title',e.job_title) order by e.full_name) from public.employees e where e.is_active),'[]'::jsonb),
    'organization_units', coalesce((select jsonb_agg(jsonb_build_object('org_unit_id',o.id,'name',o.name) order by o.name) from public.organization_units o where o.is_active),'[]'::jsonb),
    'active_plan_versions', coalesce((select jsonb_agg(jsonb_build_object('plan_version_id',pv.id,'plan_id',cp.id,'name',cp.name,'version_number',pv.version_number,'effective_start_date',pv.effective_start_date,'effective_end_date',pv.effective_end_date) order by cp.name,pv.version_number) from public.comp_plan_versions pv join public.comp_plans cp on cp.id=pv.comp_plan_id where pv.status='active'),'[]'::jsonb),
    'roles', coalesce((select jsonb_agg(jsonb_build_object('role_key',r.role_key,'display_name',r.display_name) order by r.display_name) from private.app_roles r),'[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(jsonb_build_object('permission_key',p.permission_key,'display_name',p.display_name,'category',p.category) order by p.category,p.display_name) from private.app_permissions p),'[]'::jsonb)
  ) into result;
  return result;
end;
$function$;

revoke all on function public.get_user_administration_data() from public,anon;
grant execute on function public.get_user_administration_data() to authenticated;
comment on function public.get_user_administration_data() is '103A read model for the employee and user provisioning administration workspace.';
