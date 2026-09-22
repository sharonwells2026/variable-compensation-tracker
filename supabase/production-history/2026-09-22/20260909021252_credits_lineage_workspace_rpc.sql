create or replace function public.get_compensation_credits_workspace_data()
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission('earnings.view') then
    raise exception 'Permission denied';
  end if;

  select jsonb_build_object(
    'summary', jsonb_build_object(
      'candidate_count', (select count(*) from public.comp_deal_earning_candidates_v2),
      'eligible_candidate_count', (select count(*) from public.comp_deal_earning_candidates_v2 where eligibility_status = 'eligible'),
      'pending_condition_count', (select count(*) from public.comp_deal_earning_candidates_v2 where eligibility_status = 'pending_condition'),
      'generated_earning_count', (select count(*) from public.comp_earnings where is_current is true),
      'open_review_count', (select count(*) from public.comp_deal_credit_reviews where review_status not in ('approved','rejected','resolved'))
    ),
    'lineage', coalesce((
      select jsonb_agg(jsonb_build_object(
        'candidate_key', c.candidate_key,
        'hubspot_deal_id', c.hubspot_deal_id,
        'deal_name', c.deal_name,
        'company_name', c.company_name,
        'employee_id', c.employee_id,
        'employee_name', c.full_name,
        'plan_name', c.plan_name,
        'component_name', c.plan_component_name,
        'credit_percentage', c.credit_percentage,
        'source_amount', c.source_amount,
        'calculated_earning_amount', c.calculated_earning_amount,
        'calculation_status', c.calculation_status,
        'eligibility_status', c.eligibility_status,
        'earned_date', c.earned_date,
        'eligible_date', c.eligible_date,
        'attribution_match_logic', c.attribution_match_logic,
        'deal_owner_id', c.deal_owner_id,
        'hubspot_record_url', c.hubspot_record_url,
        'earning_id', e.id,
        'earning_amount', e.earned_amount,
        'earning_eligibility_status', e.eligibility_status,
        'payment_status', e.payment_status,
        'review_status', r.review_status,
        'review_type', r.review_type,
        'review_question', r.review_question
      ) order by c.earned_date desc nulls last, c.deal_name)
      from public.comp_deal_earning_candidates_v2 c
      left join lateral (
        select ce.* from public.comp_earnings ce
        where ce.is_current is true
          and ce.employee_id = c.employee_id
          and ce.source_external_id = c.hubspot_deal_id
          and ce.plan_component_id = c.plan_component_id
        order by ce.created_at desc limit 1
      ) e on true
      left join lateral (
        select cr.* from public.comp_deal_credit_reviews cr
        where cr.employee_id = c.employee_id
          and cr.hubspot_deal_id = c.hubspot_deal_id
          and cr.plan_component_id = c.plan_component_id
        order by cr.created_at desc limit 1
      ) r on true
    ), '[]'::jsonb),
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'employee_id', r.employee_id,
        'employee_name', e.full_name,
        'hubspot_deal_id', r.hubspot_deal_id,
        'review_type', r.review_type,
        'review_question', r.review_question,
        'review_status', r.review_status,
        'decision_notes', r.decision_notes,
        'created_at', r.created_at,
        'decided_at', r.decided_at
      ) order by r.created_at desc)
      from public.comp_deal_credit_reviews r
      left join public.employees e on e.id = r.employee_id
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

revoke all on function public.get_compensation_credits_workspace_data() from public, anon;
grant execute on function public.get_compensation_credits_workspace_data() to authenticated;