-- 101D Payroll Service Reconciliation
-- Production was installed and validated manually on 2026-08-31.
-- This source-control migration captures the structural guards; canonical service RPC definitions
-- are intentionally documented in production reconciliation history and should be schema-diffed before replay.

do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.payroll_batches'::regclass and conname='payroll_batches_period_check') then alter table public.payroll_batches add constraint payroll_batches_period_check check(payroll_period_start is null or payroll_period_end is null or payroll_period_end>=payroll_period_start); end if;
 if not exists(select 1 from pg_constraint where conrelid='public.payroll_batches'::regclass and conname='payroll_batches_status_check') then alter table public.payroll_batches add constraint payroll_batches_status_check check(status in ('draft','scheduled','finalized','paid','cancelled')); end if;
 if not exists(select 1 from pg_constraint where conrelid='public.earning_payment_schedules'::regclass and conname='earning_payment_schedules_status_check') then alter table public.earning_payment_schedules add constraint earning_payment_schedules_status_check check(schedule_status in ('expected','scheduled','superseded','cancelled','paid')); end if;
end $$;
create unique index if not exists earning_payment_schedules_one_current_idx on public.earning_payment_schedules(comp_earning_id) where schedule_status in ('expected','scheduled');

create or replace function private.enforce_payroll_payment_item_editability()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare batch_status text;
begin
 select status into batch_status from public.payroll_batches where id=coalesce(new.payroll_batch_id,old.payroll_batch_id);
 if batch_status is null then raise exception 'Payroll batch not found.' using errcode='P0002'; end if;
 if batch_status<>'draft' then raise exception 'Payroll payment items cannot be changed after the batch leaves draft.' using errcode='22023'; end if;
 return coalesce(new,old);
end;$function$;
revoke all on function private.enforce_payroll_payment_item_editability() from public,anon,authenticated;
drop trigger if exists payroll_payment_items_enforce_editability on public.payroll_payment_items;
create trigger payroll_payment_items_enforce_editability before insert or update or delete on public.payroll_payment_items for each row execute function private.enforce_payroll_payment_item_editability();

-- Required public service-layer functions in the reconciled production contract:
-- public.create_comp_payroll_batch(text,date,date,date,text)
-- public.add_comp_earning_to_payroll_batch(uuid,uuid,numeric,text)
-- public.schedule_comp_payroll_batch(uuid)
-- public.mark_comp_payroll_batch_paid(uuid,date,text,text,text)
-- All are SECURITY DEFINER with authenticated-only EXECUTE and permission checks.
