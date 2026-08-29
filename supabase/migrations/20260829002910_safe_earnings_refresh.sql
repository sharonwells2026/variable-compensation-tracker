-- 085 - Safe earnings refresh engine
-- Compares current HubSpot candidates to posted earnings, applies safe changes,
-- and preserves review and lifecycle history.

create or replace view public.comp_deal_earning_refresh_delta
with (security_invoker = true)
as
with candidates as (
  select *
  from public.comp_deal_earning_candidates
  where marks_earned = true
),
current_earnings as (
  select
    ce.*,
    ce.source_snapshot->>'candidate_key' as stored_candidate_key,
    ce.source_snapshot->>'stage_name' as stored_stage_name,
    ce.source_snapshot->>'deal_name' as stored_deal_name,
    ce.source_snapshot->>'company_name' as stored_company_name
  from public.comp_earnings ce
  where ce.is_current = true
    and ce.source_type = 'hubspot_deal'
),
comparison as (
  select
    coalesce(c.candidate_key, e.stored_candidate_key) as candidate_key,
    coalesce(c.employee_id, e.employee_id) as employee_id,
    coalesce(c.full_name, emp.full_name) as full_name,
    coalesce(c.plan_component_id, e.plan_component_id) as plan_component_id,
    coalesce(c.plan_component_name, e.earning_name) as plan_component_name,
    e.id as comp_earning_id,
    coalesce(c.hubspot_deal_id, e.source_external_id) as hubspot_deal_id,
    coalesce(c.deal_name, e.stored_deal_name) as deal_name,
    coalesce(c.company_name, e.stored_company_name) as company_name,
    e.earned_date as previous_earned_date,
    c.earned_date as current_earned_date,
    e.earned_amount as previous_earned_amount,
    c.calculated_earning_amount as current_earned_amount,
    e.eligibility_status::text as previous_eligibility_status,
    c.eligibility_status as current_eligibility_status,
    e.eligible_date as previous_eligible_date,
    c.eligible_date as current_eligible_date,
    e.eligible_amount as previous_eligible_amount,
    case when c.eligibility_status = 'eligible'
      then c.calculated_earning_amount else 0 end as current_eligible_amount,
    e.stored_stage_name as previous_stage_name,
    c.stage_name as current_stage_name,
    e.manager_approval_status::text as manager_approval_status,
    e.approved_amount,
    e.payment_status::text as payment_status,
    e.paid_amount,
    c.calculation_status,
    c.requires_credit_review,
    c.credit_review_status,
    c.plan_assignment_id,
    c.invoice_paid_date,
    c.hubspot_record_url,
    (
      e.id is not null and (
        e.manager_approval_status = 'approved'
        or e.approved_amount > 0
        or e.payment_status in (
          'ready_for_payroll', 'scheduled', 'partially_paid', 'paid'
        )
        or e.paid_amount > 0
      )
    ) as is_financially_protected,
    (
      e.id is not null
      and c.candidate_key is not null
      and (
        e.earned_date is distinct from c.earned_date
        or e.earned_amount is distinct from c.calculated_earning_amount
        or e.eligibility_status::text is distinct from c.eligibility_status
        or e.eligible_date is distinct from c.eligible_date
        or e.eligible_amount is distinct from
          case when c.eligibility_status = 'eligible'
            then c.calculated_earning_amount else 0 end
        or e.stored_stage_name is distinct from c.stage_name
      )
    ) as has_changed
  from candidates c
  full join current_earnings e
    on e.employee_id = c.employee_id
   and e.plan_component_id = c.plan_component_id
   and e.source_external_id = c.hubspot_deal_id
  left join public.employees emp on emp.id = e.employee_id
)
select
  comparison.candidate_key,
  comparison.employee_id,
  comparison.full_name,
  comparison.plan_component_id,
  comparison.plan_component_name,
  comparison.comp_earning_id,
  comparison.hubspot_deal_id,
  comparison.deal_name,
  comparison.company_name,
  comparison.previous_earned_date,
  comparison.current_earned_date,
  comparison.previous_earned_amount,
  comparison.current_earned_amount,
  comparison.previous_eligibility_status,
  comparison.current_eligibility_status,
  comparison.previous_eligible_date,
  comparison.current_eligible_date,
  comparison.previous_eligible_amount,
  comparison.current_eligible_amount,
  comparison.previous_stage_name,
  comparison.current_stage_name,
  comparison.manager_approval_status,
  comparison.approved_amount,
  comparison.payment_status,
  comparison.paid_amount,
  case
    when comparison.calculation_status <> 'ready'
      then 'credit_review_required'
    when comparison.comp_earning_id is null
      then 'new_earning'
    when comparison.candidate_key is null
      and comparison.is_financially_protected
      then 'removal_requires_review'
    when comparison.candidate_key is null
      then 'remove_earning'
    when comparison.has_changed
      and comparison.is_financially_protected
      then 'update_requires_review'
    when comparison.has_changed
      then 'update_earning'
    else 'unchanged'
  end as change_type,
  case
    when comparison.calculation_status <> 'ready' then true
    when comparison.candidate_key is null
      and comparison.is_financially_protected then true
    when comparison.has_changed
      and comparison.is_financially_protected then true
    else false
  end as requires_review,
  comparison.calculation_status,
  comparison.requires_credit_review,
  comparison.credit_review_status,
  comparison.plan_assignment_id,
  comparison.invoice_paid_date,
  comparison.hubspot_record_url,
  comparison.is_financially_protected
from comparison;


create or replace function public.apply_comp_deal_earning_refresh()
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  new_count integer := 0;
  updated_count integer := 0;
  removed_count integer := 0;
  review_count integer := 0;
  missing_period_count integer := 0;
begin
  perform pg_catalog.pg_advisory_xact_lock(85085);

  drop table if exists pg_temp.comp_refresh_delta_snapshot;
  create temporary table comp_refresh_delta_snapshot
  on commit drop
  as
  select * from public.comp_deal_earning_refresh_delta;

  -- Create one pending lifecycle review per unresolved protected change.
  insert into public.comp_earning_lifecycle_events (
    comp_earning_id, employee_id, plan_assignment_id, plan_component_id,
    hubspot_deal_id, event_type, previous_status, new_status,
    event_reason, event_source, previous_state, new_state,
    requires_review, review_status, occurred_at
  )
  select
    d.comp_earning_id,
    d.employee_id,
    d.plan_assignment_id,
    d.plan_component_id,
    d.hubspot_deal_id,
    d.change_type,
    d.previous_eligibility_status,
    d.current_eligibility_status,
    case d.change_type
      when 'credit_review_required' then
        'Credit or ownership requires management review before changing this earning.'
      when 'removal_requires_review' then
        'The source no longer qualifies, but the earning is approved or paid.'
      else
        'The source changed, but the earning is approved or paid.'
    end,
    'compensation_refresh_engine',
    jsonb_build_object(
      'earned_date', d.previous_earned_date,
      'earned_amount', d.previous_earned_amount,
      'eligibility_status', d.previous_eligibility_status,
      'eligible_date', d.previous_eligible_date,
      'eligible_amount', d.previous_eligible_amount,
      'stage_name', d.previous_stage_name
    ),
    jsonb_build_object(
      'earned_date', d.current_earned_date,
      'earned_amount', d.current_earned_amount,
      'eligibility_status', d.current_eligibility_status,
      'eligible_date', d.current_eligible_date,
      'eligible_amount', d.current_eligible_amount,
      'stage_name', d.current_stage_name
    ),
    true,
    'pending',
    pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type in (
    'credit_review_required',
    'removal_requires_review',
    'update_requires_review'
  )
  and not exists (
    select 1
    from public.comp_earning_lifecycle_events existing
    where existing.employee_id = d.employee_id
      and existing.plan_component_id = d.plan_component_id
      and existing.hubspot_deal_id = d.hubspot_deal_id
      and existing.event_type = d.change_type
      and existing.review_status = 'pending'
  );
  get diagnostics review_count = row_count;

  -- Log removals before making the earning non-current.
  insert into public.comp_earning_lifecycle_events (
    comp_earning_id, employee_id, plan_assignment_id, plan_component_id,
    hubspot_deal_id, event_type, previous_status, new_status,
    event_reason, event_source, previous_state, new_state,
    requires_review, review_status, occurred_at
  )
  select
    d.comp_earning_id,
    d.employee_id,
    d.plan_assignment_id,
    d.plan_component_id,
    d.hubspot_deal_id,
    'earning_removed',
    d.previous_eligibility_status,
    'ineligible',
    'The source no longer matches the configured compensation rules.',
    'compensation_refresh_engine',
    jsonb_build_object(
      'earned_date', d.previous_earned_date,
      'earned_amount', d.previous_earned_amount,
      'eligibility_status', d.previous_eligibility_status,
      'eligible_date', d.previous_eligible_date,
      'eligible_amount', d.previous_eligible_amount,
      'stage_name', d.previous_stage_name
    ),
    jsonb_build_object('is_current', false, 'eligibility_status', 'ineligible'),
    false,
    'not_required',
    pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type = 'remove_earning';

  update public.comp_earnings earning
  set
    is_current = false,
    eligibility_status = 'ineligible'::public.eligibility_status,
    eligible_date = null,
    eligible_amount = 0,
    payment_status = 'not_payable'::public.payment_status,
    updated_at = pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type = 'remove_earning'
    and earning.id = d.comp_earning_id;
  get diagnostics removed_count = row_count;

  -- Log safe, unprotected updates before applying them.
  insert into public.comp_earning_lifecycle_events (
    comp_earning_id, employee_id, plan_assignment_id, plan_component_id,
    hubspot_deal_id, event_type, previous_status, new_status,
    event_reason, event_source, previous_state, new_state,
    requires_review, review_status, occurred_at
  )
  select
    d.comp_earning_id,
    d.employee_id,
    d.plan_assignment_id,
    d.plan_component_id,
    d.hubspot_deal_id,
    'earning_updated',
    d.previous_eligibility_status,
    d.current_eligibility_status,
    'HubSpot source values changed and the earning was recalculated.',
    'compensation_refresh_engine',
    jsonb_build_object(
      'earned_date', d.previous_earned_date,
      'earned_amount', d.previous_earned_amount,
      'eligibility_status', d.previous_eligibility_status,
      'eligible_date', d.previous_eligible_date,
      'eligible_amount', d.previous_eligible_amount,
      'stage_name', d.previous_stage_name
    ),
    jsonb_build_object(
      'earned_date', d.current_earned_date,
      'earned_amount', d.current_earned_amount,
      'eligibility_status', d.current_eligibility_status,
      'eligible_date', d.current_eligible_date,
      'eligible_amount', d.current_eligible_amount,
      'stage_name', d.current_stage_name
    ),
    false,
    'not_required',
    pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type = 'update_earning';

  update public.comp_earnings earning
  set
    earned_date = candidate.earned_date,
    earned_amount = candidate.calculated_earning_amount,
    eligibility_status = candidate.eligibility_status::public.eligibility_status,
    eligible_date = case when candidate.eligibility_status = 'eligible'
      then candidate.eligible_date else null end,
    eligible_amount = case when candidate.eligibility_status = 'eligible'
      then candidate.calculated_earning_amount else 0 end,
    eligibility_evidence = jsonb_strip_nulls(jsonb_build_object(
      'stage_name', candidate.stage_name,
      'invoice_paid_date', candidate.invoice_paid_date,
      'marks_eligible', candidate.marks_eligible
    )),
    source_url = candidate.hubspot_record_url,
    source_snapshot = earning.source_snapshot || jsonb_strip_nulls(jsonb_build_object(
      'candidate_key', candidate.candidate_key,
      'deal_name', candidate.deal_name,
      'company_name', candidate.company_name,
      'pipeline_name', candidate.pipeline_name,
      'stage_name', candidate.stage_name,
      'deal_type', candidate.hubspot_deal_type,
      'deal_owner_id', candidate.deal_owner_id,
      'company_cem_id', candidate.company_cem_id,
      'amount_source', candidate.amount_source,
      'amount_label', candidate.amount_label,
      'source_amount', candidate.source_amount,
      'component_rate', candidate.component_rate,
      'credit_method', candidate.credit_method,
      'credit_percentage', candidate.credit_percentage,
      'owner_cem_mismatch', candidate.owner_cem_mismatch,
      'credit_review_status', candidate.credit_review_status
    )),
    updated_at = pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates candidate
    on candidate.employee_id = d.employee_id
   and candidate.plan_component_id = d.plan_component_id
   and candidate.hubspot_deal_id = d.hubspot_deal_id
  where d.change_type = 'update_earning'
    and earning.id = d.comp_earning_id;
  get diagnostics updated_count = row_count;

  -- Ensure a calculation container exists for each new earning month.
  insert into public.comp_calculations (
    employee_id, comp_period_id, calculation_version, calculated_at,
    total_earned, total_eligible, total_approved, total_paid, notes
  )
  select
    candidate.employee_id,
    period.id,
    1,
    pg_catalog.now(),
    0, 0, 0, 0,
    'Created by the compensation refresh engine.'
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates candidate
    on candidate.employee_id = d.employee_id
   and candidate.plan_component_id = d.plan_component_id
   and candidate.hubspot_deal_id = d.hubspot_deal_id
  join public.comp_periods period
    on candidate.earned_date between period.start_date and period.end_date
  where d.change_type = 'new_earning'
  group by candidate.employee_id, period.id
  on conflict (employee_id, comp_period_id, calculation_version)
  do update set calculated_at = excluded.calculated_at,
    notes = excluded.notes,
    updated_at = pg_catalog.now();

  drop table if exists pg_temp.new_earning_ids;
  create temporary table new_earning_ids
  on commit drop
  as
  with inserted as (
    insert into public.comp_earnings (
      calculation_id, employee_id, plan_assignment_id, plan_component_id,
      earning_name, earning_description, source_type, source_external_id,
      source_url, source_snapshot, earned_date, earned_amount,
      eligibility_status, eligibility_condition_type,
      eligibility_condition_description, eligible_date, eligible_amount,
      eligibility_evidence, approved_amount, payment_status, paid_amount,
      supersedes_earning_id, is_current, earning_origin,
      reconciliation_status, source_match_status
    )
    select
      calculation.id,
      candidate.employee_id,
      candidate.plan_assignment_id,
      candidate.plan_component_id,
      candidate.plan_component_name,
      candidate.plan_component_name || ' for ' ||
        coalesce(candidate.deal_name, candidate.hubspot_deal_id),
      'hubspot_deal',
      candidate.hubspot_deal_id,
      candidate.hubspot_record_url,
      jsonb_strip_nulls(jsonb_build_object(
        'candidate_key', candidate.candidate_key,
        'deal_name', candidate.deal_name,
        'company_name', candidate.company_name,
        'pipeline_name', candidate.pipeline_name,
        'stage_name', candidate.stage_name,
        'deal_type', candidate.hubspot_deal_type,
        'deal_owner_id', candidate.deal_owner_id,
        'company_cem_id', candidate.company_cem_id,
        'amount_source', candidate.amount_source,
        'amount_label', candidate.amount_label,
        'source_amount', candidate.source_amount,
        'component_rate', candidate.component_rate,
        'credit_method', candidate.credit_method,
        'credit_percentage', candidate.credit_percentage,
        'owner_cem_mismatch', candidate.owner_cem_mismatch,
        'credit_review_status', candidate.credit_review_status
      )),
      candidate.earned_date,
      candidate.calculated_earning_amount,
      candidate.eligibility_status::public.eligibility_status,
      'hubspot_paid_status',
      'Eligible when the deal is in a configured Paid stage and has an Invoice Paid Date.',
      case when candidate.eligibility_status = 'eligible'
        then candidate.eligible_date else null end,
      case when candidate.eligibility_status = 'eligible'
        then candidate.calculated_earning_amount else 0 end,
      jsonb_strip_nulls(jsonb_build_object(
        'stage_name', candidate.stage_name,
        'invoice_paid_date', candidate.invoice_paid_date,
        'marks_eligible', candidate.marks_eligible
      )),
      0,
      'not_payable'::public.payment_status,
      0,
      (
        select previous.id
        from public.comp_earnings previous
        where previous.employee_id = candidate.employee_id
          and previous.plan_component_id = candidate.plan_component_id
          and previous.source_type = 'hubspot_deal'
          and previous.source_external_id = candidate.hubspot_deal_id
          and previous.is_current = false
        order by previous.updated_at desc
        limit 1
      ),
      true,
      'system_calculated'::public.earning_origin,
      'not_reviewed'::public.reconciliation_status,
      'confirmed'::public.source_match_status
    from pg_temp.comp_refresh_delta_snapshot d
    join public.comp_deal_earning_candidates candidate
      on candidate.employee_id = d.employee_id
     and candidate.plan_component_id = d.plan_component_id
     and candidate.hubspot_deal_id = d.hubspot_deal_id
    join public.comp_periods period
      on candidate.earned_date between period.start_date and period.end_date
    join public.comp_calculations calculation
      on calculation.employee_id = candidate.employee_id
     and calculation.comp_period_id = period.id
     and calculation.calculation_version = 1
    where d.change_type = 'new_earning'
      and candidate.calculation_status = 'ready'
    on conflict (employee_id, plan_component_id, source_type, source_external_id)
    where is_current = true
      and source_type is not null
      and source_external_id is not null
    do nothing
    returning id
  )
  select id from inserted;

  select count(*) into new_count from pg_temp.new_earning_ids;

  insert into public.comp_earning_lifecycle_events (
    comp_earning_id, employee_id, plan_assignment_id, plan_component_id,
    hubspot_deal_id, event_type, previous_status, new_status,
    event_reason, event_source, previous_state, new_state,
    requires_review, review_status, occurred_at
  )
  select
    earning.id,
    earning.employee_id,
    earning.plan_assignment_id,
    earning.plan_component_id,
    earning.source_external_id,
    case when earning.supersedes_earning_id is null
      then 'earning_created' else 'earning_reinstated' end,
    null,
    earning.eligibility_status::text,
    case when earning.supersedes_earning_id is null
      then 'A new source matched the configured compensation rules.'
      else 'A previously removed source qualifies again.' end,
    'compensation_refresh_engine',
    '{}'::jsonb,
    jsonb_build_object(
      'earned_date', earning.earned_date,
      'earned_amount', earning.earned_amount,
      'eligibility_status', earning.eligibility_status,
      'eligible_date', earning.eligible_date,
      'eligible_amount', earning.eligible_amount
    ),
    false,
    'not_required',
    pg_catalog.now()
  from public.comp_earnings earning
  join pg_temp.new_earning_ids inserted on inserted.id = earning.id;

  select count(*)
  into missing_period_count
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates candidate
    on candidate.employee_id = d.employee_id
   and candidate.plan_component_id = d.plan_component_id
   and candidate.hubspot_deal_id = d.hubspot_deal_id
  where d.change_type = 'new_earning'
    and not exists (
      select 1 from public.comp_periods period
      where candidate.earned_date between period.start_date and period.end_date
    );

  -- Recalculate totals only when an earning actually changed. A no-change
  -- refresh should not rewrite timestamps or create unnecessary audit noise.
  if new_count + updated_count + removed_count > 0 then
    update public.comp_calculations calculation
    set
      total_earned = coalesce(totals.total_earned, 0),
      total_eligible = coalesce(totals.total_eligible, 0),
      total_approved = coalesce(totals.total_approved, 0),
      total_paid = coalesce(totals.total_paid, 0),
      calculated_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
    from (
      select
        calculation_row.id as calculation_id,
        sum(earning.earned_amount) filter (where earning.is_current) as total_earned,
        sum(earning.eligible_amount) filter (where earning.is_current) as total_eligible,
        sum(earning.approved_amount) filter (where earning.is_current) as total_approved,
        sum(earning.paid_amount) filter (where earning.is_current) as total_paid
      from public.comp_calculations calculation_row
      left join public.comp_earnings earning
        on earning.calculation_id = calculation_row.id
      group by calculation_row.id
    ) totals
    where calculation.id = totals.calculation_id;
  end if;

  return jsonb_build_object(
    'status', 'completed',
    'new_earnings', new_count,
    'updated_earnings', updated_count,
    'removed_earnings', removed_count,
    'reviews_created', review_count,
    'candidates_without_period', missing_period_count,
    'completed_at', pg_catalog.now()
  );
end;
$$;

revoke all on function public.apply_comp_deal_earning_refresh() from public;
revoke all on function public.apply_comp_deal_earning_refresh() from anon;
revoke all on function public.apply_comp_deal_earning_refresh() from authenticated;
