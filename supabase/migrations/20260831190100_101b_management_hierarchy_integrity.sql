-- 101B Management Hierarchy Integrity
-- Reconciled from production after validation on 2026-08-31.

create or replace function private.validate_employee_management_hierarchy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  cycle_found boolean := false;
begin
  if new.manager_id is null then
    return new;
  end if;

  if new.manager_id = new.id then
    raise exception 'An employee cannot be their own manager.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.employees manager where manager.id = new.manager_id
  ) then
    raise exception 'The selected manager does not exist.' using errcode = '22023';
  end if;

  with recursive management_chain as (
    select manager.id, manager.manager_id, array[manager.id]::uuid[] as visited
    from public.employees manager
    where manager.id = new.manager_id

    union all

    select parent.id, parent.manager_id, chain.visited || parent.id
    from management_chain chain
    join public.employees parent on parent.id = chain.manager_id
    where chain.manager_id is not null
      and not parent.id = any(chain.visited)
  )
  select exists (
    select 1 from management_chain where id = new.id
  ) into cycle_found;

  if cycle_found then
    raise exception 'This manager assignment would create a circular employee reporting hierarchy.' using errcode = '22023';
  end if;

  return new;
end;
$function$;

revoke all on function private.validate_employee_management_hierarchy() from public, anon, authenticated;

drop trigger if exists employees_validate_management_hierarchy on public.employees;
create trigger employees_validate_management_hierarchy
before insert or update of id, manager_id on public.employees
for each row execute function private.validate_employee_management_hierarchy();
