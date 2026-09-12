create or replace function public.save_compensation_plan_component_eligibility(selected_component_id uuid, selected_mode text, selected_waiting_days integer default null::integer, selected_rule_set_id uuid default null::uuid, selected_description text default null::text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  normalized_mode text := lower(trim(coalesce(selected_mode,'')));
  stored_mode text;
  version_status public.plan_version_status;
  old_configuration jsonb;
  new_eligibility jsonb;
  previous_waiting_days integer;
  rule_purpose text;
  rule_component_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  if not private.has_permission('plans.edit') then
    raise exception 'Plan eligibility editing is not permitted.' using errcode = '42501';
  end if;

  select pv.status, c.rule_configuration, c.additional_eligibility_waiting_days
  into version_status, old_configuration, previous_waiting_days
  from public.comp_plan_components c
  join public.comp_plan_versions pv on pv.id = c.plan_version_id
  where c.id = selected_component_id
  for update of c;

  if version_status is null then
    raise exception 'Plan component does not exist.' using errcode = '22023';
  end if;

  if version_status <> 'draft' then
    raise exception 'Only components in draft plan versions can be edited.' using errcode = '42501';
  end if;

  if normalized_mode not in ('immediate','waiting_period','rule','customer_payment') then
    raise exception 'Eligibility mode must be immediate, waiting_period, customer_payment, or rule.' using errcode = '22023';
  end if;

  stored_mode := case when normalized_mode = 'customer_payment' then 'rule' else normalized_mode end;

  if normalized_mode = 'waiting_period' then
    if selected_waiting_days is null or selected_waiting_days < 0 then
      raise exception 'Waiting-period eligibility requires a non-negative number of days.' using errcode = '22023';
    end if;
    if selected_rule_set_id is not null then
      raise exception 'Waiting-period eligibility cannot also reference an eligibility rule set.' using errcode = '22023';
    end if;
  elsif normalized_mode in ('rule','customer_payment') then
    if selected_rule_set_id is null then
      raise exception 'Rule-based eligibility requires an eligibility rule set.' using errcode = '22023';
    end if;

    select rs.purpose, rs.plan_component_id
    into rule_purpose, rule_component_id
    from public.comp_rule_sets rs
    where rs.id = selected_rule_set_id;

    if rule_purpose is null then
      raise exception 'Eligibility rule set does not exist.' using errcode = '22023';
    end if;
    if rule_purpose <> 'eligibility' then
      raise exception 'The selected rule set is not an eligibility rule set.' using errcode = '22023';
    end if;
    if rule_component_id <> selected_component_id then
      raise exception 'Eligibility rule set must belong to the same plan component.' using errcode = '22023';
    end if;
    if selected_waiting_days is not null then
      raise exception 'Rule-based eligibility cannot also use a waiting-period value.' using errcode = '22023';
    end if;
  else
    if selected_waiting_days is not null or selected_rule_set_id is not null then
      raise exception 'Immediate eligibility cannot include a waiting period or eligibility rule set.' using errcode = '22023';
    end if;
  end if;

  new_eligibility := jsonb_strip_nulls(jsonb_build_object(
    'mode', stored_mode,
    'business_concept', case when normalized_mode='customer_payment' then 'customer_payment_received' else null end,
    'waiting_days', case when normalized_mode = 'waiting_period' then selected_waiting_days else null end,
    'rule_set_id', case when stored_mode = 'rule' then selected_rule_set_id else null end,
    'description', coalesce(nullif(trim(coalesce(selected_description,'')),''), case when normalized_mode='customer_payment' then 'Customer payment received' else null end)
  ));

  update public.comp_plan_components
  set additional_eligibility_waiting_days = case
        when normalized_mode = 'waiting_period' then selected_waiting_days
        else null
      end,
      rule_configuration = jsonb_set(
        coalesce(rule_configuration,'{}'::jsonb),
        '{eligibility}',
        new_eligibility,
        true
      ),
      updated_at = pg_catalog.now()
  where id = selected_component_id;

  insert into public.app_access_audit_events (
    actor_user_id,event_type,event_reason,old_state,new_state
  ) values (
    (select auth.uid()),
    'comp_plan_component_eligibility_updated',
    'The Earned-to-Eligible condition for a draft compensation plan component was updated.',
    jsonb_build_object('component_id',selected_component_id,'eligibility',coalesce(old_configuration->'eligibility','null'::jsonb),'additional_eligibility_waiting_days',previous_waiting_days),
    jsonb_build_object('component_id',selected_component_id,'eligibility',new_eligibility,'additional_eligibility_waiting_days',case when normalized_mode='waiting_period' then selected_waiting_days else null end)
  );

  return jsonb_build_object('status','saved','component_id',selected_component_id,'eligibility',new_eligibility);
end;
$function$;
