-- 093 - Draft User Employee Profile Setup
-- ALREADY APPLIED MANUALLY TO PRODUCTION.

alter table public.app_user_drafts add column if not exists job_title text;
alter table public.app_user_drafts add column if not exists department text;
alter table public.app_user_drafts add column if not exists manager_employee_id uuid references public.employees(id);
alter table public.app_user_drafts add column if not exists primary_org_unit_id uuid references public.organization_units(id);
alter table public.app_user_drafts add column if not exists plan_version_id uuid references public.comp_plan_versions(id);
alter table public.app_user_drafts add column if not exists employee_effective_start_date date default current_date;

create or replace function public.set_app_user_draft_employee_profile(
  selected_draft_user_id uuid,
  selected_job_title text default null,
  selected_department text default null,
  selected_manager_employee_id uuid default null,
  selected_primary_org_unit_id uuid default null,
  selected_plan_version_id uuid default null,
  selected_effective_start_date date default current_date
) returns jsonb
language plpgsql
security definer
set search_path=public,private
as $$
declare d public.app_user_drafts%rowtype;
begin
  if not private.has_permission('users.manage') then raise exception 'Permission denied'; end if;
  select * into d from public.app_user_drafts where id=selected_draft_user_id;
  if not found then raise exception 'Draft user not found'; end if;
  if d.status not in ('draft','ready') then raise exception 'Draft user cannot be edited in status %',d.status; end if;
  if selected_manager_employee_id is not null and not exists(select 1 from public.employees where id=selected_manager_employee_id and is_active=true) then raise exception 'Manager employee not found or inactive'; end if;
  if selected_primary_org_unit_id is not null and not exists(select 1 from public.organization_units where id=selected_primary_org_unit_id and is_active=true) then raise exception 'Organization unit not found or inactive'; end if;
  if selected_plan_version_id is not null and not exists(select 1 from public.comp_plan_versions where id=selected_plan_version_id) then raise exception 'Plan version not found'; end if;
  update public.app_user_drafts set job_title=selected_job_title,department=selected_department,manager_employee_id=selected_manager_employee_id,primary_org_unit_id=selected_primary_org_unit_id,plan_version_id=selected_plan_version_id,employee_effective_start_date=coalesce(selected_effective_start_date,current_date),updated_by=auth.uid(),updated_at=now() where id=selected_draft_user_id;
  return jsonb_build_object('draft_user_id',selected_draft_user_id,'updated',true);
end;
$$;

grant execute on function public.set_app_user_draft_employee_profile(uuid,text,text,uuid,uuid,uuid,date) to authenticated;
