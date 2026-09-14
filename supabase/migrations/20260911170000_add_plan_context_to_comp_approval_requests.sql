create or replace function public.get_my_comp_earning_approval_requests(include_completed boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare actor uuid:=auth.uid(); is_admin boolean:=false; result jsonb;
begin
 if actor is null then raise exception 'Authentication is required.' using errcode='42501'; end if;
 if not private.has_permission('earnings.approve') then raise exception 'Approval access is not permitted.' using errcode='42501'; end if;
 is_admin:=private.has_app_role('system_administrator');
 select coalesce(jsonb_agg(jsonb_build_object(
   'approval_request_id',r.id,'earning_id',e.id,'employee_id',e.employee_id,'employee_name',emp.full_name,'employee_email',emp.email,
   'plan_id',cp.id,'plan_name',cp.name,'plan_code',cp.plan_code,'plan_version_id',pv.id,'plan_version_number',pv.version_number,
   'earning_name',e.earning_name,'earning_description',e.earning_description,'earned_date',e.earned_date,'earned_amount',e.earned_amount,'eligible_amount',e.eligible_amount,'approved_amount',e.approved_amount,
   'approval_level',r.approval_level,'approval_order',r.approval_order,'status',r.status,'requested_at',r.requested_at,'completed_at',r.completed_at,'notes',r.notes,
   'requested_from',r.requested_from,'backup_requested_from',r.backup_requested_from,
   'approver_employee_id',r.chain_snapshot->>'approver_employee_id','approver_name',approver.full_name,
   'assignee_activation_required',coalesce((r.chain_snapshot->>'assignee_activation_required')::boolean,false) or r.requested_from is null,
   'source_snapshot',e.source_snapshot,'payment_status',e.payment_status,'employee_verification_status',e.employee_verification_status
 ) order by case when r.status='pending'::public.approval_status then 0 else 1 end,r.requested_at desc),'[]'::jsonb) into result
 from public.approval_requests r
 join public.comp_earnings e on e.id=r.comp_earning_id
 join public.employees emp on emp.id=e.employee_id
 left join public.comp_plan_components pc on pc.id=e.plan_component_id
 left join public.comp_plan_versions pv on pv.id=pc.plan_version_id
 left join public.comp_plans cp on cp.id=pv.comp_plan_id
 left join public.employees approver on approver.id=nullif(r.chain_snapshot->>'approver_employee_id','')::uuid
 where (include_completed or r.status='pending'::public.approval_status)
   and (is_admin or r.requested_from=actor or r.backup_requested_from=actor);
 return result;
end;
$function$;
