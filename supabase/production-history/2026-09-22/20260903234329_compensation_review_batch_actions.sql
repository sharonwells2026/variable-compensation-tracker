alter table public.compensation_review_batch_items
  add column if not exists override_reason text;

create or replace function public.update_compensation_review_batch_item(
  target_batch_item_id uuid,
  requested_included boolean default null,
  requested_proposed_amount numeric default null,
  requested_review_note text default null,
  requested_override_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := (select auth.uid());
  item_row public.compensation_review_batch_items%rowtype;
  batch_row public.compensation_review_batches%rowtype;
  original_amount numeric;
  next_amount numeric;
  next_included boolean;
  normalized_reason text := nullif(trim(coalesce(requested_override_reason,'')),'');
  normalized_note text := nullif(trim(coalesce(requested_review_note,'')),'');
begin
  if actor is null or not private.has_app_role('system_administrator') then
    raise exception 'System administrator access required.' using errcode='42501';
  end if;

  select * into item_row from public.compensation_review_batch_items where id=target_batch_item_id for update;
  if not found then raise exception 'Review batch item not found.' using errcode='P0002'; end if;
  select * into batch_row from public.compensation_review_batches where id=item_row.review_batch_id for update;
  if not found then raise exception 'Review batch not found.' using errcode='P0002'; end if;
  if batch_row.status not in ('draft','returned') then
    raise exception 'Only draft or returned review batches can be edited.' using errcode='22023';
  end if;

  original_amount := coalesce((item_row.item_snapshot->>'eligible_amount')::numeric,item_row.proposed_amount);
  next_amount := coalesce(requested_proposed_amount,item_row.proposed_amount);
  next_included := coalesce(requested_included,item_row.included);

  if next_amount < 0 then raise exception 'Proposed amount cannot be negative.' using errcode='22023'; end if;
  if next_amount <> original_amount and normalized_reason is null then
    raise exception 'A reason is required when overriding the calculated amount.' using errcode='22023';
  end if;

  update public.compensation_review_batch_items
  set proposed_amount=next_amount,
      included=next_included,
      review_note=normalized_note,
      override_reason=case when next_amount<>original_amount then normalized_reason else null end,
      updated_at=now()
  where id=target_batch_item_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(
    actor,
    'compensation_review_batch_item_updated',
    coalesce(normalized_reason,normalized_note,'Review batch item updated.'),
    jsonb_build_object('batch_item_id',item_row.id,'review_batch_id',item_row.review_batch_id,'included',item_row.included,'proposed_amount',item_row.proposed_amount),
    jsonb_build_object('batch_item_id',item_row.id,'review_batch_id',item_row.review_batch_id,'included',next_included,'proposed_amount',next_amount,'override_reason',normalized_reason),
    item_row.employee_id
  );

  return jsonb_build_object('status','updated','batch_item_id',target_batch_item_id,'included',next_included,'proposed_amount',next_amount,'override_reason',normalized_reason);
end;
$function$;

create or replace function public.submit_compensation_review_batch(target_review_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := (select auth.uid());
  batch_row public.compensation_review_batches%rowtype;
  frozen_snapshot jsonb;
  included_count integer;
  employee_count integer;
  total_amount numeric;
begin
  if actor is null or not private.has_app_role('system_administrator') then
    raise exception 'System administrator access required.' using errcode='42501';
  end if;

  select * into batch_row from public.compensation_review_batches where id=target_review_batch_id for update;
  if not found then raise exception 'Review batch not found.' using errcode='P0002'; end if;
  if batch_row.status not in ('draft','returned') then
    raise exception 'Only a draft or returned review batch can be submitted.' using errcode='22023';
  end if;

  select count(*),count(distinct employee_id),coalesce(sum(proposed_amount),0)
  into included_count,employee_count,total_amount
  from public.compensation_review_batch_items
  where review_batch_id=target_review_batch_id and included=true;

  if included_count=0 then raise exception 'At least one earning must be included before submission.' using errcode='22023'; end if;

  select jsonb_build_object(
    'review_batch_id',batch_row.id,
    'batch_name',batch_row.batch_name,
    'submitted_at',now(),
    'submission_timing','any_time',
    'item_count',included_count,
    'employee_count',employee_count,
    'proposed_total',total_amount,
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'batch_item_id',i.id,
      'comp_earning_id',i.comp_earning_id,
      'employee_id',i.employee_id,
      'proposed_amount',i.proposed_amount,
      'review_note',i.review_note,
      'override_reason',i.override_reason,
      'item_snapshot',i.item_snapshot
    ) order by i.employee_id,i.created_at),'[]'::jsonb)
  ) into frozen_snapshot
  from public.compensation_review_batch_items i
  where i.review_batch_id=target_review_batch_id and i.included=true;

  update public.compensation_review_batches
  set status='submitted',submitted_by=actor,submitted_at=now(),snapshot=frozen_snapshot,
      returned_by=null,returned_at=null,return_reason=null,updated_at=now()
  where id=target_review_batch_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(actor,'compensation_review_batch_submitted','Compensation review batch submitted for executive approval.',frozen_snapshot);

  return jsonb_build_object('status','submitted','review_batch_id',target_review_batch_id,'item_count',included_count,'employee_count',employee_count,'proposed_total',total_amount);
end;
$function$;

create or replace function public.act_on_compensation_review_batch(
  target_review_batch_id uuid,
  requested_action text,
  action_comments text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := (select auth.uid());
  batch_row public.compensation_review_batches%rowtype;
  is_admin boolean := false;
  normalized_comments text := nullif(trim(coalesce(action_comments,'')),'');
begin
  if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  is_admin:=private.has_app_role('system_administrator');
  if not is_admin and not private.has_permission('earnings.approve') then
    raise exception 'Executive approval permission required.' using errcode='42501';
  end if;
  if requested_action not in ('approved','returned') then raise exception 'Action must be approved or returned.' using errcode='22023'; end if;
  if requested_action='returned' and normalized_comments is null then raise exception 'A reason is required when returning a submission.' using errcode='22023'; end if;

  select * into batch_row from public.compensation_review_batches where id=target_review_batch_id for update;
  if not found then raise exception 'Review batch not found.' using errcode='P0002'; end if;
  if batch_row.status<>'submitted' then raise exception 'Only a submitted review batch can be approved or returned.' using errcode='22023'; end if;

  if requested_action='approved' then
    update public.compensation_review_batches
    set status='approved',approved_by=actor,approved_at=now(),updated_at=now()
    where id=target_review_batch_id;
  else
    update public.compensation_review_batches
    set status='returned',returned_by=actor,returned_at=now(),return_reason=normalized_comments,updated_at=now()
    where id=target_review_batch_id;
  end if;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state)
  values(actor,
    case when requested_action='approved' then 'compensation_review_batch_approved' else 'compensation_review_batch_returned' end,
    normalized_comments,
    jsonb_build_object('review_batch_id',target_review_batch_id,'status',batch_row.status),
    jsonb_build_object('review_batch_id',target_review_batch_id,'status',requested_action,'acted_as_system_admin',is_admin)
  );

  return jsonb_build_object('status',requested_action,'review_batch_id',target_review_batch_id,'acted_as_system_admin',is_admin);
end;
$function$;

create or replace function public.accept_compensation_review_batch_for_payment(
  target_review_batch_id uuid,
  action_comments text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  actor uuid := (select auth.uid());
  batch_row public.compensation_review_batches%rowtype;
  is_admin boolean := false;
  normalized_comments text := nullif(trim(coalesce(action_comments,'')),'');
begin
  if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  is_admin:=private.has_app_role('system_administrator');
  if not is_admin and not private.has_permission('payments.view') then
    raise exception 'Finance permission required.' using errcode='42501';
  end if;

  select * into batch_row from public.compensation_review_batches where id=target_review_batch_id for update;
  if not found then raise exception 'Review batch not found.' using errcode='P0002'; end if;
  if batch_row.status<>'approved' then raise exception 'Only an approved review batch can be accepted for payment.' using errcode='22023'; end if;

  update public.compensation_review_batches
  set status='finance_accepted',finance_accepted_by=actor,finance_accepted_at=now(),updated_at=now()
  where id=target_review_batch_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state)
  values(actor,'compensation_review_batch_finance_accepted',normalized_comments,
    jsonb_build_object('review_batch_id',target_review_batch_id,'status',batch_row.status),
    jsonb_build_object('review_batch_id',target_review_batch_id,'status','finance_accepted','acted_as_system_admin',is_admin)
  );

  return jsonb_build_object('status','finance_accepted','review_batch_id',target_review_batch_id,'acted_as_system_admin',is_admin);
end;
$function$;

revoke all on function public.update_compensation_review_batch_item(uuid,boolean,numeric,text,text) from public,anon;
revoke all on function public.submit_compensation_review_batch(uuid) from public,anon;
revoke all on function public.act_on_compensation_review_batch(uuid,text,text) from public,anon;
revoke all on function public.accept_compensation_review_batch_for_payment(uuid,text) from public,anon;
grant execute on function public.update_compensation_review_batch_item(uuid,boolean,numeric,text,text) to authenticated;
grant execute on function public.submit_compensation_review_batch(uuid) to authenticated;
grant execute on function public.act_on_compensation_review_batch(uuid,text,text) to authenticated;
grant execute on function public.accept_compensation_review_batch_for_payment(uuid,text) to authenticated;