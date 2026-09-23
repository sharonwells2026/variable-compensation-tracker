-- Resolve historical reconciliation-boundary review decisions without silently rewriting prior compensation.
insert into private.role_permissions(role_key,permission_key,allowed)
values ('finance_payroll','reconciliation.manage',true)
on conflict (role_key,permission_key) do update set allowed=excluded.allowed,updated_at=now();

CREATE OR REPLACE FUNCTION public.resolve_reconciliation_review(target_earning_id uuid, requested_decision text, requested_difference_amount numeric DEFAULT NULL::numeric, requested_comments text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  earning public.comp_earnings%rowtype;
  boundary_id uuid;
  boundary_date date;
  boundary_reference text;
  boundary_amount numeric;
  normalized_decision text := lower(trim(coalesce(requested_decision,'')));
  difference_amount numeric := abs(coalesce(requested_difference_amount,0));
  new_status public.reconciliation_status;
  adjustment_id uuid;
  action_id uuid;
  action_reason text;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode='42501';
  end if;

  if not private.has_permission('reconciliation.manage')
     and not private.has_app_role('system_administrator') then
    raise exception 'Reconciliation management is not permitted.' using errcode='42501';
  end if;

  if normalized_decision not in ('underpayment','overpayment','ignore') then
    raise exception 'Decision must be underpayment, overpayment, or ignore.';
  end if;

  select * into earning
  from public.comp_earnings
  where id=target_earning_id
  for update;

  if not found then
    raise exception 'Earning not found.';
  end if;

  if earning.is_current is not true then
    raise exception 'Only the current earning can be reconciled.';
  end if;

  if earning.reconciliation_status <> 'needs_information'::public.reconciliation_status
     or coalesce((earning.source_snapshot->>'reconciliation_review_required')::boolean,false) is not true then
    raise exception 'This earning is not awaiting reconciliation-boundary review.';
  end if;

  boundary_id := nullif(earning.source_snapshot->>'reconciliation_boundary_id','')::uuid;
  boundary_date := nullif(earning.source_snapshot->>'reconciliation_boundary_date','')::date;
  boundary_reference := earning.source_snapshot->>'reconciliation_boundary_reference';
  boundary_amount := nullif(earning.source_snapshot->>'reconciliation_boundary_amount','')::numeric;

  if normalized_decision in ('underpayment','overpayment') and difference_amount <= 0 then
    raise exception 'A positive difference amount is required for underpayment or overpayment.';
  end if;

  if normalized_decision='underpayment' then
    new_status := 'confirmed_unpaid'::public.reconciliation_status;
    action_reason := concat(
      'Historical reconciliation review classified this earning as an underpayment. ',
      'Additional amount identified: ', to_char(difference_amount,'FM9999999990.00'), '.'
    );

    insert into public.earning_adjustments(
      employee_id,comp_earning_id,comp_period_id,adjustment_type,amount,reason,
      requested_by,approval_status,effective_date,supporting_details
    )
    values(
      earning.employee_id,earning.id,(select c.comp_period_id from public.comp_calculations c where c.id=earning.calculation_id),
      'correction'::public.adjustment_type,difference_amount,
      'Reconciliation underpayment correction',actor,'pending'::public.approval_status,current_date,
      jsonb_strip_nulls(jsonb_build_object(
        'reconciliation_decision','underpayment',
        'reconciliation_boundary_id',boundary_id,
        'reconciliation_boundary_date',boundary_date,
        'reconciliation_boundary_reference',boundary_reference,
        'reconciliation_boundary_amount',boundary_amount,
        'calculated_earning_amount',earning.earned_amount,
        'difference_amount',difference_amount,
        'automatic_payment',false,
        'review_comments',nullif(trim(coalesce(requested_comments,'')),'')
      ))
    )
    returning id into adjustment_id;

  elsif normalized_decision='overpayment' then
    new_status := 'partially_matched'::public.reconciliation_status;
    action_reason := concat(
      'Historical reconciliation review classified this earning as an overpayment. ',
      'Excess amount identified: ', to_char(difference_amount,'FM9999999990.00'),
      '. No automatic clawback was created.'
    );

    insert into public.earning_adjustments(
      employee_id,comp_earning_id,comp_period_id,adjustment_type,amount,reason,
      requested_by,approval_status,effective_date,supporting_details
    )
    values(
      earning.employee_id,earning.id,(select c.comp_period_id from public.comp_calculations c where c.id=earning.calculation_id),
      'correction'::public.adjustment_type,-difference_amount,
      'Reconciliation overpayment record - recovery requires separate approval',actor,'pending'::public.approval_status,current_date,
      jsonb_strip_nulls(jsonb_build_object(
        'reconciliation_decision','overpayment',
        'reconciliation_boundary_id',boundary_id,
        'reconciliation_boundary_date',boundary_date,
        'reconciliation_boundary_reference',boundary_reference,
        'reconciliation_boundary_amount',boundary_amount,
        'calculated_earning_amount',earning.earned_amount,
        'difference_amount',difference_amount,
        'automatic_clawback',false,
        'recovery_action_required',true,
        'review_comments',nullif(trim(coalesce(requested_comments,'')),'')
      ))
    )
    returning id into adjustment_id;

  else
    new_status := 'matched'::public.reconciliation_status;
    action_reason := 'Historical reconciliation review accepted the prior settlement amount without financial change.';
  end if;

  insert into public.reconciliation_actions(
    comp_earning_id,previous_status,new_status,claimed_amount,verified_earned_amount,
    verified_paid_amount,remaining_unpaid_amount,action_reason,evidence,action_by
  )
  values(
    earning.id,earning.reconciliation_status,new_status,earning.earned_amount,earning.earned_amount,
    null,
    case when normalized_decision='underpayment' then difference_amount else 0 end,
    action_reason,
    jsonb_strip_nulls(jsonb_build_object(
      'decision',normalized_decision,
      'difference_amount',case when normalized_decision='ignore' then 0 else difference_amount end,
      'adjustment_id',adjustment_id,
      'boundary_id',boundary_id,
      'boundary_date',boundary_date,
      'boundary_reference',boundary_reference,
      'boundary_amount',boundary_amount,
      'comments',nullif(trim(coalesce(requested_comments,'')),'')
    )),
    actor
  )
  returning id into action_id;

  update public.comp_earnings
  set reconciliation_status=new_status,
      eligibility_status='waived'::public.eligibility_status,
      eligible_date=null,
      eligible_amount=0,
      approved_amount=0,
      payment_status='not_payable'::public.payment_status,
      hold_reason=null,
      reconciliation_notes=concat_ws(' ',reconciliation_notes,action_reason,
        case when nullif(trim(coalesce(requested_comments,'')),'') is not null
             then 'Reviewer note: '||trim(requested_comments) end),
      reconciled_by=actor,
      reconciled_at=now(),
      source_snapshot=coalesce(source_snapshot,'{}'::jsonb)||jsonb_build_object(
        'reconciliation_review_required',false,
        'reconciliation_resolution',normalized_decision,
        'reconciliation_resolution_amount',case when normalized_decision='ignore' then 0 else difference_amount end,
        'reconciliation_action_id',action_id,
        'reconciliation_adjustment_id',adjustment_id
      ),
      updated_at=now()
  where id=earning.id;

  return jsonb_strip_nulls(jsonb_build_object(
    'status','resolved',
    'earning_id',earning.id,
    'decision',normalized_decision,
    'difference_amount',case when normalized_decision='ignore' then 0 else difference_amount end,
    'reconciliation_action_id',action_id,
    'adjustment_id',adjustment_id,
    'financial_effect',
      case
        when normalized_decision='underpayment' then 'positive_adjustment_pending_approval'
        when normalized_decision='overpayment' then 'negative_adjustment_recorded_no_automatic_clawback'
        else 'no_change_prior_settlement_accepted'
      end
  ));
end;
$function$


revoke all on function public.resolve_reconciliation_review(uuid,text,numeric,text) from public,anon;
grant execute on function public.resolve_reconciliation_review(uuid,text,numeric,text) to authenticated;
