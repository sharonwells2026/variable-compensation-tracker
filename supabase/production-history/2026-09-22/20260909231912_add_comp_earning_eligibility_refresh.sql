create or replace function public.refresh_comp_earning_eligibility(
  target_earning_id uuid default null,
  evaluation_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  earning_record record;
  evaluation jsonb;
  evaluated_count integer := 0;
  transitioned_count integer := 0;
  waiting_count integer := 0;
  skipped_count integer := 0;
  error_count integer := 0;
  previous_status public.eligibility_status;
  previous_evidence jsonb;
  target_status text;
  evidence_payload jsonb;
  condition_description text;
  due_date date;
  eligible_date_value date;
  eligible_amount_value numeric;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  if not (private.has_app_role('system_administrator') or private.has_permission('earnings.edit')) then
    raise exception 'Earning eligibility refresh access required.' using errcode='42501';
  end if;

  if evaluation_date is null then
    raise exception 'Evaluation date is required.' using errcode='22023';
  end if;

  for earning_record in
    select e.id
    from public.comp_earnings e
    join public.comp_plan_components c on c.id=e.plan_component_id
    where e.is_current=true
      and (target_earning_id is null or e.id=target_earning_id)
      and c.rule_configuration ? 'eligibility'
      and e.eligibility_status in ('pending_condition','eligible')
    order by e.created_at,e.id
  loop
    begin
      select e.eligibility_status,e.eligibility_evidence
      into previous_status,previous_evidence
      from public.comp_earnings e
      where e.id=earning_record.id
      for update;

      evaluation := private.evaluate_comp_earning_eligibility(earning_record.id,evaluation_date);

      if evaluation->>'status' <> 'evaluated' then
        skipped_count := skipped_count + 1;
        continue;
      end if;

      evaluated_count := evaluated_count + 1;
      target_status := evaluation->>'target_eligibility_status';
      evidence_payload := coalesce(evaluation->'evidence','{}'::jsonb)
        || jsonb_build_object(
          'reason_code',evaluation->>'reason_code',
          'reason',evaluation->>'reason',
          'evaluated_at',pg_catalog.now(),
          'evaluation_date',evaluation_date
        );
      condition_description := evaluation->>'reason';
      due_date := nullif(evaluation->>'eligibility_due_date','')::date;
      eligible_date_value := nullif(evaluation->>'eligible_date','')::date;
      eligible_amount_value := coalesce(nullif(evaluation->>'eligible_amount','')::numeric,0);

      if target_status='eligible' and previous_status <> 'eligible' then
        update public.comp_earnings
        set eligibility_status='eligible'::public.eligibility_status,
            eligibility_condition_type=evaluation->>'mode',
            eligibility_condition_description=condition_description,
            eligibility_due_date=due_date,
            eligible_date=eligible_date_value,
            eligible_amount=eligible_amount_value,
            eligibility_evidence=evidence_payload,
            updated_at=pg_catalog.now()
        where id=earning_record.id;

        insert into public.earning_eligibility_events(
          comp_earning_id,previous_status,new_status,event_source,
          source_external_id,evidence,notes,changed_by,changed_at
        )
        select e.id,previous_status,'eligible'::public.eligibility_status,
          'configured_eligibility_evaluator',e.source_external_id,
          evidence_payload,condition_description,(select auth.uid()),pg_catalog.now()
        from public.comp_earnings e where e.id=earning_record.id;

        insert into public.comp_earning_lifecycle_events(
          comp_earning_id,employee_id,plan_assignment_id,plan_component_id,hubspot_deal_id,
          event_type,previous_status,new_status,event_reason,event_source,
          previous_state,new_state,requires_review,review_status,occurred_at
        )
        select e.id,e.employee_id,e.plan_assignment_id,e.plan_component_id,
          case when e.source_type='hubspot_deal' then e.source_external_id else null end,
          'earning_became_eligible',previous_status::text,'eligible',condition_description,
          'configured_eligibility_evaluator',
          jsonb_build_object('eligibility_status',previous_status,'eligibility_evidence',previous_evidence),
          jsonb_build_object('eligibility_status','eligible','eligible_date',eligible_date_value,'eligible_amount',eligible_amount_value,'eligibility_evidence',evidence_payload),
          false,'not_required',pg_catalog.now()
        from public.comp_earnings e where e.id=earning_record.id;

        transitioned_count := transitioned_count + 1;
      elsif target_status='pending_condition' and previous_status='pending_condition' then
        update public.comp_earnings
        set eligibility_condition_type=evaluation->>'mode',
            eligibility_condition_description=condition_description,
            eligibility_due_date=due_date,
            eligible_date=null,
            eligible_amount=0,
            eligibility_evidence=evidence_payload,
            updated_at=pg_catalog.now()
        where id=earning_record.id;

        if previous_evidence is distinct from evidence_payload then
          insert into public.earning_eligibility_events(
            comp_earning_id,previous_status,new_status,event_source,
            source_external_id,evidence,notes,changed_by,changed_at
          )
          select e.id,previous_status,previous_status,
            'configured_eligibility_evaluator',e.source_external_id,
            evidence_payload,condition_description,(select auth.uid()),pg_catalog.now()
          from public.comp_earnings e where e.id=earning_record.id;
        end if;

        waiting_count := waiting_count + 1;
      else
        skipped_count := skipped_count + 1;
      end if;
    exception when others then
      error_count := error_count + 1;
    end;
  end loop;

  if target_earning_id is not null and evaluated_count+skipped_count+error_count=0 then
    raise exception 'Configured earning was not found.' using errcode='22023';
  end if;

  return jsonb_build_object(
    'status','completed',
    'evaluation_date',evaluation_date,
    'evaluated',evaluated_count,
    'transitioned_to_eligible',transitioned_count,
    'still_waiting',waiting_count,
    'skipped',skipped_count,
    'errors',error_count,
    'completed_at',pg_catalog.now()
  );
end;
$function$;

revoke all on function public.refresh_comp_earning_eligibility(uuid,date) from public;
revoke all on function public.refresh_comp_earning_eligibility(uuid,date) from anon;
grant execute on function public.refresh_comp_earning_eligibility(uuid,date) to authenticated;