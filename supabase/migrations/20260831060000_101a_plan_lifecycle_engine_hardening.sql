-- 101A Plan Lifecycle Engine Hardening
-- Reconciled from the production definitions installed 2026-08-31.
-- Historical Wes lifecycle remediation is intentionally not replayed here because it is production data repair, not schema behavior.

create or replace function private.assert_plan_version_editable(selected_plan_version_id uuid)
returns void language plpgsql stable security definer set search_path = '' as $function$
declare selected_status public.plan_version_status; selected_approved_at timestamptz;
begin
  select pv.status,pv.approved_at into selected_status,selected_approved_at from public.comp_plan_versions pv where pv.id=selected_plan_version_id;
  if not found then raise exception 'Compensation plan version does not exist.' using errcode='22023'; end if;
  if selected_status <> 'draft' or selected_approved_at is not null then
    raise exception 'Approved, active, and retired compensation plan versions are immutable. Create a new draft version to make changes.' using errcode='55000';
  end if;
end;$function$;
revoke all on function private.assert_plan_version_editable(uuid) from public,anon,authenticated;

create or replace function private.enforce_comp_component_editability() returns trigger language plpgsql security definer set search_path='' as $function$
declare selected_version_id uuid;
begin
 selected_version_id:=case when tg_op='DELETE' then old.plan_version_id else new.plan_version_id end;
 perform private.assert_plan_version_editable(selected_version_id);
 return case when tg_op='DELETE' then old else new end;
end;$function$;

drop trigger if exists comp_plan_components_enforce_editability on public.comp_plan_components;
create trigger comp_plan_components_enforce_editability before insert or update or delete on public.comp_plan_components for each row execute function private.enforce_comp_component_editability();

create or replace function private.enforce_comp_deal_rule_editability() returns trigger language plpgsql security definer set search_path='' as $function$
declare selected_component_id uuid; selected_version_id uuid;
begin
 selected_component_id:=case when tg_op='DELETE' then old.plan_component_id else new.plan_component_id end;
 select c.plan_version_id into selected_version_id from public.comp_plan_components c where c.id=selected_component_id;
 if selected_version_id is null then raise exception 'Compensation plan component does not exist.' using errcode='22023'; end if;
 perform private.assert_plan_version_editable(selected_version_id);
 return case when tg_op='DELETE' then old else new end;
end;$function$;

drop trigger if exists comp_component_deal_rules_enforce_editability on public.comp_component_deal_rules;
create trigger comp_component_deal_rules_enforce_editability before insert or update or delete on public.comp_component_deal_rules for each row execute function private.enforce_comp_deal_rule_editability();

create or replace function private.enforce_comp_attribution_rule_editability() returns trigger language plpgsql security definer set search_path='' as $function$
declare selected_component_id uuid; selected_version_id uuid;
begin
 selected_component_id:=case when tg_op='DELETE' then old.plan_component_id else new.plan_component_id end;
 select c.plan_version_id into selected_version_id from public.comp_plan_components c where c.id=selected_component_id;
 if selected_version_id is null then raise exception 'Compensation plan component does not exist.' using errcode='22023'; end if;
 perform private.assert_plan_version_editable(selected_version_id);
 return case when tg_op='DELETE' then old else new end;
end;$function$;

drop trigger if exists comp_user_attribution_rules_enforce_editability on public.comp_user_attribution_rules;
create trigger comp_user_attribution_rules_enforce_editability before insert or update or delete on public.comp_user_attribution_rules for each row execute function private.enforce_comp_attribution_rule_editability();

create or replace function private.enforce_comp_plan_version_immutability() returns trigger language plpgsql security definer set search_path='' as $function$
begin
 if old.approved_at is not null then
   if new.comp_plan_id is distinct from old.comp_plan_id or new.version_number is distinct from old.version_number or new.effective_start_date is distinct from old.effective_start_date or new.currency_code is distinct from old.currency_code then
     raise exception 'Approved compensation plan versions are immutable. Create a new draft version to change plan terms.' using errcode='55000';
   end if;
   if new.effective_end_date is distinct from old.effective_end_date and new.status <> 'retired' then
     raise exception 'The effective end date of an approved version may only change as part of retirement.' using errcode='55000';
   end if;
   if old.status='draft' and new.status not in ('draft','active','retired') then raise exception 'Invalid compensation plan lifecycle transition.' using errcode='22023'; end if;
 end if;
 return new;
end;$function$;

drop trigger if exists comp_plan_versions_enforce_immutability on public.comp_plan_versions;
create trigger comp_plan_versions_enforce_immutability before update on public.comp_plan_versions for each row execute function private.enforce_comp_plan_version_immutability();

create or replace function private.validate_employee_plan_assignment() returns trigger language plpgsql security definer set search_path='' as $function$
declare version_status public.plan_version_status; version_start date; version_end date; duplicate_overlap_exists boolean; overallocated boolean;
begin
 select pv.status,pv.effective_start_date,pv.effective_end_date into version_status,version_start,version_end from public.comp_plan_versions pv where pv.id=new.plan_version_id;
 if version_start is null then raise exception 'Compensation plan version does not exist.' using errcode='22023'; end if;
 if version_status <> 'active' then raise exception 'Employee assignments may only reference an active compensation plan version.' using errcode='55000'; end if;
 if new.effective_start_date < version_start then raise exception 'Assignment start date cannot precede the plan version start date.' using errcode='22023'; end if;
 if version_end is not null and (new.effective_end_date is null or new.effective_end_date > version_end) then raise exception 'Assignment end date must fall within the plan version effective dates.' using errcode='22023'; end if;
 if new.effective_end_date is not null and new.effective_end_date < new.effective_start_date then raise exception 'Assignment end date cannot precede assignment start date.' using errcode='22023'; end if;
 select exists(select 1 from public.employee_plan_assignments existing where existing.employee_id=new.employee_id and existing.plan_version_id=new.plan_version_id and (tg_op='INSERT' or existing.id<>new.id) and daterange(existing.effective_start_date,coalesce(existing.effective_end_date+1,'infinity'::date),'[)') && daterange(new.effective_start_date,coalesce(new.effective_end_date+1,'infinity'::date),'[)')) into duplicate_overlap_exists;
 if duplicate_overlap_exists then raise exception 'This employee already has an overlapping assignment to the same compensation plan version.' using errcode='23P01'; end if;
 with candidate_dates as (
   select new.effective_start_date as check_date
   union
   select existing.effective_start_date from public.employee_plan_assignments existing where existing.employee_id=new.employee_id and (tg_op='INSERT' or existing.id<>new.id) and existing.effective_start_date>=new.effective_start_date and (new.effective_end_date is null or existing.effective_start_date<=new.effective_end_date)
 ), allocation_at_dates as (
   select d.check_date,new.allocation_percent+coalesce((select sum(existing.allocation_percent) from public.employee_plan_assignments existing where existing.employee_id=new.employee_id and (tg_op='INSERT' or existing.id<>new.id) and existing.effective_start_date<=d.check_date and (existing.effective_end_date is null or existing.effective_end_date>=d.check_date)),0) total_allocation from candidate_dates d
 ) select exists(select 1 from allocation_at_dates where total_allocation>100) into overallocated;
 if overallocated then raise exception 'Concurrent employee compensation plan allocation cannot exceed 100 percent.' using errcode='23514'; end if;
 new.earnings_eligibility_date:=new.effective_start_date+coalesce(new.eligibility_waiting_period_days,0);
 return new;
end;$function$;

drop trigger if exists employee_plan_assignments_validate on public.employee_plan_assignments;
create trigger employee_plan_assignments_validate before insert or update of employee_id,plan_version_id,allocation_percent,effective_start_date,effective_end_date,eligibility_waiting_period_days on public.employee_plan_assignments for each row execute function private.validate_employee_plan_assignment();

create or replace function public.create_compensation_plan_version(selected_plan_id uuid,selected_effective_start_date date,selected_effective_end_date date default null,selected_currency_code text default 'USD',selected_notes text default null,copy_components_from_version_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare next_version_number integer; new_version_id uuid;
begin
 if not private.has_permission('plans.create') then raise exception 'Plan version creation is not permitted.' using errcode='42501'; end if;
 perform 1 from public.comp_plans where id=selected_plan_id and is_active=true for update;
 if not found then raise exception 'The selected plan does not exist or is inactive.' using errcode='22023'; end if;
 if selected_effective_end_date is not null and selected_effective_end_date<selected_effective_start_date then raise exception 'Effective end date cannot be before start date.' using errcode='22023'; end if;
 select coalesce(max(version_number),0)+1 into next_version_number from public.comp_plan_versions where comp_plan_id=selected_plan_id;
 insert into public.comp_plan_versions(comp_plan_id,version_number,status,effective_start_date,effective_end_date,currency_code,notes) values(selected_plan_id,next_version_number,'draft',selected_effective_start_date,selected_effective_end_date,upper(trim(coalesce(selected_currency_code,'USD'))),nullif(trim(coalesce(selected_notes,'')),'')) returning id into new_version_id;
 if copy_components_from_version_id is not null then
   if not exists(select 1 from public.comp_plan_versions where id=copy_components_from_version_id and comp_plan_id=selected_plan_id) then raise exception 'Source version does not belong to this plan.' using errcode='22023'; end if;
   insert into public.comp_plan_components(plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active,payout_timing_method,allow_manager_payout_override,measurement_label)
   select new_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active,payout_timing_method,allow_manager_payout_override,measurement_label from public.comp_plan_components where plan_version_id=copy_components_from_version_id;
 end if;
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state) values(auth.uid(),'comp_plan_version_created','A new draft compensation plan version was created.',jsonb_build_object('plan_id',selected_plan_id,'plan_version_id',new_version_id,'version_number',next_version_number,'copied_from_version_id',copy_components_from_version_id));
 return jsonb_build_object('status','draft','plan_version_id',new_version_id,'version_number',next_version_number);
end;$function$;

create or replace function public.activate_compensation_plan_version(selected_plan_version_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $function$
declare selected_plan_id uuid; selected_start date; selected_end date; conflicting_active_id uuid; conflicting_active_start date;
begin
 if not private.has_permission('plans.activate') then raise exception 'Plan activation is not permitted.' using errcode='42501'; end if;
 select pv.comp_plan_id,pv.effective_start_date,pv.effective_end_date into selected_plan_id,selected_start,selected_end from public.comp_plan_versions pv where pv.id=selected_plan_version_id and pv.status='draft' and pv.approved_at is not null for update;
 if selected_plan_id is null then raise exception 'The plan version must be draft and approved before activation.' using errcode='22023'; end if;
 if selected_start>current_date then raise exception 'A future-dated compensation plan version cannot be activated before its effective start date. Leave it approved in draft status until that date.' using errcode='22023'; end if;
 perform 1 from public.comp_plans where id=selected_plan_id for update;
 select pv.id,pv.effective_start_date into conflicting_active_id,conflicting_active_start from public.comp_plan_versions pv where pv.comp_plan_id=selected_plan_id and pv.status='active' and pv.id<>selected_plan_version_id order by pv.effective_start_date desc limit 1 for update;
 if conflicting_active_id is not null then
   if conflicting_active_start>=selected_start then raise exception 'The selected version does not start after the currently active version.' using errcode='22023'; end if;
   update public.comp_plan_versions set status='retired',effective_end_date=selected_start-1,updated_at=pg_catalog.now() where id=conflicting_active_id;
 end if;
 update public.comp_plan_versions set status='active',updated_at=pg_catalog.now() where id=selected_plan_version_id;
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state) values(auth.uid(),'comp_plan_version_activated','An approved compensation plan version was activated on or after its effective date.',jsonb_build_object('plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'previous_active_version_id',conflicting_active_id));
 return jsonb_build_object('status','active','plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'retired_prior_version_id',conflicting_active_id);
end;$function$;
