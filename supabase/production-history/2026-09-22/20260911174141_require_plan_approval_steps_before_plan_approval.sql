create or replace function public.approve_compensation_plan_version(selected_plan_version_id uuid, approval_notes text default null::text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  readiness jsonb;
  component_count integer;
  approval_step_count integer;
begin
  if not private.has_permission('plans.approve') then
    raise exception 'Plan approval is not permitted.' using errcode='42501';
  end if;
  if not exists (select 1 from public.comp_plan_versions where id=selected_plan_version_id and status='draft') then
    raise exception 'Only draft versions can be approved.' using errcode='22023';
  end if;

  select count(*) into approval_step_count
  from public.comp_plan_approval_steps
  where plan_version_id=selected_plan_version_id and is_required=true;

  if approval_step_count=0 then
    raise exception 'Configure at least one required approval step on this plan before approving it.' using errcode='23514';
  end if;

  readiness:=public.validate_compensation_plan_version_readiness(selected_plan_version_id);
  if coalesce((readiness->>'ready')::boolean,false) is not true then
    raise exception 'Plan version is not ready for approval: %', readiness->'blockers' using errcode='23514';
  end if;
  component_count:=coalesce((readiness->>'component_count')::integer,0);
  update public.comp_plan_versions
  set approved_by=auth.uid(),approved_at=pg_catalog.now(),
      notes=case when nullif(trim(coalesce(approval_notes,'')),'') is null then notes when notes is null then trim(approval_notes) else notes || E'\nApproval: ' || trim(approval_notes) end,
      updated_at=pg_catalog.now()
  where id=selected_plan_version_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(auth.uid(),'comp_plan_version_approved','A readiness-validated draft compensation plan version was approved for activation.',jsonb_build_object('plan_version_id',selected_plan_version_id,'component_count',component_count,'approval_step_count',approval_step_count,'readiness',readiness));
  return jsonb_build_object('status','approved','plan_version_id',selected_plan_version_id,'component_count',component_count,'approval_step_count',approval_step_count,'readiness',readiness);
end;
$function$;
revoke all on function public.approve_compensation_plan_version(uuid,text) from public;
grant execute on function public.approve_compensation_plan_version(uuid,text) to authenticated;