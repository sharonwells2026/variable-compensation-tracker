-- Pre-provision compensation users and expose operational readiness without sending invitations.
-- This migration intentionally creates no auth.users records and sends no email.

-- Sharon manages Wes, Matt, and Rebecca.
update public.employees employee
set manager_id = manager.id,
    updated_at = now()
from public.employees manager
where lower(manager.email) = 'sharonwells@engagifii.com'
  and lower(employee.email) in ('wesmorris@engagifii.com','matthewasevedo@engagifii.com','rebeccaknight@engagifii.com')
  and employee.manager_id is distinct from manager.id;

-- Create missing pre-invite drafts using Sharon as the configuring administrator.
with actor as (
  select id from public.profiles where lower(email)='sharonwells@engagifii.com' limit 1
), source as (
  select e.id employee_id,e.email,e.full_name,e.job_title,e.department,e.manager_id,
         case lower(e.email)
           when 'wesmorris@engagifii.com' then array['employee']::text[]
           when 'matthewasevedo@engagifii.com' then array['employee']::text[]
           when 'rebeccaknight@engagifii.com' then array['employee']::text[]
           when 'namitbhatia@engagifii.com' then array['executive_administrator']::text[]
           when 'scottkey@engagifii.com' then array['finance_payroll','management_approver']::text[]
         end role_keys
  from public.employees e
  where lower(e.email) in ('wesmorris@engagifii.com','matthewasevedo@engagifii.com','rebeccaknight@engagifii.com','namitbhatia@engagifii.com','scottkey@engagifii.com')
), inserted as (
  insert into public.app_user_drafts(email,full_name,employee_id,status,created_by,updated_by,job_title,department,manager_employee_id,employee_effective_start_date)
  select lower(s.email),s.full_name,s.employee_id,'draft',a.id,a.id,s.job_title,s.department,s.manager_id,current_date
  from source s cross join actor a
  where not exists(select 1 from public.app_user_drafts d where lower(d.email)=lower(s.email) and d.status<>'cancelled')
  returning id,email
)
select 1;

-- Normalize draft metadata and roles.
with actor as (select id from public.profiles where lower(email)='sharonwells@engagifii.com' limit 1)
update public.app_user_drafts d
set employee_id=e.id,full_name=e.full_name,job_title=e.job_title,department=e.department,
    manager_employee_id=e.manager_id,updated_by=(select id from actor),updated_at=now()
from public.employees e
where lower(d.email)=lower(e.email)
  and lower(e.email) in ('wesmorris@engagifii.com','matthewasevedo@engagifii.com','rebeccaknight@engagifii.com','namitbhatia@engagifii.com','scottkey@engagifii.com')
  and d.status<>'cancelled';

with actor as (select id from public.profiles where lower(email)='sharonwells@engagifii.com' limit 1), wanted(email,role_key) as (
 values
 ('wesmorris@engagifii.com','employee'),
 ('matthewasevedo@engagifii.com','employee'),
 ('rebeccaknight@engagifii.com','employee'),
 ('namitbhatia@engagifii.com','executive_administrator'),
 ('scottkey@engagifii.com','finance_payroll'),
 ('scottkey@engagifii.com','management_approver')
)
insert into private.draft_user_roles(draft_user_id,role_key,assigned_by)
select d.id,w.role_key,a.id
from wanted w join public.app_user_drafts d on lower(d.email)=w.email cross join actor a
where d.status<>'cancelled'
on conflict(draft_user_id,role_key) do nothing;

-- Access can be staged as ready without an invitation. Matt and Rebecca remain
-- draft until their real compensation plans are assigned.
with actor as (select id from public.profiles where lower(email)='sharonwells@engagifii.com' limit 1)
update public.app_user_drafts d
set status='ready',ready_at=coalesce(ready_at,now()),updated_by=(select id from actor),updated_at=now(),
    notes=case lower(d.email)
      when 'wesmorris@engagifii.com' then 'Pre-provisioned and ready. Employee role, manager, compensation plan, and approval workflow configured. No invitation sent.'
      when 'namitbhatia@engagifii.com' then 'Pre-provisioned and ready. Executive Administrator role and executive approval responsibility configured. No invitation sent.'
      when 'scottkey@engagifii.com' then 'Pre-provisioned and ready. Finance/Payroll and Management Approver roles plus payment responsibility configured. No invitation sent.'
      else d.notes end
where lower(d.email) in ('wesmorris@engagifii.com','namitbhatia@engagifii.com','scottkey@engagifii.com')
  and d.status in ('draft','ready');

with actor as (select id from public.profiles where lower(email)='sharonwells@engagifii.com' limit 1)
update public.app_user_drafts d
set status='draft',ready_at=null,updated_by=(select id from actor),updated_at=now(),
    notes='Access, manager, and approval workflow are configured. Compensation plan assignment is still required before this user is ready.'
where lower(d.email) in ('matthewasevedo@engagifii.com','rebeccaknight@engagifii.com')
  and d.status in ('draft','ready');

-- Matt and Rebecca use the same 2026 approval/payment pattern as Wes.
do $$
declare
  actor uuid;
  sharon_employee uuid;
  sharon_user uuid;
  namit_employee uuid;
  scott_employee uuid;
  target record;
  workflow_id uuid;
begin
  select p.id,e.id into sharon_user,sharon_employee from public.profiles p join public.employees e on e.id=p.employee_id where lower(p.email)='sharonwells@engagifii.com' limit 1;
  actor:=sharon_user;
  select id into namit_employee from public.employees where lower(email)='namitbhatia@engagifii.com';
  select id into scott_employee from public.employees where lower(email)='scottkey@engagifii.com';
  for target in select id,full_name from public.employees where lower(email) in ('matthewasevedo@engagifii.com','rebeccaknight@engagifii.com') loop
    select id into workflow_id from public.employee_approval_workflow_versions where employee_id=target.id and workflow_name=target.full_name||' Compensation Review & Payment Workflow — 2026' limit 1;
    if workflow_id is null then
      insert into public.employee_approval_workflow_versions(employee_id,workflow_name,effective_start_date,effective_end_date,status,notes,created_by)
      values(target.id,target.full_name||' Compensation Review & Payment Workflow — 2026','2025-12-12','2026-12-31','active','Employee submits earnings. Sharon reviews compensation data and amount. Namit performs executive approval. Scott accepts approved compensation into Finance/payment processing and confirms actual payment.',actor)
      returning id into workflow_id;
    else
      update public.employee_approval_workflow_versions set status='active',updated_at=now() where id=workflow_id;
    end if;
    if not exists(select 1 from public.employee_approval_chains where workflow_version_id=workflow_id and approval_order=1) then
      insert into public.employee_approval_chains(employee_id,approval_order,approver_user_id,approval_level,is_required,effective_start_date,effective_end_date,created_by,workflow_version_id,step_name,approver_employee_id)
      values(target.id,1,sharon_user,'compensation_admin_review',true,'2025-12-12','2026-12-31',actor,workflow_id,'Compensation Administrator Review',sharon_employee);
    end if;
    if not exists(select 1 from public.employee_approval_chains where workflow_version_id=workflow_id and approval_order=2) then
      insert into public.employee_approval_chains(employee_id,approval_order,approval_level,is_required,effective_start_date,effective_end_date,created_by,workflow_version_id,step_name,approver_employee_id)
      values(target.id,2,'executive_approval',true,'2025-12-12','2026-12-31',actor,workflow_id,'Executive Approval',namit_employee);
    end if;
    if not exists(select 1 from public.employee_post_approval_steps where workflow_version_id=workflow_id and stage_order=1) then
      insert into public.employee_post_approval_steps(workflow_version_id,employee_id,stage_order,step_name,step_type,assignee_employee_id,is_required_for_payment,requires_payment_details,effective_start_date,effective_end_date,created_by)
      values(workflow_id,target.id,1,'Finance Accepts for Payment','finance_acknowledgement',scott_employee,true,false,'2025-12-12','2026-12-31',actor);
    end if;
  end loop;
end $$;

-- The application readers are replaced by the live definitions maintained by
-- this release. They expose readiness without granting access or creating users.
-- See app/users and app/workflow for the corresponding UI behavior.
