create or replace function private.evaluate_comp_earning_eligibility(
  target_earning_id uuid,
  evaluation_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  earning_row public.comp_earnings%rowtype;
  component_row public.comp_plan_components%rowtype;
  eligibility_config jsonb;
  mode text;
  waiting_days integer;
  rule_set_id uuid;
  rule_set_row public.comp_rule_sets%rowtype;
  root_node_id uuid;
  root_count integer;
  deal_record_id uuid;
  rule_result boolean;
  calculated_due_date date;
  calculated_eligible_date date;
  should_be_eligible boolean := false;
  reason_code text;
  reason_text text;
  evidence jsonb;
begin
  if evaluation_date is null then
    raise exception 'Evaluation date is required.' using errcode = '22023';
  end if;

  select * into earning_row
  from public.comp_earnings
  where id = target_earning_id;

  if earning_row.id is null then
    raise exception 'Compensation earning does not exist.' using errcode = '22023';
  end if;

  select * into component_row
  from public.comp_plan_components
  where id = earning_row.plan_component_id;

  if component_row.id is null then
    return jsonb_build_object(
      'status','not_evaluable',
      'earning_id',earning_row.id,
      'should_transition',false,
      'reason_code','missing_plan_component',
      'reason','The earning is not linked to a valid plan component.'
    );
  end if;

  eligibility_config := component_row.rule_configuration -> 'eligibility';

  if eligibility_config is null or jsonb_typeof(eligibility_config) <> 'object' then
    return jsonb_build_object(
      'status','not_configured',
      'earning_id',earning_row.id,
      'plan_component_id',component_row.id,
      'current_eligibility_status',earning_row.eligibility_status,
      'should_transition',false,
      'reason_code','component_eligibility_not_configured',
      'reason','This plan component does not use the configurable Earned-to-Eligible evaluator. Existing eligibility behavior should remain unchanged.'
    );
  end if;

  mode := lower(trim(coalesce(eligibility_config->>'mode','')));

  if mode not in ('immediate','waiting_period','rule') then
    return jsonb_build_object(
      'status','configuration_error',
      'earning_id',earning_row.id,
      'plan_component_id',component_row.id,
      'mode',mode,
      'should_transition',false,
      'reason_code','invalid_eligibility_mode',
      'reason','The plan component eligibility mode is invalid.'
    );
  end if;

  if earning_row.earned_date is null then
    return jsonb_build_object(
      'status','not_evaluable',
      'earning_id',earning_row.id,
      'plan_component_id',component_row.id,
      'mode',mode,
      'should_transition',false,
      'reason_code','missing_earned_date',
      'reason','The earning cannot be evaluated because it does not have an earned date.'
    );
  end if;

  if mode = 'immediate' then
    should_be_eligible := earning_row.earned_date <= evaluation_date;
    calculated_eligible_date := case when should_be_eligible then earning_row.earned_date else null end;
    reason_code := case when should_be_eligible then 'immediate_condition_satisfied' else 'earned_date_in_future' end;
    reason_text := case
      when should_be_eligible then 'The plan component becomes Eligible immediately when the earning is Earned.'
      else 'The earning has not reached its earned date yet.'
    end;

    evidence := jsonb_build_object(
      'mode','immediate',
      'earned_date',earning_row.earned_date,
      'evaluation_date',evaluation_date
    );

  elsif mode = 'waiting_period' then
    begin
      waiting_days := (eligibility_config->>'waiting_days')::integer;
    exception when others then
      waiting_days := null;
    end;

    if waiting_days is null then
      waiting_days := component_row.additional_eligibility_waiting_days;
    end if;

    if waiting_days is null or waiting_days < 0 then
      return jsonb_build_object(
        'status','configuration_error',
        'earning_id',earning_row.id,
        'plan_component_id',component_row.id,
        'mode',mode,
        'should_transition',false,
        'reason_code','invalid_waiting_period',
        'reason','The plan component waiting-period configuration is invalid.'
      );
    end if;

    calculated_due_date := earning_row.earned_date + waiting_days;
    should_be_eligible := calculated_due_date <= evaluation_date;
    calculated_eligible_date := case when should_be_eligible then calculated_due_date else null end;
    reason_code := case when should_be_eligible then 'waiting_period_completed' else 'waiting_period_in_progress' end;
    reason_text := case
      when should_be_eligible then 'The configured waiting period has completed.'
      else 'The earning is waiting for the configured eligibility period to complete.'
    end;

    evidence := jsonb_build_object(
      'mode','waiting_period',
      'waiting_days',waiting_days,
      'earned_date',earning_row.earned_date,
      'eligibility_due_date',calculated_due_date,
      'evaluation_date',evaluation_date,
      'days_remaining',greatest(calculated_due_date - evaluation_date,0)
    );

  else
    begin
      rule_set_id := (eligibility_config->>'rule_set_id')::uuid;
    exception when others then
      rule_set_id := null;
    end;

    if rule_set_id is null then
      return jsonb_build_object(
        'status','configuration_error',
        'earning_id',earning_row.id,
        'plan_component_id',component_row.id,
        'mode',mode,
        'should_transition',false,
        'reason_code','missing_rule_set',
        'reason','Rule-based eligibility requires a configured eligibility rule set.'
      );
    end if;

    select * into rule_set_row
    from public.comp_rule_sets
    where id = rule_set_id;

    if rule_set_row.id is null
       or rule_set_row.plan_component_id <> component_row.id
       or rule_set_row.purpose <> 'eligibility' then
      return jsonb_build_object(
        'status','configuration_error',
        'earning_id',earning_row.id,
        'plan_component_id',component_row.id,
        'mode',mode,
        'rule_set_id',rule_set_id,
        'should_transition',false,
        'reason_code','invalid_rule_set',
        'reason','The configured eligibility rule set is missing or does not belong to this plan component.'
      );
    end if;

    select count(*), min(id)
    into root_count, root_node_id
    from public.comp_rule_expression_nodes
    where rule_set_id = rule_set_row.id
      and parent_node_id is null;

    if root_count <> 1 or root_node_id is null then
      return jsonb_build_object(
        'status','configuration_error',
        'earning_id',earning_row.id,
        'plan_component_id',component_row.id,
        'mode',mode,
        'rule_set_id',rule_set_row.id,
        'should_transition',false,
        'reason_code','invalid_rule_expression',
        'reason','The eligibility rule set must contain exactly one root expression.'
      );
    end if;

    if earning_row.source_type = 'hubspot_deal' then
      select d.id into deal_record_id
      from public.hubspot_deals d
      where d.hubspot_deal_id = earning_row.source_external_id
      limit 1;

      if deal_record_id is null then
        return jsonb_build_object(
          'status','not_evaluable',
          'earning_id',earning_row.id,
          'plan_component_id',component_row.id,
          'mode',mode,
          'rule_set_id',rule_set_row.id,
          'should_transition',false,
          'reason_code','source_record_not_found',
          'reason','The HubSpot deal referenced by this earning is not available in the synchronized source data.'
        );
      end if;

      rule_result := public.comp_rule_evaluate_deal_node(root_node_id, deal_record_id);
    else
      return jsonb_build_object(
        'status','not_evaluable',
        'earning_id',earning_row.id,
        'plan_component_id',component_row.id,
        'mode',mode,
        'rule_set_id',rule_set_row.id,
        'source_type',earning_row.source_type,
        'should_transition',false,
        'reason_code','unsupported_source_type',
        'reason','Rule-based eligibility is currently supported for HubSpot deal earnings only.'
      );
    end if;

    should_be_eligible := coalesce(rule_result,false);
    calculated_eligible_date := case when should_be_eligible then evaluation_date else null end;
    reason_code := case when should_be_eligible then 'eligibility_rule_matched' else 'eligibility_rule_not_matched' end;
    reason_text := case
      when should_be_eligible then 'The configured eligibility rule is satisfied.'
      else 'The configured eligibility rule is not yet satisfied.'
    end;

    evidence := jsonb_build_object(
      'mode','rule',
      'rule_set_id',rule_set_row.id,
      'rule_set_name',rule_set_row.name,
      'rule_set_version',rule_set_row.version,
      'root_node_id',root_node_id,
      'source_type',earning_row.source_type,
      'source_external_id',earning_row.source_external_id,
      'evaluation_date',evaluation_date,
      'rule_result',should_be_eligible
    );
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'status','evaluated',
    'earning_id',earning_row.id,
    'employee_id',earning_row.employee_id,
    'plan_component_id',component_row.id,
    'mode',mode,
    'current_eligibility_status',earning_row.eligibility_status,
    'target_eligibility_status',case when should_be_eligible then 'eligible' else 'pending_condition' end,
    'should_transition',should_be_eligible and earning_row.eligibility_status <> 'eligible',
    'eligibility_due_date',calculated_due_date,
    'eligible_date',calculated_eligible_date,
    'eligible_amount',case when should_be_eligible then earning_row.earned_amount else 0 end,
    'reason_code',reason_code,
    'reason',reason_text,
    'evidence',evidence
  ));
end;
$function$;

revoke all on function private.evaluate_comp_earning_eligibility(uuid,date) from public;
revoke all on function private.evaluate_comp_earning_eligibility(uuid,date) from anon;
revoke all on function private.evaluate_comp_earning_eligibility(uuid,date) from authenticated;

create or replace function public.preview_comp_earning_eligibility(
  target_earning_id uuid,
  evaluation_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  earning_employee_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select employee_id into earning_employee_id
  from public.comp_earnings
  where id = target_earning_id;

  if earning_employee_id is null then
    raise exception 'Compensation earning does not exist.' using errcode = '22023';
  end if;

  if not private.can_access_employee(earning_employee_id,'earnings.view') then
    raise exception 'Earning access required.' using errcode = '42501';
  end if;

  return private.evaluate_comp_earning_eligibility(target_earning_id,evaluation_date);
end;
$function$;

revoke all on function public.preview_comp_earning_eligibility(uuid,date) from public;
revoke all on function public.preview_comp_earning_eligibility(uuid,date) from anon;
grant execute on function public.preview_comp_earning_eligibility(uuid,date) to authenticated;