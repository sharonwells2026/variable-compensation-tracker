create or replace function public.get_admin_earnings_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  actor uuid := auth.uid();
  actor_employee uuid;
  full_access boolean := false;
  result jsonb;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode='42501';
  end if;
  if not private.has_permission('earnings.view') and not private.has_permission('earnings.approve') then
    raise exception 'Earnings administration is not permitted.' using errcode='42501';
  end if;

  select p.employee_id into actor_employee from public.profiles p where p.id=actor;
  full_access := private.has_app_role('system_administrator') or private.has_permission('audit.view_all');

  with scoped as (
    select e.*, emp.full_name as employee_name, emp.email as employee_email, emp.job_title
    from public.comp_earnings e
    join public.employees emp on emp.id=e.employee_id
    where e.is_current
      and (
        full_access
        or e.employee_id=actor_employee
        or emp.manager_id=actor_employee
        or exists (
          select 1 from private.user_employee_permissions uep
          where uep.user_id=actor and uep.employee_id=e.employee_id
            and uep.permission_key in ('earnings.view','earnings.approve') and uep.allowed=true
        )
      )
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'current_earnings', count(*),
      'earned_amount', coalesce(sum(earned_amount),0),
      'eligible_amount', coalesce(sum(eligible_amount),0),
      'approved_amount', coalesce(sum(approved_amount),0),
      'paid_amount', coalesce(sum(paid_amount),0),
      'awaiting_approval', count(*) filter (where manager_approval_status::text in ('pending','submitted') or employee_verification_status::text='submitted'),
      'payment_exceptions', count(*) filter (where payment_status::text in ('held','error') or hold_reason is not null)
    ),
    'earnings', coalesce(jsonb_agg(jsonb_build_object(
      'earning_id',id,'employee_id',employee_id,'employee_name',employee_name,'employee_email',employee_email,'job_title',job_title,
      'earning_name',earning_name,'earning_description',earning_description,'source_type',source_type,'source_external_id',source_external_id,'source_url',source_url,
      'earned_date',earned_date,'earned_amount',earned_amount,'eligibility_status',eligibility_status,'eligible_date',eligible_date,'eligible_amount',eligible_amount,
      'employee_verification_status',employee_verification_status,'manager_approval_status',manager_approval_status,'executive_approval_required',executive_approval_required,
      'executive_approval_status',executive_approval_status,'approved_amount',approved_amount,'payment_status',payment_status,'paid_amount',paid_amount,'hold_reason',hold_reason,
      'expected_payment_date',expected_payment_date,'expected_pay_period_label',expected_pay_period_label,'reconciliation_status',reconciliation_status,
      'source_match_status',source_match_status,'updated_at',updated_at
    ) order by earned_date desc nulls last, updated_at desc),'[]'::jsonb)
  ) into result
  from scoped;

  return result;
end;
$function$;

create or replace function public.get_admin_audit_activity(selected_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  actor uuid := auth.uid();
  actor_employee uuid;
  full_access boolean := false;
  result jsonb;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode='42501';
  end if;
  if not private.has_permission('audit.view_all') and not private.has_permission('audit.view_assigned') then
    raise exception 'Audit activity is not permitted.' using errcode='42501';
  end if;

  select p.employee_id into actor_employee from public.profiles p where p.id=actor;
  full_access := private.has_permission('audit.view_all') or private.has_app_role('system_administrator');

  with scoped as (
    select a.*, actor_profile.full_name as actor_name, target_profile.full_name as target_name, emp.full_name as employee_name
    from public.app_access_audit_events a
    left join public.profiles actor_profile on actor_profile.id=a.actor_user_id
    left join public.profiles target_profile on target_profile.id=a.target_user_id
    left join public.employees emp on emp.id=a.related_employee_id
    where full_access
      or a.actor_user_id=actor
      or a.target_user_id=actor
      or a.related_employee_id=actor_employee
      or exists (select 1 from public.employees direct where direct.id=a.related_employee_id and direct.manager_id=actor_employee)
      or exists (
        select 1 from private.user_employee_permissions uep
        where uep.user_id=actor and uep.employee_id=a.related_employee_id
          and uep.permission_key in ('audit.view_assigned','audit.view_all') and uep.allowed=true
      )
    order by a.occurred_at desc
    limit greatest(1,least(coalesce(selected_limit,100),500))
  )
  select jsonb_build_object(
    'events', coalesce(jsonb_agg(jsonb_build_object(
      'event_id',id,'event_type',event_type,'event_reason',event_reason,'occurred_at',occurred_at,
      'actor_user_id',actor_user_id,'actor_name',actor_name,'target_user_id',target_user_id,'target_name',target_name,
      'related_employee_id',related_employee_id,'employee_name',employee_name,'related_plan_id',related_plan_id,
      'previous_state',previous_state,'new_state',new_state
    ) order by occurred_at desc),'[]'::jsonb)
  ) into result
  from scoped;

  return result;
end;
$function$;

grant execute on function public.get_admin_earnings_data() to authenticated;
grant execute on function public.get_admin_audit_activity(integer) to authenticated;