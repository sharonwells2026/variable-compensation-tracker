create or replace function public.review_comp_credit_correction(
  target_request_id uuid,
  requested_decision text,
  review_notes text
) returns jsonb
language plpgsql
security invoker
set search_path to 'public','pg_temp'
as $$
declare
  actor uuid := auth.uid();
  r public.comp_credit_correction_requests%rowtype;
  normalized_notes text := nullif(trim(coalesce(review_notes,'')),'');
begin
  if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('earnings.override') then
    raise exception 'You are not permitted to review compensation credit corrections.' using errcode='42501';
  end if;
  if requested_decision not in ('approved_for_correction','rejected','cancelled') then
    raise exception 'Decision must be approved_for_correction, rejected, or cancelled.' using errcode='22023';
  end if;
  if normalized_notes is null or length(normalized_notes) < 4 then
    raise exception 'Review notes are required.' using errcode='22023';
  end if;
  select * into r from public.comp_credit_correction_requests where id=target_request_id for update;
  if not found then raise exception 'Correction request not found.' using errcode='P0002'; end if;
  if r.status <> 'pending_review' then raise exception 'This correction request is no longer pending review.' using errcode='22023'; end if;
  update public.comp_credit_correction_requests
     set status=requested_decision,resolved_by=actor,resolved_at=now(),resolution_notes=normalized_notes,updated_at=now()
   where id=r.id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(actor,'comp_credit_correction_reviewed',normalized_notes,
    jsonb_build_object('correction_request_id',r.id,'status',r.status,'current_employee_id',r.current_employee_id,'requested_employee_id',r.requested_employee_id),
    jsonb_build_object('correction_request_id',r.id,'status',requested_decision,'reviewed_by',actor),
    r.current_employee_id);
  return jsonb_build_object('status',requested_decision,'correction_request_id',r.id);
end;
$$;
revoke all on function public.review_comp_credit_correction(uuid,text,text) from public, anon;
grant execute on function public.review_comp_credit_correction(uuid,text,text) to authenticated;