alter table public.compensation_review_batches alter column period_start drop not null;
alter table public.compensation_review_batches alter column period_end drop not null;

alter table public.compensation_review_batches drop constraint if exists compensation_review_batches_period_check;
alter table public.compensation_review_batches add constraint compensation_review_batches_period_check check (
  period_start is null or period_end is null or period_end >= period_start
);

create or replace function public.prepare_compensation_review_batch(
  requested_batch_name text,
  requested_period_start date default null,
  requested_period_end date default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := (select auth.uid());
  new_batch_id uuid;
  item_count integer := 0;
  employee_count integer := 0;
  total_amount numeric := 0;
begin
  if actor is null or not private.has_app_role('system_administrator') then
    raise exception 'System administrator access required.' using errcode='42501';
  end if;
  if nullif(trim(coalesce(requested_batch_name,'')),'') is null then
    raise exception 'Batch name is required.' using errcode='22023';
  end if;
  if requested_period_start is not null and requested_period_end is not null and requested_period_end < requested_period_start then
    raise exception 'Review period end cannot precede its start.' using errcode='22023';
  end if;

  insert into public.compensation_review_batches(batch_name,period_start,period_end,status,prepared_by)
  values(trim(requested_batch_name),requested_period_start,requested_period_end,'draft',actor)
  returning id into new_batch_id;

  insert into public.compensation_review_batch_items(
    review_batch_id,comp_earning_id,employee_id,proposed_amount,included,item_snapshot
  )
  select
    new_batch_id,
    e.id,
    e.employee_id,
    greatest(e.eligible_amount-e.paid_amount,0),
    true,
    jsonb_build_object(
      'earning_id',e.id,
      'employee_id',e.employee_id,
      'earning_name',e.earning_name,
      'source_type',e.source_type,
      'source_external_id',e.source_external_id,
      'earned_date',e.earned_date,
      'earned_amount',e.earned_amount,
      'eligibility_status',e.eligibility_status,
      'eligible_date',e.eligible_date,
      'eligible_amount',e.eligible_amount,
      'employee_verification_status',e.employee_verification_status,
      'manager_approval_status',e.manager_approval_status,
      'executive_approval_status',e.executive_approval_status,
      'payment_status',e.payment_status,
      'plan_assignment_id',e.plan_assignment_id,
      'plan_component_id',e.plan_component_id,
      'source_snapshot',e.source_snapshot,
      'eligibility_evidence',e.eligibility_evidence
    )
  from public.comp_earnings e
  where e.is_current = true
    and e.eligibility_status = 'eligible'::public.eligibility_status
    and e.eligible_amount > e.paid_amount
    and e.payment_status not in ('paid'::public.payment_status,'scheduled'::public.payment_status)
    and not exists (
      select 1
      from public.compensation_review_batch_items existing_item
      join public.compensation_review_batches existing_batch on existing_batch.id=existing_item.review_batch_id
      where existing_item.comp_earning_id=e.id
        and existing_item.included=true
        and existing_batch.status in ('submitted','approved','finance_accepted','closed')
    );

  select count(*),count(distinct employee_id),coalesce(sum(proposed_amount),0)
  into item_count,employee_count,total_amount
  from public.compensation_review_batch_items
  where review_batch_id=new_batch_id and included=true;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(actor,'compensation_review_batch_prepared','Compensation review batch prepared by system administrator.',jsonb_build_object(
    'review_batch_id',new_batch_id,
    'batch_name',trim(requested_batch_name),
    'period_start',requested_period_start,
    'period_end',requested_period_end,
    'item_count',item_count,
    'employee_count',employee_count,
    'proposed_total',total_amount,
    'submission_timing','any_time'
  ));

  return jsonb_build_object('review_batch_id',new_batch_id,'status','draft','item_count',item_count,'employee_count',employee_count,'proposed_total',total_amount,'submission_timing','any_time');
end;
$function$;

revoke all on function public.prepare_compensation_review_batch(text,date,date) from public, anon;
grant execute on function public.prepare_compensation_review_batch(text,date,date) to authenticated;