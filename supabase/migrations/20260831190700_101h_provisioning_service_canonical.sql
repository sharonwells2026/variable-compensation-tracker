-- 101H Canonical Provisioning Service
-- Exact production contract reconstructed from validated live definitions on 2026-08-31.

alter table public.app_user_drafts add column if not exists earnings_eligibility_date date;

create or replace function public.set_app_user_draft_earnings_eligibility(
  selected_draft_user_id uuid,
  selected_earnings_eligibility_date date
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  draft public.app_user_drafts%rowtype;
  version_start date;
  version_end date;
  version_status public.plan_version_status;
begin
  if not private.has_permission('users.manage') then
    raise exception 'User administration is not permitted.' using errcode='42501';
  end if;

  select * into draft from public.app_user_drafts where id=selected_draft_user_id for update;
  if draft.id is null then raise exception 'The selected draft user does not exist.' using errcode='22023'; end if;
  if draft.status not in ('draft','ready') then raise exception 'This user can no longer be edited before invitation.' using errcode='22023'; end if;
  if selected_earnings_eligibility_date is null then raise exception 'An explicit earnings eligibility date is required.' using errcode='23514'; end if;
  if draft.employee_effective_start_date is null then raise exception 'Set the employee effective start date before setting earnings eligibility.' using errcode='23514'; end if;
  if selected_earnings_eligibility_date<draft.employee_effective_start_date then raise exception 'Earnings eligibility date cannot precede the plan assignment start date.' using errcode='23514'; end if;

  if draft.plan_version_id is not null then
    select pv.status,pv.effective_start_date,pv.effective_end_date into version_status,version_start,version_end
    from public.comp_plan_versions pv where pv.id=draft.plan_version_id;
    if version_start is null then raise exception 'Selected compensation plan version does not exist.' using errcode='23514'; end if;
    if version_status<>'active' then raise exception 'Selected compensation plan version must be active.' using errcode='23514'; end if;
    if draft.employee_effective_start_date<version_start then raise exception 'Plan assignment start cannot precede the plan version start date.' using errcode='23514'; end if;
    if version_end is not null and selected_earnings_eligibility_date>version_end then raise exception 'Earnings eligibility date falls after the compensation plan version ends.' using errcode='23514'; end if;
  end if;

  update public.app_user_drafts set earnings_eligibility_date=selected_earnings_eligibility_date,updated_by=(select auth.uid()),updated_at=now()
  where id=selected_draft_user_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values((select auth.uid()),'draft_earnings_eligibility_updated','An administrator configured the explicit compensation earnings eligibility date before invitation.',
    jsonb_build_object('draft_user_id',selected_draft_user_id,'employee_effective_start_date',draft.employee_effective_start_date,'earnings_eligibility_date',selected_earnings_eligibility_date,'plan_version_id',draft.plan_version_id),draft.employee_id);

  return jsonb_build_object('status','updated','draft_user_id',selected_draft_user_id,'employee_effective_start_date',draft.employee_effective_start_date,'earnings_eligibility_date',selected_earnings_eligibility_date,'plan_version_id',draft.plan_version_id);
end;
$function$;
revoke all on function public.set_app_user_draft_earnings_eligibility(uuid,date) from public,anon;
grant execute on function public.set_app_user_draft_earnings_eligibility(uuid,date) to authenticated;

create or replace function public.prepare_app_user_draft_invitation(selected_draft_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  draft public.app_user_drafts%rowtype;
  selected_roles text[];
  invitation_id uuid;
  version_status public.plan_version_status;
  version_start date;
  version_end date;
begin
  if not private.has_permission('users.manage') then raise exception 'User administration is not permitted.' using errcode='42501'; end if;

  select * into draft from public.app_user_drafts where id=selected_draft_user_id for update;
  if draft.id is null or draft.status not in ('draft','ready') then raise exception 'This draft is not available for invitation preparation.' using errcode='22023'; end if;

  select array_agg(role_key order by role_key) into selected_roles from private.draft_user_roles where draft_user_id=draft.id;
  if coalesce(array_length(selected_roles,1),0)=0 then raise exception 'Assign at least one role before preparing the invitation.' using errcode='23514'; end if;

  if draft.employee_effective_start_date is null then raise exception 'Employee effective start date is required.' using errcode='23514'; end if;
  if draft.manager_employee_id is not null and not exists(select 1 from public.employees manager where manager.id=draft.manager_employee_id and manager.is_active=true) then raise exception 'Selected manager must be an active employee.' using errcode='23514'; end if;
  if draft.primary_org_unit_id is not null and not exists(select 1 from public.organization_units unit where unit.id=draft.primary_org_unit_id and unit.is_active=true) then raise exception 'Selected primary organization unit must be active.' using errcode='23514'; end if;

  if draft.plan_version_id is not null then
    if draft.earnings_eligibility_date is null then raise exception 'An explicit earnings eligibility date is required when a compensation plan is selected.' using errcode='23514'; end if;
    if draft.earnings_eligibility_date<draft.employee_effective_start_date then raise exception 'Earnings eligibility date cannot precede the plan assignment start date.' using errcode='23514'; end if;

    select pv.status,pv.effective_start_date,pv.effective_end_date into version_status,version_start,version_end
    from public.comp_plan_versions pv where pv.id=draft.plan_version_id;
    if version_start is null then raise exception 'Selected compensation plan version does not exist.' using errcode='23514'; end if;
    if version_status<>'active' then raise exception 'Selected compensation plan version must be active before invitation.' using errcode='23514'; end if;
    if draft.employee_effective_start_date<version_start then raise exception 'Plan assignment start cannot precede the compensation plan version start.' using errcode='23514'; end if;
    if version_end is not null and draft.employee_effective_start_date>version_end then raise exception 'Plan assignment start falls after the compensation plan version ends.' using errcode='23514'; end if;
    if version_end is not null and draft.earnings_eligibility_date>version_end then raise exception 'Earnings eligibility date falls after the compensation plan version ends.' using errcode='23514'; end if;
  end if;

  insert into public.app_user_invitations(email,full_name,employee_id,role_keys,status,invited_by,expires_at,notes,access_draft_id)
  values(draft.email,draft.full_name,draft.employee_id,selected_roles,'prepared',(select auth.uid()),now()+interval '7 days',draft.notes,draft.id)
  on conflict(email) do update set
    full_name=excluded.full_name,employee_id=excluded.employee_id,role_keys=excluded.role_keys,status='prepared',invited_by=excluded.invited_by,
    invited_at=now(),expires_at=excluded.expires_at,notes=excluded.notes,access_draft_id=excluded.access_draft_id,
    accepted_by=null,accepted_at=null,revoked_by=null,revoked_at=null
  returning id into invitation_id;

  update public.app_user_drafts set status='ready',ready_at=coalesce(ready_at,now()),updated_by=(select auth.uid()),updated_at=now() where id=draft.id;
  return jsonb_build_object('status','ready','draft_user_id',draft.id,'invitation_id',invitation_id,'invitation_sent',false,'employee_effective_start_date',draft.employee_effective_start_date,'earnings_eligibility_date',draft.earnings_eligibility_date);
end;
$function$;
revoke all on function public.prepare_app_user_draft_invitation(uuid) from public,anon;
grant execute on function public.prepare_app_user_draft_invitation(uuid) to authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  invitation public.app_user_invitations%rowtype;
  draft public.app_user_drafts%rowtype;
  linked_employee_id uuid;
  linked_draft_id uuid;
  existing_employee public.employees%rowtype;
  plan_assignment_id uuid;
  org_assignment_id uuid;
  selected_full_name text;
begin
  if new.email is null then raise exception 'An email address is required.' using errcode='42501'; end if;

  select invitation_row.* into invitation
  from public.app_user_invitations invitation_row
  where invitation_row.email=lower(new.email) and invitation_row.status='pending' and invitation_row.expires_at>now()
  for update;
  if invitation.id is null then raise exception 'An active invitation is required.' using errcode='42501'; end if;

  linked_draft_id:=invitation.access_draft_id;
  if linked_draft_id is null then raise exception 'Invitation is not linked to a provisioning draft.' using errcode='23514'; end if;
  select * into draft from public.app_user_drafts where id=linked_draft_id for update;
  if draft.id is null then raise exception 'Provisioning draft was not found.' using errcode='23514'; end if;
  if draft.status not in ('ready','invited') then raise exception 'Provisioning draft is not ready for activation.' using errcode='23514'; end if;
  if lower(draft.email)<>lower(new.email) then raise exception 'Invitation email does not match the provisioning draft.' using errcode='23514'; end if;

  selected_full_name:=coalesce(nullif(trim(draft.full_name),''),nullif(trim(invitation.full_name),''),nullif(trim(new.raw_user_meta_data->>'full_name'),''),nullif(trim(new.raw_user_meta_data->>'name'),''));

  linked_employee_id:=coalesce(
    draft.employee_id,
    invitation.employee_id,
    (select employee.id from public.employees employee where lower(employee.email)=lower(new.email) limit 1)
  );

  if linked_employee_id is not null then
    select * into existing_employee from public.employees where id=linked_employee_id for update;
    if existing_employee.id is null then raise exception 'The employee linked to this invitation no longer exists.' using errcode='23514'; end if;
    if lower(existing_employee.email)<>lower(new.email) then raise exception 'The linked employee email does not match the invited authentication user.' using errcode='23514'; end if;

    update public.employees set
      full_name=coalesce(selected_full_name,full_name),job_title=coalesce(draft.job_title,job_title),department=coalesce(draft.department,department),
      manager_id=draft.manager_employee_id,is_active=true,updated_at=now()
    where id=linked_employee_id;
  else
    if selected_full_name is null then raise exception 'Employee full name is required.' using errcode='23514'; end if;
    insert into public.employees(email,full_name,job_title,department,manager_id,hire_date,is_active)
    values(lower(new.email),selected_full_name,draft.job_title,draft.department,draft.manager_employee_id,draft.employee_effective_start_date,true)
    returning id into linked_employee_id;
  end if;

  update public.app_user_drafts set employee_id=linked_employee_id where id=linked_draft_id;
  update public.app_user_invitations set employee_id=linked_employee_id where id=invitation.id;

  insert into public.profiles(id,email,full_name,employee_id,is_active)
  values(new.id,lower(new.email),selected_full_name,linked_employee_id,true)
  on conflict(id) do update set email=excluded.email,full_name=coalesce(excluded.full_name,public.profiles.full_name),employee_id=linked_employee_id,is_active=true,updated_at=now();

  if draft.primary_org_unit_id is not null then
    select assignment.id into org_assignment_id from public.employee_org_assignments assignment
    where assignment.employee_id=linked_employee_id and assignment.org_unit_id=draft.primary_org_unit_id and assignment.effective_start_date=draft.employee_effective_start_date limit 1;
    if org_assignment_id is null then
      insert into public.employee_org_assignments(employee_id,org_unit_id,relationship_type,is_primary,effective_start_date)
      values(linked_employee_id,draft.primary_org_unit_id,'primary',true,draft.employee_effective_start_date)
      returning id into org_assignment_id;
    else
      update public.employee_org_assignments set relationship_type='primary',is_primary=true,updated_at=now() where id=org_assignment_id;
    end if;
  end if;

  if draft.plan_version_id is not null then
    if draft.earnings_eligibility_date is null then raise exception 'Provisioning cannot activate a compensation plan without an explicit earnings eligibility date.' using errcode='23514'; end if;

    select assignment.id into plan_assignment_id from public.employee_plan_assignments assignment
    where assignment.employee_id=linked_employee_id and assignment.plan_version_id=draft.plan_version_id and assignment.effective_start_date=draft.employee_effective_start_date limit 1;

    if plan_assignment_id is null then
      insert into public.employee_plan_assignments(employee_id,plan_version_id,allocation_percent,effective_start_date,earnings_eligibility_date,assignment_notes,assigned_by)
      values(linked_employee_id,draft.plan_version_id,100,draft.employee_effective_start_date,draft.earnings_eligibility_date,'Created from approved user provisioning draft.',invitation.invited_by)
      returning id into plan_assignment_id;
    else
      if not exists(select 1 from public.employee_plan_assignments assignment where assignment.id=plan_assignment_id and assignment.earnings_eligibility_date=draft.earnings_eligibility_date) then
        raise exception 'Existing compensation plan assignment conflicts with the provisioning draft eligibility date.' using errcode='23514';
      end if;
    end if;
  end if;

  insert into private.user_roles(user_id,role_key,assigned_by)
  select new.id,role_key,invitation.invited_by from private.draft_user_roles where draft_user_id=linked_draft_id
  on conflict(user_id,role_key) do nothing;

  if not found then
    insert into private.user_roles(user_id,role_key,assigned_by)
    select new.id,requested_role,invitation.invited_by
    from unnest(invitation.role_keys) requested_role
    join private.app_roles role_catalog on role_catalog.role_key=requested_role
    on conflict(user_id,role_key) do nothing;
  end if;

  insert into private.user_permission_overrides(user_id,permission_key,allowed,reason,granted_by)
  select new.id,permission_key,allowed,reason,invitation.invited_by from private.draft_user_permission_overrides where draft_user_id=linked_draft_id
  on conflict(user_id,permission_key) do update set allowed=excluded.allowed,reason=excluded.reason,granted_by=excluded.granted_by,updated_at=now();

  insert into private.user_employee_permissions(user_id,employee_id,permission_key,allowed,assigned_by)
  select new.id,employee_id,permission_key,allowed,invitation.invited_by from private.draft_user_employee_permissions where draft_user_id=linked_draft_id
  on conflict(user_id,employee_id,permission_key) do update set allowed=excluded.allowed,assigned_by=excluded.assigned_by,updated_at=now();

  insert into private.user_plan_permissions(user_id,comp_plan_id,permission_key,allowed,assigned_by)
  select new.id,comp_plan_id,permission_key,allowed,invitation.invited_by from private.draft_user_plan_permissions where draft_user_id=linked_draft_id
  on conflict(user_id,comp_plan_id,permission_key) do update set allowed=excluded.allowed,assigned_by=excluded.assigned_by,updated_at=now();

  insert into public.user_notification_preferences(user_id,notification_type,in_app_enabled,email_delivery)
  select new.id,notification_type,in_app_enabled,email_delivery from private.draft_user_notification_preferences where draft_user_id=linked_draft_id
  on conflict(user_id,notification_type) do update set in_app_enabled=excluded.in_app_enabled,email_delivery=excluded.email_delivery,updated_at=now();

  update public.app_user_invitations set status='accepted',accepted_by=new.id,accepted_at=now() where id=invitation.id;
  update public.app_user_drafts set status='activated',auth_user_id=new.id,employee_id=linked_employee_id,activated_at=now(),updated_at=now() where id=linked_draft_id;

  insert into public.app_access_audit_events(actor_user_id,target_user_id,event_type,event_reason,new_state,related_employee_id)
  values(invitation.invited_by,new.id,'draft_user_activated','The invited user activated the preconfigured account and the approved employee configuration was materialized.',
    jsonb_build_object('email',lower(new.email),'draft_user_id',linked_draft_id,'employee_id',linked_employee_id,'manager_employee_id',draft.manager_employee_id,'primary_org_unit_id',draft.primary_org_unit_id,'employee_effective_start_date',draft.employee_effective_start_date,'plan_version_id',draft.plan_version_id,'plan_assignment_id',plan_assignment_id,'earnings_eligibility_date',draft.earnings_eligibility_date),linked_employee_id);

  return new;
end;
$function$;
revoke all on function public.handle_new_user() from public,anon,authenticated;
