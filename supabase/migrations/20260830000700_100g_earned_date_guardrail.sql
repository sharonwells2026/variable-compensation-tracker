-- ============================================================
-- 100G - Earned Date Guardrail Migration
--
-- 1. Retire existing premature, unprotected future earnings.
-- 2. Prevent future-dated candidates from becoming earnings.
-- 3. Preserve candidate data for forecasting.
-- 4. Preserve historical earning and lifecycle records.
-- ============================================================

begin;

create temporary table pg_temp.premature_earnings_to_retire
on commit drop
as
select
  ce.id,
  ce.calculation_id,
  ce.employee_id,
  ce.plan_assignment_id,
  ce.plan_component_id,
  ce.source_external_id as hubspot_deal_id,
  ce.earned_date,
  ce.earned_amount,
  ce.eligibility_status,
  ce.eligible_date,
  ce.eligible_amount,
  ce.payment_status
from public.comp_earnings ce
where ce.is_current = true
  and ce.source_type = 'hubspot_deal'
  and ce.earning_origin = 'system_calculated'::public.earning_origin
  and ce.earned_date > current_date
  and coalesce(ce.approved_amount,0) = 0
  and coalesce(ce.paid_amount,0) = 0
  and ce.employee_verified_at is null
  and ce.manager_approved_at is null
  and ce.executive_approved_at is null
  and not exists (
    select 1 from public.earning_payment_schedules eps
    where eps.comp_earning_id = ce.id
  )
  and not exists (
    select 1 from public.comp_earning_lifecycle_events le
    where le.comp_earning_id = ce.id
      and (
        le.requires_review = true
        or le.review_status in ('pending','approved')
        or le.event_type ilike '%approv%'
        or le.event_type ilike '%pay%'
        or le.event_type ilike '%verif%'
      )
  );

insert into public.comp_earning_lifecycle_events (
  comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,
  event_type,previous_status,new_status,event_reason,event_source,
  previous_state,new_state,requires_review,review_status,occurred_at
)
select
  future.id,
  future.employee_id,
  future.plan_assignment_id,
  future.plan_component_id,
  future.hubspot_deal_id,
  'premature_earning_retired',
  future.eligibility_status::text,
  'not_earned_yet',
  'The earning was created before its configured earned date. It was retired from the current earnings ledger and may be recreated automatically when the earned date arrives.',
  '100G_earned_date_guardrail',
  jsonb_build_object(
    'is_current',true,
    'earned_date',future.earned_date,
    'earned_amount',future.earned_amount,
    'eligibility_status',future.eligibility_status,
    'eligible_date',future.eligible_date,
    'eligible_amount',future.eligible_amount,
    'payment_status',future.payment_status
  ),
  jsonb_build_object(
    'is_current',false,
    'reason','earned_date_is_in_future',
    'future_earned_date',future.earned_date
  ),
  false,
  'not_required',
  pg_catalog.now()
from pg_temp.premature_earnings_to_retire future;

update public.comp_earnings earning
set
  is_current = false,
  eligibility_status = 'ineligible'::public.eligibility_status,
  eligible_date = null,
  eligible_amount = 0,
  payment_status = 'not_payable'::public.payment_status,
  updated_at = pg_catalog.now()
from pg_temp.premature_earnings_to_retire future
where earning.id = future.id;

update public.comp_calculations calculation
set
  total_earned = coalesce(totals.total_earned,0),
  total_eligible = coalesce(totals.total_eligible,0),
  total_approved = coalesce(totals.total_approved,0),
  total_paid = coalesce(totals.total_paid,0),
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
  left join public.comp_earnings earning on earning.calculation_id = calculation_row.id
  where calculation_row.id in (
    select calculation_id from pg_temp.premature_earnings_to_retire
  )
  group by calculation_row.id
) totals
where calculation.id = totals.calculation_id;

create or replace function public.apply_comp_deal_earning_refresh()
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  new_count integer := 0;
  updated_count integer := 0;
  removed_count integer := 0;
  review_count integer := 0;
  missing_period_count integer := 0;
begin
  perform pg_catalog.pg_advisory_xact_lock(85085);

  drop table if exists pg_temp.comp_refresh_delta_snapshot;
  create temporary table comp_refresh_delta_snapshot on commit drop as
  select * from public.comp_deal_earning_refresh_delta;

  insert into public.comp_earning_lifecycle_events (
    comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,
    event_type,previous_status,new_status,event_reason,event_source,
    previous_state,new_state,requires_review,review_status,occurred_at
  )
  select
    d.comp_earning_id,d.employee_id,d.plan_assignment_id,d.plan_component_id,d.hubspot_deal_id,
    d.change_type,d.previous_eligibility_status,d.current_eligibility_status,
    case d.change_type
      when 'credit_review_required' then 'Credit or ownership requires management review before changing this earning.'
      when 'removal_requires_review' then 'The source no longer qualifies, but the earning is approved or paid.'
      else 'The source changed, but the earning is approved or paid.'
    end,
    'compensation_refresh_engine',
    jsonb_build_object(
      'earned_date',d.previous_earned_date,
      'earned_amount',d.previous_earned_amount,
      'eligibility_status',d.previous_eligibility_status,
      'eligible_date',d.previous_eligible_date,
      'eligible_amount',d.previous_eligible_amount,
      'stage_name',d.previous_stage_name
    ),
    jsonb_build_object(
      'earned_date',d.current_earned_date,
      'earned_amount',d.current_earned_amount,
      'eligibility_status',d.current_eligibility_status,
      'eligible_date',d.current_eligible_date,
      'eligible_amount',d.current_eligible_amount,
      'stage_name',d.current_stage_name
    ),
    true,'pending',pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type in ('credit_review_required','removal_requires_review','update_requires_review')
    and not exists (
      select 1 from public.comp_earning_lifecycle_events existing
      where existing.employee_id=d.employee_id
        and existing.plan_component_id=d.plan_component_id
        and existing.hubspot_deal_id=d.hubspot_deal_id
        and existing.event_type=d.change_type
        and existing.review_status='pending'
    );
  get diagnostics review_count = row_count;

  insert into public.comp_earning_lifecycle_events (
    comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,
    event_type,previous_status,new_status,event_reason,event_source,
    previous_state,new_state,requires_review,review_status,occurred_at
  )
  select
    d.comp_earning_id,d.employee_id,d.plan_assignment_id,d.plan_component_id,d.hubspot_deal_id,
    'earning_removed',d.previous_eligibility_status,'ineligible',
    'The source no longer matches the configured compensation rules.',
    'compensation_refresh_engine',
    jsonb_build_object(
      'earned_date',d.previous_earned_date,
      'earned_amount',d.previous_earned_amount,
      'eligibility_status',d.previous_eligibility_status,
      'eligible_date',d.previous_eligible_date,
      'eligible_amount',d.previous_eligible_amount,
      'stage_name',d.previous_stage_name
    ),
    jsonb_build_object('is_current',false,'eligibility_status','ineligible'),
    false,'not_required',pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type='remove_earning';

  update public.comp_earnings earning
  set
    is_current=false,
    eligibility_status='ineligible'::public.eligibility_status,
    eligible_date=null,
    eligible_amount=0,
    payment_status='not_payable'::public.payment_status,
    updated_at=pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  where d.change_type='remove_earning'
    and earning.id=d.comp_earning_id;
  get diagnostics removed_count = row_count;

  insert into public.comp_earning_lifecycle_events (
    comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,
    event_type,previous_status,new_status,event_reason,event_source,
    previous_state,new_state,requires_review,review_status,occurred_at
  )
  select
    d.comp_earning_id,d.employee_id,d.plan_assignment_id,d.plan_component_id,d.hubspot_deal_id,
    'earning_updated',d.previous_eligibility_status,d.current_eligibility_status,
    'HubSpot source values changed and the earning was recalculated.',
    'compensation_refresh_engine',
    jsonb_build_object(
      'earned_date',d.previous_earned_date,
      'earned_amount',d.previous_earned_amount,
      'eligibility_status',d.previous_eligibility_status,
      'eligible_date',d.previous_eligible_date,
      'eligible_amount',d.previous_eligible_amount,
      'stage_name',d.previous_stage_name
    ),
    jsonb_build_object(
      'earned_date',d.current_earned_date,
      'earned_amount',d.current_earned_amount,
      'eligibility_status',d.current_eligibility_status,
      'eligible_date',d.current_eligible_date,
      'eligible_amount',d.current_eligible_amount,
      'stage_name',d.current_stage_name
    ),
    false,'not_required',pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates candidate
    on candidate.employee_id=d.employee_id
   and candidate.plan_component_id=d.plan_component_id
   and candidate.hubspot_deal_id=d.hubspot_deal_id
  where d.change_type='update_earning'
    and candidate.earned_date <= current_date;

  update public.comp_earnings earning
  set
    earned_date=candidate.earned_date,
    earned_amount=candidate.calculated_earning_amount,
    eligibility_status=candidate.eligibility_status::public.eligibility_status,
    eligible_date=case when candidate.eligibility_status='eligible' then candidate.eligible_date else null end,
    eligible_amount=case when candidate.eligibility_status='eligible' then candidate.calculated_earning_amount else 0 end,
    eligibility_evidence=jsonb_strip_nulls(jsonb_build_object(
      'stage_name',candidate.stage_name,
      'invoice_paid_date',candidate.invoice_paid_date,
      'marks_eligible',candidate.marks_eligible
    )),
    source_url=candidate.hubspot_record_url,
    source_snapshot=earning.source_snapshot || jsonb_strip_nulls(jsonb_build_object(
      'candidate_key',candidate.candidate_key,
      'deal_name',candidate.deal_name,
      'company_name',candidate.company_name,
      'pipeline_name',candidate.pipeline_name,
      'stage_name',candidate.stage_name,
      'deal_type',candidate.hubspot_deal_type,
      'deal_owner_id',candidate.deal_owner_id,
      'company_cem_id',candidate.company_cem_id,
      'amount_source',candidate.amount_source,
      'amount_label',candidate.amount_label,
      'source_amount',candidate.source_amount,
      'component_rate',candidate.component_rate,
      'credit_method',candidate.credit_method,
      'credit_percentage',candidate.credit_percentage,
      'owner_cem_mismatch',candidate.owner_cem_mismatch,
      'credit_review_status',candidate.credit_review_status
    )),
    updated_at=pg_catalog.now()
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates candidate
    on candidate.employee_id=d.employee_id
   and candidate.plan_component_id=d.plan_component_id
   and candidate.hubspot_deal_id=d.hubspot_deal_id
  where d.change_type='update_earning'
    and earning.id=d.comp_earning_id
    and candidate.earned_date <= current_date;
  get diagnostics updated_count = row_count;

  insert into public.comp_calculations (
    employee_id,comp_period_id,calculation_version,calculated_at,
    total_earned,total_eligible,total_approved,total_paid,notes
  )
  select
    candidate.employee_id,period.id,1,pg_catalog.now(),0,0,0,0,
    'Created by the compensation refresh engine.'
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates candidate
    on candidate.employee_id=d.employee_id
   and candidate.plan_component_id=d.plan_component_id
   and candidate.hubspot_deal_id=d.hubspot_deal_id
  join public.comp_periods period
    on candidate.earned_date between period.start_date and period.end_date
  where d.change_type='new_earning'
    and candidate.earned_date <= current_date
  group by candidate.employee_id,period.id
  on conflict (employee_id,comp_period_id,calculation_version)
  do update set
    calculated_at=excluded.calculated_at,
    notes=excluded.notes,
    updated_at=pg_catalog.now();

  drop table if exists pg_temp.new_earning_ids;
  create temporary table new_earning_ids on commit drop as
  with inserted as (
    insert into public.comp_earnings (
      calculation_id,employee_id,plan_assignment_id,plan_component_id,
      earning_name,earning_description,source_type,source_external_id,
      source_url,source_snapshot,earned_date,earned_amount,
      eligibility_status,eligibility_condition_type,
      eligibility_condition_description,eligible_date,eligible_amount,
      eligibility_evidence,approved_amount,payment_status,paid_amount,
      supersedes_earning_id,is_current,earning_origin,
      reconciliation_status,source_match_status
    )
    select
      calculation.id,
      candidate.employee_id,
      candidate.plan_assignment_id,
      candidate.plan_component_id,
      candidate.plan_component_name,
      candidate.plan_component_name || ' for ' || coalesce(candidate.deal_name,candidate.hubspot_deal_id),
      'hubspot_deal',
      candidate.hubspot_deal_id,
      candidate.hubspot_record_url,
      jsonb_strip_nulls(jsonb_build_object(
        'candidate_key',candidate.candidate_key,
        'deal_name',candidate.deal_name,
        'company_name',candidate.company_name,
        'pipeline_name',candidate.pipeline_name,
        'stage_name',candidate.stage_name,
        'deal_type',candidate.hubspot_deal_type,
        'deal_owner_id',candidate.deal_owner_id,
        'company_cem_id',candidate.company_cem_id,
        'amount_source',candidate.amount_source,
        'amount_label',candidate.amount_label,
        'source_amount',candidate.source_amount,
        'component_rate',candidate.component_rate,
        'credit_method',candidate.credit_method,
        'credit_percentage',candidate.credit_percentage,
        'owner_cem_mismatch',candidate.owner_cem_mismatch,
        'credit_review_status',candidate.credit_review_status
      )),
      candidate.earned_date,
      candidate.calculated_earning_amount,
      candidate.eligibility_status::public.eligibility_status,
      'hubspot_paid_status',
      'Eligible when the deal is in a configured Paid stage and has an Invoice Paid Date.',
      case when candidate.eligibility_status='eligible' then candidate.eligible_date else null end,
      case when candidate.eligibility_status='eligible' then candidate.calculated_earning_amount else 0 end,
      jsonb_strip_nulls(jsonb_build_object(
        'stage_name',candidate.stage_name,
        'invoice_paid_date',candidate.invoice_paid_date,
        'marks_eligible',candidate.marks_eligible
      )),
      0,
      'not_payable'::public.payment_status,
      0,
      (
        select previous.id
        from public.comp_earnings previous
        where previous.employee_id=candidate.employee_id
          and previous.plan_component_id=candidate.plan_component_id
          and previous.source_type='hubspot_deal'
          and previous.source_external_id=candidate.hubspot_deal_id
          and previous.is_current=false
        order by previous.updated_at desc
        limit 1
      ),
      true,
      'system_calculated'::public.earning_origin,
      'not_reviewed'::public.reconciliation_status,
      'confirmed'::public.source_match_status
    from pg_temp.comp_refresh_delta_snapshot d
    join public.comp_deal_earning_candidates candidate
      on candidate.employee_id=d.employee_id
     and candidate.plan_component_id=d.plan_component_id
     and candidate.hubspot_deal_id=d.hubspot_deal_id
    join public.comp_periods period
      on candidate.earned_date between period.start_date and period.end_date
    join public.comp_calculations calculation
      on calculation.employee_id=candidate.employee_id
     and calculation.comp_period_id=period.id
     and calculation.calculation_version=1
    where d.change_type='new_earning'
      and candidate.calculation_status='ready'
      and candidate.earned_date <= current_date
    on conflict (employee_id,plan_component_id,source_type,source_external_id)
    where is_current=true and source_type is not null and source_external_id is not null
    do nothing
    returning id
  )
  select id from inserted;

  select count(*) into new_count from pg_temp.new_earning_ids;

  insert into public.comp_earning_lifecycle_events (
    comp_earning_id,employee_id,plan_assignment_id,plan_component_id,
    hubspot_deal_id,event_type,previous_status,new_status,
    event_reason,event_source,previous_state,new_state,
    requires_review,review_status,occurred_at
  )
  select
    earning.id,
    earning.employee_id,
    earning.plan_assignment_id,
    earning.plan_component_id,
    earning.source_external_id,
    case when earning.supersedes_earning_id is null then 'earning_created' else 'earning_reinstated' end,
    null,
    earning.eligibility_status::text,
    case when earning.supersedes_earning_id is null
      then 'A new source matched the configured compensation rules.'
      else 'A previously removed source qualifies again.' end,
    'compensation_refresh_engine',
    '{}'::jsonb,
    jsonb_build_object(
      'earned_date',earning.earned_date,
      'earned_amount',earning.earned_amount,
      'eligibility_status',earning.eligibility_status,
      'eligible_date',earning.eligible_date,
      'eligible_amount',earning.eligible_amount
    ),
    false,'not_required',pg_catalog.now()
  from public.comp_earnings earning
  join pg_temp.new_earning_ids inserted on inserted.id=earning.id;

  select count(*) into missing_period_count
  from pg_temp.comp_refresh_delta_snapshot d
  join public.comp_deal_earning_candidates candidate
    on candidate.employee_id=d.employee_id
   and candidate.plan_component_id=d.plan_component_id
   and candidate.hubspot_deal_id=d.hubspot_deal_id
  where d.change_type='new_earning'
    and candidate.earned_date <= current_date
    and not exists (
      select 1 from public.comp_periods period
      where candidate.earned_date between period.start_date and period.end_date
    );

  if new_count + updated_count + removed_count > 0 then
    update public.comp_calculations calculation
    set
      total_earned=coalesce(totals.total_earned,0),
      total_eligible=coalesce(totals.total_eligible,0),
      total_approved=coalesce(totals.total_approved,0),
      total_paid=coalesce(totals.total_paid,0),
      calculated_at=pg_catalog.now(),
      updated_at=pg_catalog.now()
    from (
      select
        calculation_row.id as calculation_id,
        sum(earning.earned_amount) filter (where earning.is_current) as total_earned,
        sum(earning.eligible_amount) filter (where earning.is_current) as total_eligible,
        sum(earning.approved_amount) filter (where earning.is_current) as total_approved,
        sum(earning.paid_amount) filter (where earning.is_current) as total_paid
      from public.comp_calculations calculation_row
      left join public.comp_earnings earning on earning.calculation_id=calculation_row.id
      group by calculation_row.id
    ) totals
    where calculation.id=totals.calculation_id;
  end if;

  return jsonb_build_object(
    'status','completed',
    'new_earnings',new_count,
    'updated_earnings',updated_count,
    'removed_earnings',removed_count,
    'reviews_created',review_count,
    'candidates_without_period',missing_period_count,
    'completed_at',pg_catalog.now()
  );
end;
$function$;

commit;
