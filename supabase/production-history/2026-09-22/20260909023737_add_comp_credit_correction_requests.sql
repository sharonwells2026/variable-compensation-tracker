create table if not exists public.comp_credit_correction_requests (
  id uuid primary key default gen_random_uuid(),
  candidate_key text not null,
  hubspot_deal_id text not null,
  plan_component_id uuid not null,
  earning_id uuid null references public.comp_earnings(id),
  current_employee_id uuid not null references public.employees(id),
  requested_employee_id uuid not null references public.employees(id),
  current_credit_percentage numeric not null,
  requested_credit_percentage numeric not null check (requested_credit_percentage > 0 and requested_credit_percentage <= 100),
  reason text not null check (length(trim(reason)) >= 8),
  status text not null default 'pending_review' check (status in ('pending_review','approved_for_correction','rejected','cancelled','applied')),
  requested_by uuid not null,
  requested_at timestamptz not null default now(),
  resolved_by uuid null,
  resolved_at timestamptz null,
  resolution_notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists comp_credit_correction_requests_candidate_idx on public.comp_credit_correction_requests(candidate_key, requested_at desc);
create index if not exists comp_credit_correction_requests_status_idx on public.comp_credit_correction_requests(status, requested_at desc);

alter table public.comp_credit_correction_requests enable row level security;

revoke all on public.comp_credit_correction_requests from anon;
revoke all on public.comp_credit_correction_requests from authenticated;
grant select, insert, update on public.comp_credit_correction_requests to authenticated;

create policy "credit corrections view permitted" on public.comp_credit_correction_requests
for select to authenticated
using ((select auth.uid()) is not null and private.has_permission('earnings.view'));

create policy "credit corrections create permitted" on public.comp_credit_correction_requests
for insert to authenticated
with check ((select auth.uid()) is not null and requested_by = (select auth.uid()) and (private.has_permission('earnings.edit') or private.has_permission('earnings.override')));

create policy "credit corrections update permitted" on public.comp_credit_correction_requests
for update to authenticated
using ((select auth.uid()) is not null and (private.has_permission('earnings.edit') or private.has_permission('earnings.override')))
with check ((select auth.uid()) is not null and (private.has_permission('earnings.edit') or private.has_permission('earnings.override')));

create or replace function public.request_comp_credit_correction(
  target_candidate_key text,
  target_employee_id uuid,
  target_credit_percentage numeric,
  correction_reason text
) returns jsonb
language plpgsql
security invoker
set search_path to 'public','pg_temp'
as $$
declare
  actor uuid := auth.uid();
  c public.comp_deal_earning_candidates_v2%rowtype;
  e public.comp_earnings%rowtype;
  request_id uuid;
  normalized_reason text := nullif(trim(coalesce(correction_reason,'')),'');
begin
  if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('earnings.edit') or private.has_permission('earnings.override')) then
    raise exception 'You are not permitted to request compensation credit corrections.' using errcode='42501';
  end if;
  if normalized_reason is null or length(normalized_reason) < 8 then
    raise exception 'A correction reason of at least 8 characters is required.' using errcode='22023';
  end if;
  if target_credit_percentage is null or target_credit_percentage <= 0 or target_credit_percentage > 100 then
    raise exception 'Credit percentage must be greater than 0 and no more than 100.' using errcode='22023';
  end if;
  select * into c from public.comp_deal_earning_candidates_v2 where candidate_key = target_candidate_key;
  if not found then raise exception 'Compensation candidate not found.' using errcode='P0002'; end if;
  if not exists(select 1 from public.employees x where x.id=target_employee_id and x.is_active=true) then
    raise exception 'The requested employee is not active.' using errcode='22023';
  end if;
  select * into e from public.comp_earnings ce
   where ce.is_current is true and ce.employee_id=c.employee_id and ce.source_external_id=c.hubspot_deal_id and ce.plan_component_id=c.plan_component_id
   order by ce.created_at desc limit 1;
  if found then
    if e.payment_status = 'paid'::public.payment_status or coalesce(e.paid_amount,0) > 0 then
      raise exception 'Paid earnings cannot be reassigned directly. Use a paid adjustment/reversal workflow.' using errcode='22023';
    end if;
    if e.employee_verification_status = 'verified'::public.verification_status or e.manager_approval_status <> 'pending'::public.approval_status or e.executive_approval_status = 'approved'::public.approval_status or coalesce(e.approved_amount,0) > 0 then
      raise exception 'This earning has entered approval. Return or reopen it before changing attribution.' using errcode='22023';
    end if;
  end if;
  if exists(select 1 from public.comp_credit_correction_requests r where r.candidate_key=target_candidate_key and r.status in ('pending_review','approved_for_correction')) then
    raise exception 'An open credit correction already exists for this transaction.' using errcode='22023';
  end if;
  insert into public.comp_credit_correction_requests(candidate_key,hubspot_deal_id,plan_component_id,earning_id,current_employee_id,requested_employee_id,current_credit_percentage,requested_credit_percentage,reason,requested_by)
  values(c.candidate_key,c.hubspot_deal_id,c.plan_component_id,case when found then e.id else null end,c.employee_id,target_employee_id,coalesce(c.credit_percentage,100),target_credit_percentage,normalized_reason,actor)
  returning id into request_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,previous_state,new_state,related_employee_id)
  values(actor,'comp_credit_correction_requested',normalized_reason,
    jsonb_build_object('candidate_key',c.candidate_key,'employee_id',c.employee_id,'credit_percentage',c.credit_percentage,'earning_id',case when found then e.id else null end),
    jsonb_build_object('correction_request_id',request_id,'requested_employee_id',target_employee_id,'requested_credit_percentage',target_credit_percentage,'status','pending_review'),
    c.employee_id);
  return jsonb_build_object('status','pending_review','correction_request_id',request_id,'candidate_key',c.candidate_key);
end;
$$;

revoke all on function public.request_comp_credit_correction(text,uuid,numeric,text) from public, anon;
grant execute on function public.request_comp_credit_correction(text,uuid,numeric,text) to authenticated;

create or replace function public.get_comp_credit_correction_targets() returns jsonb
language plpgsql
security invoker
set search_path to 'public','pg_temp'
as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('earnings.edit') or private.has_permission('earnings.override')) then raise exception 'Permission denied.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'full_name',full_name,'email',email) order by full_name),'[]'::jsonb)
    into result from public.employees where is_active=true;
  return result;
end;
$$;
revoke all on function public.get_comp_credit_correction_targets() from public, anon;
grant execute on function public.get_comp_credit_correction_targets() to authenticated;