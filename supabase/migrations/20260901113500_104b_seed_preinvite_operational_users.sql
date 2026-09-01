-- 104B - Pre-invite operational users and executive access tier
-- Captures production configuration for Namit Bhatia, Scott Key, and Rebecca Knight.
-- No invitations are sent by this migration.

begin;

-- Executive tier: broad compensation operations without security/user administration.
insert into private.app_roles (role_key, display_name, description, is_system)
values (
  'executive_administrator',
  'Executive administrator',
  'Executive-level compensation administration with broad operational visibility and authority, excluding system security and user-access administration.',
  true
)
on conflict (role_key) do update
set display_name = excluded.display_name,
    description = excluded.description,
    is_system = excluded.is_system;

-- Keep this role intentionally below system administrator.
insert into private.role_permissions (role_key, permission_key, allowed)
select 'executive_administrator', p.permission_key, true
from private.app_permissions p
where p.permission_key not in (
  'permissions.override',
  'roles.assign',
  'settings.manage',
  'users.manage'
)
on conflict (role_key, permission_key) do update
set allowed = excluded.allowed,
    updated_at = now();

delete from private.role_permissions
where role_key = 'executive_administrator'
  and permission_key in (
    'permissions.override',
    'roles.assign',
    'settings.manage',
    'users.manage'
  );

-- Finance / Accounting organization unit.
insert into public.organization_units (
  name, code, unit_type, parent_unit_id, description, is_active, display_order
)
values (
  'Finance / Accounting',
  'FINANCE_ACCOUNTING',
  'department',
  null,
  'Finance, accounting, payroll, and payment administration.',
  true,
  20
)
on conflict (code) do update
set name = excluded.name,
    unit_type = excluded.unit_type,
    description = excluded.description,
    is_active = true,
    updated_at = now();

-- Employee records. Rebecca manager intentionally remains unset until her
-- Sharon/Namit reporting relationship is confirmed.
insert into public.employees (email, full_name, job_title, department, manager_id, is_active)
values ('namitbhatia@engagifii.com','Namit Bhatia','CEO','Growth',null,true)
on conflict (email) do update
set full_name=excluded.full_name, job_title=excluded.job_title,
    department=excluded.department, manager_id=null, is_active=true, updated_at=now();

insert into public.employees (email, full_name, job_title, department, manager_id, is_active)
select 'scottkey@engagifii.com','Scott Key','CFO','Finance / Accounting',n.id,true
from public.employees n
where lower(n.email)='namitbhatia@engagifii.com'
on conflict (email) do update
set full_name=excluded.full_name, job_title=excluded.job_title,
    department=excluded.department, manager_id=excluded.manager_id,
    is_active=true, updated_at=now();

insert into public.employees (email, full_name, job_title, department, manager_id, is_active)
values ('rebeccaknight@engagifii.com','Rebecca Knight','Director of Association Solutions','Growth',null,true)
on conflict (email) do update
set full_name=excluded.full_name, job_title=excluded.job_title,
    department=excluded.department, is_active=true, updated_at=now();

-- Effective-dated organization membership.
insert into public.employee_org_assignments (
  employee_id, org_unit_id, relationship_type, is_primary, effective_start_date
)
select e.id,o.id,'primary',true,date '2026-09-01'
from public.employees e
join public.organization_units o on o.code='GROWTH'
where lower(e.email)='namitbhatia@engagifii.com'
on conflict (employee_id,org_unit_id,effective_start_date) do update
set relationship_type='primary',is_primary=true,effective_end_date=null,updated_at=now();

insert into public.employee_org_assignments (
  employee_id, org_unit_id, relationship_type, is_primary, effective_start_date
)
select e.id,o.id,'primary',true,date '2026-09-01'
from public.employees e
join public.organization_units o on o.code='FINANCE_ACCOUNTING'
where lower(e.email)='scottkey@engagifii.com'
on conflict (employee_id,org_unit_id,effective_start_date) do update
set relationship_type='primary',is_primary=true,effective_end_date=null,updated_at=now();

insert into public.employee_org_assignments (
  employee_id, org_unit_id, relationship_type, is_primary, effective_start_date
)
select e.id,o.id,'primary',true,date '2026-09-01'
from public.employees e
join public.organization_units o on o.code='GROWTH'
where lower(e.email)='rebeccaknight@engagifii.com'
on conflict (employee_id,org_unit_id,effective_start_date) do update
set relationship_type='primary',is_primary=true,effective_end_date=null,updated_at=now();

-- Draft owner is resolved by email rather than hard-coding an auth UUID.
do $block$
declare
  actor uuid;
  namit_employee uuid;
  scott_employee uuid;
  rebecca_employee uuid;
  growth_unit uuid;
  finance_unit uuid;
  namit_draft uuid;
  scott_draft uuid;
  rebecca_draft uuid;
begin
  select id into actor from auth.users where lower(email)='sharonwells@engagifii.com' limit 1;
  if actor is null then
    raise exception 'Sharon Wells auth user is required to seed pre-invite drafts.';
  end if;

  select id into namit_employee from public.employees where lower(email)='namitbhatia@engagifii.com';
  select id into scott_employee from public.employees where lower(email)='scottkey@engagifii.com';
  select id into rebecca_employee from public.employees where lower(email)='rebeccaknight@engagifii.com';
  select id into growth_unit from public.organization_units where code='GROWTH';
  select id into finance_unit from public.organization_units where code='FINANCE_ACCOUNTING';

  insert into public.app_user_drafts (
    email,full_name,employee_id,status,created_by,updated_by,notes,
    job_title,department,manager_employee_id,primary_org_unit_id,
    plan_version_id,employee_effective_start_date,earnings_eligibility_date
  ) values (
    'namitbhatia@engagifii.com','Namit Bhatia',namit_employee,'draft',actor,actor,
    'Pre-invite user configuration. Do not send invitation until explicitly approved.',
    'CEO','Growth',null,growth_unit,null,date '2026-09-01',null
  )
  on conflict (email) do update set
    full_name=excluded.full_name,employee_id=excluded.employee_id,status='draft',updated_by=actor,
    notes=excluded.notes,job_title=excluded.job_title,department=excluded.department,
    manager_employee_id=null,primary_org_unit_id=excluded.primary_org_unit_id,
    plan_version_id=null,employee_effective_start_date=excluded.employee_effective_start_date,
    earnings_eligibility_date=null,updated_at=now()
  returning id into namit_draft;

  insert into public.app_user_drafts (
    email,full_name,employee_id,status,created_by,updated_by,notes,
    job_title,department,manager_employee_id,primary_org_unit_id,
    plan_version_id,employee_effective_start_date,earnings_eligibility_date
  ) values (
    'scottkey@engagifii.com','Scott Key',scott_employee,'draft',actor,actor,
    'Pre-invite user configuration. Do not send invitation until explicitly approved.',
    'CFO','Finance / Accounting',namit_employee,finance_unit,null,date '2026-09-01',null
  )
  on conflict (email) do update set
    full_name=excluded.full_name,employee_id=excluded.employee_id,status='draft',updated_by=actor,
    notes=excluded.notes,job_title=excluded.job_title,department=excluded.department,
    manager_employee_id=excluded.manager_employee_id,primary_org_unit_id=excluded.primary_org_unit_id,
    plan_version_id=null,employee_effective_start_date=excluded.employee_effective_start_date,
    earnings_eligibility_date=null,updated_at=now()
  returning id into scott_draft;

  insert into public.app_user_drafts (
    email,full_name,employee_id,status,created_by,updated_by,notes,
    job_title,department,manager_employee_id,primary_org_unit_id,
    plan_version_id,employee_effective_start_date,earnings_eligibility_date
  ) values (
    'rebeccaknight@engagifii.com','Rebecca Knight',rebecca_employee,'draft',actor,actor,
    'Pre-invite user configuration. Do not send invitation until explicitly approved.',
    'Director of Association Solutions','Growth',null,growth_unit,null,date '2026-09-01',null
  )
  on conflict (email) do update set
    full_name=excluded.full_name,employee_id=excluded.employee_id,status='draft',updated_by=actor,
    notes=excluded.notes,job_title=excluded.job_title,department=excluded.department,
    primary_org_unit_id=excluded.primary_org_unit_id,plan_version_id=null,
    employee_effective_start_date=excluded.employee_effective_start_date,
    earnings_eligibility_date=null,updated_at=now()
  returning id into rebecca_draft;

  delete from private.draft_user_roles where draft_user_id in (namit_draft,scott_draft,rebecca_draft);
  insert into private.draft_user_roles(draft_user_id,role_key,assigned_by)
  values
    (namit_draft,'executive_administrator',actor),
    (scott_draft,'finance_payroll',actor),
    (scott_draft,'management_approver',actor),
    (rebecca_draft,'employee',actor);

  delete from private.draft_user_permission_overrides where draft_user_id in (namit_draft,scott_draft,rebecca_draft);
  insert into private.draft_user_permission_overrides(
    draft_user_id,permission_key,allowed,reason,granted_by
  ) values
    (scott_draft,'audit.view_all',true,'CFO requires company-wide reporting and audit visibility.',actor),
    (scott_draft,'reports.export_assigned',true,'CFO requires company-wide reporting and audit visibility.',actor);
end
$block$;

-- Employee administration read model includes pre-invite draft state.
create or replace function public.get_employee_administration_data()
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

  select jsonb_build_object('employees',coalesce(jsonb_agg(row_data order by row_data->>'full_name'),'[]'::jsonb)) into result
  from (
    select jsonb_build_object(
      'employee_id',e.id,'full_name',e.full_name,'email',e.email,'title',e.job_title,'department',e.department,
      'manager_name',mgr.full_name,'is_active',e.is_active,
      'profile_status',case when pr.id is null then 'not_provisioned' when pr.is_active then 'active' else 'inactive' end,
      'has_app_access',coalesce(pr.is_active,false),
      'draft_user_id',d.id,'draft_status',d.status,
      'draft_roles',coalesce((select jsonb_agg(r.role_key order by r.role_key) from private.draft_user_roles r where r.draft_user_id=d.id),'[]'::jsonb),
      'plan_name',cp.name,'plan_status',pv.status::text,
      'plan_effective_start_date',pa.effective_start_date,'plan_effective_end_date',pa.effective_end_date,
      'earnings_eligibility_date',pa.earnings_eligibility_date,
      'workflow_name',wv.workflow_name,'workflow_status',wv.status,
      'readiness',case when pr.is_active and pa.id is not null and pa.earnings_eligibility_date is not null and wv.id is not null then 'ready' else 'needs_setup' end,
      'readiness_reasons',to_jsonb(array_remove(array[
        case when pr.id is null and d.id is not null then 'Application access is configured as a pre-invite draft.' when pr.id is null then 'Application access has not been provisioned.' when not pr.is_active then 'Application access is inactive.' end,
        case when pa.id is null then 'No compensation plan is assigned for today.' end,
        case when pa.id is not null and pa.earnings_eligibility_date is null then 'Earnings eligibility date is missing.' end,
        case when wv.id is null then 'No active approval workflow is configured for today.' end
      ],null))
    ) row_data
    from public.employees e
    left join public.employees mgr on mgr.id=e.manager_id
    left join lateral (select p.* from public.profiles p where p.employee_id=e.id order by p.is_active desc,p.updated_at desc limit 1) pr on true
    left join lateral (select x.* from public.app_user_drafts x where x.employee_id=e.id and x.status<>'cancelled' order by x.updated_at desc limit 1) d on true
    left join lateral (select a.* from public.employee_plan_assignments a where a.employee_id=e.id and a.effective_start_date<=current_date and (a.effective_end_date is null or a.effective_end_date>=current_date) order by a.effective_start_date desc limit 1) pa on true
    left join public.comp_plan_versions pv on pv.id=pa.plan_version_id
    left join public.comp_plans cp on cp.id=pv.comp_plan_id
    left join lateral (select v.* from public.employee_approval_workflow_versions v where v.employee_id=e.id and v.status='active' and v.effective_start_date<=current_date and (v.effective_end_date is null or v.effective_end_date>=current_date) order by v.effective_start_date desc limit 1) wv on true
    where e.is_active
  ) q;
  return coalesce(result,jsonb_build_object('employees','[]'::jsonb));
end;
$function$;

revoke all on function public.get_employee_administration_data() from public,anon;
grant execute on function public.get_employee_administration_data() to authenticated;

commit;
