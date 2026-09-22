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