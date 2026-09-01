-- 098 - Team Scope Authorization Engine
-- Applied manually to production and verified before source-control sync.

create or replace function private.can_access_employee(
  target_employee_id uuid,
  required_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
with recursive
current_actor as (
  select private.current_employee_id() as employee_id
),
required_scope as (
  select
    case
      when required_permission in ('earnings.approve','earnings.return','claims.review') then 'approve'
      when required_permission in ('earnings.adjust','earnings.override') then 'manage'
      else 'view'
    end as scope_type
),
explicit_employee_decision as (
  select employee_permission.allowed
  from private.user_employee_permissions employee_permission
  where employee_permission.user_id = auth.uid()
    and employee_permission.employee_id = target_employee_id
    and employee_permission.permission_key = required_permission
  limit 1
),
current_management_scopes as (
  select
    scope.org_unit_id,
    scope.scope_type,
    scope.include_descendants
  from public.management_scopes scope
  join current_actor actor on actor.employee_id = scope.manager_employee_id
  join required_scope needed on (
    scope.scope_type = needed.scope_type
    or (needed.scope_type = 'view' and scope.scope_type in ('view','manage','approve'))
  )
  where current_date >= scope.effective_start_date
    and (scope.effective_end_date is null or current_date <= scope.effective_end_date)
),
scope_org_tree as (
  select
    scope.org_unit_id as root_org_unit_id,
    scope.org_unit_id as covered_org_unit_id,
    scope.include_descendants
  from current_management_scopes scope

  union all

  select
    tree.root_org_unit_id,
    child.id as covered_org_unit_id,
    tree.include_descendants
  from scope_org_tree tree
  join public.organization_units child
    on child.parent_unit_id = tree.covered_org_unit_id
  where tree.include_descendants = true
    and child.is_active = true
),
management_scope_access as (
  select exists (
    select 1
    from public.employee_org_assignments assignment
    join scope_org_tree tree
      on tree.covered_org_unit_id = assignment.org_unit_id
    where assignment.employee_id = target_employee_id
      and current_date >= assignment.effective_start_date
      and (assignment.effective_end_date is null or current_date <= assignment.effective_end_date)
  ) as allowed
)
select
  private.has_permission(required_permission)
  and (
    private.has_app_role('system_administrator')
    or target_employee_id = (select employee_id from current_actor)
    or coalesce((select allowed from explicit_employee_decision), false) = true
    or (
      not exists (
        select 1 from explicit_employee_decision where allowed = false
      )
      and coalesce((select allowed from management_scope_access), false)
    )
  );
$function$;

revoke all on function private.can_access_employee(uuid,text) from public;
revoke all on function private.can_access_employee(uuid,text) from anon;
grant execute on function private.can_access_employee(uuid,text) to authenticated;
