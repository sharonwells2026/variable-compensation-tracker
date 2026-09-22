create table if not exists public.compensation_review_batches (
  id uuid primary key default gen_random_uuid(),
  batch_name text not null check (nullif(trim(batch_name),'') is not null),
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','submitted','approved','returned','finance_accepted','closed','cancelled')),
  prepared_by uuid references public.profiles(id),
  submitted_by uuid references public.profiles(id),
  submitted_at timestamptz,
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  returned_by uuid references public.profiles(id),
  returned_at timestamptz,
  return_reason text,
  finance_accepted_by uuid references public.profiles(id),
  finance_accepted_at timestamptz,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint compensation_review_batches_period_check check (period_end >= period_start)
);

create table if not exists public.compensation_review_batch_items (
  id uuid primary key default gen_random_uuid(),
  review_batch_id uuid not null references public.compensation_review_batches(id) on delete cascade,
  comp_earning_id uuid not null references public.comp_earnings(id),
  employee_id uuid not null references public.employees(id),
  proposed_amount numeric not null check (proposed_amount >= 0),
  included boolean not null default true,
  review_note text,
  item_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (review_batch_id, comp_earning_id)
);

create index if not exists compensation_review_batches_status_idx on public.compensation_review_batches(status, period_end desc);
create index if not exists compensation_review_batch_items_batch_idx on public.compensation_review_batch_items(review_batch_id, employee_id);
create index if not exists compensation_review_batch_items_earning_idx on public.compensation_review_batch_items(comp_earning_id);

alter table public.compensation_review_batches enable row level security;
alter table public.compensation_review_batch_items enable row level security;

revoke all on public.compensation_review_batches from anon, authenticated;
revoke all on public.compensation_review_batch_items from anon, authenticated;

create or replace function public.prepare_compensation_review_batch(
  requested_batch_name text,
  requested_period_start date,
  requested_period_end date
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
  if requested_period_start is null or requested_period_end is null or requested_period_end < requested_period_start then
    raise exception 'A valid review period is required.' using errcode='22023';
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
    e.eligible_amount,
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
    and e.earned_date between requested_period_start and requested_period_end
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
  values(actor,'compensation_review_batch_prepared','Monthly compensation review batch prepared by system administrator.',jsonb_build_object(
    'review_batch_id',new_batch_id,
    'batch_name',trim(requested_batch_name),
    'period_start',requested_period_start,
    'period_end',requested_period_end,
    'item_count',item_count,
    'employee_count',employee_count,
    'proposed_total',total_amount
  ));

  return jsonb_build_object('review_batch_id',new_batch_id,'status','draft','item_count',item_count,'employee_count',employee_count,'proposed_total',total_amount);
end;
$function$;

revoke all on function public.prepare_compensation_review_batch(text,date,date) from public, anon;
grant execute on function public.prepare_compensation_review_batch(text,date,date) to authenticated;

create or replace function public.get_compensation_review_batches()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare payload jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_app_role('system_administrator') or private.has_permission('earnings.approve') or private.has_permission('payments.view')) then
    raise exception 'Compensation review access required.' using errcode='42501';
  end if;

  select jsonb_build_object(
    'batches',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',b.id,'batch_name',b.batch_name,'period_start',b.period_start,'period_end',b.period_end,'status',b.status,
        'prepared_by',b.prepared_by,'submitted_by',b.submitted_by,'submitted_at',b.submitted_at,
        'approved_by',b.approved_by,'approved_at',b.approved_at,'returned_by',b.returned_by,'returned_at',b.returned_at,
        'return_reason',b.return_reason,'finance_accepted_by',b.finance_accepted_by,'finance_accepted_at',b.finance_accepted_at,
        'snapshot',b.snapshot,'created_at',b.created_at,
        'item_count',(select count(*) from public.compensation_review_batch_items i where i.review_batch_id=b.id and i.included=true),
        'employee_count',(select count(distinct i.employee_id) from public.compensation_review_batch_items i where i.review_batch_id=b.id and i.included=true),
        'proposed_total',(select coalesce(sum(i.proposed_amount),0) from public.compensation_review_batch_items i where i.review_batch_id=b.id and i.included=true)
      ) order by b.created_at desc)
      from public.compensation_review_batches b
    ),'[]'::jsonb),
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'review_batch_id',i.review_batch_id,'comp_earning_id',i.comp_earning_id,'employee_id',i.employee_id,
        'employee_name',e.full_name,'proposed_amount',i.proposed_amount,'included',i.included,'review_note',i.review_note,'item_snapshot',i.item_snapshot
      ) order by e.full_name,i.created_at)
      from public.compensation_review_batch_items i
      join public.employees e on e.id=i.employee_id
    ),'[]'::jsonb)
  ) into payload;
  return payload;
end;
$function$;

revoke all on function public.get_compensation_review_batches() from public, anon;
grant execute on function public.get_compensation_review_batches() to authenticated;