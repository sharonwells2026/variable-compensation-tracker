create or replace function public.admin_create_role(requested_role_key text,requested_display_name text,requested_description text default '',copy_from_role_key text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); k text:=lower(trim(coalesce(requested_role_key,''))); begin
 if actor is null or not private.has_permission('roles.create') then raise exception 'You are not permitted to create roles.' using errcode='42501'; end if;
 if k !~ '^[a-z][a-z0-9_]{2,63}$' then raise exception 'Role key must use lowercase letters, numbers, and underscores.' using errcode='22023'; end if;
 if nullif(trim(coalesce(requested_display_name,'')),'') is null then raise exception 'Role name is required.' using errcode='22023'; end if;
 insert into private.app_roles(role_key,display_name,description,is_system) values(k,trim(requested_display_name),coalesce(trim(requested_description),''),false);
 if copy_from_role_key is not null then insert into private.role_permissions(role_key,permission_key,allowed) select k,permission_key,allowed from private.role_permissions where role_key=copy_from_role_key on conflict(role_key,permission_key) do nothing; end if;
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state) values(actor,'custom_role_created','Custom role created.',jsonb_build_object('role_key',k,'display_name',trim(requested_display_name),'copy_from',copy_from_role_key));
 return jsonb_build_object('status','created','role_key',k);
end;$function$;
revoke all on function public.admin_create_role(text,text,text,text) from public; grant execute on function public.admin_create_role(text,text,text,text) to authenticated;

create or replace function public.admin_update_role(target_role_key text,requested_display_name text,requested_description text)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); sys boolean; begin
 if actor is null or not private.has_permission('roles.edit') then raise exception 'You are not permitted to edit roles.' using errcode='42501'; end if;
 select is_system into sys from private.app_roles where role_key=target_role_key; if not found then raise exception 'Role not found.' using errcode='P0002'; end if;
 if sys then raise exception 'Built-in role identity cannot be renamed. Edit its permission defaults instead.' using errcode='22023'; end if;
 update private.app_roles set display_name=trim(requested_display_name),description=coalesce(trim(requested_description),'') where role_key=target_role_key;
 return jsonb_build_object('status','saved');
end;$function$;
revoke all on function public.admin_update_role(text,text,text) from public; grant execute on function public.admin_update_role(text,text,text) to authenticated;

create or replace function public.admin_delete_role(target_role_key text)
returns jsonb language plpgsql security definer set search_path=''
as $function$ declare actor uuid:=(select auth.uid()); sys boolean; assignments integer; begin
 if actor is null or not private.has_permission('roles.delete') then raise exception 'You are not permitted to delete roles.' using errcode='42501'; end if;
 select is_system into sys from private.app_roles where role_key=target_role_key; if not found then raise exception 'Role not found.' using errcode='P0002'; end if;
 if sys then raise exception 'Built-in roles cannot be deleted.' using errcode='22023'; end if;
 select (select count(*) from private.user_roles where role_key=target_role_key)+(select count(*) from private.draft_user_roles where role_key=target_role_key) into assignments;
 if assignments>0 then raise exception 'Remove this role from all users before deleting it.' using errcode='22023'; end if;
 delete from private.role_permissions where role_key=target_role_key; delete from private.app_roles where role_key=target_role_key;
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state) values(actor,'custom_role_deleted','Custom role deleted.',jsonb_build_object('role_key',target_role_key));
 return jsonb_build_object('status','deleted');
end;$function$;
revoke all on function public.admin_delete_role(text) from public; grant execute on function public.admin_delete_role(text) to authenticated;