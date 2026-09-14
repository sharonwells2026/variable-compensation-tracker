create or replace function public.validate_compensation_plan_version_readiness(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_status text;
  v_start date;
  v_component_count integer := 0;
  v_assignment_count integer := 0;
  v_blockers jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  c record;
  q record;
  e jsonb;
  latest_preview record;
begin
  if not (private.has_permission('plans.view') or private.has_permission('plans.edit') or private.has_permission('plans.approve') or private.has_permission('plans.activate')) then
    raise exception 'Plan readiness is not permitted.' using errcode = '42501';
  end if;
  select pv.status::text, pv.effective_start_date into v_status, v_start from public.comp_plan_versions pv where pv.id = selected_plan_version_id;
  if v_status is null then raise exception 'Plan version not found.' using errcode = '22023'; end if;
  select count(*) into v_component_count from public.comp_plan_components c where c.plan_version_id = selected_plan_version_id and c.is_active = true;
  if v_component_count = 0 then v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','no_components','section','components','message','Add at least one active compensation component.')); end if;
  select count(*) into v_assignment_count from public.comp_plan_draft_assignments da where da.plan_version_id = selected_plan_version_id;
  if v_status = 'draft' and v_assignment_count = 0 then v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','no_applicability','section','applicability','message','Choose at least one employee this plan will apply to.')); end if;
  for c in select id,name,component_code,rule_configuration,additional_eligibility_waiting_days from public.comp_plan_components where plan_version_id=selected_plan_version_id and is_active=true order by calculation_order,name loop
    select rs.id,rs.updated_at,rs.is_active into q from public.comp_rule_sets rs where rs.plan_component_id=c.id and rs.purpose='qualification' order by rs.version desc,rs.updated_at desc limit 1;
    if q.id is null then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','missing_earned_rule','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs an Earned qualification rule.',c.name)));
    else
      select pr.supported,pr.rule_updated_at,pr.previewed_at into latest_preview from public.comp_rule_set_preview_runs pr where pr.rule_set_id=q.id order by pr.previewed_at desc limit 1;
      if latest_preview.previewed_at is null or latest_preview.supported is distinct from true or latest_preview.rule_updated_at is distinct from q.updated_at then v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','earned_rule_needs_preview','section','earned','component_id',c.id,'component_name',c.name,'rule_set_id',q.id,'message',format('Preview the current Earned rule for %s before approval.',c.name))); end if;
    end if;
    e := coalesce(c.rule_configuration->'eligibility','{}'::jsonb);
    if nullif(e->>'mode','') is null then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','missing_eligibility','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s needs an Eligible condition.',c.name)));
    elsif e->>'mode'='waiting_period' and coalesce((e->>'waiting_days')::integer,-1)<0 then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','invalid_waiting_period','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s has an invalid eligibility waiting period.',c.name)));
    elsif e->>'mode'='rule' then
      if nullif(e->>'rule_set_id','') is null then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','missing_eligibility_rule','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s needs an eligibility rule.',c.name)));
      else
        select rs.id,rs.updated_at,rs.is_active into q from public.comp_rule_sets rs where rs.id=(e->>'rule_set_id')::uuid and rs.plan_component_id=c.id and rs.purpose='eligibility' limit 1;
        if q.id is null then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','invalid_eligibility_rule','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s references an eligibility rule that is missing or belongs elsewhere.',c.name)));
        else
          select pr.supported,pr.rule_updated_at,pr.previewed_at into latest_preview from public.comp_rule_set_preview_runs pr where pr.rule_set_id=q.id order by pr.previewed_at desc limit 1;
          if latest_preview.previewed_at is null or latest_preview.supported is distinct from true or latest_preview.rule_updated_at is distinct from q.updated_at then v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','eligibility_rule_needs_preview','section','eligible','component_id',c.id,'component_name',c.name,'rule_set_id',q.id,'message',format('Preview the current Eligible rule for %s before approval.',c.name))); end if;
        end if;
      end if;
    end if;
  end loop;
  if v_start is null then v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code','missing_effective_start','section','effective_period','message','Set an effective start date.')); end if;
  return jsonb_build_object('plan_version_id',selected_plan_version_id,'status',v_status,'ready',jsonb_array_length(v_blockers)=0,'component_count',v_component_count,'draft_assignment_count',v_assignment_count,'blocker_count',jsonb_array_length(v_blockers),'warning_count',jsonb_array_length(v_warnings),'blockers',v_blockers,'warnings',v_warnings,'checked_at',pg_catalog.now());
end;
$function$;
revoke all on function public.validate_compensation_plan_version_readiness(uuid) from public, anon;
grant execute on function public.validate_compensation_plan_version_readiness(uuid) to authenticated;

create or replace function public.approve_compensation_plan_version(selected_plan_version_id uuid, approval_notes text default null::text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare readiness jsonb; component_count integer;
begin
  if not private.has_permission('plans.approve') then raise exception 'Plan approval is not permitted.' using errcode='42501'; end if;
  if not exists(select 1 from public.comp_plan_versions where id=selected_plan_version_id and status='draft') then raise exception 'Only draft versions can be approved.' using errcode='22023'; end if;
  readiness := public.validate_compensation_plan_version_readiness(selected_plan_version_id);
  if coalesce((readiness->>'ready')::boolean,false) is not true then raise exception 'Plan version is not ready for approval: %',readiness->'blockers' using errcode='23514'; end if;
  component_count := coalesce((readiness->>'component_count')::integer,0);
  update public.comp_plan_versions set approved_by=auth.uid(),approved_at=pg_catalog.now(),notes=case when nullif(trim(coalesce(approval_notes,'')),'') is null then notes when notes is null then trim(approval_notes) else notes||E'\nApproval: '||trim(approval_notes) end,updated_at=pg_catalog.now() where id=selected_plan_version_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state) values(auth.uid(),'comp_plan_version_approved','A readiness-validated draft compensation plan version was approved for activation.',jsonb_build_object('plan_version_id',selected_plan_version_id,'component_count',component_count,'readiness',readiness));
  return jsonb_build_object('status','approved','plan_version_id',selected_plan_version_id,'component_count',component_count,'readiness',readiness);
end;
$function$;
revoke all on function public.approve_compensation_plan_version(uuid,text) from public, anon;
grant execute on function public.approve_compensation_plan_version(uuid,text) to authenticated;

create or replace function public.activate_compensation_plan_version(selected_plan_version_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare selected_plan_id uuid; selected_start date; selected_end date; conflicting_active_id uuid; conflicting_active_start date; readiness jsonb; promoted_count integer:=0;
begin
  if not private.has_permission('plans.activate') then raise exception 'Plan activation is not permitted.' using errcode='42501'; end if;
  select pv.comp_plan_id,pv.effective_start_date,pv.effective_end_date into selected_plan_id,selected_start,selected_end from public.comp_plan_versions pv where pv.id=selected_plan_version_id and pv.status='draft' and pv.approved_at is not null for update;
  if selected_plan_id is null then raise exception 'The plan version must be draft and approved before activation.' using errcode='22023'; end if;
  readiness:=public.validate_compensation_plan_version_readiness(selected_plan_version_id);
  if coalesce((readiness->>'ready')::boolean,false) is not true then raise exception 'Plan version is no longer ready for activation: %',readiness->'blockers' using errcode='23514'; end if;
  if selected_start>current_date then raise exception 'A future-dated compensation plan version cannot be activated before its effective start date. Leave it approved in draft status until that date.' using errcode='22023'; end if;
  perform 1 from public.comp_plans where id=selected_plan_id for update;
  select pv.id,pv.effective_start_date into conflicting_active_id,conflicting_active_start from public.comp_plan_versions pv where pv.comp_plan_id=selected_plan_id and pv.status='active' and pv.id<>selected_plan_version_id order by pv.effective_start_date desc limit 1 for update;
  if conflicting_active_id is not null then if conflicting_active_start>=selected_start then raise exception 'The selected version does not start after the currently active version.' using errcode='22023'; end if; update public.comp_plan_versions set status='retired',effective_end_date=selected_start-1,updated_at=pg_catalog.now() where id=conflicting_active_id; end if;
  insert into public.employee_plan_assignments(employee_id,plan_version_id,related_job_role_id,allocation_percent,effective_start_date,effective_end_date,assignment_notes,assigned_by,eligibility_waiting_period_days,earnings_eligibility_date)
  select da.employee_id,da.plan_version_id,null,da.allocation_percent,da.effective_start_date,da.effective_end_date,da.assignment_notes,auth.uid(),da.eligibility_waiting_period_days,da.effective_start_date+da.eligibility_waiting_period_days from public.comp_plan_draft_assignments da where da.plan_version_id=selected_plan_version_id
  on conflict(employee_id,plan_version_id) do update set allocation_percent=excluded.allocation_percent,effective_start_date=excluded.effective_start_date,effective_end_date=excluded.effective_end_date,assignment_notes=excluded.assignment_notes,assigned_by=excluded.assigned_by,eligibility_waiting_period_days=excluded.eligibility_waiting_period_days,earnings_eligibility_date=excluded.earnings_eligibility_date,updated_at=pg_catalog.now();
  get diagnostics promoted_count=row_count;
  update public.comp_plan_versions set status='active',updated_at=pg_catalog.now() where id=selected_plan_version_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state) values(auth.uid(),'comp_plan_version_activated','A readiness-validated compensation plan version was activated and draft applicability was promoted to live assignments.',jsonb_build_object('plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'previous_active_version_id',conflicting_active_id,'promoted_assignment_count',promoted_count,'readiness',readiness));
  return jsonb_build_object('status','active','plan_id',selected_plan_id,'plan_version_id',selected_plan_version_id,'effective_start_date',selected_start,'retired_prior_version_id',conflicting_active_id,'promoted_assignment_count',promoted_count,'readiness',readiness);
end;
$function$;
revoke all on function public.activate_compensation_plan_version(uuid) from public, anon;
grant execute on function public.activate_compensation_plan_version(uuid) to authenticated;