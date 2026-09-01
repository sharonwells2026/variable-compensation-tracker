insert into public.organization_units (name,code,unit_type,description,is_active,display_order)
select 'Finance / Accounting','FINANCE_ACCOUNTING','department','Finance and accounting department',true,20
where not exists (select 1 from public.organization_units where code='FINANCE_ACCOUNTING');

insert into private.app_roles (role_key,display_name,description,is_system)
values ('executive_administrator','Executive administrator','Executive-level compensation administration with broad operational visibility and authority, excluding system security and user-access administration.',true)
on conflict (role_key) do update set display_name=excluded.display_name,description=excluded.description;

insert into private.role_permissions (role_key,permission_key,allowed)
select 'executive_administrator',p.permission_key,true
from private.app_permissions p
where p.permission_key not in ('users.manage','roles.assign','permissions.override','settings.manage')
on conflict (role_key,permission_key) do update set allowed=excluded.allowed,updated_at=now();
