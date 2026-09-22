alter table public.comp_credit_correction_requests add column if not exists replacement_earning_id uuid references public.comp_earnings(id);

create or replace function public.apply_comp_credit_correction_replacement(target_request_id uuid, application_reason text)
returns jsonb
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
 actor uuid:=auth.uid(); r public.comp_credit_correction_requests%rowtype; e public.comp_earnings%rowtype; p jsonb; period_id uuid; calc_id uuid; replacement_id uuid; next_version int; earned numeric; eligible numeric; exec_required boolean; normalized_reason text:=nullif(trim(coalesce(application_reason,'')),'');
begin
 if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
 if not private.has_permission('earnings.override') then raise exception 'Permission denied.' using errcode='42501'; end if;
 if normalized_reason is null or length(normalized_reason)<8 then raise exception 'An application reason of at least 8 characters is required.' using errcode='22023'; end if;
 select * into r from public.comp_credit_correction_requests where id=target_request_id for update;
 if not found then raise exception 'Correction request not found.' using errcode='P0002'; end if;
 if r.status<>'ready_to_apply' then raise exception 'Correction must be processed to ready_to_apply before replacement.' using errcode='22023'; end if;
 if r.correction_path='paid_adjustment' then raise exception 'Paid corrections require the approved adjustment/reversal path before replacement.' using errcode='22023'; end if;
 if r.replacement_earning_id is not null then raise exception 'This correction already has a replacement earning.' using errcode='22023'; end if;
 if r.earning_id is null then raise exception 'No source earning is linked to this correction.' using errcode='22023'; end if;
 select * into e from public.comp_earnings where id=r.earning_id for update;
 if not found then raise exception 'Source earning not found.' using errcode='P0002'; end if;
 if not e.is_current then raise exception 'Source earning is no longer current.' using errcode='22023'; end if;
 if e.payment_status in ('paid'::public.payment_status,'partially_paid'::public.payment_status) or coalesce(e.paid_amount,0)>0 then raise exception 'Source earning now has payment history. Use the paid adjustment path.' using errcode='22023'; end if;
 p:=public.preview_comp_credit_correction_replacement(r.candidate_key,r.requested_employee_id,r.requested_credit_percentage);
 if not coalesce((p->>'valid')::boolean,false) then return jsonb_build_object('status','replacement_blocked','correction_request_id',r.id,'preview',p); end if;
 period_id:=(p->>'comp_period_id')::uuid; earned:=(p->>'corrected_earned_amount')::numeric;
 select coalesce(max(calculation_version),0)+1 into next_version from public.comp_calculations where employee_id=r.requested_employee_id and comp_period_id=period_id;
 eligible:=case when e.eligibility_status in ('eligible'::public.eligibility_status,'waived'::public.eligibility_status) then earned else 0 end;
 select exists(select 1 from public.employee_approval_chains ac where ac.employee_id=r.requested_employee_id and ac.is_required=true and ac.approval_level='executive_approval' and e.earned_date>=ac.effective_start_date and (ac.effective_end_date is null or e.earned_date<=ac.effective_end_date)) into exec_required;
 insert into public.comp_calculations(employee_id,comp_period_id,calculation_version,calculated_at,calculated_by,total_earned,total_eligible,total_approved,total_paid,notes)
 values(r.requested_employee_id,period_id,next_version,now(),actor,earned,eligible,0,0,'Replacement calculation created by approved attribution correction '||r.id) returning id into calc_id;
 insert into public.comp_earnings(calculation_id,employee_id,plan_assignment_id,plan_component_id,earning_name,earning_description,source_type,source_external_id,source_url,source_snapshot,earned_date,earned_amount,eligibility_status,eligibility_condition_type,eligibility_condition_description,eligibility_due_date,eligible_date,eligible_amount,eligibility_evidence,employee_verification_status,manager_approval_status,executive_approval_required,executive_approval_status,approved_amount,payment_status,paid_amount,supersedes_earning_id,is_current,earning_origin,reconciliation_status,source_match_status,historical_reference,reconciliation_notes)
 values(calc_id,r.requested_employee_id,(p->>'target_plan_assignment_id')::uuid,(p->>'target_plan_component_id')::uuid,(p->>'target_component_name'),e.earning_description,e.source_type,e.source_external_id,e.source_url,e.source_snapshot||jsonb_build_object('candidate_key',r.candidate_key,'credit_percentage',r.requested_credit_percentage,'source_amount',(p->>'source_amount')::numeric,'component_rate',case when p->>'rate' is null then null else (p->>'rate')::numeric end,'correction_lineage',jsonb_build_object('correction_request_id',r.id,'supersedes_earning_id',e.id,'original_employee_id',e.employee_id,'replacement_employee_id',r.requested_employee_id,'applied_by',actor,'applied_at',now(),'reason',normalized_reason)),e.earned_date,earned,e.eligibility_status,e.eligibility_condition_type,e.eligibility_condition_description,e.eligibility_due_date,e.eligible_date,eligible,e.eligibility_evidence||jsonb_build_object('correction_request_id',r.id),'pending_employee'::public.verification_status,'pending'::public.approval_status,exec_required,case when exec_required then 'pending'::public.approval_status else 'not_required'::public.approval_status end,0,'not_payable'::public.payment_status,0,e.id,true,e.earning_origin,'not_reviewed'::public.reconciliation_status,e.source_match_status,e.historical_reference,'Replacement created from approved attribution correction; original history retained.') returning id into replacement_id;
 update public.comp_earnings set is_current=false,updated_at=now() where id=e.id;
 insert into public.comp_earning_lifecycle_events(comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,event_type,previous_status,new_status,event_reason,event_source,previous_state,new_state,requires_review,review_status)
 values(e.id,e.employee_id,e.plan_assignment_id,e.plan_component_id,e.source_external_id,'superseded_by_attribution_correction',e.payment_status::text,'superseded',normalized_reason,'compensation_tracker',jsonb_build_object('is_current',true,'earned_amount',e.earned_amount,'employee_id',e.employee_id),jsonb_build_object('is_current',false,'replacement_earning_id',replacement_id,'correction_request_id',r.id),false,'not_required'),
 (replacement_id,r.requested_employee_id,(p->>'target_plan_assignment_id')::uuid,(p->>'target_plan_component_id')::uuid,e.source_external_id,'created_from_attribution_correction',null,'pending_employee',normalized_reason,'compensation_tracker','{}'::jsonb,jsonb_build_object('supersedes_earning_id',e.id,'correction_request_id',r.id,'earned_amount',earned,'credit_percentage',r.requested_credit_percentage),false,'not_required');
 update public.comp_credit_correction_requests set status='applied',replacement_earning_id=replacement_id,resolved_by=actor,resolved_at=now(),resolution_notes=concat_ws(E'\n',resolution_notes,normalized_reason),updated_at=now() where id=r.id;
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id) values(actor,'comp_credit_correction_replacement_applied',normalized_reason,jsonb_build_object('correction_request_id',r.id,'source_earning_id',e.id,'source_employee_id',e.employee_id,'source_amount',e.earned_amount),jsonb_build_object('replacement_earning_id',replacement_id,'replacement_employee_id',r.requested_employee_id,'replacement_amount',earned,'calculation_id',calc_id,'calculation_version',next_version),r.requested_employee_id);
 return jsonb_build_object('status','applied','correction_request_id',r.id,'source_earning_id',e.id,'replacement_earning_id',replacement_id,'calculation_id',calc_id,'calculation_version',next_version,'preview',p);
end;
$$;
revoke all on function public.apply_comp_credit_correction_replacement(uuid,text) from public,anon;
grant execute on function public.apply_comp_credit_correction_replacement(uuid,text) to authenticated;