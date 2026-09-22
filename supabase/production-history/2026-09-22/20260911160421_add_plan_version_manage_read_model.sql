create or replace function public.get_compensation_plan_version_manage_data(selected_plan_version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare payload jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('plans.view') or private.has_permission('plans.edit')) then raise exception 'Plan access required.' using errcode='42501'; end if;

  select jsonb_build_object(
    'version',jsonb_build_object(
      'version_id',v.id,'version_number',v.version_number,'status',v.status,
      'effective_start_date',v.effective_start_date,'effective_end_date',v.effective_end_date,
      'currency_code',v.currency_code,'notes',v.notes,'approved_at',v.approved_at,
      'based_on_version_id',v.based_on_version_id
    ),
    'plan',jsonb_build_object('plan_id',p.id,'name',p.name,'plan_code',p.plan_code,'description',p.description),
    'components',coalesce((select jsonb_agg(jsonb_build_object(
      'component_id',c.id,'name',c.name,'component_code',c.component_code,'description',c.description,
      'calculation_type',c.calculation_type,'measurement_source',c.measurement_source,'measurement_period',c.measurement_period,
      'rule_configuration',c.rule_configuration,'maximum_payout',c.maximum_payout,'is_active',c.is_active,
      'deal_rules',coalesce((select jsonb_agg(jsonb_build_object(
        'id',dr.id,'pipeline_id',dr.hubspot_pipeline_id,'pipeline_name',hp.pipeline_name,
        'stage_id',dr.hubspot_stage_id,'stage_name',hs.stage_name,'deal_type',dr.hubspot_deal_type,
        'amount_source',dr.amount_source,'amount_label',dr.amount_label,'marks_earned',dr.marks_earned,
        'marks_eligible',dr.marks_eligible,'effective_start_date',dr.effective_start_date,'effective_end_date',dr.effective_end_date
      ) order by dr.priority, hp.pipeline_name, hs.stage_name, dr.hubspot_deal_type)
        from public.comp_component_deal_rules dr
        left join public.hubspot_pipelines hp on hp.hubspot_pipeline_id=dr.hubspot_pipeline_id
        left join public.hubspot_pipeline_stages hs on hs.hubspot_pipeline_id=dr.hubspot_pipeline_id and hs.hubspot_stage_id=dr.hubspot_stage_id
        where dr.plan_component_id=c.id and dr.is_active=true),'[]'::jsonb),
      'attribution_rules',coalesce((select jsonb_agg(jsonb_build_object(
        'id',ar.id,'purpose',ar.attribution_purpose,'hubspot_user_field_keys',ar.hubspot_user_field_keys,
        'match_logic',ar.match_logic,'credit_percentage',ar.credit_percentage,'qualifying_pipeline_ids',ar.qualifying_pipeline_ids,
        'qualifying_deal_types',ar.qualifying_deal_types,'priority',ar.priority,'allow_stacking',ar.allow_stacking,
        'rule_configuration',ar.rule_configuration,'effective_start_date',ar.effective_start_date,'effective_end_date',ar.effective_end_date
      ) order by ar.priority,ar.created_at) from public.comp_user_attribution_rules ar where ar.plan_component_id=c.id and ar.is_active=true),'[]'::jsonb),
      'rule_sets',coalesce((select jsonb_agg(jsonb_build_object('id',rs.id,'name',rs.name,'purpose',rs.purpose,'version',rs.version,'is_active',rs.is_active) order by rs.purpose,rs.version desc) from public.comp_rule_sets rs where rs.plan_component_id=c.id),'[]'::jsonb)
    ) order by c.calculation_order,c.name) from public.comp_plan_components c where c.plan_version_id=v.id),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object('employee_id',da.employee_id,'employee_name',e.full_name,'allocation_percent',da.allocation_percent,'effective_start_date',da.effective_start_date,'effective_end_date',da.effective_end_date) order by e.full_name) from public.comp_plan_draft_assignments da join public.employees e on e.id=da.employee_id where da.plan_version_id=v.id),'[]'::jsonb)
  ) into payload
  from public.comp_plan_versions v join public.comp_plans p on p.id=v.comp_plan_id
  where v.id=selected_plan_version_id;

  if payload is null then raise exception 'Plan version not found.' using errcode='22023'; end if;
  return payload;
end;
$$;
revoke all on function public.get_compensation_plan_version_manage_data(uuid) from public,anon;
grant execute on function public.get_compensation_plan_version_manage_data(uuid) to authenticated;