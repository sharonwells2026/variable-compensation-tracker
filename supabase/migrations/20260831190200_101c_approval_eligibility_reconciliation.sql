-- 101C Approval + Eligibility Hardening
-- Reconciled from verified production state on 2026-08-31.
-- Approval service RPCs installed in production are captured separately by live schema reconciliation;
-- this migration captures the structural eligibility and approval-chain guards added after 101A.

alter table public.comp_plan_components
  add column if not exists additional_eligibility_waiting_days integer;

alter table public.employee_plan_assignments
  alter column earnings_eligibility_date set not null;

alter table public.app_user_drafts
  add column if not exists earnings_eligibility_date date;

do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.comp_plan_components'::regclass and conname='comp_plan_components_additional_eligibility_waiting_days_check') then
    alter table public.comp_plan_components add constraint comp_plan_components_additional_eligibility_waiting_days_check check (additional_eligibility_waiting_days is null or additional_eligibility_waiting_days >= 0);
  end if;
end $$;

create or replace function private.resolve_comp_earning_eligibility_date(target_plan_assignment_id uuid,target_plan_component_id uuid)
returns date language plpgsql stable security definer set search_path=''
as $function$
declare a public.employee_plan_assignments%rowtype; c public.comp_plan_components%rowtype;
begin
  select * into a from public.employee_plan_assignments where id=target_plan_assignment_id;
  if not found then raise exception 'Compensation plan assignment not found.' using errcode='P0002'; end if;
  if a.earnings_eligibility_date is null then return null; end if;
  if target_plan_component_id is null then return a.earnings_eligibility_date; end if;
  select * into c from public.comp_plan_components where id=target_plan_component_id;
  if not found then raise exception 'Compensation plan component not found.' using errcode='P0002'; end if;
  if c.plan_version_id <> a.plan_version_id then raise exception 'Compensation component does not belong to the assigned plan version.' using errcode='22023'; end if;
  return a.earnings_eligibility_date + coalesce(c.additional_eligibility_waiting_days,0);
end;$function$;
revoke all on function private.resolve_comp_earning_eligibility_date(uuid,uuid) from public,anon,authenticated;

create or replace function private.validate_employee_approval_chain()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
 if new.effective_end_date is not null and new.effective_end_date<new.effective_start_date then raise exception 'Approval-chain end date cannot precede its start date.' using errcode='22023'; end if;
 if new.approval_order<=0 then raise exception 'Approval order must be greater than zero.' using errcode='22023'; end if;
 if new.backup_approver_user_id is not null and new.backup_approver_user_id=new.approver_user_id then raise exception 'Primary and backup approvers must be different users.' using errcode='22023'; end if;
 if not exists(select 1 from public.profiles p where p.id=new.approver_user_id and p.is_active=true) then raise exception 'Primary approver must be an active application user.' using errcode='22023'; end if;
 if new.backup_approver_user_id is not null and not exists(select 1 from public.profiles p where p.id=new.backup_approver_user_id and p.is_active=true) then raise exception 'Backup approver must be an active application user.' using errcode='22023'; end if;
 if exists(select 1 from public.profiles p where p.id=new.approver_user_id and p.employee_id=new.employee_id) then raise exception 'An employee cannot be their own compensation approver.' using errcode='22023'; end if;
 if new.backup_approver_user_id is not null and exists(select 1 from public.profiles p where p.id=new.backup_approver_user_id and p.employee_id=new.employee_id) then raise exception 'An employee cannot be their own backup compensation approver.' using errcode='22023'; end if;
 if exists(select 1 from public.employee_approval_chains x where x.employee_id=new.employee_id and x.approval_order=new.approval_order and x.id<>new.id and daterange(x.effective_start_date,coalesce(x.effective_end_date+1,'infinity'::date),'[)') && daterange(new.effective_start_date,coalesce(new.effective_end_date+1,'infinity'::date),'[)')) then raise exception 'This approval step overlaps another effective approval step for the employee.' using errcode='22023'; end if;
 return new;
end;$function$;
revoke all on function private.validate_employee_approval_chain() from public,anon,authenticated;
drop trigger if exists employee_approval_chains_validate on public.employee_approval_chains;
create trigger employee_approval_chains_validate before insert or update on public.employee_approval_chains for each row execute function private.validate_employee_approval_chain();

-- Ensure eligibility-date-only edits are validated.
drop trigger if exists employee_plan_assignments_validate on public.employee_plan_assignments;
create trigger employee_plan_assignments_validate before insert or update of employee_id,plan_version_id,allocation_percent,effective_start_date,effective_end_date,eligibility_waiting_period_days,earnings_eligibility_date on public.employee_plan_assignments for each row execute function private.validate_employee_plan_assignment();
