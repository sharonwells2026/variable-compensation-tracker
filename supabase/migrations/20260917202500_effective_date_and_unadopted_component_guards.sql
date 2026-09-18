-- Harden effective-date previews and prevent Sharon's unadopted renewal proposal from generating earnings.

create or replace function public.comp_rule_is_effective(
  selected_rule_configuration jsonb,
  selected_measurement_date date default current_date
)
returns boolean
language sql
immutable
set search_path to ''
as $function$
  select selected_measurement_date >= coalesce(nullif(selected_rule_configuration->>'effective_start_date','')::date,'-infinity'::date)
     and selected_measurement_date <= coalesce(nullif(selected_rule_configuration->>'effective_end_date','')::date,'infinity'::date);
$function$;

-- The generic evaluator is configuration-only. Callers must not treat a component as payable
-- when its configuration is outside the selected measurement date.
-- Component refresh paths already apply deal-rule dates; this helper is also used by previews/tests.

update public.comp_plan_components
set is_active=false,
    description=concat_ws(' ',description,'Review-only historical proposal; not an adopted compensation term.'),
    updated_at=now()
where component_code='SHARON_RENEWAL_OVERRIDE_REVIEW'
  and plan_version_id='8f281e19-db02-43d6-bf4f-7dcc77e9cf05';

update public.comp_component_deal_rules
set is_active=false,updated_at=now()
where plan_component_id in (
  select id from public.comp_plan_components
  where component_code='SHARON_RENEWAL_OVERRIDE_REVIEW'
    and plan_version_id='8f281e19-db02-43d6-bf4f-7dcc77e9cf05'
);

update public.comp_user_attribution_rules
set is_active=false,updated_at=now()
where plan_component_id in (
  select id from public.comp_plan_components
  where component_code='SHARON_RENEWAL_OVERRIDE_REVIEW'
    and plan_version_id='8f281e19-db02-43d6-bf4f-7dcc77e9cf05'
);
