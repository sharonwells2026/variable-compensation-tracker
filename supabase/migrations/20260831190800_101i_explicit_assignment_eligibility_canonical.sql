-- 101I Canonical Explicit Assignment Eligibility
-- Exact production validator contract reconstructed from validated live definition on 2026-08-31.

alter table public.employee_plan_assignments
  alter column earnings_eligibility_date set not null;

create or replace function private.validate_employee_plan_assignment()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  version_status public.plan_version_status;
  version_start date;
  version_end date;
  duplicate_overlap_exists boolean;
  overallocated boolean;
begin
  select pv.status,pv.effective_start_date,pv.effective_end_date
  into version_status,version_start,version_end
  from public.comp_plan_versions pv
  where pv.id=new.plan_version_id;

  if version_start is null then raise exception 'Compensation plan version does not exist.' using errcode='22023'; end if;
  if version_status<>'active' then raise exception 'Employee assignments may only reference an active compensation plan version.' using errcode='55000'; end if;
  if new.effective_start_date<version_start then raise exception 'Assignment start date cannot precede the plan version start date.' using errcode='22023'; end if;
  if version_end is not null and (new.effective_end_date is null or new.effective_end_date>version_end) then raise exception 'Assignment end date must fall within the plan version effective dates.' using errcode='22023'; end if;
  if new.effective_end_date is not null and new.effective_end_date<new.effective_start_date then raise exception 'Assignment end date cannot precede assignment start date.' using errcode='22023'; end if;
  if new.earnings_eligibility_date is null then raise exception 'An explicit earnings eligibility date is required for every compensation plan assignment.' using errcode='22023'; end if;
  if new.earnings_eligibility_date<new.effective_start_date then raise exception 'Earnings eligibility date cannot precede assignment start date.' using errcode='22023'; end if;
  if new.effective_end_date is not null and new.earnings_eligibility_date>new.effective_end_date then raise exception 'Earnings eligibility date cannot fall after assignment end date.' using errcode='22023'; end if;

  select exists(
    select 1 from public.employee_plan_assignments existing
    where existing.employee_id=new.employee_id
      and existing.plan_version_id=new.plan_version_id
      and (tg_op='INSERT' or existing.id<>new.id)
      and daterange(existing.effective_start_date,coalesce(existing.effective_end_date+1,'infinity'::date),'[)')
          && daterange(new.effective_start_date,coalesce(new.effective_end_date+1,'infinity'::date),'[)')
  ) into duplicate_overlap_exists;

  if duplicate_overlap_exists then raise exception 'This employee already has an overlapping assignment to the same compensation plan version.' using errcode='23P01'; end if;

  with candidate_dates as (
    select new.effective_start_date as check_date
    union
    select existing.effective_start_date
    from public.employee_plan_assignments existing
    where existing.employee_id=new.employee_id
      and (tg_op='INSERT' or existing.id<>new.id)
      and existing.effective_start_date>=new.effective_start_date
      and (new.effective_end_date is null or existing.effective_start_date<=new.effective_end_date)
  ), allocation_at_dates as (
    select d.check_date,
      new.allocation_percent + coalesce((
        select sum(existing.allocation_percent)
        from public.employee_plan_assignments existing
        where existing.employee_id=new.employee_id
          and (tg_op='INSERT' or existing.id<>new.id)
          and existing.effective_start_date<=d.check_date
          and (existing.effective_end_date is null or existing.effective_end_date>=d.check_date)
      ),0) as total_allocation
    from candidate_dates d
  )
  select exists(select 1 from allocation_at_dates where total_allocation>100)
  into overallocated;

  if overallocated then raise exception 'Concurrent employee compensation plan allocation cannot exceed 100 percent.' using errcode='23514'; end if;
  return new;
end;
$function$;

drop trigger if exists employee_plan_assignments_validate on public.employee_plan_assignments;
create trigger employee_plan_assignments_validate
before insert or update of employee_id,plan_version_id,allocation_percent,effective_start_date,effective_end_date,eligibility_waiting_period_days,earnings_eligibility_date
on public.employee_plan_assignments
for each row execute function private.validate_employee_plan_assignment();
