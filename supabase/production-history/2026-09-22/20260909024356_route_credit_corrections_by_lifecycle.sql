alter table public.comp_credit_correction_requests add column if not exists correction_path text not null default 'direct';
alter table public.comp_credit_correction_requests drop constraint if exists comp_credit_correction_requests_correction_path_check;
alter table public.comp_credit_correction_requests add constraint comp_credit_correction_requests_correction_path_check check (correction_path in ('direct','reopen_required','paid_adjustment'));

create or replace function public.request_comp_credit_correction(target_candidate_key text, target_employee_id uuid, target_credit_percentage numeric, correction_reason text)
returns jsonb
language plpgsql
set search_path to 'public','pg_temp'
as $function$
declare
  actor uuid := auth.uid();
  c public.comp_deal_earning_candidates_v2%rowtype;
  e public.comp_earnings%rowtype;
  request_id uuid;
  normalized_reason text := nullif(trim(coalesce(correction_reason,'')),'');
  path text := 'direct';
begin
  if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('earnings.edit') or private.has_permission('earnings.override')) then
    raise exception 'You are not permitted to request compensation credit corrections.' using errcode='42501';
  end if;
  if normalized_reason is null or length(normalized_reason) < 8 then
    raise exception 'A correction reason of at least 8 characters is required.' using errcode='22023';
  end if;
  if target_credit_percentage is null or target_credit_percentage <= 0 or target_credit_percentage > 100 then
    raise exception 'Credit percentage must be greater than 0 and no more than 100.' using errcode='22023';
  end if;
  select * into c from public.comp_deal_earning_candidates_v2 where candidate_key = target_candidate_key;
  if not found then raise exception 'Compensation candidate not found.' using errcode='P0002'; end if;
  if not exists(select 1 from public.employees x where x.id=target_employee_id and x.is_active=true) then
    raise exception 'The requested employee is not active.' using errcode='22023';
  end if;
  select * into e from public.comp_earnings ce
   where ce.is_current is true and ce.employee_id=c.employee_id and ce.source_external_id=c.hubspot_deal_id and ce.plan_component_id=c.plan_component_id
   order by ce.created_at desc limit 1;
  if found then
    if e.payment_status in ('paid'::public.payment_status,'partially_paid'::public.payment_status) or coalesce(e.paid_amount,0) > 0 then
      path := 'paid_adjustment';
    elsif e.employee_verification_status = 'verified'::public.verification_status
       or e.manager_approval_status in ('approved'::public.approval_status,'returned'::public.approval_status,'rejected'::public.approval_status)
       or e.executive_approval_status = 'approved'::public.approval_status
       or coalesce(e.approved_amount,0) > 0
       or e.finance_accepted_at is not null then
      path := 'reopen_required';
    end if;
  end if;
  if exists(select 1 from public.comp_credit_correction_requests r where r.candidate_key=target_candidate_key and r.status in ('pending_review','approved_for_correction')) then
    raise exception 'An open credit correction already exists for this transaction.' using errcode='22023';
  end if;
  insert into public.comp_credit_correction_requests(candidate_key,hubspot_deal_id,plan_component_id,earning_id,current_employee_id,requested_employee_id,current_credit_percentage,requested_credit_percentage,reason,requested_by,correction_path)
  values(c.candidate_key,c.hubspot_deal_id,c.plan_component_id,case when found then e.id else null end,c.employee_id,target_employee_id,coalesce(c.credit_percentage,100),target_credit_percentage,normalized_reason,actor,path)
  returning id into request_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(actor,'comp_credit_correction_requested',normalized_reason,
    jsonb_build_object('candidate_key',c.candidate_key,'employee_id',c.employee_id,'credit_percentage',c.credit_percentage,'earning_id',case when found then e.id else null end,'payment_status',case when found then e.payment_status else null end),
    jsonb_build_object('correction_request_id',request_id,'requested_employee_id',target_employee_id,'requested_credit_percentage',target_credit_percentage,'status','pending_review','correction_path',path),
    c.employee_id);
  return jsonb_build_object('status','pending_review','correction_request_id',request_id,'candidate_key',c.candidate_key,'correction_path',path);
end;
$function$;

create or replace function public.get_comp_credit_correction_queue()
returns jsonb
language plpgsql
set search_path to 'public','pg_temp'
as $function$
declare result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('earnings.edit') or private.has_permission('earnings.override')) then raise exception 'Permission denied.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'candidate_key',r.candidate_key,'hubspot_deal_id',r.hubspot_deal_id,'earning_id',r.earning_id,
    'current_employee_id',r.current_employee_id,'current_employee_name',ce.full_name,
    'requested_employee_id',r.requested_employee_id,'requested_employee_name',re.full_name,
    'current_credit_percentage',r.current_credit_percentage,'requested_credit_percentage',r.requested_credit_percentage,
    'reason',r.reason,'status',r.status,'correction_path',r.correction_path,'requested_at',r.requested_at,
    'resolution_notes',r.resolution_notes,'resolved_at',r.resolved_at,
    'earning_payment_status',e.payment_status,'earning_paid_amount',e.paid_amount,'earning_approved_amount',e.approved_amount,
    'employee_verification_status',e.employee_verification_status,'manager_approval_status',e.manager_approval_status,
    'executive_approval_status',e.executive_approval_status
  ) order by r.requested_at desc),'[]'::jsonb)
  into result
  from public.comp_credit_correction_requests r
  left join public.employees ce on ce.id=r.current_employee_id
  left join public.employees re on re.id=r.requested_employee_id
  left join public.comp_earnings e on e.id=r.earning_id;
  return result;
end;
$function$;

revoke all on function public.get_comp_credit_correction_queue() from public;
grant execute on function public.get_comp_credit_correction_queue() to authenticated;