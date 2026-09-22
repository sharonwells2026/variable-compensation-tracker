-- 086 - Access, permissions, settings, invitations, and notifications
-- Role defaults are inherited. A per-user decision can explicitly grant or deny
-- one action. Employee and plan decisions can then narrow that action to one
-- employee or one plan. A user-specific decision always wins over a role default.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
grant usage on schema private to authenticated;

create table if not exists private.app_roles (
  role_key text primary key,
  display_name text not null,
  description text not null,
  is_system boolean not null default true,
  created_at timestamptz not null default now(),
  constraint app_roles_role_key_check
    check (role_key ~ '^[a-z][a-z0-9_]*$')
);

create table if not exists private.app_permissions (
  permission_key text primary key,
  category text not null,
  display_name text not null,
  description text not null,
  created_at timestamptz not null default now(),
  constraint app_permissions_permission_key_check
    check (permission_key ~ '^[a-z][a-z0-9_.]*$')
);

create table if not exists private.role_permissions (
  role_key text not null references private.app_roles(role_key) on delete cascade,
  permission_key text not null references private.app_permissions(permission_key) on delete cascade,
  allowed boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (role_key, permission_key)
);

create table if not exists private.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role_key text not null references private.app_roles(role_key) on delete restrict,
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz not null default now(),
  primary key (user_id, role_key)
);

create table if not exists private.user_permission_overrides (
  user_id uuid not null references auth.users(id) on delete cascade,
  permission_key text not null references private.app_permissions(permission_key) on delete cascade,
  allowed boolean not null,
  reason text,
  granted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, permission_key)
);

create table if not exists private.user_employee_permissions (
  user_id uuid not null references auth.users(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  permission_key text not null references private.app_permissions(permission_key) on delete cascade,
  allowed boolean not null default true,
  assigned_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, employee_id, permission_key)
);

create table if not exists private.user_plan_permissions (
  user_id uuid not null references auth.users(id) on delete cascade,
  comp_plan_id uuid not null references public.comp_plans(id) on delete cascade,
  permission_key text not null references private.app_permissions(permission_key) on delete cascade,
  allowed boolean not null default true,
  assigned_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, comp_plan_id, permission_key)
);

revoke all on all tables in schema private from public;
revoke all on all tables in schema private from anon;
revoke all on all tables in schema private from authenticated;

insert into private.app_roles (role_key, display_name, description)
values
  ('system_administrator', 'System administrator', 'Full access to compensation data, configuration, security, and audit history.'),
  ('management_approver', 'Management approver', 'Reviews assigned employees and handles approvals, corrections, flags, and adjustments.'),
  ('finance_payroll', 'Finance or payroll', 'Controls approved and payable earnings, payment scheduling, exports, holds, and corrections.'),
  ('plan_administrator', 'Plan administrator', 'Creates, versions, configures, and prepares compensation plans for activation.'),
  ('employee', 'Employee', 'Views and acts on the signed-in employee’s own plan, earnings, submissions, and statements.'),
  ('auditor_read_only', 'Auditor or read-only', 'Reads only explicitly assigned employees or compensation plans.')
on conflict (role_key) do update set
  display_name = excluded.display_name,
  description = excluded.description;

insert into private.app_permissions (permission_key, category, display_name, description)
values
  ('users.manage', 'Users', 'Manage users', 'Invite, activate, deactivate, and configure user access.'),
  ('roles.assign', 'Users', 'Assign roles', 'Assign or remove inherited application roles.'),
  ('permissions.override', 'Users', 'Override permissions', 'Grant or deny a permission for a specific user.'),
  ('settings.manage', 'Settings', 'Manage organization settings', 'Configure time zone, currency, plan years, pay periods, deadlines, refreshes, domains, and retention.'),
  ('plans.view', 'Plans', 'View plans', 'View compensation plan rules and versions.'),
  ('plans.create', 'Plans', 'Create plans', 'Create compensation plans and draft versions.'),
  ('plans.edit', 'Plans', 'Edit plans', 'Edit draft plan components and rules.'),
  ('plans.activate', 'Plans', 'Activate plans', 'Activate an approved, acknowledged, effective-dated plan version.'),
  ('plans.approve', 'Plans', 'Approve plans', 'Provide management approval before plan activation.'),
  ('plans.acknowledge_own', 'Plans', 'Acknowledge own plan', 'Acknowledge an assigned plan version.'),
  ('earnings.view', 'Earnings', 'View earnings', 'View compensation earnings within the user’s assigned scope.'),
  ('earnings.submit_own', 'Earnings', 'Submit own earnings', 'Submit the signed-in employee’s earnings for approval.'),
  ('earnings.dispute_own', 'Earnings', 'Request correction', 'Request a correction or dispute an earning.'),
  ('earnings.attach_own', 'Earnings', 'Add supporting documents', 'Add comments or supporting documents to an earning.'),
  ('claims.submit_own', 'Earnings', 'Submit missing earning claims', 'Submit a HubSpot deal that the employee believes should produce an earning.'),
  ('claims.review', 'Approvals', 'Review missing earning claims', 'Review, approve, deny, or return an employee’s missing earning claim.'),
  ('earnings.approve', 'Approvals', 'Approve or reject earnings', 'Approve or reject earnings for assigned employees.'),
  ('earnings.return', 'Approvals', 'Return earnings', 'Return an earning to the employee for correction.'),
  ('earnings.override', 'Approvals', 'Override earning amounts', 'Override an earning amount with a required reason and audit record.'),
  ('earnings.adjust', 'Approvals', 'Add adjustments', 'Create a manual earning or adjustment with approval history.'),
  ('flags.resolve', 'Approvals', 'Resolve data flags', 'Resolve ownership, source-data, and compensation review flags.'),
  ('payments.view', 'Payments', 'View payable earnings', 'View approved and payable earnings within scope.'),
  ('payments.schedule', 'Payments', 'Schedule payments', 'Assign earnings to a payment schedule or payroll period.'),
  ('payments.mark_paid', 'Payments', 'Mark payments paid', 'Record completed compensation payments.'),
  ('payments.export', 'Payments', 'Export payroll files', 'Export approved payroll-ready compensation.'),
  ('payments.hold', 'Payments', 'Manage payment holds', 'Place or release payment holds.'),
  ('payments.correct', 'Payments', 'Correct payment records', 'Correct payment details while preserving audit history.'),
  ('reports.download_own', 'Reports', 'Download own reports', 'Download the signed-in employee’s statements and reports.'),
  ('reports.export_assigned', 'Reports', 'Export assigned reports', 'Export reports for assigned employees or plans.'),
  ('audit.view_assigned', 'Audit', 'View assigned audit history', 'View audit history only for explicitly assigned employees or plans.'),
  ('audit.view_all', 'Audit', 'View all audit history', 'View the complete compensation and access audit history.'),
  ('hubspot.refresh', 'Integrations', 'Refresh HubSpot', 'Run the protected HubSpot and compensation refresh.'),
  ('notifications.configure_own', 'Notifications', 'Configure own notifications', 'Choose in-app and email delivery per notification type.')
on conflict (permission_key) do update set
  category = excluded.category,
  display_name = excluded.display_name,
  description = excluded.description;

-- Role permissions are additive. A user-specific override, when present,
-- takes precedence and may either grant or deny a permission.
insert into private.role_permissions (role_key, permission_key)
select 'system_administrator', permission_key from private.app_permissions
on conflict (role_key, permission_key) do update set allowed = true, updated_at = now();

insert into private.role_permissions (role_key, permission_key)
values
  ('management_approver', 'plans.view'),
  ('management_approver', 'earnings.view'),
  ('management_approver', 'earnings.approve'),
  ('management_approver', 'earnings.return'),
  ('management_approver', 'earnings.override'),
  ('management_approver', 'earnings.adjust'),
  ('management_approver', 'flags.resolve'),
  ('management_approver', 'claims.review'),
  ('finance_payroll', 'earnings.view'),
  ('finance_payroll', 'payments.view'),
  ('finance_payroll', 'payments.schedule'),
  ('finance_payroll', 'payments.mark_paid'),
  ('finance_payroll', 'payments.export'),
  ('finance_payroll', 'payments.hold'),
  ('finance_payroll', 'payments.correct'),
  ('plan_administrator', 'plans.view'),
  ('plan_administrator', 'plans.create'),
  ('plan_administrator', 'plans.edit'),
  ('plan_administrator', 'plans.activate'),
  ('employee', 'plans.view'),
  ('employee', 'plans.acknowledge_own'),
  ('employee', 'earnings.view'),
  ('employee', 'earnings.submit_own'),
  ('employee', 'earnings.dispute_own'),
  ('employee', 'earnings.attach_own'),
  ('employee', 'claims.submit_own'),
  ('employee', 'reports.download_own'),
  ('employee', 'notifications.configure_own'),
  ('auditor_read_only', 'plans.view'),
  ('auditor_read_only', 'earnings.view'),
  ('auditor_read_only', 'audit.view_assigned')
on conflict (role_key, permission_key) do update set allowed = true, updated_at = now();

-- Every signed-in role may manage its own user-editable preferences. This is
-- separate from security, organization, and workflow settings, which remain
-- administrator-controlled.
insert into private.role_permissions (role_key, permission_key)
select role_key, 'notifications.configure_own'
from private.app_roles
on conflict (role_key, permission_key) do update set allowed = true, updated_at = now();

alter table public.profiles
  add column if not exists is_active boolean not null default true,
  add column if not exists deactivated_at timestamptz,
  add column if not exists deactivated_by uuid references auth.users(id),
  add column if not exists deactivation_reason text;

create table if not exists public.organization_settings (
  setting_key text primary key,
  setting_value jsonb not null,
  description text not null,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.organization_settings enable row level security;

create table if not exists public.user_setting_definitions (
  setting_key text primary key,
  category text not null,
  display_name text not null,
  description text not null,
  default_value jsonb not null,
  user_can_edit boolean not null default false,
  administrator_can_edit boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.user_setting_definitions enable row level security;

insert into public.user_setting_definitions (
  setting_key, category, display_name, description, default_value,
  user_can_edit, administrator_can_edit
)
values
  ('display_time_zone', 'Display', 'Display time zone', 'Controls how dates and times are displayed for this user.', '"America/New_York"', true, true),
  ('date_format', 'Display', 'Date format', 'Controls the date format displayed to this user.', '"MMM d, yyyy"', true, true),
  ('default_dashboard_period', 'Display', 'Default dashboard period', 'Controls the period shown when the user opens the dashboard.', '"YTD"', true, true),
  ('email_digest_time', 'Notifications', 'Email digest time', 'Controls when daily or weekly email summaries are sent.', '"08:00"', true, true),
  ('email_digest_day', 'Notifications', 'Weekly digest day', 'Controls which weekday a weekly email summary is sent.', '"Monday"', true, true),
  ('management_landing_view', 'Display', 'Management landing view', 'Controls the default management workspace screen.', '"dashboard"', true, true),
  ('account_roles', 'Security', 'Application roles', 'Inherited access roles assigned to the user.', '[]', false, true),
  ('permission_overrides', 'Security', 'Permission overrides', 'Explicit permission grants or denials for the user.', '{}', false, true),
  ('employee_access_scope', 'Security', 'Employee access scope', 'Employees and actions this user is permitted to access.', '[]', false, true),
  ('account_active', 'Security', 'Account active', 'Whether the user may sign in to the application.', 'true', false, true)
on conflict (setting_key) do update set
  category = excluded.category,
  display_name = excluded.display_name,
  description = excluded.description,
  default_value = excluded.default_value,
  user_can_edit = excluded.user_can_edit,
  administrator_can_edit = excluded.administrator_can_edit,
  updated_at = now();

create table if not exists public.user_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  setting_key text not null references public.user_setting_definitions(setting_key) on delete cascade,
  setting_value jsonb not null,
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, setting_key)
);
alter table public.user_settings enable row level security;

insert into public.organization_settings (setting_key, setting_value, description)
values
  ('localization', '{"time_zone":"America/New_York","currency_code":"USD"}', 'Application time zone and reporting currency.'),
  ('plan_calendar', '{"plan_year_start_month":1,"calendar_year_start_month":1}', 'Plan-year and calendar-year boundaries.'),
  ('payroll', '{"period_type":"monthly","payment_target_rule":"configurable"}', 'Pay periods and target payment dates.'),
  ('approvals', '{"default_due_days":5,"escalation_enabled":true,"escalation_days":2}', 'Approval deadlines and escalation defaults.'),
  ('hubspot_refresh', '{"refresh_on_open":true,"manual_refresh":true,"scheduled_refresh":"not_configured"}', 'HubSpot synchronization schedule and controls.'),
  ('allowed_email_domains', '["engagifii.com"]', 'Email domains permitted for invited users.'),
  ('audit_retention', '{"retain_history":"indefinitely","allow_deletion":false}', 'Retention rules for access, configuration, earnings, approval, and payment history.')
on conflict (setting_key) do nothing;

create table if not exists public.app_user_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  full_name text,
  employee_id uuid references public.employees(id),
  role_keys text[] not null default array['employee']::text[],
  status text not null default 'pending',
  invited_by uuid not null references auth.users(id),
  invited_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  revoked_by uuid references auth.users(id),
  revoked_at timestamptz,
  notes text,
  constraint app_user_invitations_email_lowercase_check check (email = lower(email)),
  constraint app_user_invitations_status_check check (status in ('pending','accepted','expired','revoked'))
);
alter table public.app_user_invitations enable row level security;

create table if not exists public.employee_approval_chains (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  approval_order integer not null,
  approver_user_id uuid not null references auth.users(id),
  backup_approver_user_id uuid references auth.users(id),
  approval_level text not null default 'manager',
  is_required boolean not null default true,
  effective_start_date date not null,
  effective_end_date date,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_approval_chains_order_check check (approval_order > 0),
  constraint employee_approval_chains_date_check check (effective_end_date is null or effective_end_date >= effective_start_date),
  unique (employee_id, approval_order, effective_start_date)
);
alter table public.employee_approval_chains enable row level security;

create table if not exists public.plan_version_acknowledgments (
  id uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references public.comp_plan_versions(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  acknowledged_by uuid not null references auth.users(id),
  acknowledged_at timestamptz not null default now(),
  acknowledgment_text text not null,
  plan_snapshot jsonb not null default '{}'::jsonb,
  unique (plan_version_id, employee_id)
);
alter table public.plan_version_acknowledgments enable row level security;

create table if not exists public.missing_earning_claims (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  submitted_by uuid not null references auth.users(id),
  hubspot_deal_id text not null,
  plan_component_id uuid references public.comp_plan_components(id),
  explanation text not null,
  status text not null default 'submitted',
  assigned_to uuid references auth.users(id),
  linked_comp_earning_id uuid references public.comp_earnings(id),
  resolution text,
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint missing_earning_claims_status_check
    check (status in ('submitted','under_review','returned','approved','denied','resolved')),
  constraint missing_earning_claims_explanation_check
    check (char_length(trim(explanation)) >= 10)
);
alter table public.missing_earning_claims enable row level security;

create index if not exists missing_earning_claims_employee_idx
  on public.missing_earning_claims(employee_id, submitted_at desc);
create index if not exists missing_earning_claims_queue_idx
  on public.missing_earning_claims(assigned_to, status, submitted_at);

create table if not exists public.notification_types (
  notification_type text primary key,
  display_name text not null,
  description text not null,
  default_priority text not null default 'normal',
  is_active boolean not null default true,
  constraint notification_types_priority_check check (default_priority in ('low','normal','high','urgent'))
);
alter table public.notification_types enable row level security;

insert into public.notification_types (notification_type, display_name, description, default_priority)
values
  ('earning_created', 'New earning', 'A new earning was created.', 'normal'),
  ('earning_eligible', 'Earning eligible', 'An earning became eligible for payment.', 'high'),
  ('approval_status_changed', 'Approval status changed', 'An earning was submitted, approved, rejected, or returned.', 'high'),
  ('plan_assigned_or_changed', 'Plan assigned or changed', 'A compensation plan was assigned or changed.', 'high'),
  ('payment_scheduled', 'Payment scheduled', 'A compensation payment was scheduled.', 'normal'),
  ('payment_completed', 'Payment completed', 'A compensation payment was recorded as paid.', 'high'),
  ('ownership_or_data_mismatch', 'Ownership or data mismatch', 'An ownership or source-data mismatch requires review.', 'high'),
  ('earning_changed_or_removed', 'Earning changed or removed', 'A refresh changed or removed a previously earned item.', 'urgent'),
  ('hubspot_refresh_failed', 'HubSpot refresh failed', 'HubSpot synchronization did not complete.', 'urgent'),
  ('approval_overdue', 'Approval overdue', 'An approval passed its due date.', 'high'),
  ('payment_overdue', 'Payment overdue', 'A scheduled payment passed its target date.', 'urgent')
on conflict (notification_type) do update set
  display_name = excluded.display_name,
  description = excluded.description,
  default_priority = excluded.default_priority;

create table if not exists private.role_notification_defaults (
  role_key text not null references private.app_roles(role_key) on delete cascade,
  notification_type text not null references public.notification_types(notification_type) on delete cascade,
  in_app_enabled boolean not null default true,
  email_delivery text not null default 'immediate',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (role_key, notification_type),
  constraint role_notification_defaults_delivery_check check (email_delivery in ('off','immediate','daily','weekly'))
);

insert into private.role_notification_defaults (role_key, notification_type, in_app_enabled, email_delivery)
select role.role_key, notification.notification_type, true,
  case
    when notification.default_priority in ('urgent','high') then 'immediate'
    else 'daily'
  end
from private.app_roles role
cross join public.notification_types notification
on conflict (role_key, notification_type) do nothing;

create table if not exists public.user_notification_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_type text not null references public.notification_types(notification_type) on delete cascade,
  in_app_enabled boolean not null default true,
  email_delivery text not null default 'immediate',
  updated_at timestamptz not null default now(),
  primary key (user_id, notification_type),
  constraint user_notification_preferences_delivery_check check (email_delivery in ('off','immediate','daily','weekly'))
);
alter table public.user_notification_preferences enable row level security;

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  notification_type text not null references public.notification_types(notification_type),
  title text not null,
  message text not null,
  priority text not null default 'normal',
  related_record_type text,
  related_record_id text,
  action_url text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  email_status text not null default 'not_queued',
  email_queued_at timestamptz,
  email_sent_at timestamptz,
  constraint app_notifications_priority_check check (priority in ('low','normal','high','urgent')),
  constraint app_notifications_email_status_check check (email_status in ('not_queued','queued','sent','failed','suppressed'))
);
alter table public.app_notifications enable row level security;

create index if not exists app_notifications_recipient_unread_idx
  on public.app_notifications(recipient_user_id, created_at desc)
  where read_at is null;

create table if not exists public.app_access_audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id),
  target_user_id uuid references auth.users(id),
  event_type text not null,
  event_reason text,
  previous_state jsonb not null default '{}'::jsonb,
  new_state jsonb not null default '{}'::jsonb,
  related_employee_id uuid references public.employees(id),
  related_plan_id uuid references public.comp_plans(id),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table public.app_access_audit_events enable row level security;

create index if not exists app_access_audit_actor_idx
  on public.app_access_audit_events(actor_user_id, occurred_at desc);
create index if not exists app_access_audit_target_idx
  on public.app_access_audit_events(target_user_id, occurred_at desc);

revoke all on table public.organization_settings from anon, authenticated;
revoke all on table public.user_setting_definitions from anon, authenticated;
revoke all on table public.user_settings from anon, authenticated;
revoke all on table public.app_user_invitations from anon, authenticated;
revoke all on table public.employee_approval_chains from anon, authenticated;
revoke all on table public.plan_version_acknowledgments from anon, authenticated;
revoke all on table public.missing_earning_claims from anon, authenticated;
revoke all on table public.notification_types from anon, authenticated;
revoke all on table public.user_notification_preferences from anon, authenticated;
revoke all on table public.app_notifications from anon, authenticated;
revoke all on table public.app_access_audit_events from anon, authenticated;

create or replace function private.has_app_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from private.user_roles role_assignment
      join public.profiles profile on profile.id = role_assignment.user_id
      where role_assignment.user_id = (select auth.uid())
        and role_assignment.role_key = required_role
        and profile.is_active = true
    );
$$;

create or replace function private.has_permission(required_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then false
    when not exists (
      select 1 from public.profiles profile
      where profile.id = (select auth.uid()) and profile.is_active = true
    ) then false
    when exists (
      select 1 from private.user_permission_overrides override_row
      where override_row.user_id = (select auth.uid())
        and override_row.permission_key = required_permission
    ) then (
      select override_row.allowed
      from private.user_permission_overrides override_row
      where override_row.user_id = (select auth.uid())
        and override_row.permission_key = required_permission
    )
    else coalesce((
      select bool_or(role_permission.allowed)
      from private.user_roles user_role
      join private.role_permissions role_permission
        on role_permission.role_key = user_role.role_key
      where user_role.user_id = (select auth.uid())
        and role_permission.permission_key = required_permission
    ), false)
  end;
$$;

create or replace function private.current_employee_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select profile.employee_id
  from public.profiles profile
  where profile.id = (select auth.uid())
    and profile.is_active = true;
$$;

create or replace function private.can_access_employee(
  target_employee_id uuid,
  required_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission(required_permission)
    and (
      private.has_app_role('system_administrator')
      or target_employee_id = private.current_employee_id()
      or exists (
        select 1
        from private.user_employee_permissions employee_permission
        where employee_permission.user_id = (select auth.uid())
          and employee_permission.employee_id = target_employee_id
          and employee_permission.permission_key = required_permission
          and employee_permission.allowed = true
      )
    );
$$;

create or replace function private.can_access_plan(
  target_plan_id uuid,
  required_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission(required_permission)
    and (
      private.has_app_role('system_administrator')
      or exists (
        select 1
        from private.user_plan_permissions plan_permission
        where plan_permission.user_id = (select auth.uid())
          and plan_permission.comp_plan_id = target_plan_id
          and plan_permission.permission_key = required_permission
          and plan_permission.allowed = true
      )
    );
$$;

revoke all on function private.has_app_role(text) from public, anon;
revoke all on function private.has_permission(text) from public, anon;
revoke all on function private.current_employee_id() from public, anon;
revoke all on function private.can_access_employee(uuid, text) from public, anon;
revoke all on function private.can_access_plan(uuid, text) from public, anon;
grant execute on function private.has_app_role(text) to authenticated;
grant execute on function private.has_permission(text) to authenticated;
grant execute on function private.current_employee_id() to authenticated;
grant execute on function private.can_access_employee(uuid, text) to authenticated;
grant execute on function private.can_access_plan(uuid, text) to authenticated;

-- Harden account creation: authorization never depends on user-editable metadata.
-- A matching, unexpired administrator invitation is required for every new user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation public.app_user_invitations%rowtype;
  linked_employee_id uuid;
begin
  if new.email is null then
    raise exception 'An email address is required.' using errcode = '42501';
  end if;

  select invitation_row.*
  into invitation
  from public.app_user_invitations invitation_row
  where invitation_row.email = lower(new.email)
    and invitation_row.status = 'pending'
    and invitation_row.expires_at > pg_catalog.now()
  for update;

  if invitation.id is null then
    raise exception 'An active invitation is required.' using errcode = '42501';
  end if;

  linked_employee_id := coalesce(
    invitation.employee_id,
    (
      select employee.id
      from public.employees employee
      where lower(employee.email) = lower(new.email)
      limit 1
    )
  );

  insert into public.profiles (
    id, email, full_name, employee_id, is_active
  )
  values (
    new.id,
    lower(new.email),
    coalesce(invitation.full_name, new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    linked_employee_id,
    true
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    employee_id = coalesce(excluded.employee_id, public.profiles.employee_id),
    is_active = true,
    updated_at = pg_catalog.now();

  insert into private.user_roles (user_id, role_key, assigned_by)
  select new.id, requested_role, invitation.invited_by
  from unnest(invitation.role_keys) requested_role
  join private.app_roles role_catalog on role_catalog.role_key = requested_role
  on conflict (user_id, role_key) do nothing;

  update public.app_user_invitations
  set status = 'accepted', accepted_by = new.id, accepted_at = pg_catalog.now()
  where id = invitation.id;

  insert into public.app_access_audit_events (
    actor_user_id, target_user_id, event_type, event_reason, new_state, related_employee_id
  ) values (
    invitation.invited_by,
    new.id,
    'invitation_accepted',
    'The invited user completed first sign-in.',
    jsonb_build_object('email', lower(new.email), 'roles', invitation.role_keys),
    linked_employee_id
  );

  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Preserve the existing confirmed Sharon account and assign full administration.
insert into private.user_roles (user_id, role_key, assigned_by)
select user_row.id, 'system_administrator', user_row.id
from auth.users user_row
where lower(user_row.email) = 'sharonwells@engagifii.com'
on conflict (user_id, role_key) do nothing;

create or replace function public.get_current_user_access()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then
      jsonb_build_object('authenticated', false)
    else
      jsonb_build_object(
        'authenticated', true,
        'user_id', profile.id,
        'email', profile.email,
        'full_name', profile.full_name,
        'employee_id', profile.employee_id,
        'is_active', profile.is_active,
        'roles', coalesce((
          select jsonb_agg(user_role.role_key order by user_role.role_key)
          from private.user_roles user_role
          where user_role.user_id = profile.id
        ), '[]'::jsonb),
        'permissions', coalesce((
          select jsonb_agg(permission.permission_key order by permission.permission_key)
          from private.app_permissions permission
          where private.has_permission(permission.permission_key)
        ), '[]'::jsonb)
      )
  end
  from public.profiles profile
  where profile.id = (select auth.uid());
$$;

create or replace function public.get_compensation_employee_data(target_employee_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  resolved_employee_id uuid := coalesce(target_employee_id, private.current_employee_id());
  result jsonb;
begin
  if resolved_employee_id is null
     or not private.can_access_employee(resolved_employee_id, 'earnings.view') then
    raise exception 'Employee access is not permitted.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'employee', jsonb_build_object(
      'id', employee.id,
      'full_name', employee.full_name,
      'email', employee.email,
      'job_title', employee.job_title,
      'department', employee.department,
      'is_active', employee.is_active
    ),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'assignment_id', assignment.id,
        'plan_name', plan.name,
        'version_number', version.version_number,
        'status', version.status,
        'effective_start_date', assignment.effective_start_date,
        'effective_end_date', assignment.effective_end_date,
        'acknowledged', exists (
          select 1 from public.plan_version_acknowledgments acknowledgment
          where acknowledgment.plan_version_id = version.id
            and acknowledgment.employee_id = resolved_employee_id
        )
      ) order by assignment.effective_start_date desc)
      from public.employee_plan_assignments assignment
      join public.comp_plan_versions version on version.id = assignment.plan_version_id
      join public.comp_plans plan on plan.id = version.comp_plan_id
      where assignment.employee_id = resolved_employee_id
    ), '[]'::jsonb),
    'components', coalesce((
      select jsonb_agg(jsonb_build_object(
        'component_id', component.id,
        'component_name', component.name,
        'component_code', component.component_code,
        'description', component.description,
        'calculation_type', component.calculation_type,
        'measurement_source', component.measurement_source,
        'measurement_period', component.measurement_period,
        'rule_configuration', component.rule_configuration,
        'earned_amount', coalesce(summary.earned_amount, 0),
        'eligible_amount', coalesce(summary.eligible_amount, 0),
        'paid_amount', coalesce(summary.paid_amount, 0),
        'earning_count', coalesce(summary.earning_count, 0)
      ) order by component.calculation_order)
      from public.employee_plan_assignments assignment
      join public.comp_plan_components component on component.plan_version_id = assignment.plan_version_id
      left join lateral (
        select
          sum(earning.earned_amount) filter (where earning.is_current) as earned_amount,
          sum(earning.eligible_amount) filter (where earning.is_current) as eligible_amount,
          sum(earning.paid_amount) filter (where earning.is_current) as paid_amount,
          count(*) filter (where earning.is_current) as earning_count
        from public.comp_earnings earning
        where earning.employee_id = resolved_employee_id
          and earning.plan_component_id = component.id
      ) summary on true
      where assignment.employee_id = resolved_employee_id
        and component.is_active = true
    ), '[]'::jsonb),
    'earnings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'earning_id', earning.id,
        'component_name', component.name,
        'earning_name', earning.earning_name,
        'source_external_id', earning.source_external_id,
        'source_url', earning.source_url,
        'earned_date', earning.earned_date,
        'earned_amount', earning.earned_amount,
        'eligibility_status', earning.eligibility_status,
        'eligible_date', earning.eligible_date,
        'eligible_amount', earning.eligible_amount,
        'manager_approval_status', earning.manager_approval_status,
        'payment_status', earning.payment_status,
        'paid_amount', earning.paid_amount,
        'source_snapshot', earning.source_snapshot
      ) order by earning.earned_date desc, earning.created_at desc)
      from public.comp_earnings earning
      left join public.comp_plan_components component on component.id = earning.plan_component_id
      where earning.employee_id = resolved_employee_id
        and earning.is_current = true
    ), '[]'::jsonb)
  )
  into result
  from public.employees employee
  where employee.id = resolved_employee_id;

  return result;
end;
$$;

create or replace function public.get_my_notification_preferences()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'notification_type', notification.notification_type,
    'display_name', notification.display_name,
    'description', notification.description,
    'in_app_enabled', coalesce(preference.in_app_enabled, inherited.in_app_enabled, true),
    'email_delivery', coalesce(preference.email_delivery, inherited.email_delivery, 'immediate'),
    'is_user_override', preference.user_id is not null
  ) order by notification.display_name), '[]'::jsonb)
  from public.notification_types notification
  left join public.user_notification_preferences preference
    on preference.user_id = (select auth.uid())
   and preference.notification_type = notification.notification_type
  left join lateral (
    select
      bool_or(role_default.in_app_enabled) as in_app_enabled,
      case
        when bool_or(role_default.email_delivery = 'immediate') then 'immediate'
        when bool_or(role_default.email_delivery = 'daily') then 'daily'
        when bool_or(role_default.email_delivery = 'weekly') then 'weekly'
        else 'off'
      end as email_delivery
    from private.user_roles user_role
    join private.role_notification_defaults role_default
      on role_default.role_key = user_role.role_key
     and role_default.notification_type = notification.notification_type
    where user_role.user_id = (select auth.uid())
  ) inherited on true
  where notification.is_active = true
    and private.has_permission('notifications.configure_own');
$$;

create or replace function public.set_my_notification_preference(
  selected_notification_type text,
  enable_in_app boolean,
  selected_email_delivery text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.has_permission('notifications.configure_own') then
    raise exception 'Notification settings are not permitted.' using errcode = '42501';
  end if;
  if selected_email_delivery not in ('off','immediate','daily','weekly') then
    raise exception 'Invalid email delivery setting.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.notification_types notification
    where notification.notification_type = selected_notification_type
      and notification.is_active = true
  ) then
    raise exception 'Unknown notification type.' using errcode = '22023';
  end if;

  insert into public.user_notification_preferences (
    user_id, notification_type, in_app_enabled, email_delivery, updated_at
  ) values (
    (select auth.uid()), selected_notification_type, enable_in_app,
    selected_email_delivery, pg_catalog.now()
  )
  on conflict (user_id, notification_type) do update set
    in_app_enabled = excluded.in_app_enabled,
    email_delivery = excluded.email_delivery,
    updated_at = excluded.updated_at;

  return jsonb_build_object('status','saved','notification_type',selected_notification_type);
end;
$$;

create or replace function public.get_my_user_settings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'setting_key', definition.setting_key,
    'category', definition.category,
    'display_name', definition.display_name,
    'description', definition.description,
    'setting_value', coalesce(user_setting.setting_value, definition.default_value),
    'user_can_edit', definition.user_can_edit,
    'is_user_override', user_setting.user_id is not null
  ) order by definition.category, definition.display_name), '[]'::jsonb)
  from public.user_setting_definitions definition
  left join public.user_settings user_setting
    on user_setting.user_id = (select auth.uid())
   and user_setting.setting_key = definition.setting_key
  where definition.is_active = true;
$$;

create or replace function public.set_my_user_setting(
  selected_setting_key text,
  selected_setting_value jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Sign-in required.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.user_setting_definitions definition
    where definition.setting_key = selected_setting_key
      and definition.is_active = true
      and definition.user_can_edit = true
  ) then
    raise exception 'This setting can only be changed by an administrator.' using errcode = '42501';
  end if;

  insert into public.user_settings (
    user_id, setting_key, setting_value, updated_by, updated_at
  ) values (
    (select auth.uid()), selected_setting_key, selected_setting_value,
    (select auth.uid()), pg_catalog.now()
  )
  on conflict (user_id, setting_key) do update set
    setting_value = excluded.setting_value,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  return jsonb_build_object('status','saved','setting_key',selected_setting_key);
end;
$$;

create or replace function public.submit_missing_earning_claim(
  submitted_hubspot_deal_id text,
  submitted_explanation text,
  submitted_plan_component_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  claimant_employee_id uuid := private.current_employee_id();
  assigned_approver uuid;
  new_claim_id uuid;
  normalized_deal_id text := trim(submitted_hubspot_deal_id);
begin
  if not private.has_permission('claims.submit_own')
     or claimant_employee_id is null then
    raise exception 'Missing earning claims are not permitted.' using errcode = '42501';
  end if;
  if normalized_deal_id = '' or normalized_deal_id !~ '^[0-9]+$' then
    raise exception 'Enter the numeric HubSpot deal ID.' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(submitted_explanation, ''))) < 10 then
    raise exception 'Please explain why the deal should count.' using errcode = '22023';
  end if;
  if submitted_plan_component_id is not null and not exists (
    select 1
    from public.employee_plan_assignments assignment
    join public.comp_plan_components component
      on component.plan_version_id = assignment.plan_version_id
    where assignment.employee_id = claimant_employee_id
      and component.id = submitted_plan_component_id
      and component.is_active = true
  ) then
    raise exception 'The selected plan component is not assigned to this employee.' using errcode = '42501';
  end if;

  select chain.approver_user_id
  into assigned_approver
  from public.employee_approval_chains chain
  where chain.employee_id = claimant_employee_id
    and chain.is_required = true
    and current_date >= chain.effective_start_date
    and (chain.effective_end_date is null or current_date <= chain.effective_end_date)
  order by chain.approval_order
  limit 1;

  if assigned_approver is null then
    select user_role.user_id
    into assigned_approver
    from private.user_roles user_role
    join public.profiles profile on profile.id = user_role.user_id
    where user_role.role_key = 'system_administrator'
      and profile.is_active = true
    order by user_role.assigned_at
    limit 1;
  end if;

  insert into public.missing_earning_claims (
    employee_id, submitted_by, hubspot_deal_id, plan_component_id,
    explanation, assigned_to
  ) values (
    claimant_employee_id, (select auth.uid()), normalized_deal_id,
    submitted_plan_component_id, trim(submitted_explanation), assigned_approver
  ) returning id into new_claim_id;

  insert into public.app_access_audit_events (
    actor_user_id, target_user_id, event_type, event_reason,
    new_state, related_employee_id
  ) values (
    (select auth.uid()), assigned_approver, 'missing_earning_claim_submitted',
    'An employee submitted a HubSpot deal for compensation review.',
    jsonb_build_object(
      'claim_id', new_claim_id,
      'hubspot_deal_id', normalized_deal_id,
      'plan_component_id', submitted_plan_component_id,
      'explanation', trim(submitted_explanation)
    ),
    claimant_employee_id
  );

  if assigned_approver is not null then
    insert into public.app_notifications (
      recipient_user_id, notification_type, title, message, priority,
      related_record_type, related_record_id
    ) values (
      assigned_approver,
      'ownership_or_data_mismatch',
      'Missing earning claim submitted',
      'An employee submitted HubSpot deal ' || normalized_deal_id || ' for review.',
      'high',
      'missing_earning_claim',
      new_claim_id::text
    );
  end if;

  return jsonb_build_object(
    'status', 'submitted',
    'claim_id', new_claim_id,
    'hubspot_deal_id', normalized_deal_id,
    'deal_is_synchronized', exists (
      select 1 from public.hubspot_deals deal
      where deal.hubspot_deal_id = normalized_deal_id
    ),
    'assigned_to', assigned_approver
  );
end;
$$;

-- Administrative access editor. One call changes exactly one decision at one
-- scope. Passing null restores inheritance from the user's role defaults.
create or replace function public.set_user_permission_decision(
  target_user_id uuid,
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
declare
  previous_decision boolean;
begin
  if not private.has_permission('permissions.override') then
    raise exception 'Permission administration is not allowed.' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users user_row where user_row.id = target_user_id) then
    raise exception 'The selected user does not exist.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from private.app_permissions permission
    where permission.permission_key = selected_permission_key
  ) then
    raise exception 'The selected permission does not exist.' using errcode = '22023';
  end if;
  if selected_scope_type not in ('global','employee','plan') then
    raise exception 'Scope must be global, employee, or plan.' using errcode = '22023';
  end if;
  if selected_scope_type <> 'global' and selected_scope_id is null then
    raise exception 'An employee or plan must be selected for this scope.' using errcode = '22023';
  end if;

  if selected_scope_type = 'global' then
    select decision.allowed into previous_decision
    from private.user_permission_overrides decision
    where decision.user_id = target_user_id
      and decision.permission_key = selected_permission_key;
    if selected_allowed is null then
      delete from private.user_permission_overrides decision
      where decision.user_id = target_user_id
        and decision.permission_key = selected_permission_key;
    else
      insert into private.user_permission_overrides (
        user_id, permission_key, allowed, reason, granted_by, updated_at
      ) values (
        target_user_id, selected_permission_key, selected_allowed,
        nullif(trim(coalesce(decision_reason,'')),''), (select auth.uid()), pg_catalog.now()
      )
      on conflict (user_id, permission_key) do update set
        allowed = excluded.allowed, reason = excluded.reason,
        granted_by = excluded.granted_by, updated_at = excluded.updated_at;
    end if;
  elsif selected_scope_type = 'employee' then
    if not exists (select 1 from public.employees employee where employee.id = selected_scope_id) then
      raise exception 'The selected employee does not exist.' using errcode = '22023';
    end if;
    select decision.allowed into previous_decision
    from private.user_employee_permissions decision
    where decision.user_id = target_user_id
      and decision.employee_id = selected_scope_id
      and decision.permission_key = selected_permission_key;
    if selected_allowed is null then
      delete from private.user_employee_permissions decision
      where decision.user_id = target_user_id
        and decision.employee_id = selected_scope_id
        and decision.permission_key = selected_permission_key;
    else
      insert into private.user_employee_permissions (
        user_id, employee_id, permission_key, allowed, assigned_by, updated_at
      ) values (
        target_user_id, selected_scope_id, selected_permission_key,
        selected_allowed, (select auth.uid()), pg_catalog.now()
      )
      on conflict (user_id, employee_id, permission_key) do update set
        allowed = excluded.allowed, assigned_by = excluded.assigned_by,
        updated_at = excluded.updated_at;
    end if;
  else
    if not exists (select 1 from public.comp_plans plan where plan.id = selected_scope_id) then
      raise exception 'The selected plan does not exist.' using errcode = '22023';
    end if;
    select decision.allowed into previous_decision
    from private.user_plan_permissions decision
    where decision.user_id = target_user_id
      and decision.comp_plan_id = selected_scope_id
      and decision.permission_key = selected_permission_key;
    if selected_allowed is null then
      delete from private.user_plan_permissions decision
      where decision.user_id = target_user_id
        and decision.comp_plan_id = selected_scope_id
        and decision.permission_key = selected_permission_key;
    else
      insert into private.user_plan_permissions (
        user_id, comp_plan_id, permission_key, allowed, assigned_by, updated_at
      ) values (
        target_user_id, selected_scope_id, selected_permission_key,
        selected_allowed, (select auth.uid()), pg_catalog.now()
      )
      on conflict (user_id, comp_plan_id, permission_key) do update set
        allowed = excluded.allowed, assigned_by = excluded.assigned_by,
        updated_at = excluded.updated_at;
    end if;
  end if;

  insert into public.app_access_audit_events (
    actor_user_id, target_user_id, event_type, event_reason,
    previous_state, new_state, related_employee_id, related_plan_id
  ) values (
    (select auth.uid()), target_user_id, 'permission_decision_changed',
    coalesce(nullif(trim(coalesce(decision_reason,'')),''), 'Access configuration changed.'),
    jsonb_build_object('allowed', previous_decision),
    jsonb_build_object('permission_key', selected_permission_key,
      'scope_type', selected_scope_type, 'scope_id', selected_scope_id,
      'allowed', selected_allowed, 'inherits_when_null', selected_allowed is null),
    case when selected_scope_type = 'employee' then selected_scope_id end,
    case when selected_scope_type = 'plan' then selected_scope_id end
  );

  return jsonb_build_object('status','saved','user_id',target_user_id,
    'permission_key',selected_permission_key,'scope_type',selected_scope_type,
    'scope_id',selected_scope_id,'allowed',selected_allowed,
    'inherits',selected_allowed is null);
end;
$$;

create or replace function public.get_user_access_configuration(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not private.has_permission('permissions.override') then
    raise exception 'Permission administration is not allowed.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'user_id', target_user_id,
    'roles', coalesce((select jsonb_agg(role_assignment.role_key order by role_assignment.role_key)
      from private.user_roles role_assignment where role_assignment.user_id = target_user_id), '[]'::jsonb),
    'global_decisions', coalesce((select jsonb_agg(jsonb_build_object(
      'permission_key', decision.permission_key, 'allowed', decision.allowed, 'reason', decision.reason)
      order by decision.permission_key)
      from private.user_permission_overrides decision where decision.user_id = target_user_id), '[]'::jsonb),
    'employee_decisions', coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', decision.employee_id, 'employee_name', employee.full_name,
      'permission_key', decision.permission_key, 'allowed', decision.allowed)
      order by employee.full_name, decision.permission_key)
      from private.user_employee_permissions decision
      join public.employees employee on employee.id = decision.employee_id
      where decision.user_id = target_user_id), '[]'::jsonb),
    'plan_decisions', coalesce((select jsonb_agg(jsonb_build_object(
      'comp_plan_id', decision.comp_plan_id, 'plan_name', plan.name,
      'permission_key', decision.permission_key, 'allowed', decision.allowed)
      order by plan.name, decision.permission_key)
      from private.user_plan_permissions decision
      join public.comp_plans plan on plan.id = decision.comp_plan_id
      where decision.user_id = target_user_id), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create or replace function public.refresh_compensation_management_data(force_refresh boolean default true)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  hubspot_result jsonb;
  earnings_result jsonb;
begin
  if not private.has_permission('hubspot.refresh') then
    raise exception 'Management permission is required to refresh HubSpot.' using errcode = '42501';
  end if;

  hubspot_result := public.refresh_hubspot_compensation_data(force_refresh);

  if hubspot_result->>'status' in ('completed','skipped') then
    earnings_result := public.apply_comp_deal_earning_refresh();
  else
    earnings_result := jsonb_build_object('status','not_run','reason','HubSpot refresh did not complete.');
  end if;

  insert into public.app_access_audit_events (
    actor_user_id, event_type, event_reason, new_state
  ) values (
    (select auth.uid()),
    'management_compensation_refresh',
    'An authorized management user refreshed HubSpot and compensation earnings.',
    jsonb_build_object('hubspot', hubspot_result, 'earnings', earnings_result)
  );

  return jsonb_build_object(
    'status', 'completed',
    'hubspot', hubspot_result,
    'earnings', earnings_result,
    'completed_at', pg_catalog.now()
  );
end;
$$;

create or replace function public.get_compensation_dashboard_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  dashboard_data jsonb;
begin
  if not private.has_permission('earnings.view')
     or not private.has_app_role('system_administrator') then
    raise exception 'Management access required.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'deals', (select count(*) from public.hubspot_deals),
    'companies', (select count(*) from public.hubspot_companies),
    'associations', (select count(*) from public.hubspot_deal_company_associations),
    'unlinkedDeals', (
      select count(*) from public.hubspot_deals deal
      where not exists (
        select 1 from public.hubspot_deal_company_associations association
        where association.hubspot_deal_id = deal.hubspot_deal_id
      )
    ),
    'unreviewedChanges', (
      select count(*) from public.hubspot_record_changes change
      where change.requires_review = true and change.review_status = 'unreviewed'
    ),
    'lastSync', (
      select sync_run.completed_at from public.hubspot_sync_runs sync_run
      where sync_run.status = 'completed'
      order by sync_run.completed_at desc nulls last limit 1
    ),
    'recentChanges', coalesce((
      select jsonb_agg(to_jsonb(change_row))
      from (
        select change.detected_at,
          coalesce(deal.deal_name, 'Unknown HubSpot deal') as deal_name,
          change.field_name, change.old_value, change.new_value, change.review_status
        from public.hubspot_record_changes change
        left join public.hubspot_deals deal
          on deal.hubspot_deal_id = change.hubspot_object_id
        where change.object_type = 'deal'
        order by change.detected_at desc limit 10
      ) change_row
    ), '[]'::jsonb)
  ) into dashboard_data;

  return dashboard_data;
end;
$$;

-- Raw synchronization functions are internal. Authenticated users must use the
-- management wrapper, which checks the effective permission first.
revoke all on function public.refresh_hubspot_compensation_data(boolean) from public, anon, authenticated;
revoke all on function public.sync_hubspot_deals() from public, anon, authenticated;
revoke all on function public.sync_hubspot_companies() from public, anon, authenticated;
revoke all on function public.sync_hubspot_deal_company_associations() from public, anon, authenticated;
revoke all on function public.apply_comp_deal_earning_refresh() from public, anon, authenticated;

revoke all on function public.get_current_user_access() from public, anon;
revoke all on function public.get_compensation_employee_data(uuid) from public, anon;
revoke all on function public.get_my_notification_preferences() from public, anon;
revoke all on function public.set_my_notification_preference(text, boolean, text) from public, anon;
revoke all on function public.get_my_user_settings() from public, anon;
revoke all on function public.set_my_user_setting(text, jsonb) from public, anon;
revoke all on function public.submit_missing_earning_claim(text, text, uuid) from public, anon;
revoke all on function public.set_user_permission_decision(uuid, text, text, uuid, boolean, text) from public, anon;
revoke all on function public.get_user_access_configuration(uuid) from public, anon;
revoke all on function public.refresh_compensation_management_data(boolean) from public, anon;
revoke all on function public.get_compensation_dashboard_data() from public, anon;

grant execute on function public.get_current_user_access() to authenticated;
grant execute on function public.get_compensation_employee_data(uuid) to authenticated;
grant execute on function public.get_my_notification_preferences() to authenticated;
grant execute on function public.set_my_notification_preference(text, boolean, text) to authenticated;
grant execute on function public.get_my_user_settings() to authenticated;
grant execute on function public.set_my_user_setting(text, jsonb) to authenticated;
grant execute on function public.submit_missing_earning_claim(text, text, uuid) to authenticated;
grant execute on function public.set_user_permission_decision(uuid, text, text, uuid, boolean, text) to authenticated;
grant execute on function public.get_user_access_configuration(uuid) to authenticated;
grant execute on function public.refresh_compensation_management_data(boolean) to authenticated;
grant execute on function public.get_compensation_dashboard_data() to authenticated;
