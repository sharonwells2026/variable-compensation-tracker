create or replace function public.validate_comp_credit_correction_target(target_candidate_key text, target_employee_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  c public.comp_deal_earning_candidates_v2%rowtype;
  source_component public.comp_plan_components%rowtype;
  source_version public.comp_plan_versions%rowtype;
  target_assignment public.employee_plan_assignments%rowtype;
  target_component public.comp_plan_components%rowtype;
  target_version public.comp_plan_versions%rowtype;
  target_name text;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('earnings.edit') or private.has_permission('earnings.override')) then raise exception 'Permission denied.' using errcode='42501'; end if;
  select * into c from public.comp_deal_earning_candidates_v2 where candidate_key=target_candidate_key;
  if not found then raise exception 'Compensation candidate not found.' using errcode='P0002'; end if;
  select * into source_component from public.comp_plan_components where id=c.plan_component_id;
  select * into source_version from public.comp_plan_versions where id=source_component.plan_version_id;
  select full_name into target_name from public.employees where id=target_employee_id and is_active=true;
  if target_name is null then return jsonb_build_object('valid',false,'status','inactive_employee','message','The requested employee is not active.'); end if;
  select epa.* into target_assignment
  from public.employee_plan_assignments epa join public.comp_plan_versions pv on pv.id=epa.plan_version_id
  where epa.employee_id=target_employee_id
    and c.earned_date >= epa.effective_start_date
    and (epa.effective_end_date is null or c.earned_date <= epa.effective_end_date)
    and c.earned_date >= epa.earnings_eligibility_date
    and pv.comp_plan_id=source_version.comp_plan_id
  order by epa.effective_start_date desc limit 1;
  if not found then
    return jsonb_build_object('valid',false,'status','plan_resolution_required','message',target_name||' does not have the applicable compensation plan assigned for the earning date.','employee_name',target_name,'earned_date',c.earned_date,'source_component_code',source_component.component_code);
  end if;
  select * into target_version from public.comp_plan_versions where id=target_assignment.plan_version_id;
  select * into target_component from public.comp_plan_components where plan_version_id=target_assignment.plan_version_id and component_code=source_component.component_code and is_active=true limit 1;
  if not found then
    return jsonb_build_object('valid',false,'status','component_resolution_required','message',target_name||' has a plan assignment for the earning date, but that plan version does not contain the applicable compensation component.','employee_name',target_name,'earned_date',c.earned_date,'source_component_code',source_component.component_code,'target_plan_version_id',target_assignment.plan_version_id);
  end if;
  if target_version.status::text not in ('active','approved') then
    return jsonb_build_object('valid',false,'status','plan_version_not_active','message','The matching target plan version is not active or approved.','employee_name',target_name,'target_plan_version_id',target_version.id,'target_plan_version_status',target_version.status);
  end if;
  return jsonb_build_object('valid',true,'status','compatible','message','Target employee has a compatible plan and component for the earning date.','employee_name',target_name,'earned_date',c.earned_date,'target_plan_assignment_id',target_assignment.id,'target_plan_version_id',target_version.id,'target_plan_component_id',target_component.id,'component_code',target_component.component_code);
end;
$$;
revoke all on function public.validate_comp_credit_correction_target(text,uuid) from public, anon;
grant execute on function public.validate_comp_credit_correction_target(text,uuid) to authenticated;