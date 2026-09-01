-- ============================================================
-- 100H-100J Generic Compensation Engine - Production Reconciliation
-- Reconstructed from the verified production contract on 2026-08-31.
-- Captures the V2 candidate engine, attribution resolver, generic delta,
-- and controlled refresh behavior that were installed incrementally in
-- production during the 100H-100J audit remediation sequence.
-- ============================================================

-- ------------------------------------------------------------
-- 100J reusable HubSpot user attribution resolver
-- ------------------------------------------------------------
create or replace function private.resolve_comp_user_attribution(
  selected_employee_id uuid,
  selected_plan_component_id uuid,
  selected_hubspot_deal_id text,
  selected_attribution_purpose text default 'earning',
  selected_metric_key text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  deal_pipeline_id text;
  deal_type text;
  deal_close_date date;
  applicable_rule_count integer := 0;
  configuration_error_count integer := 0;
  matched_rule_count integer := 0;
  resolved_credit_percentage numeric;
  resolution_status text;
  selected_rule_id uuid;
  selected_priority integer;
  selected_allow_stacking boolean;
  rule_evidence jsonb := '[]'::jsonb;
begin
  select d.hubspot_pipeline_id,d.hubspot_deal_type,d.close_date
  into deal_pipeline_id,deal_type,deal_close_date
  from public.hubspot_deals d
  where d.hubspot_deal_id=selected_hubspot_deal_id;

  if deal_close_date is null then
    return jsonb_build_object(
      'status','deal_not_found_or_missing_close_date',
      'matched',false,
      'employee_id',selected_employee_id,
      'plan_component_id',selected_plan_component_id,
      'hubspot_deal_id',selected_hubspot_deal_id
    );
  end if;

  with applicable_rules as (
    select
      r.id,r.priority,r.allow_stacking,r.credit_percentage,
      r.hubspot_user_field_keys,r.match_logic,r.rule_configuration,
      private.evaluate_hubspot_user_attribution(
        selected_employee_id,
        selected_hubspot_deal_id,
        r.hubspot_user_field_keys,
        r.match_logic
      ) attribution_result
    from public.comp_user_attribution_rules r
    where r.plan_component_id=selected_plan_component_id
      and r.attribution_purpose=selected_attribution_purpose
      and (
        selected_attribution_purpose <> 'metric'
        or r.metric_key is not distinct from selected_metric_key
      )
      and r.is_active=true
      and deal_close_date>=r.effective_start_date
      and deal_close_date<=coalesce(r.effective_end_date,'infinity'::date)
      and (r.qualifying_pipeline_ids='[]'::jsonb or r.qualifying_pipeline_ids ? deal_pipeline_id)
      and (r.qualifying_deal_types='[]'::jsonb or r.qualifying_deal_types ? deal_type)
  ), classified as (
    select *,
      attribution_result->>'status' attribution_status,
      coalesce((attribution_result->>'matched')::boolean,false) matched,
      case when attribution_result->>'status' in (
        'invalid_user_field_configuration','missing_employee_hubspot_owner','deal_not_found'
      ) then true else false end configuration_error
    from applicable_rules
  ), summary as (
    select
      count(*) applicable_rule_count,
      count(*) filter(where configuration_error) configuration_error_count,
      count(*) filter(where matched) matched_rule_count,
      jsonb_agg(
        jsonb_build_object(
          'rule_id',id,
          'priority',priority,
          'allow_stacking',allow_stacking,
          'credit_percentage',credit_percentage,
          'matched',matched,
          'configuration_error',configuration_error,
          'attribution_status',attribution_status,
          'attribution_result',attribution_result
        ) order by priority,id
      ) rule_evidence
    from classified
  )
  select s.applicable_rule_count,s.configuration_error_count,s.matched_rule_count,
         coalesce(s.rule_evidence,'[]'::jsonb)
  into applicable_rule_count,configuration_error_count,matched_rule_count,rule_evidence
  from summary s;

  if applicable_rule_count=0 then
    return jsonb_build_object(
      'status','no_applicable_rule','matched',false,'resolved_credit_percentage',0,
      'employee_id',selected_employee_id,'plan_component_id',selected_plan_component_id,
      'hubspot_deal_id',selected_hubspot_deal_id,'rule_evidence',rule_evidence
    );
  end if;

  if configuration_error_count>0 then
    return jsonb_build_object(
      'status','configuration_error','matched',false,'resolved_credit_percentage',null,
      'employee_id',selected_employee_id,'plan_component_id',selected_plan_component_id,
      'hubspot_deal_id',selected_hubspot_deal_id,
      'applicable_rule_count',applicable_rule_count,
      'configuration_error_count',configuration_error_count,
      'rule_evidence',rule_evidence
    );
  end if;

  if matched_rule_count=0 then
    return jsonb_build_object(
      'status','legitimate_non_match','matched',false,'resolved_credit_percentage',0,
      'employee_id',selected_employee_id,'plan_component_id',selected_plan_component_id,
      'hubspot_deal_id',selected_hubspot_deal_id,
      'applicable_rule_count',applicable_rule_count,'matched_rule_count',0,
      'rule_evidence',rule_evidence
    );
  end if;

  with matched_rules as (
    select r.id,r.priority,r.allow_stacking,r.credit_percentage
    from public.comp_user_attribution_rules r
    where r.plan_component_id=selected_plan_component_id
      and r.attribution_purpose=selected_attribution_purpose
      and (
        selected_attribution_purpose <> 'metric'
        or r.metric_key is not distinct from selected_metric_key
      )
      and r.is_active=true
      and deal_close_date>=r.effective_start_date
      and deal_close_date<=coalesce(r.effective_end_date,'infinity'::date)
      and (r.qualifying_pipeline_ids='[]'::jsonb or r.qualifying_pipeline_ids ? deal_pipeline_id)
      and (r.qualifying_deal_types='[]'::jsonb or r.qualifying_deal_types ? deal_type)
      and coalesce((private.evaluate_hubspot_user_attribution(
        selected_employee_id,selected_hubspot_deal_id,r.hubspot_user_field_keys,r.match_logic
      )->>'matched')::boolean,false)=true
  ), stacking_summary as (
    select
      count(*) filter(where allow_stacking=true) stacking_count,
      least(100::numeric,coalesce(sum(credit_percentage) filter(where allow_stacking=true),0)) stacking_credit_percentage
    from matched_rules
  )
  select
    case when ss.stacking_count>0 then ss.stacking_credit_percentage
         else (select mr.credit_percentage from matched_rules mr order by mr.priority,mr.id limit 1) end,
    case when ss.stacking_count>0 then 'matched_stacked' else 'matched_single' end
  into resolved_credit_percentage,resolution_status
  from stacking_summary ss;

  select r.id,r.priority,r.allow_stacking
  into selected_rule_id,selected_priority,selected_allow_stacking
  from public.comp_user_attribution_rules r
  where r.plan_component_id=selected_plan_component_id
    and r.attribution_purpose=selected_attribution_purpose
    and (
      selected_attribution_purpose <> 'metric'
      or r.metric_key is not distinct from selected_metric_key
    )
    and r.is_active=true
    and deal_close_date>=r.effective_start_date
    and deal_close_date<=coalesce(r.effective_end_date,'infinity'::date)
    and (r.qualifying_pipeline_ids='[]'::jsonb or r.qualifying_pipeline_ids ? deal_pipeline_id)
    and (r.qualifying_deal_types='[]'::jsonb or r.qualifying_deal_types ? deal_type)
    and coalesce((private.evaluate_hubspot_user_attribution(
      selected_employee_id,selected_hubspot_deal_id,r.hubspot_user_field_keys,r.match_logic
    )->>'matched')::boolean,false)=true
  order by r.priority,r.id
  limit 1;

  return jsonb_build_object(
    'status',resolution_status,
    'matched',true,
    'resolved_credit_percentage',resolved_credit_percentage,
    'employee_id',selected_employee_id,
    'plan_component_id',selected_plan_component_id,
    'hubspot_deal_id',selected_hubspot_deal_id,
    'selected_rule_id',selected_rule_id,
    'selected_priority',selected_priority,
    'selected_allow_stacking',selected_allow_stacking,
    'applicable_rule_count',applicable_rule_count,
    'matched_rule_count',matched_rule_count,
    'rule_evidence',rule_evidence
  );
end;
$function$;

revoke all on function private.resolve_comp_user_attribution(uuid,uuid,text,text,text)
from public,anon,authenticated;

-- ------------------------------------------------------------
-- 100H / 100J safe generic deal candidate engine
-- ------------------------------------------------------------
create or replace view public.comp_deal_earning_candidates_v2
with (security_invoker=true)
as
with qualified_deals as (
  select
    e.id employee_id,e.full_name,e.email,e.hubspot_owner_id employee_hubspot_owner_id,
    epa.id plan_assignment_id,
    cp.id comp_plan_id,cp.name plan_name,
    pv.id plan_version_id,pv.version_number,pv.status::text plan_status,
    c.id plan_component_id,c.component_code,c.name plan_component_name,
    c.calculation_type,c.measurement_source,c.measurement_label,
    c.rule_configuration component_configuration,
    dr.id deal_rule_id,dr.amount_source,dr.amount_label,
    dr.marks_earned,dr.marks_eligible,dr.marks_paid,
    d.hubspot_deal_id,d.deal_name,d.hubspot_owner_id deal_owner_id,
    d.hubspot_pipeline_id,p.pipeline_name,d.hubspot_stage_id,s.stage_name,
    d.hubspot_deal_type,d.close_date,d.invoice_paid_date,
    d.contract_term_years,d.contract_term_months,d.hubspot_record_url,
    company.hubspot_company_id,company.company_name,
    company.customer_experience_manager_id company_cem_id,
    case dr.amount_source
      when 'amount' then d.amount
      when 'average_arr' then d.average_arr
      when 'first_year_arr' then d.first_year_arr
      when 'one_time_fee' then d.one_time_fee
      when 'total_contract_value' then d.total_contract_value
      else null::numeric
    end source_amount
  from public.employees e
  join public.employee_plan_assignments epa on epa.employee_id=e.id
  join public.comp_plan_versions pv on pv.id=epa.plan_version_id
  join public.comp_plans cp on cp.id=pv.comp_plan_id
  join public.comp_plan_components c on c.plan_version_id=pv.id and c.is_active=true
  join public.comp_component_deal_rules dr on dr.plan_component_id=c.id
    and dr.is_active=true and dr.calculation_action='include' and dr.marks_earned=true
  join public.hubspot_deals d on d.hubspot_pipeline_id=dr.hubspot_pipeline_id
    and d.hubspot_stage_id=dr.hubspot_stage_id
    and d.hubspot_deal_type=dr.hubspot_deal_type
  join public.hubspot_pipelines p on p.hubspot_pipeline_id=d.hubspot_pipeline_id
  join public.hubspot_pipeline_stages s on s.hubspot_pipeline_id=d.hubspot_pipeline_id
    and s.hubspot_stage_id=d.hubspot_stage_id
  left join lateral (
    select a.hubspot_company_id
    from public.hubspot_deal_company_associations a
    where a.hubspot_deal_id=d.hubspot_deal_id
    order by a.is_primary desc,a.last_synced_at desc
    limit 1
  ) association on true
  left join public.hubspot_companies company on company.hubspot_company_id=association.hubspot_company_id
  where d.close_date is not null
    and d.close_date>=greatest(epa.effective_start_date,pv.effective_start_date,dr.effective_start_date)
    and d.close_date<=least(
      coalesce(epa.effective_end_date,'infinity'::date),
      coalesce(pv.effective_end_date,'infinity'::date),
      coalesce(dr.effective_end_date,'infinity'::date)
    )
), resolved as (
  select q.*,
    private.resolve_comp_user_attribution(q.employee_id,q.plan_component_id,q.hubspot_deal_id,'earning',null) attribution_result
  from qualified_deals q
), attribution_state as (
  select r.*,
    attribution_result->>'status' attribution_status,
    coalesce((attribution_result->>'matched')::boolean,false) attribution_matched,
    nullif(attribution_result->>'resolved_credit_percentage','')::numeric resolved_credit_percentage,
    nullif(attribution_result->>'selected_rule_id','')::uuid selected_attribution_rule_id
  from resolved r
), with_rule_metadata as (
  select a.*,
    rule.id attribution_rule_id,
    rule.hubspot_user_field_keys,
    rule.match_logic attribution_match_logic,
    a.resolved_credit_percentage credit_percentage,
    rule.priority attribution_priority,
    coalesce((a.attribution_result->>'selected_allow_stacking')::boolean,rule.allow_stacking,false) allow_stacking,
    rule.rule_configuration attribution_configuration
  from attribution_state a
  left join public.comp_user_attribution_rules rule on rule.id=a.selected_attribution_rule_id
), calculated as (
  select a.*,
    public.evaluate_compensation_rule(
      a.calculation_type,a.component_configuration,a.source_amount,
      a.contract_term_years,null,a.close_date
    ) calculation_result
  from with_rule_metadata a
  where a.attribution_matched=true or a.attribution_status='configuration_error'
)
select
  md5(employee_id::text||':'||plan_component_id::text||':'||hubspot_deal_id) candidate_key,
  employee_id,full_name,email,employee_hubspot_owner_id,plan_assignment_id,
  comp_plan_id,plan_name,plan_version_id,version_number,plan_status,
  plan_component_id,component_code,plan_component_name,
  calculation_type,measurement_source,measurement_label,
  deal_rule_id,attribution_rule_id,hubspot_user_field_keys,attribution_match_logic,
  credit_percentage,attribution_priority,allow_stacking,
  hubspot_deal_id,deal_name,deal_owner_id,hubspot_pipeline_id,pipeline_name,
  hubspot_stage_id,stage_name,hubspot_deal_type,hubspot_company_id,company_name,company_cem_id,
  close_date earned_date,
  case when marks_eligible=true and invoice_paid_date is not null then invoice_paid_date else null::date end eligible_date,
  amount_source,amount_label,source_amount,contract_term_years,contract_term_months,
  nullif(calculation_result->>'resolved_rate','')::numeric resolved_rate,
  nullif(calculation_result->>'resolved_fixed_amount','')::numeric resolved_fixed_amount,
  case
    when attribution_status='configuration_error' then null::numeric
    when attribution_matched=true and calculation_result->>'status'='ready'
      then round(nullif(calculation_result->>'calculated_amount','')::numeric*(resolved_credit_percentage/100::numeric),2)
    else null::numeric
  end calculated_earning_amount,
  case when attribution_status='configuration_error' then 'attribution_configuration_error'
       else calculation_result->>'status' end calculation_status,
  case when attribution_status='configuration_error' then 'HubSpot user attribution configuration requires review.'
       else calculation_result->>'explanation' end calculation_explanation,
  calculation_result,attribution_result,
  case when marks_eligible=true and invoice_paid_date is not null then 'eligible' else 'pending_condition' end eligibility_status,
  marks_earned,marks_eligible,marks_paid,invoice_paid_date,hubspot_record_url,
  component_configuration,attribution_configuration
from calculated;

comment on view public.comp_deal_earning_candidates_v2 is
'100J safe generic candidate engine. Uses reusable attribution resolution with deterministic priority, stacking support, and fail-safe configuration-error candidates so attribution configuration defects cannot silently appear as earning removals.';

-- ------------------------------------------------------------
-- 100I generic delta engine
-- ------------------------------------------------------------
create or replace view public.comp_deal_earning_refresh_delta
with (security_invoker=true)
as
with candidates as (
  select * from public.comp_deal_earning_candidates_v2 where marks_earned=true
), current_earnings as (
  select ce.*,
    ce.source_snapshot->>'candidate_key' stored_candidate_key,
    ce.source_snapshot->>'stage_name' stored_stage_name,
    ce.source_snapshot->>'deal_name' stored_deal_name,
    ce.source_snapshot->>'company_name' stored_company_name
  from public.comp_earnings ce
  where ce.is_current=true and ce.source_type='hubspot_deal'
), comparison as (
  select
    c.candidate_key,
    coalesce(c.employee_id,e.employee_id) employee_id,
    coalesce(c.full_name,emp.full_name) full_name,
    coalesce(c.plan_component_id,e.plan_component_id) plan_component_id,
    coalesce(c.plan_component_name,e.earning_name) plan_component_name,
    e.id comp_earning_id,
    coalesce(c.hubspot_deal_id,e.source_external_id) hubspot_deal_id,
    coalesce(c.deal_name,e.stored_deal_name) deal_name,
    coalesce(c.company_name,e.stored_company_name) company_name,
    e.earned_date previous_earned_date,c.earned_date current_earned_date,
    e.earned_amount previous_earned_amount,c.calculated_earning_amount current_earned_amount,
    e.eligibility_status::text previous_eligibility_status,c.eligibility_status current_eligibility_status,
    e.eligible_date previous_eligible_date,c.eligible_date current_eligible_date,
    e.eligible_amount previous_eligible_amount,
    case when c.eligibility_status='eligible' then c.calculated_earning_amount else 0::numeric end current_eligible_amount,
    e.stored_stage_name previous_stage_name,c.stage_name current_stage_name,
    e.manager_approval_status::text manager_approval_status,e.approved_amount,
    e.payment_status::text payment_status,e.paid_amount,
    c.calculation_status,c.plan_assignment_id,c.invoice_paid_date,c.hubspot_record_url,
    e.id is not null and (
      e.manager_approval_status='approved'::public.approval_status
      or coalesce(e.approved_amount,0)>0
      or e.payment_status in (
        'ready_for_payroll'::public.payment_status,'scheduled'::public.payment_status,
        'partially_paid'::public.payment_status,'paid'::public.payment_status
      )
      or coalesce(e.paid_amount,0)>0
    ) is_financially_protected,
    e.id is not null and c.candidate_key is not null and (
      e.earned_date is distinct from c.earned_date
      or e.earned_amount is distinct from c.calculated_earning_amount
      or e.eligibility_status::text is distinct from c.eligibility_status
      or e.eligible_date is distinct from c.eligible_date
      or e.eligible_amount is distinct from case when c.eligibility_status='eligible' then c.calculated_earning_amount else 0::numeric end
      or e.stored_stage_name is distinct from c.stage_name
    ) has_changed,
    c.calculation_explanation,c.calculation_result,c.attribution_rule_id,c.attribution_result,
    c.credit_percentage,c.calculation_type,c.resolved_rate,c.resolved_fixed_amount,
    c.component_configuration,c.attribution_configuration
  from candidates c
  full join current_earnings e
    on e.employee_id=c.employee_id
   and e.plan_component_id=c.plan_component_id
   and e.source_external_id=c.hubspot_deal_id
  left join public.employees emp on emp.id=e.employee_id
), classified as (
  select comparison.*,
    case
      when comp_earning_id is null and candidate_key is not null and current_earned_date>current_date then 'future_forecast_only'
      when candidate_key is not null and calculation_status<>'ready' then 'calculation_review_required'
      when comp_earning_id is null and candidate_key is not null then 'new_earning'
      when candidate_key is null and comp_earning_id is not null and is_financially_protected then 'removal_requires_review'
      when candidate_key is null and comp_earning_id is not null then 'remove_earning'
      when has_changed and is_financially_protected then 'update_requires_review'
      when has_changed then 'update_earning'
      else 'unchanged'
    end generic_change_type,
    case
      when candidate_key is not null and calculation_status<>'ready' then true
      when candidate_key is null and comp_earning_id is not null and is_financially_protected then true
      when has_changed and is_financially_protected then true
      else false
    end generic_requires_review
  from comparison
)
select
  candidate_key,employee_id,full_name,plan_component_id,plan_component_name,
  comp_earning_id,hubspot_deal_id,deal_name,company_name,
  previous_earned_date,current_earned_date,previous_earned_amount,current_earned_amount,
  previous_eligibility_status,current_eligibility_status,
  previous_eligible_date,current_eligible_date,previous_eligible_amount,current_eligible_amount,
  previous_stage_name,current_stage_name,manager_approval_status,approved_amount,payment_status,paid_amount,
  generic_change_type change_type,generic_requires_review requires_review,
  calculation_status,generic_requires_review requires_credit_review,
  case when generic_requires_review then 'review_required' else 'not_required' end credit_review_status,
  plan_assignment_id,invoice_paid_date,hubspot_record_url,is_financially_protected,
  calculation_explanation,calculation_result,attribution_rule_id,attribution_result,
  credit_percentage,calculation_type,resolved_rate,resolved_fixed_amount,
  component_configuration,attribution_configuration
from classified;

comment on view public.comp_deal_earning_refresh_delta is
'100I generic compensation earning refresh delta. Uses comp_deal_earning_candidates_v2 and generic calculation/HubSpot attribution metadata while preserving the existing refresh boundary. Future-dated candidates remain forecast-only and financially protected earnings require review before destructive changes.';

-- ------------------------------------------------------------
-- 100I controlled generic refresh engine
-- ------------------------------------------------------------
create or replace function public.apply_comp_deal_earning_refresh()
returns jsonb
language plpgsql
set search_path=''
as $function$
declare
  new_count integer:=0;
  updated_count integer:=0;
  removed_count integer:=0;
  review_count integer:=0;
  missing_period_count integer:=0;
begin
  perform pg_catalog.pg_advisory_xact_lock(85085);

  drop table if exists pg_temp.comp_refresh_delta_snapshot;
  create temporary table comp_refresh_delta_snapshot on commit drop as
  select * from public.comp_deal_earning_refresh_delta;

  insert into public.comp_earning_lifecycle_events(
    comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,
    event_type,previous_status,new_status,event_reason,event_source,
    previous_state,new_state,requires_review,review_status,occurred_at
  )
  select
    d.comp_earning_id,d.employee_id,d.plan_assignment_id,d.plan_component_id,d.hubspot_deal_id,
    d.change_type,d.previous_eligibility_status,d.current_eligibility_status,
    case d.change_type
      when 'calculation_review_required' then 'The generic compensation engine could not calculate this candidate cleanly and management review is required.'
      when 'removal_requires_review' then 'The source no longer qualifies under the configured compensation rules, but the earning is financially protected.'
      when 'update_requires_review' then 'The source changed under the configured compensation rules, but the earning is financially protected.'
      else 'The compensation source requires management review.' end,
    'generic_compensation_refresh_engine',
    jsonb_strip_nulls(jsonb_build_object(
      'earned_date',d.previous_earned_date,'earned_amount',d.previous_earned_amount,
      'eligibility_status',d.previous_eligibility_status,'eligible_date',d.previous_eligible_date,
      'eligible_amount',d.previous_eligible_amount,'stage_name',d.previous_stage_name
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'earned_date',d.current_earned_date,'earned_amount',d.current_earned_amount,
      'eligibility_status',d.current_eligibility_status,'eligible_date',d.current_eligible_date,
      'eligible_amount',d.current_eligible_amount,'stage_name',d.current_stage_name
    )),
    true,'pending',pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type in ('calculation_review_required','removal_requires_review','update_requires_review')
    and not exists(
      select 1 from public.comp_earning_lifecycle_events existing
      where existing.employee_id=d.employee_id
        and existing.plan_component_id=d.plan_component_id
        and existing.hubspot_deal_id=d.hubspot_deal_id
        and existing.event_type=d.change_type
        and existing.review_status='pending'
    );
  get diagnostics review_count=row_count;

  insert into public.comp_earning_lifecycle_events(
    comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,
    event_type,previous_status,new_status,event_reason,event_source,
    previous_state,new_state,requires_review,review_status,occurred_at
  )
  select
    d.comp_earning_id,d.employee_id,d.plan_assignment_id,d.plan_component_id,d.hubspot_deal_id,
    'earning_removed',d.previous_eligibility_status,'ineligible',
    'The source no longer matches the configured generic compensation attribution and calculation rules.',
    'generic_compensation_refresh_engine',
    jsonb_strip_nulls(jsonb_build_object(
      'earned_date',d.previous_earned_date,'earned_amount',d.previous_earned_amount,
      'eligibility_status',d.previous_eligibility_status,'eligible_date',d.previous_eligible_date,
      'eligible_amount',d.previous_eligible_amount,'stage_name',d.previous_stage_name
    )),
    jsonb_build_object('is_current',false,'eligibility_status','ineligible','reason','no_longer_qualifies_under_generic_rules'),
    false,'not_required',pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type='remove_earning';

  update public.comp_earnings earning
  set is_current=false,
      eligibility_status='ineligible'::public.eligibility_status,
      eligible_date=null,eligible_amount=0,
      payment_status='not_payable'::public.payment_status,
      updated_at=pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type='remove_earning' and earning.id=d.comp_earning_id;
  get diagnostics removed_count=row_count;

  insert into public.comp_earning_lifecycle_events(
    comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,
    event_type,previous_status,new_status,event_reason,event_source,
    previous_state,new_state,requires_review,review_status,occurred_at
  )
  select d.comp_earning_id,d.employee_id,d.plan_assignment_id,d.plan_component_id,d.hubspot_deal_id,
    'earning_updated',d.previous_eligibility_status,d.current_eligibility_status,
    'HubSpot source, attribution, or calculation values changed and the earning was recalculated by the generic compensation engine.',
    'generic_compensation_refresh_engine',
    jsonb_strip_nulls(jsonb_build_object(
      'earned_date',d.previous_earned_date,'earned_amount',d.previous_earned_amount,
      'eligibility_status',d.previous_eligibility_status,'eligible_date',d.previous_eligible_date,
      'eligible_amount',d.previous_eligible_amount,'stage_name',d.previous_stage_name
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'earned_date',d.current_earned_date,'earned_amount',d.current_earned_amount,
      'eligibility_status',d.current_eligibility_status,'eligible_date',d.current_eligible_date,
      'eligible_amount',d.current_eligible_amount,'stage_name',d.current_stage_name
    )),
    false,'not_required',pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates_v2 candidate
    on candidate.employee_id=d.employee_id
   and candidate.plan_component_id=d.plan_component_id
   and candidate.hubspot_deal_id=d.hubspot_deal_id
  where d.change_type='update_earning'
    and candidate.calculation_status='ready'
    and candidate.earned_date<=current_date;

  update public.comp_earnings earning
  set earned_date=candidate.earned_date,
      earned_amount=candidate.calculated_earning_amount,
      eligibility_status=candidate.eligibility_status::public.eligibility_status,
      eligible_date=case when candidate.eligibility_status='eligible' then candidate.eligible_date else null end,
      eligible_amount=case when candidate.eligibility_status='eligible' then candidate.calculated_earning_amount else 0 end,
      eligibility_evidence=jsonb_strip_nulls(jsonb_build_object(
        'stage_name',candidate.stage_name,'invoice_paid_date',candidate.invoice_paid_date,'marks_eligible',candidate.marks_eligible
      )),
      source_url=candidate.hubspot_record_url,
      source_snapshot=coalesce(earning.source_snapshot,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
        'candidate_key',candidate.candidate_key,'engine_version','generic_v2',
        'deal_name',candidate.deal_name,'company_name',candidate.company_name,
        'pipeline_name',candidate.pipeline_name,'stage_name',candidate.stage_name,
        'deal_type',candidate.hubspot_deal_type,'deal_owner_id',candidate.deal_owner_id,
        'company_cem_id',candidate.company_cem_id,'amount_source',candidate.amount_source,
        'amount_label',candidate.amount_label,'source_amount',candidate.source_amount,
        'contract_term_years',candidate.contract_term_years,'contract_term_months',candidate.contract_term_months,
        'calculation_type',candidate.calculation_type,'calculation_status',candidate.calculation_status,
        'calculation_explanation',candidate.calculation_explanation,'calculation_result',candidate.calculation_result,
        'resolved_rate',candidate.resolved_rate,'resolved_fixed_amount',candidate.resolved_fixed_amount,
        'credit_percentage',candidate.credit_percentage,'attribution_rule_id',candidate.attribution_rule_id,
        'attribution_result',candidate.attribution_result
      )),
      updated_at=pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates_v2 candidate
    on candidate.employee_id=d.employee_id
   and candidate.plan_component_id=d.plan_component_id
   and candidate.hubspot_deal_id=d.hubspot_deal_id
  where d.change_type='update_earning'
    and earning.id=d.comp_earning_id
    and candidate.calculation_status='ready'
    and candidate.earned_date<=current_date;
  get diagnostics updated_count=row_count;

  insert into public.comp_calculations(
    employee_id,comp_period_id,calculation_version,calculated_at,
    total_earned,total_eligible,total_approved,total_paid,notes
  )
  select candidate.employee_id,period.id,1,pg_catalog.now(),0,0,0,0,
         'Created by the generic compensation refresh engine.'
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates_v2 candidate
    on candidate.employee_id=d.employee_id
   and candidate.plan_component_id=d.plan_component_id
   and candidate.hubspot_deal_id=d.hubspot_deal_id
  join public.comp_periods period on candidate.earned_date between period.start_date and period.end_date
  where d.change_type='new_earning'
    and candidate.calculation_status='ready'
    and candidate.earned_date<=current_date
  group by candidate.employee_id,period.id
  on conflict(employee_id,comp_period_id,calculation_version)
  do update set calculated_at=excluded.calculated_at,notes=excluded.notes,updated_at=pg_catalog.now();

  drop table if exists pg_temp.new_earning_ids;
  create temporary table new_earning_ids on commit drop as
  with inserted as (
    insert into public.comp_earnings(
      calculation_id,employee_id,plan_assignment_id,plan_component_id,
      earning_name,earning_description,source_type,source_external_id,
      source_url,source_snapshot,earned_date,earned_amount,
      eligibility_status,eligibility_condition_type,eligibility_condition_description,
      eligible_date,eligible_amount,eligibility_evidence,
      approved_amount,payment_status,paid_amount,supersedes_earning_id,is_current,
      earning_origin,reconciliation_status,source_match_status
    )
    select
      calculation.id,candidate.employee_id,candidate.plan_assignment_id,candidate.plan_component_id,
      candidate.plan_component_name,
      candidate.plan_component_name||' for '||coalesce(candidate.deal_name,candidate.hubspot_deal_id),
      'hubspot_deal',candidate.hubspot_deal_id,candidate.hubspot_record_url,
      jsonb_strip_nulls(jsonb_build_object(
        'candidate_key',candidate.candidate_key,'engine_version','generic_v2',
        'deal_name',candidate.deal_name,'company_name',candidate.company_name,
        'pipeline_name',candidate.pipeline_name,'stage_name',candidate.stage_name,
        'deal_type',candidate.hubspot_deal_type,'deal_owner_id',candidate.deal_owner_id,
        'company_cem_id',candidate.company_cem_id,'amount_source',candidate.amount_source,
        'amount_label',candidate.amount_label,'source_amount',candidate.source_amount,
        'contract_term_years',candidate.contract_term_years,'contract_term_months',candidate.contract_term_months,
        'calculation_type',candidate.calculation_type,'calculation_status',candidate.calculation_status,
        'calculation_explanation',candidate.calculation_explanation,'calculation_result',candidate.calculation_result,
        'resolved_rate',candidate.resolved_rate,'resolved_fixed_amount',candidate.resolved_fixed_amount,
        'credit_percentage',candidate.credit_percentage,'attribution_rule_id',candidate.attribution_rule_id,
        'attribution_result',candidate.attribution_result
      )),
      candidate.earned_date,candidate.calculated_earning_amount,
      candidate.eligibility_status::public.eligibility_status,
      'hubspot_paid_status',
      'Eligible when the configured HubSpot paid condition is satisfied and an Invoice Paid Date is present.',
      case when candidate.eligibility_status='eligible' then candidate.eligible_date else null end,
      case when candidate.eligibility_status='eligible' then candidate.calculated_earning_amount else 0 end,
      jsonb_strip_nulls(jsonb_build_object(
        'stage_name',candidate.stage_name,'invoice_paid_date',candidate.invoice_paid_date,'marks_eligible',candidate.marks_eligible
      )),
      0,'not_payable'::public.payment_status,0,
      (
        select previous.id from public.comp_earnings previous
        where previous.employee_id=candidate.employee_id
          and previous.plan_component_id=candidate.plan_component_id
          and previous.source_type='hubspot_deal'
          and previous.source_external_id=candidate.hubspot_deal_id
          and previous.is_current=false
        order by previous.updated_at desc limit 1
      ),
      true,'system_calculated'::public.earning_origin,
      'not_reviewed'::public.reconciliation_status,'confirmed'::public.source_match_status
    from pg_temp.comp_refresh_delta_snapshot d
    join public.comp_deal_earning_candidates_v2 candidate
      on candidate.employee_id=d.employee_id
     and candidate.plan_component_id=d.plan_component_id
     and candidate.hubspot_deal_id=d.hubspot_deal_id
    join public.comp_periods period on candidate.earned_date between period.start_date and period.end_date
    join public.comp_calculations calculation
      on calculation.employee_id=candidate.employee_id
     and calculation.comp_period_id=period.id
     and calculation.calculation_version=1
    where d.change_type='new_earning'
      and candidate.calculation_status='ready'
      and candidate.earned_date<=current_date
    on conflict(employee_id,plan_component_id,source_type,source_external_id)
      where is_current=true and source_type is not null and source_external_id is not null
    do nothing
    returning id
  ) select id from inserted;

  select count(*) into new_count from pg_temp.new_earning_ids;

  insert into public.comp_earning_lifecycle_events(
    comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,
    event_type,previous_status,new_status,event_reason,event_source,
    previous_state,new_state,requires_review,review_status,occurred_at
  )
  select earning.id,earning.employee_id,earning.plan_assignment_id,earning.plan_component_id,earning.source_external_id,
    case when earning.supersedes_earning_id is null then 'earning_created' else 'earning_reinstated' end,
    null,earning.eligibility_status::text,
    case when earning.supersedes_earning_id is null
         then 'A new HubSpot source matched the configured generic compensation rules.'
         else 'A previously retired HubSpot source qualifies again under the configured generic compensation rules.' end,
    'generic_compensation_refresh_engine','{}'::jsonb,
    jsonb_build_object(
      'earned_date',earning.earned_date,'earned_amount',earning.earned_amount,
      'eligibility_status',earning.eligibility_status,'eligible_date',earning.eligible_date,
      'eligible_amount',earning.eligible_amount
    ),false,'not_required',pg_catalog.now()
  from public.comp_earnings earning
  join pg_temp.new_earning_ids inserted on inserted.id=earning.id;

  select count(*) into missing_period_count
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates_v2 candidate
    on candidate.employee_id=d.employee_id
   and candidate.plan_component_id=d.plan_component_id
   and candidate.hubspot_deal_id=d.hubspot_deal_id
  where d.change_type='new_earning'
    and candidate.calculation_status='ready'
    and candidate.earned_date<=current_date
    and not exists(
      select 1 from public.comp_periods period
      where candidate.earned_date between period.start_date and period.end_date
    );

  if new_count+updated_count+removed_count>0 then
    update public.comp_calculations calculation
    set total_earned=coalesce(totals.total_earned,0),
        total_eligible=coalesce(totals.total_eligible,0),
        total_approved=coalesce(totals.total_approved,0),
        total_paid=coalesce(totals.total_paid,0),
        calculated_at=pg_catalog.now(),updated_at=pg_catalog.now()
    from (
      select calculation_row.id calculation_id,
        sum(earning.earned_amount) filter(where earning.is_current) total_earned,
        sum(earning.eligible_amount) filter(where earning.is_current) total_eligible,
        sum(earning.approved_amount) filter(where earning.is_current) total_approved,
        sum(earning.paid_amount) filter(where earning.is_current) total_paid
      from public.comp_calculations calculation_row
      left join public.comp_earnings earning on earning.calculation_id=calculation_row.id
      group by calculation_row.id
    ) totals
    where calculation.id=totals.calculation_id;
  end if;

  return jsonb_build_object(
    'status','completed','engine','generic_v2',
    'new_earnings',new_count,'updated_earnings',updated_count,
    'removed_earnings',removed_count,'reviews_created',review_count,
    'candidates_without_period',missing_period_count,'completed_at',pg_catalog.now()
  );
end;
$function$;
