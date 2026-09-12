create or replace function public.update_compensation_plan_draft_version(
  selected_plan_version_id uuid,
  selected_effective_start_date date,
  selected_effective_end_date date default null,
  selected_currency_code text default 'USD',
  selected_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_status text;
  v_plan_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan editing is not permitted.' using errcode='42501'; end if;
  select pv.status::text,pv.comp_plan_id into v_status,v_plan_id from public.comp_plan_versions pv where pv.id=selected_plan_version_id for update;
  if v_status is null then raise exception 'Plan version not found.' using errcode='22023'; end if;
  if v_status <> 'draft' then raise exception 'Only draft plan versions can be edited.' using errcode='22023'; end if;
  if selected_effective_start_date is null then raise exception 'Effective start date is required.' using errcode='22023'; end if;
  if selected_effective_end_date is not null and selected_effective_end_date < selected_effective_start_date then raise exception 'Effective end date cannot be before start date.' using errcode='22023'; end if;
  update public.comp_plan_versions set effective_start_date=selected_effective_start_date,effective_end_date=selected_effective_end_date,currency_code=upper(trim(coalesce(selected_currency_code,'USD'))),notes=nullif(trim(coalesce(selected_notes,'')),''),updated_at=pg_catalog.now() where id=selected_plan_version_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state) values((select auth.uid()),'comp_plan_draft_version_updated','Draft compensation plan dates/details updated.',jsonb_build_object('plan_id',v_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_effective_start_date,'effective_end_date',selected_effective_end_date));
  return jsonb_build_object('status','updated','plan_version_id',selected_plan_version_id,'effective_start_date',selected_effective_start_date,'effective_end_date',selected_effective_end_date);
end;
$$;
revoke all on function public.update_compensation_plan_draft_version(uuid,date,date,text,text) from public,anon;
grant execute on function public.update_compensation_plan_draft_version(uuid,date,date,text,text) to authenticated;
