create or replace function public.delete_compensation_plan_draft(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  selected_plan_id uuid;
  selected_status public.plan_version_status;
  remaining_versions integer;
  earning_count integer;
  assignment_count integer;
  calculation_count integer;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan editing is not permitted.' using errcode='42501'; end if;

  select pv.comp_plan_id,pv.status into selected_plan_id,selected_status
  from public.comp_plan_versions pv where pv.id=selected_plan_version_id for update;
  if selected_plan_id is null then raise exception 'Plan version does not exist.' using errcode='22023'; end if;
  if selected_status<>'draft' then raise exception 'Only draft plan versions can be deleted. Active or historical versions must be retired.' using errcode='42501'; end if;

  select count(*) into earning_count from public.comp_earnings e join public.comp_plan_components c on c.id=e.plan_component_id where c.plan_version_id=selected_plan_version_id;
  select count(*) into assignment_count from public.employee_plan_assignments a where a.plan_version_id=selected_plan_version_id;
  select count(*) into calculation_count from public.comp_calculations cc where cc.plan_version_id=selected_plan_version_id;
  if earning_count>0 or assignment_count>0 or calculation_count>0 then
    raise exception 'This draft has financial or historical dependencies and cannot be deleted. Retire or preserve it instead.' using errcode='42501';
  end if;

  delete from public.app_user_drafts where plan_version_id=selected_plan_version_id;
  delete from public.comp_plan_versions where id=selected_plan_version_id;
  select count(*) into remaining_versions from public.comp_plan_versions where comp_plan_id=selected_plan_id;
  if remaining_versions=0 then
    delete from private.draft_user_plan_permissions where comp_plan_id=selected_plan_id;
    delete from private.user_plan_permissions where comp_plan_id=selected_plan_id;
    update public.app_access_audit_events set related_plan_id=null where related_plan_id=selected_plan_id;
    delete from public.comp_plans where id=selected_plan_id;
  end if;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state)
  values((select auth.uid()),'comp_plan_draft_deleted','An unused draft compensation plan version was deleted.',jsonb_build_object('plan_version_id',selected_plan_version_id,'plan_id',selected_plan_id),'null'::jsonb);
  return jsonb_build_object('status','deleted','plan_version_id',selected_plan_version_id,'plan_id',selected_plan_id,'plan_deleted',remaining_versions=0);
end;
$function$;
revoke all on function public.delete_compensation_plan_draft(uuid) from public;
grant execute on function public.delete_compensation_plan_draft(uuid) to authenticated;