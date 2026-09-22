create or replace function public.validate_compensation_plan_version_readiness_core(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_status text; v_start date; v_component_count integer:=0; v_assignment_count integer:=0;
  v_blockers jsonb:='[]'::jsonb; v_warnings jsonb:='[]'::jsonb;
  c record; q record; e jsonb; latest_preview record; missing_agreement record;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('plans.view') or private.has_permission('plans.edit') or private.has_permission('plans.approve') or private.has_permission('plans.activate')) then raise exception 'Plan readiness is not permitted.' using errcode='42501'; end if;
  select pv.status::text,pv.effective_start_date into v_status,v_start from public.comp_plan_versions pv where pv.id=selected_plan_version_id;
  if v_status is null then raise exception 'Plan version not found.' using errcode='22023'; end if;
  select count(*) into v_component_count from public.comp_plan_components c where c.plan_version_id=selected_plan_version_id and c.is_active=true;
  if v_component_count=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','no_components','section','earning_types','message','Add at least one active Earning Type.')); end if;
  select count(*) into v_assignment_count from public.comp_plan_draft_assignments da where da.plan_version_id=selected_plan_version_id;
  if v_status='draft' and v_assignment_count=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','no_applicability','section','applicability','message','Choose at least one employee this plan will apply to.')); end if;
  if v_status='draft' then
    for missing_agreement in select da.employee_id,e.full_name from public.comp_plan_draft_assignments da join public.employees e on e.id=da.employee_id where da.plan_version_id=selected_plan_version_id and not exists (select 1 from public.comp_plan_agreements a where a.plan_version_id=selected_plan_version_id and (a.applies_to_everyone=true or a.employee_id=da.employee_id)) order by e.full_name loop
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_agreement','section','agreements','employee_id',missing_agreement.employee_id,'employee_name',missing_agreement.full_name,'message',format('%s needs a signed compensation agreement for this plan.',missing_agreement.full_name)));
    end loop;
  end if;
  for c in select id,name,component_code,calculation_type,measurement_source,measurement_period,maximum_payout,rule_configuration,additional_eligibility_waiting_days from public.comp_plan_components where plan_version_id=selected_plan_version_id and is_active=true order by calculation_order,name loop
    if nullif(trim(coalesce(c.calculation_type,'')),'') is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_calculation_type','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a payout method.',c.name))); end if;
    if nullif(trim(coalesce(c.measurement_source,'')),'') is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_measurement_source','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a payment basis.',c.name))); end if;
    if nullif(trim(coalesce(c.measurement_period,'')),'') is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_measurement_period','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a calculation frequency.',c.name))); end if;
    if c.calculation_type in ('percentage','tiered_percentage') then
      if c.calculation_type='percentage' and (c.rule_configuration->>'rate') is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_rate','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a percentage rate.',c.name)));
      elsif c.calculation_type='percentage' and coalesce((c.rule_configuration->>'rate')::numeric,-1)<0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','invalid_rate','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s has an invalid percentage rate.',c.name)));
      elsif c.calculation_type='tiered_percentage' and jsonb_array_length(coalesce(c.rule_configuration->'tiers','[]'::jsonb))=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_tiers','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs at least one payout tier.',c.name))); end if;
    elsif c.calculation_type in ('fixed_amount','fixed_amount_per_unit','milestone_bonus','threshold_bonus') then
      if (c.rule_configuration->>'amount') is null and c.calculation_type in ('fixed_amount','fixed_amount_per_unit','milestone_bonus') then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_amount','section','earning_types','component_id',c.id,'component_name',c.name,'message',format('%s needs a payout amount.',c.name))); end if;
    end if;
    q:=null; select rs.id,rs.updated_at,rs.is_active into q from public.comp_rule_sets rs where rs.plan_component_id=c.id and rs.purpose='qualification' order by rs.version desc,rs.updated_at desc limit 1;
    if q.id is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_earned_rule','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs Earned conditions.',c.name)));
    else latest_preview:=null; select pr.supported,pr.rule_updated_at,pr.previewed_at into latest_preview from public.comp_rule_set_preview_runs pr where pr.rule_set_id=q.id order by pr.previewed_at desc limit 1;
      if latest_preview.previewed_at is null or latest_preview.supported is distinct from true or latest_preview.rule_updated_at is distinct from q.updated_at then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','earned_rule_needs_preview','section','earned','component_id',c.id,'component_name',c.name,'rule_set_id',q.id,'message',format('Check the current Earned conditions for %s against real HubSpot data.',c.name))); end if;
    end if;
    e:=coalesce(c.rule_configuration->'eligibility','{}'::jsonb);
    if nullif(e->>'mode','') is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_eligibility','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s needs a Can be paid when choice.',c.name)));
    elsif e->>'mode'='waiting_period' and coalesce((e->>'waiting_days')::integer,-1)<0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','invalid_waiting_period','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s has an invalid waiting period.',c.name)));
    elsif e->>'mode'='rule' then
      if nullif(e->>'rule_set_id','') is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_eligibility_rule','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s needs conditions that determine when it can be paid.',c.name)));
      else q:=null; select rs.id,rs.updated_at,rs.is_active into q from public.comp_rule_sets rs where rs.id=(e->>'rule_set_id')::uuid and rs.plan_component_id=c.id and rs.purpose='eligibility' limit 1;
        if q.id is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','invalid_eligibility_rule','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s references payment conditions that are missing or belong elsewhere.',c.name)));
        else latest_preview:=null; select pr.supported,pr.rule_updated_at,pr.previewed_at into latest_preview from public.comp_rule_set_preview_runs pr where pr.rule_set_id=q.id order by pr.previewed_at desc limit 1;
          if latest_preview.previewed_at is null or latest_preview.supported is distinct from true or latest_preview.rule_updated_at is distinct from q.updated_at then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','eligibility_rule_needs_preview','section','eligible','component_id',c.id,'component_name',c.name,'rule_set_id',q.id,'message',format('Check the current payment conditions for %s against real HubSpot data.',c.name))); end if;
        end if;
      end if;
    end if;
  end loop;
  if v_start is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_effective_start','section','effective_period','message','Set an effective start date.')); end if;
  return jsonb_build_object('plan_version_id',selected_plan_version_id,'status',v_status,'ready',jsonb_array_length(v_blockers)=0,'component_count',v_component_count,'draft_assignment_count',v_assignment_count,'blocker_count',jsonb_array_length(v_blockers),'warning_count',jsonb_array_length(v_warnings),'blockers',v_blockers,'warnings',v_warnings,'checked_at',pg_catalog.now());
end;
$function$;
revoke all on function public.validate_compensation_plan_version_readiness_core(uuid) from public;
grant execute on function public.validate_compensation_plan_version_readiness_core(uuid) to authenticated;