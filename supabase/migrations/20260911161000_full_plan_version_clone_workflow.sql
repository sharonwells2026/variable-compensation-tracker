alter table public.comp_plan_versions
  add column if not exists based_on_version_id uuid references public.comp_plan_versions(id);

create or replace function public.create_compensation_plan_version_from_source(
  selected_plan_id uuid,
  source_plan_version_id uuid,
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
  next_version_number integer;
  new_version_id uuid;
  source_status text;
  copied_component_count integer := 0;
  copied_deal_rule_count integer := 0;
  copied_attribution_rule_count integer := 0;
  copied_legacy_credit_rule_count integer := 0;
  copied_rule_set_count integer := 0;
  copied_assignment_count integer := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.create') then raise exception 'Plan version creation is not permitted.' using errcode='42501'; end if;

  perform 1 from public.comp_plans where id=selected_plan_id and is_active=true for update;
  if not found then raise exception 'The selected plan does not exist or is inactive.' using errcode='22023'; end if;

  if exists(select 1 from public.comp_plan_versions where comp_plan_id=selected_plan_id and status='draft') then
    raise exception 'This plan already has a draft version. Open the existing draft instead.' using errcode='23505';
  end if;

  select pv.status::text into source_status from public.comp_plan_versions pv
  where pv.id=source_plan_version_id and pv.comp_plan_id=selected_plan_id;
  if source_status is null then raise exception 'The source version does not belong to this plan.' using errcode='22023'; end if;
  if source_status='draft' then raise exception 'A new draft cannot be based on another draft.' using errcode='22023'; end if;

  if selected_effective_end_date is not null and selected_effective_end_date < selected_effective_start_date then
    raise exception 'Effective end date cannot be before start date.' using errcode='22023';
  end if;

  select coalesce(max(version_number),0)+1 into next_version_number from public.comp_plan_versions where comp_plan_id=selected_plan_id;
  insert into public.comp_plan_versions(comp_plan_id,version_number,status,effective_start_date,effective_end_date,currency_code,notes,based_on_version_id)
  values(selected_plan_id,next_version_number,'draft',selected_effective_start_date,selected_effective_end_date,upper(trim(coalesce(selected_currency_code,'USD'))),nullif(trim(coalesce(selected_notes,'')),''),source_plan_version_id)
  returning id into new_version_id;

  create temporary table clone_component_map(old_id uuid primary key,new_id uuid not null unique) on commit drop;
  insert into clone_component_map select id,gen_random_uuid() from public.comp_plan_components where plan_version_id=source_plan_version_id;

  insert into public.comp_plan_components(id,plan_version_id,name,component_code,description,calculation_type,measurement_source,measurement_period,calculation_order,rule_configuration,maximum_payout,is_active,payout_timing_method,allow_manager_payout_override,measurement_label,additional_eligibility_waiting_days)
  select m.new_id,new_version_id,c.name,c.component_code,c.description,c.calculation_type,c.measurement_source,c.measurement_period,c.calculation_order,c.rule_configuration,c.maximum_payout,c.is_active,c.payout_timing_method,c.allow_manager_payout_override,c.measurement_label,c.additional_eligibility_waiting_days
  from public.comp_plan_components c join clone_component_map m on m.old_id=c.id;
  get diagnostics copied_component_count=row_count;

  insert into public.comp_component_deal_rules(plan_component_id,hubspot_pipeline_id,hubspot_stage_id,hubspot_deal_type,calculation_action,marks_earned,marks_eligible,marks_paid,amount_source,amount_label,priority,is_active,effective_start_date,effective_end_date,rule_notes)
  select m.new_id,r.hubspot_pipeline_id,r.hubspot_stage_id,r.hubspot_deal_type,r.calculation_action,r.marks_earned,r.marks_eligible,r.marks_paid,r.amount_source,r.amount_label,r.priority,r.is_active,r.effective_start_date,r.effective_end_date,r.rule_notes
  from public.comp_component_deal_rules r join clone_component_map m on m.old_id=r.plan_component_id;
  get diagnostics copied_deal_rule_count=row_count;

  insert into public.comp_user_attribution_rules(plan_component_id,attribution_purpose,metric_key,hubspot_user_field_keys,match_logic,credit_percentage,qualifying_pipeline_ids,qualifying_deal_types,priority,allow_stacking,rule_configuration,effective_start_date,effective_end_date,is_active)
  select m.new_id,r.attribution_purpose,r.metric_key,r.hubspot_user_field_keys,r.match_logic,r.credit_percentage,r.qualifying_pipeline_ids,r.qualifying_deal_types,r.priority,r.allow_stacking,r.rule_configuration,r.effective_start_date,r.effective_end_date,r.is_active
  from public.comp_user_attribution_rules r join clone_component_map m on m.old_id=r.plan_component_id;
  get diagnostics copied_attribution_rule_count=row_count;

  insert into public.comp_credit_rules(plan_component_id,credit_method,named_employee_id,qualifying_pipeline_ids,qualifying_deal_types,credit_percentage,priority,allow_stacking,rule_configuration,effective_start_date,effective_end_date)
  select m.new_id,r.credit_method,r.named_employee_id,r.qualifying_pipeline_ids,r.qualifying_deal_types,r.credit_percentage,r.priority,r.allow_stacking,r.rule_configuration,r.effective_start_date,r.effective_end_date
  from public.comp_credit_rules r join clone_component_map m on m.old_id=r.plan_component_id;
  get diagnostics copied_legacy_credit_rule_count=row_count;

  create temporary table clone_rule_set_map(old_id uuid primary key,new_id uuid not null unique) on commit drop;
  insert into clone_rule_set_map
  select rs.id,gen_random_uuid() from public.comp_rule_sets rs join clone_component_map cm on cm.old_id=rs.plan_component_id;

  insert into public.comp_rule_sets(id,plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,outcome_configuration,created_by,updated_by)
  select rsm.new_id,cm.new_id,rs.name,rs.purpose,rs.description,rs.evaluation_scope,rs.version,rs.is_active,rs.stop_on_match,rs.outcome_configuration,auth.uid(),auth.uid()
  from public.comp_rule_sets rs join clone_rule_set_map rsm on rsm.old_id=rs.id join clone_component_map cm on cm.old_id=rs.plan_component_id;
  get diagnostics copied_rule_set_count=row_count;

  create temporary table clone_predicate_map(old_id uuid primary key,new_id uuid not null unique) on commit drop;
  insert into clone_predicate_map
  select p.id,gen_random_uuid() from public.comp_rule_predicates p join clone_rule_set_map rsm on rsm.old_id=p.rule_set_id;

  insert into public.comp_rule_predicates(id,rule_set_id,rule_key,display_name,object_type,association_path,property_name,operator_key,comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes,association_quantifier,aggregate_function,aggregate_window)
  select pm.new_id,rsm.new_id,p.rule_key,p.display_name,p.object_type,p.association_path,p.property_name,p.operator_key,p.comparison_value,p.comparison_value_type,p.case_sensitive,p.include_null_as_match,p.notes,p.association_quantifier,p.aggregate_function,p.aggregate_window
  from public.comp_rule_predicates p join clone_predicate_map pm on pm.old_id=p.id join clone_rule_set_map rsm on rsm.old_id=p.rule_set_id;

  create temporary table clone_node_map(old_id uuid primary key,new_id uuid not null unique) on commit drop;
  insert into clone_node_map
  select n.id,gen_random_uuid() from public.comp_rule_expression_nodes n join clone_rule_set_map rsm on rsm.old_id=n.rule_set_id;

  insert into public.comp_rule_expression_nodes(id,rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
  select nm.new_id,rsm.new_id,null,n.node_type,pm.new_id,n.logical_operator,n.negate,n.sort_order,n.label
  from public.comp_rule_expression_nodes n join clone_node_map nm on nm.old_id=n.id join clone_rule_set_map rsm on rsm.old_id=n.rule_set_id left join clone_predicate_map pm on pm.old_id=n.predicate_id;

  update public.comp_rule_expression_nodes new_node
  set parent_node_id=parent_map.new_id
  from clone_node_map node_map
  join public.comp_rule_expression_nodes old_node on old_node.id=node_map.old_id
  join clone_node_map parent_map on parent_map.old_id=old_node.parent_node_id
  where new_node.id=node_map.new_id;

  insert into public.comp_plan_draft_assignments(plan_version_id,employee_id,allocation_percent,effective_start_date,effective_end_date,eligibility_waiting_period_days,assignment_notes,created_by,updated_by)
  select new_version_id,a.employee_id,a.allocation_percent,selected_effective_start_date,
    case when a.effective_end_date is not null and a.effective_end_date>=selected_effective_start_date then a.effective_end_date else null end,
    greatest(0,a.earnings_eligibility_date-a.effective_start_date),
    coalesce(a.assignment_notes,'Copied from plan version '||source_plan_version_id::text),auth.uid(),auth.uid()
  from public.employee_plan_assignments a
  where a.plan_version_id=source_plan_version_id and (a.effective_end_date is null or a.effective_end_date>=selected_effective_start_date);
  get diagnostics copied_assignment_count=row_count;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(auth.uid(),'comp_plan_version_cloned','A new draft compensation plan version was created from an existing version.',jsonb_build_object('plan_id',selected_plan_id,'plan_version_id',new_version_id,'version_number',next_version_number,'based_on_version_id',source_plan_version_id,'component_count',copied_component_count,'deal_rule_count',copied_deal_rule_count,'attribution_rule_count',copied_attribution_rule_count,'legacy_credit_rule_count',copied_legacy_credit_rule_count,'rule_set_count',copied_rule_set_count,'draft_assignment_count',copied_assignment_count,'agreements_copied',false));

  return jsonb_build_object('status','draft','plan_version_id',new_version_id,'version_number',next_version_number,'based_on_version_id',source_plan_version_id,'component_count',copied_component_count,'deal_rule_count',copied_deal_rule_count,'attribution_rule_count',copied_attribution_rule_count,'legacy_credit_rule_count',copied_legacy_credit_rule_count,'rule_set_count',copied_rule_set_count,'draft_assignment_count',copied_assignment_count,'agreements_copied',false);
end;
$$;

revoke all on function public.create_compensation_plan_version_from_source(uuid,uuid,date,date,text,text) from public,anon;
grant execute on function public.create_compensation_plan_version_from_source(uuid,uuid,date,date,text,text) to authenticated;

comment on function public.create_compensation_plan_version_from_source(uuid,uuid,date,date,text,text) is
'Creates one editable draft from a non-draft source version, cloning compensation configuration and current employee applicability while preserving the source version, earnings, preview history, and signed agreements.';
