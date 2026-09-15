-- Infer the employee-credit source for simple Deal/Company qualification rules so
-- a newly built pilot plan can flow into the generic_v2 candidate engine.

create or replace function private.sync_simple_qualification_to_deal_rules(target_rule_set_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  component_id uuid;
  purpose_name text;
  plan_start date;
  amount_source_name text;
  stage_values text[];
  type_values text[];
  inferred_field_key text;
begin
  select rs.plan_component_id, rs.purpose, pv.effective_start_date,
         coalesce(nullif(c.measurement_source,''),'amount')
    into component_id, purpose_name, plan_start, amount_source_name
  from public.comp_rule_sets rs
  join public.comp_plan_components c on c.id=rs.plan_component_id
  join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where rs.id=target_rule_set_id;

  if component_id is null or purpose_name <> 'qualification' then return; end if;

  delete from public.comp_component_deal_rules
  where plan_component_id=component_id
    and rule_notes='generated_from_simple_qualification';

  select array_agg(distinct v) into stage_values
  from (
    select case when jsonb_typeof(p.comparison_value)='string' then p.comparison_value #>> '{}'
                else x.value end as v
    from public.comp_rule_predicates p
    left join lateral jsonb_array_elements_text(case when jsonb_typeof(p.comparison_value)='array' then p.comparison_value else '[]'::jsonb end) x(value) on true
    where p.rule_set_id=target_rule_set_id and p.object_type='deal' and p.property_name='dealstage'
  ) q where v is not null and v<>'';

  select array_agg(distinct v) into type_values
  from (
    select case when jsonb_typeof(p.comparison_value)='string' then p.comparison_value #>> '{}'
                else x.value end as v
    from public.comp_rule_predicates p
    left join lateral jsonb_array_elements_text(case when jsonb_typeof(p.comparison_value)='array' then p.comparison_value else '[]'::jsonb end) x(value) on true
    where p.rule_set_id=target_rule_set_id and p.object_type='deal' and p.property_name='dealtype'
  ) q where v is not null and v<>'';

  if coalesce(array_length(stage_values,1),0)>0 and coalesce(array_length(type_values,1),0)>0 then
    insert into public.comp_component_deal_rules(
      plan_component_id, hubspot_pipeline_id, hubspot_stage_id, hubspot_deal_type,
      calculation_action, marks_earned, marks_eligible, marks_paid,
      amount_source, amount_label, priority, is_active, effective_start_date, rule_notes
    )
    select distinct component_id, s.hubspot_pipeline_id, stage_id, deal_type,
           'include', true, false, false,
           amount_source_name,
           case amount_source_name when 'average_arr' then 'ARR' when 'first_year_arr' then 'First Year ARR' when 'one_time_fee' then 'One-time Fee' when 'total_contract_value' then 'Total Contract Value' else 'Deal Amount' end,
           100, true, plan_start, 'generated_from_simple_qualification'
    from unnest(stage_values) stage_id
    join public.hubspot_pipeline_stages s on s.hubspot_stage_id=stage_id
    cross join unnest(type_values) deal_type;
  end if;

  -- Prefer the business ownership field the administrator actually used in the Earned rules.
  select case
    when exists(select 1 from public.comp_rule_predicates p where p.rule_set_id=target_rule_set_id and p.object_type='company' and p.property_name='customer_experience_manager_id') then 'company_cem'
    when exists(select 1 from public.comp_rule_predicates p where p.rule_set_id=target_rule_set_id and p.object_type='deal' and p.property_name='solutions_advisor_id') then 'solutions_advisor'
    when exists(select 1 from public.comp_rule_predicates p where p.rule_set_id=target_rule_set_id and p.object_type='deal' and p.property_name='business_development_owner_id') then 'business_development_owner'
    when exists(select 1 from public.comp_rule_predicates p where p.rule_set_id=target_rule_set_id and p.object_type='deal' and p.property_name='hubspot_owner_id') then 'deal_owner'
    else 'deal_owner'
  end into inferred_field_key;

  if not exists(
    select 1 from public.comp_user_attribution_rules r
    where r.plan_component_id=component_id and r.attribution_purpose='earning' and r.is_active
  ) then
    insert into public.comp_user_attribution_rules(
      plan_component_id,attribution_purpose,metric_key,hubspot_user_field_keys,match_logic,
      credit_percentage,qualifying_pipeline_ids,qualifying_deal_types,priority,allow_stacking,
      rule_configuration,effective_start_date,is_active
    ) values(
      component_id,'earning',null,jsonb_build_array(inferred_field_key),'any',100,
      '[]'::jsonb,'[]'::jsonb,10,false,
      jsonb_build_object('configuration_source','simple_qualification_inference','description','Pilot attribution inferred from Earned conditions.'),
      plan_start,true
    );
  end if;
end;
$$;

revoke all on function private.sync_simple_qualification_to_deal_rules(uuid) from public, anon, authenticated;

-- Backfill draft qualification rule sets already created during UAT.
do $$
declare r record;
begin
  for r in
    select rs.id
    from public.comp_rule_sets rs
    join public.comp_plan_components c on c.id=rs.plan_component_id
    join public.comp_plan_versions pv on pv.id=c.plan_version_id
    where rs.purpose='qualification' and pv.status='draft'
  loop
    perform private.sync_simple_qualification_to_deal_rules(r.id);
  end loop;
end;
$$;
