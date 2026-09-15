-- Pilot hardening: make Earning Types created in the current plan builder feed the
-- existing generic_v2 earnings engine without changing auth or RevOS architecture.

create or replace function private.sync_simple_qualification_to_deal_rules(target_rule_set_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  component_id uuid;
  purpose_name text;
  plan_start date;
  amount_source_name text;
  stage_values text[];
  type_values text[];
begin
  select rs.plan_component_id, rs.purpose, pv.effective_start_date,
         coalesce(nullif(c.measurement_source,''),'amount')
    into component_id, purpose_name, plan_start, amount_source_name
  from public.comp_rule_sets rs
  join public.comp_plan_components c on c.id=rs.plan_component_id
  join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where rs.id=target_rule_set_id;

  if component_id is null or purpose_name <> 'qualification' then return; end if;

  delete from public.comp_component_deal_rules
  where plan_component_id=component_id
    and rule_notes='generated_from_simple_qualification';

  select array_agg(distinct v) into stage_values
  from (
    select case when jsonb_typeof(p.comparison_value)='string' then p.comparison_value #>> '{}'
                else x.value end as v
    from public.comp_rule_predicates p
    left join lateral jsonb_array_elements_text(
      case when jsonb_typeof(p.comparison_value)='array' then p.comparison_value else '[]'::jsonb end
    ) x(value) on true
    where p.rule_set_id=target_rule_set_id and p.object_type='deal' and p.property_name='dealstage'
  ) q where v is not null and v<>'';

  select array_agg(distinct v) into type_values
  from (
    select case when jsonb_typeof(p.comparison_value)='string' then p.comparison_value #>> '{}'
                else x.value end as v
    from public.comp_rule_predicates p
    left join lateral jsonb_array_elements_text(
      case when jsonb_typeof(p.comparison_value)='array' then p.comparison_value else '[]'::jsonb end
    ) x(value) on true
    where p.rule_set_id=target_rule_set_id and p.object_type='deal' and p.property_name='dealtype'
  ) q where v is not null and v<>'';

  if coalesce(array_length(stage_values,1),0)=0 or coalesce(array_length(type_values,1),0)=0 then return; end if;

  insert into public.comp_component_deal_rules(
    plan_component_id, hubspot_pipeline_id, hubspot_stage_id, hubspot_deal_type,
    calculation_action, marks_earned, marks_eligible, marks_paid,
    amount_source, amount_label, priority, is_active, effective_start_date, rule_notes
  )
  select distinct component_id, s.hubspot_pipeline_id, stage_id, deal_type,
         'include', true, false, false,
         amount_source_name,
         case amount_source_name
           when 'average_arr' then 'ARR'
           when 'first_year_arr' then 'First Year ARR'
           when 'one_time_fee' then 'One-time Fee'
           when 'total_contract_value' then 'Total Contract Value'
           else 'Deal Amount'
         end,
         100, true, plan_start, 'generated_from_simple_qualification'
  from unnest(stage_values) stage_id
  join public.hubspot_pipeline_stages s on s.hubspot_stage_id=stage_id
  cross join unnest(type_values) deal_type;
end;
$$;

revoke all on function private.sync_simple_qualification_to_deal_rules(uuid) from public, anon, authenticated;

create or replace function private.sync_simple_qualification_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.sync_simple_qualification_to_deal_rules(coalesce(new.rule_set_id,old.rule_set_id));
  return coalesce(new,old);
end;
$$;

revoke all on function private.sync_simple_qualification_trigger() from public, anon, authenticated;

drop trigger if exists sync_simple_qualification_to_deal_rules on public.comp_rule_predicates;
create trigger sync_simple_qualification_to_deal_rules
after insert or update or delete on public.comp_rule_predicates
for each row execute function private.sync_simple_qualification_trigger();

create or replace function public.get_comp_component_attribution_config(selected_component_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  access jsonb;
  result jsonb;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to view compensation attribution';
  end if;
  select jsonb_build_object(
    'fields',coalesce((select jsonb_agg(jsonb_build_object('field_key',f.field_key,'display_name',f.display_name,'object_type',f.object_type) order by f.calculation_order) from public.comp_hubspot_user_fields f where f.is_active),'[]'::jsonb),
    'current',(
      select jsonb_build_object('id',r.id,'field_keys',r.hubspot_user_field_keys,'match_logic',r.match_logic,'credit_percentage',r.credit_percentage)
      from public.comp_user_attribution_rules r
      where r.plan_component_id=selected_component_id and r.attribution_purpose='earning' and r.is_active
      order by r.priority,r.created_at limit 1
    )
  ) into result;
  return result;
end;
$$;

grant execute on function public.get_comp_component_attribution_config(uuid) to authenticated;
revoke execute on function public.get_comp_component_attribution_config(uuid) from anon;

create or replace function public.save_comp_component_attribution(selected_component_id uuid, selected_field_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  access jsonb;
  version_status text;
  plan_start date;
  new_id uuid;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to edit compensation attribution';
  end if;
  select pv.status::text,pv.effective_start_date into version_status,plan_start
  from public.comp_plan_components c
  join public.comp_plan_versions pv on pv.id=c.plan_version_id
  where c.id=selected_component_id;
  if version_status is null then raise exception 'Earning Type does not exist.'; end if;
  if version_status<>'draft' then raise exception 'Only draft Earning Types can change credit attribution.'; end if;
  if not exists(select 1 from public.comp_hubspot_user_fields f where f.field_key=selected_field_key and f.is_active) then
    raise exception 'Choose an available HubSpot user field for credit attribution.';
  end if;
  update public.comp_user_attribution_rules
  set is_active=false,updated_at=pg_catalog.now()
  where plan_component_id=selected_component_id and attribution_purpose='earning' and is_active;
  insert into public.comp_user_attribution_rules(
    plan_component_id,attribution_purpose,metric_key,hubspot_user_field_keys,match_logic,
    credit_percentage,qualifying_pipeline_ids,qualifying_deal_types,priority,allow_stacking,
    rule_configuration,effective_start_date,is_active
  ) values(
    selected_component_id,'earning',null,jsonb_build_array(selected_field_key),'any',
    100,'[]'::jsonb,'[]'::jsonb,10,false,
    jsonb_build_object('configuration_source','earning_type_editor','description','Credit assigned from '||selected_field_key),
    plan_start,true
  ) returning id into new_id;
  return jsonb_build_object('status','saved','rule_id',new_id,'field_key',selected_field_key);
end;
$$;

grant execute on function public.save_comp_component_attribution(uuid,text) to authenticated;
revoke execute on function public.save_comp_component_attribution(uuid,text) from anon;

create or replace function public.refresh_compensation_management_data(force_refresh boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  hubspot_result jsonb;
  earnings_result jsonb;
  eligibility_result jsonb;
begin
  if not private.has_permission('hubspot.refresh') then
    raise exception 'Management permission is required to refresh HubSpot.' using errcode='42501';
  end if;
  hubspot_result:=public.refresh_hubspot_compensation_data(force_refresh);
  if hubspot_result->>'status' in ('completed','skipped') then
    earnings_result:=public.apply_comp_deal_earning_refresh();
    eligibility_result:=public.refresh_comp_earning_eligibility(null,current_date);
  else
    earnings_result:=jsonb_build_object('status','not_run','reason','HubSpot refresh did not complete.');
    eligibility_result:=jsonb_build_object('status','not_run','reason','Earnings refresh did not run.');
  end if;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(auth.uid(),'management_compensation_refresh','An authorized management user refreshed HubSpot, compensation earnings, and configured eligibility.',jsonb_build_object('hubspot',hubspot_result,'earnings',earnings_result,'eligibility',eligibility_result));
  return jsonb_build_object('status','completed','hubspot',hubspot_result,'earnings',earnings_result,'eligibility',eligibility_result,'completed_at',pg_catalog.now());
end;
$$;

grant execute on function public.refresh_compensation_management_data(boolean) to authenticated;
revoke execute on function public.refresh_compensation_management_data(boolean) from anon;
