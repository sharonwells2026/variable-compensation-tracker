-- 095 - Create Matt Asevedo Employee
-- ALREADY APPLIED MANUALLY TO PRODUCTION.
-- Creates the employee record and primary Growth organization assignment only.
-- Does not create an auth user or send an invitation.

do $$
declare
  matt_employee_id uuid;
  growth_unit_id uuid;
begin
  insert into public.employees (email,full_name,job_title,department,is_active)
  values ('matthewasevedo@engagifii.com','Matt Asevedo','Senior Solutions Advisor','Growth',true)
  on conflict (email) do update set full_name=excluded.full_name,job_title=excluded.job_title,department=excluded.department,is_active=true,updated_at=now()
  returning id into matt_employee_id;

  select id into growth_unit_id from public.organization_units where code='GROWTH' limit 1;
  if growth_unit_id is null then raise exception 'Growth organization unit was not found.'; end if;

  if not exists (select 1 from public.employee_org_assignments where employee_id=matt_employee_id and org_unit_id=growth_unit_id and effective_end_date is null) then
    insert into public.employee_org_assignments (employee_id,org_unit_id,relationship_type,is_primary,effective_start_date)
    values (matt_employee_id,growth_unit_id,'primary',true,current_date);
  end if;
end $$;
