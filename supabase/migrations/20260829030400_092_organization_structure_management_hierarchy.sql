-- 092 - Organization Structure and Management Hierarchy
-- ALREADY APPLIED MANUALLY TO PRODUCTION.

create table if not exists public.organization_units (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  unit_type text not null check (unit_type in ('department','team','division','group')),
  parent_org_unit_id uuid references public.organization_units(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.employee_org_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  org_unit_id uuid not null references public.organization_units(id) on delete cascade,
  relationship_type text not null default 'member' check (relationship_type in ('primary','member','dotted_line')),
  is_primary boolean not null default false,
  effective_start_date date not null default current_date,
  effective_end_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.management_scopes (
  id uuid primary key default gen_random_uuid(),
  manager_employee_id uuid not null references public.employees(id) on delete cascade,
  org_unit_id uuid not null references public.organization_units(id) on delete cascade,
  scope_type text not null default 'view' check (scope_type in ('view','manage','approve')),
  include_descendants boolean not null default true,
  effective_start_date date not null default current_date,
  effective_end_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.organization_units (name,code,unit_type,is_active)
values ('Growth','GROWTH','department',true)
on conflict (code) do update set name=excluded.name,unit_type=excluded.unit_type,is_active=true,updated_at=now();

insert into public.employee_org_assignments (employee_id,org_unit_id,relationship_type,is_primary,effective_start_date)
select e.id,ou.id,'primary',true,current_date
from public.employees e
join public.organization_units ou on ou.code='GROWTH'
where lower(e.email) in (lower('sharonwells@engagifii.com'),lower('wesmorris@engagifii.com'))
and not exists (select 1 from public.employee_org_assignments x where x.employee_id=e.id and x.org_unit_id=ou.id and x.effective_end_date is null);
