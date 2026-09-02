create or replace function public.get_user_preview_targets()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;
  if not private.user_has_permission(actor, 'users.preview_as') then
    raise exception 'You do not have permission to preview another user';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'employee_id', e.id,
      'full_name', e.full_name,
      'email', e.email,
      'job_title', e.job_title,
      'department', e.department,
      'user_id', p.id,
      'has_app_access', p.id is not null,
      'is_active', coalesce(p.is_active, false),
      'roles', coalesce((
        select jsonb_agg(ur.role_key order by ur.role_key)
        from private.user_roles ur
        where ur.user_id = p.id
      ), '[]'::jsonb)
    ) order by e.full_name)
    from public.employees e
    left join public.profiles p on p.employee_id = e.id
    where e.is_active = true
      and p.id is not null
      and p.id <> actor
  ), '[]'::jsonb);
end;
$$;

create or replace function public.begin_user_preview(selected_employee_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  target_profile public.profiles%rowtype;
  target_employee public.employees%rowtype;
  payload jsonb;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;
  if not private.user_has_permission(actor, 'users.preview_as') then
    raise exception 'You do not have permission to preview another user';
  end if;

  select * into target_employee
  from public.employees
  where id = selected_employee_id;

  if target_employee.id is null then
    raise exception 'Employee not found';
  end if;

  select * into target_profile
  from public.profiles
  where employee_id = selected_employee_id
    and is_active = true
  limit 1;

  if target_profile.id is null then
    raise exception 'This employee does not have active application access';
  end if;

  if target_profile.id = actor then
    raise exception 'Use your own account normally instead of preview mode';
  end if;

  payload := jsonb_build_object(
    'preview', true,
    'read_only', true,
    'actor_user_id', actor,
    'user_id', target_profile.id,
    'employee_id', target_employee.id,
    'email', target_profile.email,
    'full_name', coalesce(target_profile.full_name, target_employee.full_name),
    'job_title', target_employee.job_title,
    'department', target_employee.department,
    'roles', coalesce((
      select jsonb_agg(ur.role_key order by ur.role_key)
      from private.user_roles ur
      where ur.user_id = target_profile.id
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(ap.permission_key order by ap.permission_key)
      from private.app_permissions ap
      where private.user_has_permission(target_profile.id, ap.permission_key)
    ), '[]'::jsonb)
  );

  insert into public.app_access_audit_events(
    actor_user_id,target_user_id,event_type,event_reason,previous_state,new_state,related_employee_id,occurred_at
  ) values (
    actor,target_profile.id,'user_preview_started','Read-only view-as-user preview','{}'::jsonb,payload,target_employee.id,now()
  );

  return payload;
end;
$$;

create or replace function public.end_user_preview(selected_employee_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  target_user uuid;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;
  if not private.user_has_permission(actor, 'users.preview_as') then
    raise exception 'You do not have permission to preview another user';
  end if;

  select id into target_user from public.profiles where employee_id = selected_employee_id limit 1;

  insert into public.app_access_audit_events(
    actor_user_id,target_user_id,event_type,event_reason,previous_state,new_state,related_employee_id,occurred_at
  ) values (
    actor,target_user,'user_preview_ended','Returned to authenticated account',jsonb_build_object('preview',true,'employee_id',selected_employee_id),jsonb_build_object('preview',false),selected_employee_id,now()
  );

  return jsonb_build_object('preview',false,'employee_id',selected_employee_id);
end;
$$;

grant execute on function public.get_user_preview_targets() to authenticated;
grant execute on function public.begin_user_preview(uuid) to authenticated;
grant execute on function public.end_user_preview(uuid) to authenticated;
