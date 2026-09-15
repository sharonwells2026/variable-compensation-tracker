-- Prevent a plan from activating when a deal-based Earning Type cannot produce earnings.
-- This is Compensation-domain validation only; it does not alter shared RevOS access/auth.

create or replace function private.guard_comp_plan_activation_engine_readiness()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  bad_component record;
begin
  if new.status='active' and old.status is distinct from 'active' then
    select c.id,c.name into bad_component
    from public.comp_plan_components c
    where c.plan_version_id=new.id
      and c.is_active=true
      and c.measurement_source in ('amount','average_arr','first_year_arr','one_time_fee','total_contract_value')
      and (
        not exists(
          select 1 from public.comp_component_deal_rules dr
          where dr.plan_component_id=c.id and dr.is_active=true and dr.marks_earned=true
        )
        or not exists(
          select 1 from public.comp_user_attribution_rules ar
          where ar.plan_component_id=c.id and ar.attribution_purpose='earning' and ar.is_active=true
        )
      )
    order by c.calculation_order,c.name
    limit 1;

    if bad_component.id is not null then
      raise exception 'Earning Type "%" is not ready to generate earnings. Add Deal Type + Deal Stage Earned conditions and a credit owner field before activating this plan.',bad_component.name using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_comp_plan_activation_engine_readiness() from public,anon,authenticated;

drop trigger if exists guard_comp_plan_activation_engine_readiness on public.comp_plan_versions;
create trigger guard_comp_plan_activation_engine_readiness
before update of status on public.comp_plan_versions
for each row execute function private.guard_comp_plan_activation_engine_readiness();
