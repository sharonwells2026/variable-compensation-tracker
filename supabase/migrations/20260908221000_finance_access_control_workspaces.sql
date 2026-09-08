-- Finance individual-payment workspace and granular access administration.

create or replace function public.get_finance_payment_workspace_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
  result jsonb;
begin
  if actor is null or not private.has_permission('payments.view') then
    raise exception 'You are not permitted to view Finance payments.' using errcode='42501';
  end if;

  select jsonb_build_object(
    'accepted_unpaid', coalesce((
      select jsonb_agg(jsonb_build_object(
        'earning_id', e.id,
        'employee_id', e.employee_id,
        'employee_name', emp.full_name,
        'earning_name', e.earning_name,
        'earned_date', e.earned_date,
        'earned_amount', e.earned_amount,
        'approved_amount', e.approved_amount,
        'paid_amount', coalesce(e.paid_amount,0),
        'remaining_amount', greatest(coalesce(e.approved_amount,0)-coalesce(e.paid_amount,0),0),
        'payment_status', e.payment_status,
        'pay_period_start', e.expected_pay_period_start,
        'pay_period_end', e.expected_pay_period_end,
        'pay_period_label', e.expected_pay_period_label,
        'finance_accepted_at', e.finance_accepted_at
      ) order by coalesce(e.expected_pay_period_start,e.earned_date),emp.full_name,e.earned_date,e.id)
      from public.comp_earnings e
      join public.employees emp on emp.id=e.employee_id
      where e.is_current
        and e.approved_amount > 0
        and e.payment_status in ('ready_for_payroll'::public.payment_status,'partially_paid'::public.payment_status)
    ), '[]'::jsonb),
    'paid', coalesce((
      select jsonb_agg(jsonb_build_object(
        'earning_id', e.id,
        'employee_id', e.employee_id,
        'employee_name', emp.full_name,
        'earning_name', e.earning_name,
        'earned_date', e.earned_date,
        'approved_amount', e.approved_amount,
        'paid_amount', e.paid_amount,
        'payment_status', e.payment_status,
        'pay_period_start', e.expected_pay_period_start,
        'pay_period_end', e.expected_pay_period_end,
        'pay_period_label', e.expected_pay_period_label,
        'actual_payment_date', pay.actual_payment_date,
        'payment_reference', pay.payment_reference,
        'payment_method', pay.payment_method
      ) order by pay.actual_payment_date desc nulls last,emp.full_name,e.id)
      from public.comp_earnings e
      join public.employees emp on emp.id=e.employee_id
      left join lateral (
        select b.actual_payment_date,b.payment_reference,b.payment_method
        from public.payroll_payment_items i
        join public.payroll_batches b on b.id=i.payroll_batch_id
        where i.comp_earning_id=e.id and b.status='paid'
        order by b.actual_payment_date desc nulls last,b.created_at desc
        limit 1
      ) pay on true
      where e.is_current and e.payment_status='paid'::public.payment_status
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$;
revoke all on function public.get_finance_payment_workspace_data() from public;
grant execute on function public.get_finance_payment_workspace_data() to authenticated;

insert into private.app_permissions(permission_key,category,display_name,description)
values
('users.view','Users','View users','View user identities, status, roles, and effective access.'),
('users.create','Users','Create users','Create or stage a user record before invitation.'),
('users.edit','Users','Edit users','Edit user profile and access configuration.'),
('users.deactivate','Users','Deactivate users','Deactivate or reactivate application access.'),
('users.invite','Users','Invite users','Send or record an application invitation.'),
('roles.view','Users','View roles','View application roles and inherited permissions.'),
('roles.create','Users','Create roles','Create a custom application role.'),
('roles.edit','Users','Edit roles','Edit a custom role name, description, and permission defaults.'),
('roles.delete','Users','Delete roles','Delete an unused custom role.'),
('role_permissions.edit','Users','Edit role permissions','Allow or deny individual permissions on a role.'),
('permissions.view','Users','View permission catalog','View the full permission catalog and descriptions.'),
('payments.accept','Payments','Accept compensation','Accept fully approved compensation into a payroll period.'),
('payments.assign_period','Payments','Assign payroll period','Assign a standard or custom payroll period.'),
('payments.change_period','Payments','Change payroll period','Change the payroll period before payment.'),
('payments.view_history','Payments','View payment history','View paid compensation and payment history.'),
('earnings.create','Earnings','Create earnings','Create a manual earning where business rules permit.'),
('earnings.edit','Earnings','Edit earnings','Edit an earning before it becomes historically locked.'),
('earnings.void','Earnings','Void earnings','Void an earning while preserving historical auditability.'),
('plans.duplicate','Plans','Duplicate plans','Duplicate a plan or version into a new draft.'),
('plans.delete_draft','Plans','Delete draft plans','Delete draft-only plan configuration.'),
('plans.assign','Plans','Assign plans','Assign an effective plan version to an employee.'),
('reports.view','Reports','View reports','View compensation reports within scope.'),
('audit.export','Audit','Export audit history','Export authorized audit history.'),
('integrations.view','Integrations','View integration status','View integration health and synchronization status.'),
('integrations.configure','Integrations','Configure integrations','Configure integration settings and mappings.')
on conflict(permission_key) do update set category=excluded.category,display_name=excluded.display_name,description=excluded.description;

insert into private.role_permissions(role_key,permission_key,allowed)
select 'system_administrator',p.permission_key,true from private.app_permissions p
on conflict(role_key,permission_key) do update set allowed=true,updated_at=now();
insert into private.role_permissions(role_key,permission_key,allowed)
values
('finance_payroll','payments.accept',true),('finance_payroll','payments.assign_period',true),('finance_payroll','payments.change_period',true),('finance_payroll','payments.view_history',true),
('executive_administrator','reports.view',true),('executive_administrator','payments.view_history',true),
('management_approver','reports.view',true),
('plan_administrator','plans.duplicate',true),('plan_administrator','plans.delete_draft',true),('plan_administrator','plans.assign',true)
on conflict(role_key,permission_key) do update set allowed=excluded.allowed,updated_at=now();

create or replace function private.has_permission(required_permission text)
returns boolean
language sql
stable security definer
set search_path=''
as $function$
  select case
    when (select auth.uid()) is null then false
    when not exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active=true) then false
    when exists(select 1 from private.user_roles ur where ur.user_id=(select auth.uid()) and ur.role_key='system_administrator') then true
    when exists(select 1 from private.user_permission_overrides o where o.user_id=(select auth.uid()) and o.permission_key=required_permission) then
      (select o.allowed from private.user_permission_overrides o where o.user_id=(select auth.uid()) and o.permission_key=required_permission)
    else coalesce((select bool_or(rp.allowed) from private.user_roles ur join private.role_permissions rp on rp.role_key=ur.role_key where ur.user_id=(select auth.uid()) and rp.permission_key=required_permission),false)
  end;
$function$;

create or replace function public.get_access_control_admin_data()
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare actor uuid:=(select auth.uid()); result jsonb;
begin
 if actor is null or not private.has_permission('permissions.view') then raise exception 'You are not permitted to view access administration.' using errcode='42501'; end if;
 select jsonb_build_object(
  'roles',coalesce((select jsonb_agg(jsonb_build_object('role_key',r.role_key,'display_name',r.display_name,'description',r.description,'is_system',r.is_system,'permissions',coalesce((select jsonb_agg(jsonb_build_object('permission_key',p.permission_key,'allowed',rp.allowed,'display_name',p.display_name,'category',p.category) order by p.category,p.display_name) from private.role_permissions rp join private.app_permissions p on p.permission_key=rp.permission_key where rp.role_key=r.role_key),'[]'::jsonb)) order by r.display_name) from private.app_roles r),'[]'::jsonb),
  'permissions',coalesce((select jsonb_agg(jsonb_build_object('permission_key',p.permission_key,'category',p.category,'display_name',p.display_name,'description',p.description) order by p.category,p.display_name) from private.app_permissions p),'[]'::jsonb),
  'active_users',coalesce((select jsonb_agg(jsonb_build_object('user_id',p.id,'email',p.email,'full_name',coalesce(emp.full_name,p.email),'roles',coalesce((select jsonb_agg(ur.role_key order by ur.role_key) from private.user_roles ur where ur.user_id=p.id),'[]'::jsonb),'overrides',coalesce((select jsonb_agg(jsonb_build_object('permission_key',o.permission_key,'allowed',o.allowed,'reason',o.reason) order by o.permission_key) from private.user_permission_overrides o where o.user_id=p.id),'[]'::jsonb)) order by coalesce(emp.full_name,p.email)) from public.profiles p left join public.employees emp on lower(emp.email)=lower(p.email) where p.is_active=true),'[]'::jsonb),
  'draft_users',coalesce((select jsonb_agg(jsonb_build_object('draft_user_id',d.id,'email',d.email,'full_name',d.full_name,'status',d.status,'roles',coalesce((select jsonb_agg(dr.role_key order by dr.role_key) from private.draft_user_roles dr where dr.draft_user_id=d.id),'[]'::jsonb),'overrides',coalesce((select jsonb_agg(jsonb_build_object('permission_key',o.permission_key,'allowed',o.allowed,'reason',o.reason) order by o.permission_key) from private.draft_user_permission_overrides o where o.draft_user_id=d.id),'[]'::jsonb)) order by d.full_name) from public.app_user_drafts d where d.status not in ('activated','cancelled')),'[]'::jsonb)
 ) into result;
 return result;
end;$function$;
revoke all on function public.get_access_control_admin_data() from public;
grant execute on function public.get_access_control_admin_data() to authenticated;

create or replace function public.admin_set_role_permission(target_role_key text,target_permission_key text,requested_allowed boolean)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); begin
 if actor is null or not private.has_permission('role_permissions.edit') then raise exception 'You are not permitted to edit role permissions.' using errcode='42501'; end if;
 if target_role_key='system_administrator' and requested_allowed=false then raise exception 'System Administrator permissions cannot be denied.' using errcode='22023'; end if;
 if not exists(select 1 from private.app_roles where role_key=target_role_key) then raise exception 'Role not found.' using errcode='P0002'; end if;
 if not exists(select 1 from private.app_permissions where permission_key=target_permission_key) then raise exception 'Permission not found.' using errcode='P0002'; end if;
 insert into private.role_permissions(role_key,permission_key,allowed) values(target_role_key,target_permission_key,requested_allowed)
 on conflict(role_key,permission_key) do update set allowed=excluded.allowed,updated_at=now();
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state) values(actor,'role_permission_changed','Role permission changed.',jsonb_build_object('role_key',target_role_key,'permission_key',target_permission_key,'allowed',requested_allowed));
 return jsonb_build_object('status','saved');
end;$function$;
revoke all on function public.admin_set_role_permission(text,text,boolean) from public;
grant execute on function public.admin_set_role_permission(text,text,boolean) to authenticated;

create or replace function public.admin_set_user_permission_override(target_user_id uuid,target_permission_key text,requested_state text,requested_reason text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); normalized text:=lower(trim(coalesce(requested_state,''))); begin
 if actor is null or not private.has_permission('permissions.override') then raise exception 'You are not permitted to override user permissions.' using errcode='42501'; end if;
 if normalized not in ('inherit','allow','deny') then raise exception 'State must be inherit, allow, or deny.' using errcode='22023'; end if;
 if not exists(select 1 from private.app_permissions where permission_key=target_permission_key) then raise exception 'Permission not found.' using errcode='P0002'; end if;
 if exists(select 1 from private.user_roles where user_id=target_user_id and role_key='system_administrator') then raise exception 'System Administrator effective permissions cannot be overridden.' using errcode='22023'; end if;
 if normalized='inherit' then delete from private.user_permission_overrides where user_id=target_user_id and permission_key=target_permission_key;
 else insert into private.user_permission_overrides(user_id,permission_key,allowed,reason,granted_by) values(target_user_id,target_permission_key,normalized='allow',nullif(trim(coalesce(requested_reason,'')),''),actor)
 on conflict(user_id,permission_key) do update set allowed=excluded.allowed,reason=excluded.reason,granted_by=actor,updated_at=now(); end if;
 return jsonb_build_object('status','saved','state',normalized);
end;$function$;
revoke all on function public.admin_set_user_permission_override(uuid,text,text,text) from public;
grant execute on function public.admin_set_user_permission_override(uuid,text,text,text) to authenticated;

create or replace function public.admin_set_draft_user_permission_override(target_draft_user_id uuid,target_permission_key text,requested_state text,requested_reason text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); normalized text:=lower(trim(coalesce(requested_state,''))); begin
 if actor is null or not private.has_permission('permissions.override') then raise exception 'You are not permitted to override draft user permissions.' using errcode='42501'; end if;
 if normalized not in ('inherit','allow','deny') then raise exception 'State must be inherit, allow, or deny.' using errcode='22023'; end if;
 if exists(select 1 from private.draft_user_roles where draft_user_id=target_draft_user_id and role_key='system_administrator') then raise exception 'System Administrator effective permissions cannot be overridden.' using errcode='22023'; end if;
 if normalized='inherit' then delete from private.draft_user_permission_overrides where draft_user_id=target_draft_user_id and permission_key=target_permission_key;
 else insert into private.draft_user_permission_overrides(draft_user_id,permission_key,allowed,reason,granted_by) values(target_draft_user_id,target_permission_key,normalized='allow',nullif(trim(coalesce(requested_reason,'')),''),actor)
 on conflict(draft_user_id,permission_key) do update set allowed=excluded.allowed,reason=excluded.reason,granted_by=actor,updated_at=now(); end if;
 return jsonb_build_object('status','saved','state',normalized);
end;$function$;
revoke all on function public.admin_set_draft_user_permission_override(uuid,text,text,text) from public;
grant execute on function public.admin_set_draft_user_permission_override(uuid,text,text,text) to authenticated;

create or replace function public.admin_set_user_role(target_user_id uuid,target_role_key text,requested_assigned boolean)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); admin_count integer; begin
 if actor is null or not private.has_permission('roles.assign') then raise exception 'You are not permitted to assign roles.' using errcode='42501'; end if;
 if requested_assigned then insert into private.user_roles(user_id,role_key,assigned_by) values(target_user_id,target_role_key,actor) on conflict(user_id,role_key) do nothing;
 else
  if target_role_key='system_administrator' then select count(distinct user_id) into admin_count from private.user_roles where role_key='system_administrator'; if admin_count<=1 and exists(select 1 from private.user_roles where user_id=target_user_id and role_key='system_administrator') then raise exception 'The final System Administrator cannot be removed.' using errcode='22023'; end if; end if;
  delete from private.user_roles where user_id=target_user_id and role_key=target_role_key;
 end if;
 return jsonb_build_object('status','saved');
end;$function$;
revoke all on function public.admin_set_user_role(uuid,text,boolean) from public;
grant execute on function public.admin_set_user_role(uuid,text,boolean) to authenticated;

create or replace function public.admin_set_draft_user_role(target_draft_user_id uuid,target_role_key text,requested_assigned boolean)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); begin
 if actor is null or not private.has_permission('roles.assign') then raise exception 'You are not permitted to assign roles.' using errcode='42501'; end if;
 if requested_assigned then insert into private.draft_user_roles(draft_user_id,role_key,assigned_by) values(target_draft_user_id,target_role_key,actor) on conflict(draft_user_id,role_key) do nothing; else delete from private.draft_user_roles where draft_user_id=target_draft_user_id and role_key=target_role_key; end if;
 return jsonb_build_object('status','saved');
end;$function$;
revoke all on function public.admin_set_draft_user_role(uuid,text,boolean) from public;
grant execute on function public.admin_set_draft_user_role(uuid,text,boolean) to authenticated;

create or replace function public.admin_create_role(requested_role_key text,requested_display_name text,requested_description text default '',copy_from_role_key text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); k text:=lower(trim(coalesce(requested_role_key,''))); begin
 if actor is null or not private.has_permission('roles.create') then raise exception 'You are not permitted to create roles.' using errcode='42501'; end if;
 if k !~ '^[a-z][a-z0-9_]{2,63}$' then raise exception 'Role key must use lowercase letters, numbers, and underscores.' using errcode='22023'; end if;
 insert into private.app_roles(role_key,display_name,description,is_system) values(k,trim(requested_display_name),coalesce(trim(requested_description),''),false);
 if copy_from_role_key is not null then insert into private.role_permissions(role_key,permission_key,allowed) select k,permission_key,allowed from private.role_permissions where role_key=copy_from_role_key on conflict(role_key,permission_key) do nothing; end if;
 return jsonb_build_object('status','created','role_key',k);
end;$function$;
revoke all on function public.admin_create_role(text,text,text,text) from public;
grant execute on function public.admin_create_role(text,text,text,text) to authenticated;

create or replace function public.admin_update_role(target_role_key text,requested_display_name text,requested_description text)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); sys boolean; begin
 if actor is null or not private.has_permission('roles.edit') then raise exception 'You are not permitted to edit roles.' using errcode='42501'; end if;
 select is_system into sys from private.app_roles where role_key=target_role_key; if not found then raise exception 'Role not found.' using errcode='P0002'; end if;
 if sys then raise exception 'Built-in role identity cannot be renamed. Edit its permission defaults instead.' using errcode='22023'; end if;
 update private.app_roles set display_name=trim(requested_display_name),description=coalesce(trim(requested_description),'') where role_key=target_role_key;
 return jsonb_build_object('status','saved');
end;$function$;
revoke all on function public.admin_update_role(text,text,text) from public;
grant execute on function public.admin_update_role(text,text,text) to authenticated;

create or replace function public.admin_delete_role(target_role_key text)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); sys boolean; assignments integer; begin
 if actor is null or not private.has_permission('roles.delete') then raise exception 'You are not permitted to delete roles.' using errcode='42501'; end if;
 select is_system into sys from private.app_roles where role_key=target_role_key; if not found then raise exception 'Role not found.' using errcode='P0002'; end if;
 if sys then raise exception 'Built-in roles cannot be deleted.' using errcode='22023'; end if;
 select (select count(*) from private.user_roles where role_key=target_role_key)+(select count(*) from private.draft_user_roles where role_key=target_role_key) into assignments;
 if assignments>0 then raise exception 'Remove this role from all users before deleting it.' using errcode='22023'; end if;
 delete from private.role_permissions where role_key=target_role_key;
 delete from private.app_roles where role_key=target_role_key;
 return jsonb_build_object('status','deleted');
end;$function$;
revoke all on function public.admin_delete_role(text) from public;
grant execute on function public.admin_delete_role(text) to authenticated;
