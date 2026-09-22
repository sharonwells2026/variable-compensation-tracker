create or replace function public.process_comp_credit_correction(target_request_id uuid, processing_reason text)
returns jsonb
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
 actor uuid:=auth.uid(); r public.comp_credit_correction_requests%rowtype; e public.comp_earnings%rowtype; normalized_reason text:=nullif(trim(coalesce(processing_reason,'')),''); adj_id uuid; compatibility jsonb;
begin
 if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
 if not private.has_permission('earnings.override') then raise exception 'Permission denied.' using errcode='42501'; end if;
 if normalized_reason is null or length(normalized_reason)<8 then raise exception 'A processing reason of at least 8 characters is required.' using errcode='22023'; end if;
 select * into r from public.comp_credit_correction_requests where id=target_request_id for update;
 if not found then raise exception 'Correction request not found.' using errcode='P0002'; end if;
 if r.status<>'approved_for_correction' then raise exception 'Correction must be approved before processing.' using errcode='22023'; end if;
 compatibility:=public.validate_comp_credit_correction_target(r.candidate_key,r.requested_employee_id);
 if not coalesce((compatibility->>'valid')::boolean,false) then
   return jsonb_build_object('status','plan_resolution_required','correction_path',r.correction_path,'correction_request_id',r.id,'validation',compatibility);
 end if;
 if r.earning_id is not null then select * into e from public.comp_earnings where id=r.earning_id for update; end if;
 if r.correction_path='direct' then
   update public.comp_credit_correction_requests set status='ready_to_apply',resolution_notes=concat_ws(E'\n',resolution_notes,normalized_reason),updated_at=now() where id=r.id;
   insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id) values(actor,'comp_credit_correction_ready_to_apply',normalized_reason,jsonb_build_object('request_id',r.id,'status',r.status),jsonb_build_object('request_id',r.id,'status','ready_to_apply','correction_path',r.correction_path,'validation',compatibility),r.current_employee_id);
   return jsonb_build_object('status','ready_to_apply','correction_path',r.correction_path,'correction_request_id',r.id,'validation',compatibility);
 elsif r.correction_path='reopen_required' then
   if r.earning_id is null then raise exception 'No earning is linked to this correction.' using errcode='22023'; end if;
   if e.payment_status in ('paid'::public.payment_status,'partially_paid'::public.payment_status) or coalesce(e.paid_amount,0)>0 then raise exception 'This earning now has payment history. Use the paid adjustment path.' using errcode='22023'; end if;
   update public.approval_requests set status='returned'::public.approval_status,completed_at=now(),notes=concat_ws(E'\n',notes,'Returned for attribution correction: '||normalized_reason) where comp_earning_id=e.id and status='pending'::public.approval_status;
   update public.comp_earnings set employee_verification_status='correction_requested'::public.verification_status,manager_approval_status='returned'::public.approval_status,executive_approval_status='returned'::public.approval_status,payment_status='not_payable'::public.payment_status,finance_accepted_by=null,finance_accepted_at=null,expected_payment_date=null,expected_pay_period_label=null,expected_pay_period_start=null,expected_pay_period_end=null,updated_at=now() where id=e.id;
   insert into public.comp_earning_lifecycle_events(comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,event_type,previous_status,new_status,event_reason,event_source,previous_state,new_state,requires_review,review_status) values(e.id,e.employee_id,e.plan_assignment_id,e.plan_component_id,e.source_external_id,'returned_for_attribution_correction',e.payment_status::text,'correction_requested',normalized_reason,'compensation_tracker',jsonb_build_object('manager_approval_status',e.manager_approval_status,'executive_approval_status',e.executive_approval_status,'payment_status',e.payment_status),jsonb_build_object('manager_approval_status','returned','executive_approval_status','returned','payment_status','not_payable','correction_request_id',r.id,'validation',compatibility),true,'pending');
   update public.comp_credit_correction_requests set status='ready_to_apply',resolution_notes=concat_ws(E'\n',resolution_notes,normalized_reason),updated_at=now() where id=r.id;
   return jsonb_build_object('status','ready_to_apply','correction_path',r.correction_path,'correction_request_id',r.id,'earning_id',e.id,'validation',compatibility);
 elsif r.correction_path='paid_adjustment' then
   if r.earning_id is null then raise exception 'No paid earning is linked to this correction.' using errcode='22023'; end if;
   if not (e.payment_status in ('paid'::public.payment_status,'partially_paid'::public.payment_status) or coalesce(e.paid_amount,0)>0) then raise exception 'This earning no longer has paid history; re-evaluate the correction path.' using errcode='22023'; end if;
   insert into public.earning_adjustments(employee_id,comp_earning_id,comp_period_id,adjustment_type,amount,reason,requested_by,approval_status,effective_date,supporting_details) values(e.employee_id,e.id,null,'correction'::public.adjustment_type,-abs(coalesce(nullif(e.paid_amount,0),e.earned_amount,0)),normalized_reason,actor,'pending'::public.approval_status,current_date,jsonb_build_object('correction_request_id',r.id,'original_paid_amount',e.paid_amount,'requested_employee_id',r.requested_employee_id,'requested_credit_percentage',r.requested_credit_percentage,'validation',compatibility,'purpose','preserve_paid_history_and_reverse_for_replacement')) returning id into adj_id;
   update public.comp_credit_correction_requests set status='adjustment_pending',resolution_notes=concat_ws(E'\n',resolution_notes,normalized_reason),updated_at=now() where id=r.id;
   insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id) values(actor,'paid_comp_credit_correction_adjustment_created',normalized_reason,jsonb_build_object('request_id',r.id,'earning_id',e.id,'paid_amount',e.paid_amount),jsonb_build_object('request_id',r.id,'adjustment_id',adj_id,'status','adjustment_pending','validation',compatibility),e.employee_id);
   return jsonb_build_object('status','adjustment_pending','correction_path',r.correction_path,'correction_request_id',r.id,'adjustment_id',adj_id,'earning_id',e.id,'validation',compatibility);
 end if;
 raise exception 'Unknown correction path.' using errcode='22023';
end;$$;
revoke all on function public.process_comp_credit_correction(uuid,text) from public,anon;
grant execute on function public.process_comp_credit_correction(uuid,text) to authenticated;