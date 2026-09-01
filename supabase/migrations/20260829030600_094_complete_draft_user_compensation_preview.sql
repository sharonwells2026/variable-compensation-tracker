-- 094 - Complete Draft User Compensation Preview
-- ALREADY APPLIED MANUALLY TO PRODUCTION.
-- Extends pre-invitation preview so an administrator can verify the real compensation plan/components
-- and, when available, actual employee earnings before inviting the user.

create or replace function public.get_app_user_draft_preview(
  selected_draft_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  result jsonb;
begin
  if not private.has_app_role('system_administrator')
     or not private.has_permission('users.manage') then
    raise exception 'System administrator access is required for user preview.'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.app_user_drafts draft
    where draft.id = selected_draft_user_id
  ) then
    raise exception 'The selected draft user does not exist.'
      using errcode = '22023';
  end if;

  select jsonb_build_object(
    'preview_mode', true,
    'read_only', true,
    'preview_banner', 'Previewing as ' || draft.full_name,

    'user', jsonb_build_object(
      'draft_user_id', draft.id,
      'email', draft.email,
      'full_name', draft.full_name,
      'employee_id', draft.employee_id,
      'status', draft.status,
      'invitation_sent', draft.status in ('invited','activated'),
      'job_title', coalesce(draft.job_title, employee.job_title),
      'department', coalesce(draft.department, employee.department),
      'manager_employee_id', coalesce(draft.manager_employee_id, employee.manager_id),
      'primary_org_unit_id', draft.primary_org_unit_id,
      'selected_plan_version_id', coalesce(draft.plan_version_id, current_assignment.plan_version_id),
      'employee_effective_start_date', draft.employee_effective_start_date
    ),

    'roles', coalesce((
      select jsonb_agg(draft_role.role_key order by draft_role.role_key)
      from private.draft_user_roles draft_role
      where draft_role.draft_user_id = draft.id
    ), '[]'::jsonb),

    'permissions', coalesce((
      select jsonb_agg(permission.permission_key order by permission.permission_key)
      from private.app_permissions permission
      where private.draft_has_permission(draft.id, permission.permission_key)
    ), '[]'::jsonb),

    'workspaces', jsonb_strip_nulls(jsonb_build_object(
      'my_dashboard', case
        when (draft.employee_id is not null or draft.plan_version_id is not null)
          and private.draft_has_permission(draft.id, 'workspace.view_self')
        then jsonb_build_object(
          'enabled', true,
          'employee_id', draft.employee_id,
          'preview_plan_version_id', coalesce(draft.plan_version_id, current_assignment.plan_version_id)
        )
      end,
      'team_dashboard', case
        when private.draft_has_permission(draft.id, 'workspace.view_team')
        then jsonb_build_object(
          'enabled', true,
          'employee_scope', coalesce((
            select jsonb_agg(distinct employee_permission.employee_id)
            from private.draft_user_employee_permissions employee_permission
            where employee_permission.draft_user_id = draft.id
              and employee_permission.allowed = true
          ), '[]'::jsonb),
          'primary_org_unit_id', draft.primary_org_unit_id
        )
      end,
      'administration', case
        when private.draft_has_permission(draft.id, 'workspace.view_administration')
        then jsonb_build_object('enabled', true)
      end
    )),

    'employee_access', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employee_id', employee_permission.employee_id,
        'employee_name', scoped_employee.full_name,
        'permission_key', employee_permission.permission_key,
        'allowed', employee_permission.allowed
      ) order by scoped_employee.full_name, employee_permission.permission_key)
      from private.draft_user_employee_permissions employee_permission
      join public.employees scoped_employee on scoped_employee.id = employee_permission.employee_id
      where employee_permission.draft_user_id = draft.id
    ), '[]'::jsonb),

    'plan_access', coalesce((
      select jsonb_agg(jsonb_build_object(
        'comp_plan_id', plan_permission.comp_plan_id,
        'plan_name', permitted_plan.name,
        'permission_key', plan_permission.permission_key,
        'allowed', plan_permission.allowed
      ) order by permitted_plan.name, plan_permission.permission_key)
      from private.draft_user_plan_permissions plan_permission
      join public.comp_plans permitted_plan on permitted_plan.id = plan_permission.comp_plan_id
      where plan_permission.draft_user_id = draft.id
    ), '[]'::jsonb),

    'compensation_preview', jsonb_build_object(
      'preview_source', case
        when draft.employee_id is not null then 'existing_employee'
        when draft.plan_version_id is not null then 'selected_plan'
        else 'no_plan_selected'
      end,
      'plan', case
        when preview_version.id is null then null
        else jsonb_build_object(
          'plan_id', preview_plan.id,
          'plan_version_id', preview_version.id,
          'name', preview_plan.name,
          'plan_code', preview_plan.plan_code,
          'description', preview_plan.description,
          'version_number', preview_version.version_number,
          'status', preview_version.status,
          'effective_start_date', preview_version.effective_start_date,
          'effective_end_date', preview_version.effective_end_date
        )
      end,
      'components', coalesce((
        select jsonb_agg(jsonb_build_object(
          'component_id', component.id,
          'name', component.name,
          'component_code', component.component_code,
          'description', component.description,
          'calculation_type', component.calculation_type,
          'measurement_source', component.measurement_source,
          'measurement_period', component.measurement_period,
          'measurement_label', component.measurement_label,
          'maximum_payout', component.maximum_payout,
          'rule_configuration', component.rule_configuration,
          'earned_amount', coalesce(component_summary.earned_amount,0),
          'eligible_amount', coalesce(component_summary.eligible_amount,0),
          'approved_amount', coalesce(component_summary.approved_amount,0),
          'paid_amount', coalesce(component_summary.paid_amount,0),
          'earning_count', coalesce(component_summary.earning_count,0),
          'preview_has_live_earnings', coalesce(component_summary.earning_count,0) > 0
        ) order by component.calculation_order)
        from public.comp_plan_components component
        left join lateral (
          select
            sum(earning.earned_amount) filter (where earning.is_current) as earned_amount,
            sum(earning.eligible_amount) filter (where earning.is_current) as eligible_amount,
            sum(earning.approved_amount) filter (where earning.is_current) as approved_amount,
            sum(earning.paid_amount) filter (where earning.is_current) as paid_amount,
            count(*) filter (where earning.is_current) as earning_count
          from public.comp_earnings earning
          where draft.employee_id is not null
            and earning.employee_id = draft.employee_id
            and earning.plan_component_id = component.id
        ) component_summary on true
        where component.plan_version_id = preview_version.id
          and component.is_active = true
      ), '[]'::jsonb),
      'earnings', case
        when draft.employee_id is null then '[]'::jsonb
        else coalesce((
          select jsonb_agg(jsonb_build_object(
            'earning_id', earning.id,
            'component_id', earning.plan_component_id,
            'component_name', earning_component.name,
            'earning_name', earning.earning_name,
            'earning_description', earning.earning_description,
            'source_type', earning.source_type,
            'source_external_id', earning.source_external_id,
            'source_url', earning.source_url,
            'earned_date', earning.earned_date,
            'earned_amount', earning.earned_amount,
            'eligibility_status', earning.eligibility_status,
            'eligible_date', earning.eligible_date,
            'eligible_amount', earning.eligible_amount,
            'employee_verification_status', earning.employee_verification_status,
            'manager_approval_status', earning.manager_approval_status,
            'executive_approval_status', earning.executive_approval_status,
            'approved_amount', earning.approved_amount,
            'payment_status', earning.payment_status,
            'paid_amount', earning.paid_amount,
            'hold_reason', earning.hold_reason
          ) order by earning.earned_date desc, earning.created_at desc)
          from public.comp_earnings earning
          left join public.comp_plan_components earning_component on earning_component.id = earning.plan_component_id
          where earning.employee_id = draft.employee_id
            and earning.is_current = true
        ), '[]'::jsonb)
      end
    )
  ) into result
  from public.app_user_drafts draft
  left join public.employees employee on employee.id = draft.employee_id
  left join lateral (
    select assignment.plan_version_id
    from public.employee_plan_assignments assignment
    where assignment.employee_id = draft.employee_id
      and assignment.effective_start_date <= current_date
      and (assignment.effective_end_date is null or assignment.effective_end_date >= current_date)
    order by assignment.effective_start_date desc
    limit 1
  ) current_assignment on true
  left join public.comp_plan_versions preview_version
    on preview_version.id = coalesce(draft.plan_version_id, current_assignment.plan_version_id)
  left join public.comp_plans preview_plan on preview_plan.id = preview_version.comp_plan_id
  where draft.id = selected_draft_user_id;

  return result;
end;
$function$;

grant execute on function public.get_app_user_draft_preview(uuid) to authenticated;
