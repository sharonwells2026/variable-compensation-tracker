insert into private.app_permissions (permission_key, category, display_name, description)
values (
  'users.preview_as',
  'Users',
  'Preview as user',
  'Safely preview the application using another employee''s effective access and data scope without impersonating that person for transactions.'
)
on conflict (permission_key) do update
set category = excluded.category,
    display_name = excluded.display_name,
    description = excluded.description;

insert into private.role_permissions (role_key, permission_key, allowed)
values ('system_administrator', 'users.preview_as', true)
on conflict (role_key, permission_key) do update
set allowed = excluded.allowed,
    updated_at = now();
