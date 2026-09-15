-- Rule Builder -> live deal evaluator compatibility bridge.
--
-- New Earning Types are configured with comp_rule_sets / comp_rule_predicates,
-- while the current deal candidate engine still reads comp_component_deal_rules
-- plus comp_user_attribution_rules. This bridge materializes the simple,
-- business-facing Deal rules used by the plan editor into those executable
-- structures after a successful preview. Existing active plans are untouched.

create or replace function private.sync_rule_builder_deal_execution(target_rule_set_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_component_id uuid;
  target_version_id uuid;
  target_version_status public.plan_version_status;
  target_measurement_source text;
  target_eligibility jsonb;
  unsupported_count integer := 0;
  stage_count integer := 0;
  deal_type_count integer := 0;
  generated_count integer := 0;
  attribution_field_key text := 'deal_owner';
  has_company_cem boolean := false;
  has_deal_owner boolean := false;
begin
  select c.id,
         c.plan_version_id,
         pv.status,
         c.measurement_source,
         coalesce(c.rule_configuration->'eligibility','{}'::jsonb)
  into target_component_id,
       target_version_id,
       target_version_status,
       target_measurement_source,
       target_eligibility
  from public.comp_rule_sets rs
  join public.comp_plan_components c on c.id=rs.plan_component_id
  join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where rs.id=target_rule_set_id
    and rs.purpose='qualification';

  if target_component_id is null then
    return jsonb_build_object('supported',false,'reason','qualification_rule_not_found');
  end if;

  if target_version_status <> 'draft' then
    return jsonb_build_object('supported',false,'reason','only_draft_components_are_synchronized');
  end if;

  if target_measurement_source not in ('amount','average_arr','first_year_arr','one_time_fee','total_contract_value') then
    return jsonb_build_object('supported',false,'reason','measurement_source_not_deal_based','measurement_source',target_measurement_source);
  end if;

  select count(*) into unsupported_count
  from public.comp_rule_predicates p
  where p.rule_set_id=target_rule_set_id
    and not (
      (p.object_type='deal' and p.property_name='dealstage' and p.operator_key in ('is','is_any_of'))
      or (p.object_type='deal' and p.property_name='dealtype' and p.operator_key in ('is','is_any_of'))
      or (p.object_type='deal' and p.property_name='hubspot_owner_id' and p.operator_key in ('is','is_any_of'))
      or (p.object_type='company' and p.property_name='customer_experience_manager_id' and p.operator_key in ('is','is_any_of'))
    );

  if unsupported_count > 0 then
    delete from public.comp_component_deal_rules
    where plan_component_id=target_component_id
      and rule_notes='Generated from Rule Builder qualification';

    delete from public.comp_user_attribution_rules
    where plan_component_id=target_component_id
      and rule_configuration->>'configuration_source'='rule_builder_auto';

    return jsonb_build_object('supported',false,'reason','qualification_contains_conditions_not_supported_by_current_deal_engine','unsupported_predicate_count',unsupported_count);
  end if;

  select count(*) into stage_count
  from public.comp_rule_predicates p
  where p.rule_set_id=target_rule_set_id
    and p.object_type='deal'
    and p.property_name='dealstage'
    and p.operator_key in ('is','is_any_of');

  select count(*) into deal_type_count
  from public.comp_rule_predicates p
  where p.rule_set_id=target_rule_set_id
    and p.object_type='deal'
    and p.property_name='dealtype'
    and p.operator_key in ('is','is_any_of');

  if stage_count=0 or deal_type_count=0 then
    return jsonb_build_object('supported',false,'reason','deal_stage_and_deal_type_are_required_for_live_execution');
  end if;

  select exists(
    select 1 from public.comp_rule_predicates p
    where p.rule_set_id=target_rule_set_id
      and p.object_type='company'
      and p.property_name='customer_experience_manager_id'
      and p.operator_key in ('is','is_any_of')
  ) into has_company_cem;

  select exists(
    select 1 from public.comp_rule_predicates p
    where p.rule_set_id=target_rule_set_id
      and p.object_type='deal'
      and p.property_name='hubspot_owner_id'
      and p.operator_key in ('is','is_any_of')
  ) into has_deal_owner;

  if has_company_cem and has_deal_owner then
    return jsonb_build_object('supported',false,'reason','choose_one_credit_source_deal_owner_or_customer_experience_manager');
  elsif has_company_cem then
    attribution_field_key := 'company_cem';
  else
    attribution_field_key := 'deal_owner';
  end if;

  delete from public.comp_component_deal_rules
  where plan_component_id=target_component_id
    and rule_notes='Generated from Rule Builder qualification';

  with stage_values as (
    select distinct value as stage_id
    from public.comp_rule_predicates p
    cross join lateral jsonb_array_elements_text(
      case when jsonb_typeof(p.comparison_value)='array'
           then p.comparison_value
           else jsonb_build_array(p.comparison_value #>> '{}') end
    ) x(value)
    where p.rule_set_id=target_rule_set_id
      and p.object_type='deal'
      and p.property_name='dealstage'
      and p.operator_key in ('is','is_any_of')
  ),
  deal_type_values as (
    select distinct value as deal_type
    from public.comp_rule_predicates p
    cross join lateral jsonb_array_elements_text(
      case when jsonb_typeof(p.comparison_value)='array'
           then p.comparison_value
           else jsonb_build_array(p.comparison_value #>> '{}') end
    ) x(value)
    where p.rule_set_id=target_rule_set_id
      and p.object_type='deal'
      and p.property_name='dealtype'
      and p.operator_key in ('is','is_any_of')
  )
  insert into public.comp_component_deal_rules(
    plan_component_id,
    hubspot_pipeline_id,
    hubspot_stage_id,
    hubspot_deal_type,
    calculation_action,
    marks_earned,
    marks_eligible,
    marks_paid,
    amount_source,
    amount_label,
    priority,
    is_active,
    effective_start_date,
    effective_end_date,
    rule_notes
  )
  select target_component_id,
         s.hubspot_pipeline_id,
         sv.stage_id,
         dt.deal_type,
         'include',
         true,
         coalesce(target_eligibility->>'business_concept','')='customer_payment_received',
         false,
         target_measurement_source,
         case target_measurement_source
           when 'amount' then 'Deal Amount'
           when 'average_arr' then 'ARR'
           when 'first_year_arr' then 'First Year ARR'
           when 'one_time_fee' then 'One-Time Fee'
           when 'total_contract_value' then 'Total Contract Value'
           else target_measurement_source
         end,
         100,
         true,
         pv.effective_start_date,
         pv.effective_end_date,
         'Generated from Rule Builder qualification'
  from stage_values sv
  join public.hubspot_pipeline_stages s on s.hubspot_stage_id=sv.stage_id
  cross join deal_type_values dt
  join public.hubspot_deal_types hdt on hdt.internal_value=dt.deal_type
  join public.comp_plan_versions pv on pv.id=target_version_id
  on conflict (plan_component_id,hubspot_pipeline_id,hubspot_stage_id,hubspot_deal_type,calculation_action)
  do update set
    marks_earned=excluded.marks_earned,
    marks_eligible=excluded.marks_eligible,
    marks_paid=excluded.marks_paid,
    amount_source=excluded.amount_source,
    amount_label=excluded.amount_label,
    priority=excluded.priority,
    is_active=excluded.is_active,
    effective_start_date=excluded.effective_start_date,
    effective_end_date=excluded.effective_end_date,
    rule_notes=excluded.rule_notes,
    updated_at=pg_catalog.now();

  get diagnostics generated_count = row_count;

  delete from public.comp_user_attribution_rules
  where plan_component_id=target_component_id
    and rule_configuration->>'configuration_source'='rule_builder_auto';

  insert into public.comp_user_attribution_rules(
    plan_component_id,
    attribution_purpose,
    metric_key,
    hubspot_user_field_keys,
    match_logic,
    credit_percentage,
    qualifying_pipeline_ids,
    qualifying_deal_types,
    priority,
    allow_stacking,
    rule_configuration,
    effective_start_date,
    effective_end_date,
    is_active
  ) values (
    target_component_id,
    'earning',
    null,
    jsonb_build_array(attribution_field_key),
    'any',
    100,
    '[]'::jsonb,
    '[]'::jsonb,
    10,
    false,
    jsonb_build_object(
      'configuration_source','rule_builder_auto',
      'description',case attribution_field_key when 'company_cem' then 'Automatically attributed using Customer Experience Manager from the Earned conditions.' else 'Automatically attributed using Deal Owner.' end
    ),
    '1900-01-01'::date,
    null,
    true
  );

  return jsonb_build_object(
    'supported',true,
    'plan_component_id',target_component_id,
    'generated_deal_rule_count',generated_count,
    'attribution_field_key',attribution_field_key,
    'eligibility_business_concept',target_eligibility->>'business_concept'
  );
end;
$$;

revoke all on function private.sync_rule_builder_deal_execution(uuid) from public, anon, authenticated;

create or replace function private.sync_rule_builder_after_preview()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.supported is true then
    perform private.sync_rule_builder_deal_execution(new.rule_set_id);
  end if;
  return new;
end;
$$;

revoke all on function private.sync_rule_builder_after_preview() from public, anon, authenticated;

drop trigger if exists sync_rule_builder_after_preview on public.comp_rule_set_preview_runs;
create trigger sync_rule_builder_after_preview
after insert on public.comp_rule_set_preview_runs
for each row execute function private.sync_rule_builder_after_preview();

create or replace function private.sync_rule_builder_eligibility_to_deal_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.rule_configuration->'eligibility' is distinct from new.rule_configuration->'eligibility' then
    update public.comp_component_deal_rules
       set marks_eligible = coalesce(new.rule_configuration->'eligibility'->>'business_concept','')='customer_payment_received',
           updated_at = pg_catalog.now()
     where plan_component_id=new.id
       and rule_notes='Generated from Rule Builder qualification';
  end if;
  return new;
end;
$$;

revoke all on function private.sync_rule_builder_eligibility_to_deal_rules() from public, anon, authenticated;

drop trigger if exists sync_rule_builder_eligibility_to_deal_rules on public.comp_plan_components;
create trigger sync_rule_builder_eligibility_to_deal_rules
after update of rule_configuration on public.comp_plan_components
for each row execute function private.sync_rule_builder_eligibility_to_deal_rules();
