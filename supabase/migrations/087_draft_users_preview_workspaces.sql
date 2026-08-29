-- 087 - Draft users, secure user preview, and multiple workspaces
--
-- Goals:
--   1. Let an administrator configure a person before creating an Auth account.
--   2. Preview the person's effective navigation and data scope without
--      impersonating them or issuing a session in their name.
--   3. Preserve the draft configuration when the invitation is accepted.
--   4. Let one signed-in person switch between My, Team, and Administration
--      workspaces when their combined roles and permissions allow it.
--
-- Preview is intentionally read-only. It returns a calculated access model;
-- it never changes auth.uid(), creates a login session, or performs actions as
-- the draft user.

create table if not exists public.app_user_drafts (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  full_name text not null,
  employee_id uuid references public.employees(id),
  auth_user_id uuid unique references auth.users(id),
  status text not null default 'draft',
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  ready_at timestamptz,
  invited_at timestamptz,
  activated_at timestamptz,
  cancelled_at timestamptz,
  notes text,
  constraint app_user_drafts_email_lowercase_check check (email = lower(email)),
  constraint app_user_drafts_status_check
    check (status in ('draft','ready','invited','activated','cancelled'))
);
alter table public.app_user_drafts enable row level security;
revoke all on table public.app_user_drafts from public, anon, authenticated;

create table if not exists private.draft_user_roles (
  draft_user_id uuid not null references public.app_user_drafts(id) on delete cascade,
  role_key text not null references private.app_roles(role_key) on delete restrict,
  assigned_by uuid not null references auth.users(id),
  assigned_at timestamptz not null default now(),
  primary key (draft_user_id, role_key)
);

create table if not exists private.draft_user_permission_overrides (
  draft_user_id uuid not null references public.app_user_drafts(id) on delete cascade,
  permission_key text not null references private.app_permissions(permission_key) on delete cascade,
  allowed boolean not null,
  reason text,
  granted_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (draft_user_id, permission_key)
);

create table if not exists private.draft_user_employee_permissions (
  draft_user_id uuid not null references public.app_user_drafts(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  permission_key text not null references private.app_permissions(permission_key) on delete cascade,
  allowed boolean not null,
  assigned_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (draft_user_id, employee_id, permission_key)
);

create table if not exists private.draft_user_plan_permissions (
  draft_user_id uuid not null references public.app_user_drafts(id) on delete cascade,
  comp_plan_id uuid not null references public.comp_plans(id) on delete cascade,
  permission_key text not null references private.app_permissions(permission_key) on delete cascade,
  allowed boolean not null,
  assigned_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (draft_user_id, comp_plan_id, permission_key)
);

revoke all on table private.draft_user_roles from public, anon, authenticated;
revoke all on table private.draft_user_permission_overrides from public, anon, authenticated;
revoke all on table private.draft_user_employee_permissions from public, anon, authenticated;
revoke all on table private.draft_user_plan_permissions from public, anon, authenticated;

insert into private.app_permissions (permission_key, category, display_name, description)
values
  ('workspace.view_self', 'Workspaces', 'View My dashboard', 'View the signed-in employee’s own plan, earnings, targets, and payments.'),
  ('workspace.view_team', 'Workspaces', 'View Team dashboard', 'View assigned employees, approvals, flags, and team compensation information.'),
  ('workspace.view_administration', 'Workspaces', 'View Administration', 'View authorized administrative configuration and operational tools.')
on conflict (permission_key) do update set
  category = excluded.category,
  display_name = excluded.display_name,
  description = excluded.description;

insert into private.role_permissions (role_key, permission_key, allowed)
values
  ('employee', 'workspace.view_self', true),
  ('management_approver', 'workspace.view_team', true),
  ('finance_payroll', 'workspace.view_administration', true),
  ('plan_administrator', 'workspace.view_administration', true),
  ('auditor_read_only', 'workspace.view_team', true)
on conflict (role_key, permission_key) do update set
  allowed = excluded.allowed,
  updated_at = now();

insert into private.role_permissions (role_key, permission_key, allowed)
select 'system_administrator', permission.permission_key, true
from private.app_permissions permission
on conflict (role_key, permission_key) do update set
  allowed = true,
  updated_at = now();

create or replace function private.draft_has_permission(
  selected_draft_user_id uuid,
  required_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (
      select 1
      from private.draft_user_permission_overrides override_row
      where override_row.draft_user_id = selected_draft_user_id
        and override_row.permission_key = required_permission
    ) then (
      select override_row.allowed
      from private.draft_user_permission_overrides override_row
      where override_row.draft_user_id = selected_draft_user_id
        and override_row.permission_key = required_permission
    )
    else coalesce((
      select bool_or(role_permission.allowed)
      from private.draft_user_roles draft_role
      join private.role_permissions role_permission
        on role_permission.role_key = draft_role.role_key
      where draft_role.draft_user_id = selected_draft_user_id
        and role_permission.permission_key = required_permission
    ), false)
  end;
$$;
revoke all on function private.draft_has_permission(uuid, text) from public, anon;
grant execute on function private.draft_has_permission(uuid, text) to authenticated;

create or replace function public.create_app_user_draft(
  selected_email text,
  selected_full_name text,
  selected_employee_id uuid default null,
  selected_role_keys text[] default array['employee']::text[],
  selected_notes text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  normalized_email text := lower(trim(selected_email));
  new_draft_id uuid;
begin
  if not private.has_permission('users.manage') then
    raise exception 'User administration is not permitted.' using errcode = '42501';
  end if;
  if normalized_email = '' or normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Enter a valid email address.' using errcode = '22023';
  end if;
  if split_part(normalized_email, '@', 2) <> 'engagifii.com' then
    raise exception 'The email domain is not allowed.' using errcode = '42501';
  end if;
  if trim(coalesce(selected_full_name, '')) = '' then
    raise exception 'A full name is required.' using errcode = '22023';
  end if;
  if exists (select 1 from auth.users account where lower(account.email) = normalized_email) then
    raise exception 'An active account already exists for this email.' using errcode = '23505';
  end if;
  if selected_employee_id is not null and not exists (
    select 1 from public.employees employee where employee.id = selected_employee_id
  ) then
    raise exception 'The selected employee does not exist.' using errcode = '22023';
  end if;
  if coalesce(array_length(selected_role_keys, 1), 0) = 0 or exists (
    select 1
    from unnest(selected_role_keys) requested_role
    where not exists (
      select 1 from private.app_roles role_catalog
      where role_catalog.role_key = requested_role
    )
  ) then
    raise exception 'Select at least one valid application role.' using errcode = '22023';
  end if;

  insert into public.app_user_drafts (
    email, full_name, employee_id, created_by, updated_by, notes
  ) values (
    normalized_email, trim(selected_full_name), selected_employee_id,
    (select auth.uid()), (select auth.uid()), nullif(trim(coalesce(selected_notes,'')),'')
  ) returning id into new_draft_id;

  insert into private.draft_user_roles (draft_user_id, role_key, assigned_by)
  select new_draft_id, requested_role, (select auth.uid())
  from unnest(selected_role_keys) requested_role;

  insert into public.app_access_audit_events (
    actor_user_id, event_type, event_reason, new_state, related_employee_id
  ) values (
    (select auth.uid()), 'user_draft_created',
    'An administrator created a user configuration before invitation.',
    jsonb_build_object('draft_user_id', new_draft_id, 'email', normalized_email,
      'roles', selected_role_keys, 'status', 'draft'),
    selected_employee_id
  );

  return jsonb_build_object('status','draft','draft_user_id',new_draft_id,
    'email',normalized_email,'invitation_sent',false);
end;
$$;

create or replace function public.get_app_user_draft_preview(selected_draft_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not private.has_app_role('system_administrator')
     or not private.has_permission('users.manage') then
    raise exception 'System administrator access is required for user preview.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.app_user_drafts draft where draft.id = selected_draft_user_id
  ) then
    raise exception 'The selected draft user does not exist.' using errcode = '22023';
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
      'invitation_sent', draft.status in ('invited','activated')
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
        when draft.employee_id is not null
          and private.draft_has_permission(draft.id, 'workspace.view_self')
        then jsonb_build_object('enabled',true,'employee_id',draft.employee_id)
      end,
      'team_dashboard', case
        when private.draft_has_permission(draft.id, 'workspace.view_team')
        then jsonb_build_object('enabled',true,'employee_scope',coalesce((
          select jsonb_agg(distinct permission.employee_id)
          from private.draft_user_employee_permissions permission
          where permission.draft_user_id = draft.id and permission.allowed = true
        ),'[]'::jsonb))
      end,
      'administration', case
        when private.draft_has_permission(draft.id, 'workspace.view_administration')
        then jsonb_build_object('enabled',true)
      end
    )),
    'employee_access', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employee_id', permission.employee_id,
        'employee_name', employee.full_name,
        'permission_key', permission.permission_key,
        'allowed', permission.allowed
      ) order by employee.full_name, permission.permission_key)
      from private.draft_user_employee_permissions permission
      join public.employees employee on employee.id = permission.employee_id
      where permission.draft_user_id = draft.id
    ), '[]'::jsonb),
    'plan_access', coalesce((
      select jsonb_agg(jsonb_build_object(
        'comp_plan_id', permission.comp_plan_id,
        'plan_name', plan.name,
        'permission_key', permission.permission_key,
        'allowed', permission.allowed
      ) order by plan.name, permission.permission_key)
      from private.draft_user_plan_permissions permission
      join public.comp_plans plan on plan.id = permission.comp_plan_id
      where permission.draft_user_id = draft.id
    ), '[]'::jsonb)
  ) into result
  from public.app_user_drafts draft
  where draft.id = selected_draft_user_id;

  return result;
end;
$$;

create or replace function public.get_my_available_workspaces()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'default_workspace', case
      when private.has_permission('workspace.view_self')
        and private.current_employee_id() is not null then 'my_dashboard'
      when private.has_permission('workspace.view_team') then 'team_dashboard'
      when private.has_permission('workspace.view_administration') then 'administration'
      else 'none'
    end,
    'workspaces', jsonb_strip_nulls(jsonb_build_object(
      'my_dashboard', case
        when private.has_permission('workspace.view_self')
          and private.current_employee_id() is not null
        then jsonb_build_object('enabled',true,'employee_id',private.current_employee_id())
      end,
      'team_dashboard', case
        when private.has_permission('workspace.view_team')
        then jsonb_build_object('enabled',true)
      end,
      'administration', case
        when private.has_permission('workspace.view_administration')
        then jsonb_build_object('enabled',true)
      end
    ))
  );
$$;

revoke all on function public.create_app_user_draft(text, text, uuid, text[], text) from public, anon;
revoke all on function public.get_app_user_draft_preview(uuid) from public, anon;
revoke all on function public.get_my_available_workspaces() from public, anon;
grant execute on function public.create_app_user_draft(text, text, uuid, text[], text) to authenticated;
grant execute on function public.get_app_user_draft_preview(uuid) to authenticated;
grant execute on function public.get_my_available_workspaces() to authenticated;

alter table public.app_user_invitations
  add column if not exists access_draft_id uuid unique
    references public.app_user_drafts(id) on delete set null;
alter table public.app_user_invitations
  drop constraint if exists app_user_invitations_status_check;
alter table public.app_user_invitations
  add constraint app_user_invitations_status_check
    check (status in ('prepared','pending','accepted','expired','revoked'));

create table if not exists private.draft_user_notification_preferences (
  draft_user_id uuid not null references public.app_user_drafts(id) on delete cascade,
  notification_type text not null references public.notification_types(notification_type) on delete cascade,
  in_app_enabled boolean not null default true,
  email_delivery text not null default 'immediate',
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (draft_user_id, notification_type),
  constraint draft_user_notification_delivery_check
    check (email_delivery in ('off','immediate','daily','weekly'))
);
revoke all on table private.draft_user_notification_preferences from public, anon, authenticated;

-- Change one role without replacing the person's other roles.
create or replace function public.set_app_user_draft_role(
  selected_draft_user_id uuid,
  selected_role_key text,
  selected_assigned boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.has_permission('roles.assign') then
    raise exception 'Role administration is not permitted.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.app_user_drafts draft where draft.id = selected_draft_user_id and draft.status in ('draft','ready')) then
    raise exception 'Only a draft or ready user can be changed.' using errcode = '22023';
  end if;
  if not exists (select 1 from private.app_roles role_catalog where role_catalog.role_key = selected_role_key) then
    raise exception 'The selected role does not exist.' using errcode = '22023';
  end if;

  if selected_assigned then
    insert into private.draft_user_roles (draft_user_id, role_key, assigned_by)
    values (selected_draft_user_id, selected_role_key, (select auth.uid()))
    on conflict (draft_user_id, role_key) do nothing;
  else
    if (select count(*) from private.draft_user_roles where draft_user_id = selected_draft_user_id) <= 1 then
      raise exception 'A draft user must retain at least one role.' using errcode = '23514';
    end if;
    delete from private.draft_user_roles
    where draft_user_id = selected_draft_user_id and role_key = selected_role_key;
  end if;

  update public.app_user_drafts set updated_by = (select auth.uid()), updated_at = now()
  where id = selected_draft_user_id;
  return jsonb_build_object('status','saved','draft_user_id',selected_draft_user_id,
    'role_key',selected_role_key,'assigned',selected_assigned);
end;
$$;

-- Change one granular permission at global, employee, or plan scope. Null
-- restores role inheritance, matching the active-user permission editor.
create or replace function public.set_app_user_draft_permission(
  selected_draft_user_id uuid,
  selected_permission_key text,
  selected_scope_type text,
  selected_scope_id uuid default null,
  selected_allowed boolean default null,
  decision_reason text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.has_permission('permissions.override') then
    raise exception 'Permission administration is not permitted.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.app_user_drafts draft where draft.id = selected_draft_user_id and draft.status in ('draft','ready')) then
    raise exception 'Only a draft or ready user can be changed.' using errcode = '22023';
  end if;
  if not exists (select 1 from private.app_permissions permission where permission.permission_key = selected_permission_key) then
    raise exception 'The selected permission does not exist.' using errcode = '22023';
  end if;
  if selected_scope_type not in ('global','employee','plan') then
    raise exception 'Scope must be global, employee, or plan.' using errcode = '22023';
  end if;
  if selected_scope_type <> 'global' and selected_scope_id is null then
    raise exception 'Select an employee or plan for this scope.' using errcode = '22023';
  end if;

  if selected_scope_type = 'global' then
    if selected_allowed is null then
      delete from private.draft_user_permission_overrides
      where draft_user_id = selected_draft_user_id and permission_key = selected_permission_key;
    else
      insert into private.draft_user_permission_overrides
        (draft_user_id, permission_key, allowed, reason, granted_by, updated_at)
      values (selected_draft_user_id, selected_permission_key, selected_allowed,
        nullif(trim(coalesce(decision_reason,'')),''), (select auth.uid()), now())
      on conflict (draft_user_id, permission_key) do update set
        allowed=excluded.allowed, reason=excluded.reason,
        granted_by=excluded.granted_by, updated_at=excluded.updated_at;
    end if;
  elsif selected_scope_type = 'employee' then
    if not exists (select 1 from public.employees where id = selected_scope_id) then
      raise exception 'The selected employee does not exist.' using errcode = '22023';
    end if;
    if selected_allowed is null then
      delete from private.draft_user_employee_permissions
      where draft_user_id=selected_draft_user_id and employee_id=selected_scope_id
        and permission_key=selected_permission_key;
    else
      insert into private.draft_user_employee_permissions
        (draft_user_id,employee_id,permission_key,allowed,assigned_by,updated_at)
      values (selected_draft_user_id,selected_scope_id,selected_permission_key,
        selected_allowed,(select auth.uid()),now())
      on conflict (draft_user_id,employee_id,permission_key) do update set
        allowed=excluded.allowed,assigned_by=excluded.assigned_by,updated_at=excluded.updated_at;
    end if;
  else
    if not exists (select 1 from public.comp_plans where id = selected_scope_id) then
      raise exception 'The selected plan does not exist.' using errcode = '22023';
    end if;
    if selected_allowed is null then
      delete from private.draft_user_plan_permissions
      where draft_user_id=selected_draft_user_id and comp_plan_id=selected_scope_id
        and permission_key=selected_permission_key;
    else
      insert into private.draft_user_plan_permissions
        (draft_user_id,comp_plan_id,permission_key,allowed,assigned_by,updated_at)
      values (selected_draft_user_id,selected_scope_id,selected_permission_key,
        selected_allowed,(select auth.uid()),now())
      on conflict (draft_user_id,comp_plan_id,permission_key) do update set
        allowed=excluded.allowed,assigned_by=excluded.assigned_by,updated_at=excluded.updated_at;
    end if;
  end if;

  update public.app_user_drafts set updated_by=(select auth.uid()),updated_at=now()
  where id=selected_draft_user_id;
  return jsonb_build_object('status','saved','draft_user_id',selected_draft_user_id,
    'permission_key',selected_permission_key,'scope_type',selected_scope_type,
    'scope_id',selected_scope_id,'allowed',selected_allowed,
    'inherits',selected_allowed is null);
end;
$$;

-- Copy an existing active user's access into a draft, then allow individual
-- changes before preview or invitation.
create or replace function public.copy_user_access_to_draft(
  source_user_id uuid,
  selected_draft_user_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.has_permission('permissions.override') then
    raise exception 'Permission administration is not permitted.' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id=source_user_id) then
    raise exception 'The source user does not exist.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.app_user_drafts where id=selected_draft_user_id and status in ('draft','ready')) then
    raise exception 'The destination draft cannot be changed.' using errcode = '22023';
  end if;

  delete from private.draft_user_roles where draft_user_id=selected_draft_user_id;
  delete from private.draft_user_permission_overrides where draft_user_id=selected_draft_user_id;
  delete from private.draft_user_employee_permissions where draft_user_id=selected_draft_user_id;
  delete from private.draft_user_plan_permissions where draft_user_id=selected_draft_user_id;

  insert into private.draft_user_roles (draft_user_id,role_key,assigned_by)
  select selected_draft_user_id,role_key,(select auth.uid())
  from private.user_roles where user_id=source_user_id;
  insert into private.draft_user_permission_overrides
    (draft_user_id,permission_key,allowed,reason,granted_by)
  select selected_draft_user_id,permission_key,allowed,
    'Copied from another user.',(select auth.uid())
  from private.user_permission_overrides where user_id=source_user_id;
  insert into private.draft_user_employee_permissions
    (draft_user_id,employee_id,permission_key,allowed,assigned_by)
  select selected_draft_user_id,employee_id,permission_key,allowed,(select auth.uid())
  from private.user_employee_permissions where user_id=source_user_id;
  insert into private.draft_user_plan_permissions
    (draft_user_id,comp_plan_id,permission_key,allowed,assigned_by)
  select selected_draft_user_id,comp_plan_id,permission_key,allowed,(select auth.uid())
  from private.user_plan_permissions where user_id=source_user_id;

  if not exists (select 1 from private.draft_user_roles where draft_user_id=selected_draft_user_id) then
    raise exception 'The source user has no roles to copy.' using errcode = '23514';
  end if;
  return jsonb_build_object('status','copied','source_user_id',source_user_id,
    'draft_user_id',selected_draft_user_id);
end;
$$;

-- Prepare the invitation record but do not send email. Sending remains an
-- explicit later UI action after the administrator finishes previewing.
create or replace function public.prepare_app_user_draft_invitation(selected_draft_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  draft public.app_user_drafts%rowtype;
  selected_roles text[];
  invitation_id uuid;
begin
  if not private.has_permission('users.manage') then
    raise exception 'User administration is not permitted.' using errcode = '42501';
  end if;
  select * into draft from public.app_user_drafts where id=selected_draft_user_id for update;
  if draft.id is null or draft.status not in ('draft','ready') then
    raise exception 'This draft is not available for invitation preparation.' using errcode = '22023';
  end if;
  select array_agg(role_key order by role_key) into selected_roles
  from private.draft_user_roles where draft_user_id=draft.id;
  if coalesce(array_length(selected_roles,1),0)=0 then
    raise exception 'Assign at least one role before preparing the invitation.' using errcode = '23514';
  end if;

  insert into public.app_user_invitations
    (email,full_name,employee_id,role_keys,status,invited_by,expires_at,notes,access_draft_id)
  values (draft.email,draft.full_name,draft.employee_id,selected_roles,'prepared',
    (select auth.uid()),now()+interval '7 days',draft.notes,draft.id)
  on conflict (email) do update set
    full_name=excluded.full_name,employee_id=excluded.employee_id,
    role_keys=excluded.role_keys,status='prepared',invited_by=excluded.invited_by,
    invited_at=now(),expires_at=excluded.expires_at,notes=excluded.notes,
    access_draft_id=excluded.access_draft_id,accepted_by=null,accepted_at=null,
    revoked_by=null,revoked_at=null
  returning id into invitation_id;

  update public.app_user_drafts set status='ready',ready_at=coalesce(ready_at,now()),
    updated_by=(select auth.uid()),updated_at=now() where id=draft.id;
  return jsonb_build_object('status','ready','draft_user_id',draft.id,
    'invitation_id',invitation_id,'invitation_sent',false);
end;
$$;

-- Call only after the external email provider confirms that the invitation was
-- sent. A prepared invitation cannot activate an account.
create or replace function public.mark_app_user_draft_invited(selected_draft_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  invitation_id uuid;
begin
  if not private.has_permission('users.manage') then
    raise exception 'User administration is not permitted.' using errcode='42501';
  end if;
  update public.app_user_invitations set status='pending',invited_at=now(),
    expires_at=now()+interval '7 days'
  where access_draft_id=selected_draft_user_id and status='prepared'
  returning id into invitation_id;
  if invitation_id is null then
    raise exception 'No prepared invitation exists for this draft.' using errcode='22023';
  end if;
  update public.app_user_drafts set status='invited',invited_at=now(),
    updated_by=(select auth.uid()),updated_at=now()
  where id=selected_draft_user_id and status='ready';
  return jsonb_build_object('status','invited','draft_user_id',selected_draft_user_id,
    'invitation_id',invitation_id);
end;
$$;

-- Replace the 086 activation trigger so a prepared draft's exact roles,
-- granular scopes, and notification preferences transfer to the real account.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation public.app_user_invitations%rowtype;
  linked_employee_id uuid;
  linked_draft_id uuid;
begin
  if new.email is null then raise exception 'An email address is required.' using errcode='42501'; end if;
  select invitation_row.* into invitation
  from public.app_user_invitations invitation_row
  where invitation_row.email=lower(new.email) and invitation_row.status='pending'
    and invitation_row.expires_at>now() for update;
  if invitation.id is null then raise exception 'An active invitation is required.' using errcode='42501'; end if;

  linked_draft_id := invitation.access_draft_id;
  linked_employee_id := coalesce(invitation.employee_id,(
    select id from public.employees where lower(email)=lower(new.email) limit 1));
  insert into public.profiles (id,email,full_name,employee_id,is_active)
  values (new.id,lower(new.email),coalesce(invitation.full_name,new.raw_user_meta_data->>'full_name',new.raw_user_meta_data->>'name'),linked_employee_id,true)
  on conflict (id) do update set email=excluded.email,
    full_name=coalesce(excluded.full_name,public.profiles.full_name),
    employee_id=coalesce(excluded.employee_id,public.profiles.employee_id),
    is_active=true,updated_at=now();

  insert into private.user_roles (user_id,role_key,assigned_by)
  select new.id,role_key,invitation.invited_by
  from private.draft_user_roles where draft_user_id=linked_draft_id
  on conflict (user_id,role_key) do nothing;
  if not found then
    insert into private.user_roles (user_id,role_key,assigned_by)
    select new.id,requested_role,invitation.invited_by
    from unnest(invitation.role_keys) requested_role
    join private.app_roles role_catalog on role_catalog.role_key=requested_role
    on conflict (user_id,role_key) do nothing;
  end if;

  insert into private.user_permission_overrides (user_id,permission_key,allowed,reason,granted_by)
  select new.id,permission_key,allowed,reason,invitation.invited_by
  from private.draft_user_permission_overrides where draft_user_id=linked_draft_id
  on conflict (user_id,permission_key) do update set allowed=excluded.allowed,reason=excluded.reason,granted_by=excluded.granted_by,updated_at=now();
  insert into private.user_employee_permissions (user_id,employee_id,permission_key,allowed,assigned_by)
  select new.id,employee_id,permission_key,allowed,invitation.invited_by
  from private.draft_user_employee_permissions where draft_user_id=linked_draft_id
  on conflict (user_id,employee_id,permission_key) do update set allowed=excluded.allowed,assigned_by=excluded.assigned_by,updated_at=now();
  insert into private.user_plan_permissions (user_id,comp_plan_id,permission_key,allowed,assigned_by)
  select new.id,comp_plan_id,permission_key,allowed,invitation.invited_by
  from private.draft_user_plan_permissions where draft_user_id=linked_draft_id
  on conflict (user_id,comp_plan_id,permission_key) do update set allowed=excluded.allowed,assigned_by=excluded.assigned_by,updated_at=now();
  insert into public.user_notification_preferences (user_id,notification_type,in_app_enabled,email_delivery)
  select new.id,notification_type,in_app_enabled,email_delivery
  from private.draft_user_notification_preferences where draft_user_id=linked_draft_id
  on conflict (user_id,notification_type) do update set in_app_enabled=excluded.in_app_enabled,email_delivery=excluded.email_delivery,updated_at=now();

  update public.app_user_invitations set status='accepted',accepted_by=new.id,accepted_at=now() where id=invitation.id;
  update public.app_user_drafts set status='activated',auth_user_id=new.id,activated_at=now(),updated_at=now()
  where id=linked_draft_id;
  insert into public.app_access_audit_events
    (actor_user_id,target_user_id,event_type,event_reason,new_state,related_employee_id)
  values (invitation.invited_by,new.id,'draft_user_activated',
    'The invited user activated the preconfigured account.',
    jsonb_build_object('email',lower(new.email),'draft_user_id',linked_draft_id),linked_employee_id);
  return new;
end;
$$;

revoke all on function public.set_app_user_draft_role(uuid,text,boolean) from public,anon;
revoke all on function public.set_app_user_draft_permission(uuid,text,text,uuid,boolean,text) from public,anon;
revoke all on function public.copy_user_access_to_draft(uuid,uuid) from public,anon;
revoke all on function public.prepare_app_user_draft_invitation(uuid) from public,anon;
revoke all on function public.mark_app_user_draft_invited(uuid) from public,anon;
grant execute on function public.set_app_user_draft_role(uuid,text,boolean) to authenticated;
grant execute on function public.set_app_user_draft_permission(uuid,text,text,uuid,boolean,text) to authenticated;
grant execute on function public.copy_user_access_to_draft(uuid,uuid) to authenticated;
grant execute on function public.prepare_app_user_draft_invitation(uuid) to authenticated;
grant execute on function public.mark_app_user_draft_invited(uuid) to authenticated;
revoke all on function public.handle_new_user() from public,anon,authenticated;
