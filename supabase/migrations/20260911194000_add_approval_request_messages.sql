create table if not exists public.approval_request_messages (
  id uuid primary key default gen_random_uuid(),
  approval_request_id uuid not null references public.approval_requests(id) on delete cascade,
  sender_user_id uuid not null,
  message_body text not null,
  created_at timestamptz not null default now()
);
create index if not exists approval_request_messages_request_created_idx on public.approval_request_messages(approval_request_id,created_at);
alter table public.approval_request_messages enable row level security;

create or replace function public.get_approval_request_messages(target_approval_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare actor uuid:=auth.uid(); req public.approval_requests%rowtype; earning_employee uuid; result jsonb;
begin
  if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select * into req from public.approval_requests where id=target_approval_request_id;
  if not found then raise exception 'Approval request not found.' using errcode='P0002'; end if;
  select employee_id into earning_employee from public.comp_earnings where id=req.comp_earning_id;
  if not (private.has_permission('earnings.approve') or actor=req.requested_from or actor=req.backup_requested_from or exists(select 1 from public.profiles p join public.employees e on lower(e.email)=lower(p.email) where p.id=actor and e.id=earning_employee)) then raise exception 'You are not permitted to view this approval conversation.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'approval_request_id',m.approval_request_id,'sender_user_id',m.sender_user_id,'sender_name',coalesce(p.full_name,p.email),'message_body',m.message_body,'created_at',m.created_at) order by m.created_at,m.id),'[]'::jsonb)
  into result from public.approval_request_messages m left join public.profiles p on p.id=m.sender_user_id where m.approval_request_id=target_approval_request_id;
  return result;
end;
$function$;

create or replace function public.add_approval_request_message(target_approval_request_id uuid, message_body text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare actor uuid:=auth.uid(); req public.approval_requests%rowtype; earning_employee uuid; normalized text:=nullif(trim(coalesce(message_body,'')),''); new_id uuid;
begin
  if actor is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if normalized is null then raise exception 'Message cannot be blank.' using errcode='22023'; end if;
  select * into req from public.approval_requests where id=target_approval_request_id;
  if not found then raise exception 'Approval request not found.' using errcode='P0002'; end if;
  select employee_id into earning_employee from public.comp_earnings where id=req.comp_earning_id;
  if not (private.has_permission('earnings.approve') or actor=req.requested_from or actor=req.backup_requested_from or exists(select 1 from public.profiles p join public.employees e on lower(e.email)=lower(p.email) where p.id=actor and e.id=earning_employee)) then raise exception 'You are not permitted to message on this approval.' using errcode='42501'; end if;
  insert into public.approval_request_messages(approval_request_id,sender_user_id,message_body) values(target_approval_request_id,actor,normalized) returning id into new_id;
  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state,related_employee_id)
  values(actor,'approval_request_message_added','A clarification message was added to an approval request.',jsonb_build_object('approval_request_id',target_approval_request_id,'message_id',new_id),earning_employee);
  return jsonb_build_object('status','created','message_id',new_id,'approval_request_id',target_approval_request_id);
end;
$function$;
revoke all on function public.get_approval_request_messages(uuid) from public;
revoke all on function public.add_approval_request_message(uuid,text) from public;
grant execute on function public.get_approval_request_messages(uuid) to authenticated;
grant execute on function public.add_approval_request_message(uuid,text) to authenticated;