-- 105 Planned approval workflows with pre-invite approvers
-- Production migration installed 2026-09-01.
-- Allows workflow design against an employee whose app account is still pre-invite,
-- while keeping runtime approval requests restricted to active app users.

alter table public.employee_approval_chains
  add column if not exists approver_employee_id uuid references public.employees(id),
  add column if not exists backup_approver_employee_id uuid references public.employees(id);

alter table public.employee_approval_chains
  alter column approver_user_id drop not null;

create index if not exists employee_approval_chains_approver_employee_idx
  on public.employee_approval_chains(approver_employee_id);
create index if not exists employee_approval_chains_backup_employee_idx
  on public.employee_approval_chains(backup_approver_employee_id);

create or replace function private.draft_employee_has_permission(selected_employee_id uuid, required_permission text)
returns boolean
language sql stable security definer set search_path=''
as $function$
with latest_draft as (
  select d.id from public.app_user_drafts d
  where d.employee_id=selected_employee_id and d.status<>'cancelled'
  order by d.updated_at desc limit 1
)
select coalesce(
  (select o.allowed from latest_draft d join private.draft_user_permission_overrides o on o.draft_user_id=d.id where o.permission_key=required_permission limit 1),
  exists(select 1 from latest_draft d join private.draft_user_roles r on r.draft_user_id=d.id join private.role_permissions rp on rp.role_key=r.role_key where rp.permission_key=required_permission and rp.allowed=true),
  false
);
$function$;
revoke all on function private.draft_employee_has_permission(uuid,text) from public,anon,authenticated;

create or replace function private.resolve_employee_approver_user(selected_employee_id uuid)
returns uuid
language sql stable security definer set search_path=''
as $function$
select p.id from public.profiles p
where p.employee_id=selected_employee_id and p.is_active=true
  and private.user_has_permission(p.id,'earnings.approve')
order by p.updated_at desc limit 1;
$function$;
revoke all on function private.resolve_employee_approver_user(uuid) from public,anon,authenticated;

-- Canonical production definitions updated by this migration:
-- private.validate_employee_approval_chain()
-- public.create_employee_approval_workflow(uuid,text,date,date,jsonb,text)
-- public.activate_ready_employee_approval_workflow(uuid)
-- private.open_next_comp_earning_approval(uuid,uuid)
-- public.get_approval_workflow_admin_data()
--
-- Behavioral contract:
-- * approval steps store canonical approver employee ids;
-- * active approver user ids are resolved when available;
-- * a pre-invite draft is acceptable only when its effective permissions include earnings.approve;
-- * unresolved workflows remain status='draft';
-- * runtime routing joins workflow versions and only routes active/ended historical workflows;
-- * draft workflows can never generate an approval request;
-- * activate_ready_employee_approval_workflow re-resolves approver users and activates only when all approvers are live.
