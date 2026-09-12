-- Compensation plan agreements: private plan-version files scoped to one employee or everyone on the plan.

create table if not exists public.comp_plan_agreements (
  id uuid primary key default gen_random_uuid(),
  plan_version_id uuid not null references public.comp_plan_versions(id) on delete cascade,
  employee_id uuid null references public.employees(id) on delete cascade,
  applies_to_everyone boolean not null default false,
  file_name text not null,
  storage_path text not null unique,
  mime_type text null,
  file_size_bytes bigint null,
  signed_at date null,
  notes text null,
  uploaded_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comp_plan_agreements_scope_check check (
    (applies_to_everyone and employee_id is null)
    or (not applies_to_everyone and employee_id is not null)
  )
);

alter table public.comp_plan_agreements enable row level security;
revoke all on public.comp_plan_agreements from anon, authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'compensation-agreements',
  'compensation-agreements',
  false,
  15728640,
  array['application/pdf','image/png','image/jpeg','application/vnd.openxmlformats-officedocument.wordprocessingml.document']
)
on conflict (id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "comp agreements insert" on storage.objects;
create policy "comp agreements insert" on storage.objects
for insert to authenticated
with check (bucket_id='compensation-agreements' and private.has_permission('plans.edit'));

drop policy if exists "comp agreements select" on storage.objects;
create policy "comp agreements select" on storage.objects
for select to authenticated
using (
  bucket_id='compensation-agreements'
  and (
    private.has_permission('plans.view')
    or private.has_permission('plans.edit')
    or private.has_permission('users.manage')
  )
);

drop policy if exists "comp agreements delete" on storage.objects;
create policy "comp agreements delete" on storage.objects
for delete to authenticated
using (bucket_id='compensation-agreements' and private.has_permission('plans.edit'));

create or replace function public.save_comp_plan_agreement(
  selected_plan_version_id uuid,
  selected_employee_id uuid,
  selected_applies_to_everyone boolean,
  selected_file_name text,
  selected_storage_path text,
  selected_mime_type text default null,
  selected_file_size_bytes bigint default null,
  selected_signed_at date default null,
  selected_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  version_status public.plan_version_status;
  saved_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan editing is not permitted.' using errcode='42501'; end if;

  select status into version_status
  from public.comp_plan_versions
  where id=selected_plan_version_id;

  if version_status is null then raise exception 'Plan version does not exist.' using errcode='22023'; end if;
  if version_status <> 'draft' then raise exception 'Agreements may only be added to a draft plan version.' using errcode='42501'; end if;
  if trim(coalesce(selected_file_name,''))='' or trim(coalesce(selected_storage_path,''))='' then raise exception 'File name and storage path are required.' using errcode='22023'; end if;
  if selected_applies_to_everyone and selected_employee_id is not null then raise exception 'An agreement for everyone cannot also be scoped to one employee.' using errcode='22023'; end if;
  if not selected_applies_to_everyone and selected_employee_id is null then raise exception 'Choose an employee or mark the agreement as applying to everyone.' using errcode='22023'; end if;
  if selected_employee_id is not null and not exists(select 1 from public.employees where id=selected_employee_id) then raise exception 'Employee does not exist.' using errcode='22023'; end if;

  insert into public.comp_plan_agreements(
    plan_version_id,employee_id,applies_to_everyone,file_name,storage_path,mime_type,file_size_bytes,signed_at,notes,uploaded_by
  ) values (
    selected_plan_version_id,selected_employee_id,selected_applies_to_everyone,trim(selected_file_name),trim(selected_storage_path),
    nullif(trim(coalesce(selected_mime_type,'')),''),selected_file_size_bytes,selected_signed_at,nullif(trim(coalesce(selected_notes,'')),''),auth.uid()
  ) returning id into saved_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(
    auth.uid(),
    'comp_plan_agreement_added',
    'A compensation agreement was attached to a draft plan.',
    jsonb_build_object('agreement_id',saved_id,'plan_version_id',selected_plan_version_id,'employee_id',selected_employee_id,'applies_to_everyone',selected_applies_to_everyone,'file_name',trim(selected_file_name))
  );

  return jsonb_build_object('status','saved','agreement_id',saved_id);
end;
$$;

create or replace function public.delete_comp_plan_agreement(selected_agreement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  agreement_record public.comp_plan_agreements%rowtype;
  version_status public.plan_version_status;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not private.has_permission('plans.edit') then raise exception 'Plan editing is not permitted.' using errcode='42501'; end if;

  select * into agreement_record
  from public.comp_plan_agreements
  where id=selected_agreement_id
  for update;

  if agreement_record.id is null then raise exception 'Agreement does not exist.' using errcode='22023'; end if;

  select status into version_status
  from public.comp_plan_versions
  where id=agreement_record.plan_version_id;

  if version_status <> 'draft' then raise exception 'Agreements may only be removed from a draft plan version.' using errcode='42501'; end if;

  delete from public.comp_plan_agreements where id=selected_agreement_id;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(
    auth.uid(),
    'comp_plan_agreement_removed',
    'A compensation agreement was removed from a draft plan.',
    jsonb_build_object('agreement_id',selected_agreement_id,'plan_version_id',agreement_record.plan_version_id,'employee_id',agreement_record.employee_id,'file_name',agreement_record.file_name,'storage_path',agreement_record.storage_path)
  );

  return jsonb_build_object('status','deleted','storage_path',agreement_record.storage_path);
end;
$$;

create or replace function public.get_comp_plan_agreements(selected_plan_version_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('plans.view') or private.has_permission('plans.edit') or private.has_permission('users.manage')) then raise exception 'Agreement access is not permitted.' using errcode='42501'; end if;
  if not exists(select 1 from public.comp_plan_versions where id=selected_plan_version_id) then raise exception 'Plan version not found.' using errcode='22023'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'agreement_id',a.id,
    'plan_version_id',a.plan_version_id,
    'employee_id',a.employee_id,
    'employee_name',e.full_name,
    'applies_to_everyone',a.applies_to_everyone,
    'file_name',a.file_name,
    'storage_path',a.storage_path,
    'mime_type',a.mime_type,
    'file_size_bytes',a.file_size_bytes,
    'signed_at',a.signed_at,
    'notes',a.notes,
    'created_at',a.created_at
  ) order by a.created_at desc),'[]'::jsonb)
  into payload
  from public.comp_plan_agreements a
  left join public.employees e on e.id=a.employee_id
  where a.plan_version_id=selected_plan_version_id;

  return payload;
end;
$$;

create or replace function public.get_employee_comp_plan_agreements(selected_employee_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare payload jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if not (private.has_permission('users.manage') or private.has_permission('plans.view') or private.has_permission('plans.edit') or private.has_permission('users.act_as')) then raise exception 'Employee agreement access is not permitted.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'agreement_id',a.id,
    'file_name',a.file_name,
    'storage_path',a.storage_path,
    'mime_type',a.mime_type,
    'file_size_bytes',a.file_size_bytes,
    'signed_at',a.signed_at,
    'notes',a.notes,
    'applies_to_everyone',a.applies_to_everyone,
    'plan_version_id',pv.id,
    'version_number',pv.version_number,
    'plan_name',p.name,
    'plan_code',p.plan_code,
    'created_at',a.created_at
  ) order by a.created_at desc),'[]'::jsonb)
  into payload
  from public.comp_plan_agreements a
  join public.comp_plan_versions pv on pv.id=a.plan_version_id
  join public.comp_plans p on p.id=pv.comp_plan_id
  where a.applies_to_everyone=true or a.employee_id=selected_employee_id;

  return payload;
end;
$$;

revoke all on function public.save_comp_plan_agreement(uuid,uuid,boolean,text,text,text,bigint,date,text) from public,anon;
grant execute on function public.save_comp_plan_agreement(uuid,uuid,boolean,text,text,text,bigint,date,text) to authenticated;
revoke all on function public.delete_comp_plan_agreement(uuid) from public,anon;
grant execute on function public.delete_comp_plan_agreement(uuid) to authenticated;
revoke all on function public.get_comp_plan_agreements(uuid) from public,anon;
grant execute on function public.get_comp_plan_agreements(uuid) to authenticated;
revoke all on function public.get_employee_comp_plan_agreements(uuid) from public,anon;
grant execute on function public.get_employee_comp_plan_agreements(uuid) to authenticated;

create or replace function public.validate_compensation_plan_version_readiness(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
  missing_agreement record;
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
    for missing_agreement in
      select da.employee_id,e.full_name
      from public.comp_plan_draft_assignments da
      join public.employees e on e.id=da.employee_id
      where da.plan_version_id=selected_plan_version_id
        and not exists(
          select 1 from public.comp_plan_agreements a
          where a.plan_version_id=selected_plan_version_id
            and (a.applies_to_everyone=true or a.employee_id=da.employee_id)
        )
      order by e.full_name
    loop
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'code','missing_agreement',
        'section','agreements',
        'employee_id',missing_agreement.employee_id,
        'employee_name',missing_agreement.full_name,
        'message',format('%s needs a signed compensation agreement for this plan.',missing_agreement.full_name)
      ));
    end loop;
  end if;

  for c in
    select id,name,component_code,rule_configuration,additional_eligibility_waiting_days
    from public.comp_plan_components
    where plan_version_id=selected_plan_version_id and is_active=true
    order by calculation_order,name
  loop
    q:=null;
    select rs.id,rs.updated_at,rs.is_active into q
    from public.comp_rule_sets rs
    where rs.plan_component_id=c.id and rs.purpose='qualification'
    order by rs.version desc,rs.updated_at desc limit 1;

    if q.id is null then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_earned_rule','section','earned','component_id',c.id,'component_name',c.name,'message',format('%s needs Earned conditions.',c.name)));
    else
      latest_preview:=null;
      select pr.supported,pr.rule_updated_at,pr.previewed_at into latest_preview
      from public.comp_rule_set_preview_runs pr
      where pr.rule_set_id=q.id order by pr.previewed_at desc limit 1;
      if latest_preview.previewed_at is null or latest_preview.supported is distinct from true or latest_preview.rule_updated_at is distinct from q.updated_at then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','earned_rule_needs_preview','section','earned','component_id',c.id,'component_name',c.name,'rule_set_id',q.id,'message',format('Check the current Earned conditions for %s against real HubSpot data.',c.name)));
      end if;
    end if;

    e:=coalesce(c.rule_configuration->'eligibility','{}'::jsonb);
    if nullif(e->>'mode','') is null then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_eligibility','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s needs a Can be paid when choice.',c.name)));
    elsif e->>'mode'='waiting_period' and coalesce((e->>'waiting_days')::integer,-1)<0 then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','invalid_waiting_period','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s has an invalid waiting period.',c.name)));
    elsif e->>'mode'='rule' then
      if nullif(e->>'rule_set_id','') is null then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_eligibility_rule','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s needs conditions that determine when it can be paid.',c.name)));
      else
        q:=null;
        select rs.id,rs.updated_at,rs.is_active into q
        from public.comp_rule_sets rs
        where rs.id=(e->>'rule_set_id')::uuid and rs.plan_component_id=c.id and rs.purpose='eligibility'
        limit 1;
        if q.id is null then
          v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','invalid_eligibility_rule','section','eligible','component_id',c.id,'component_name',c.name,'message',format('%s references payment conditions that are missing or belong elsewhere.',c.name)));
        else
          latest_preview:=null;
          select pr.supported,pr.rule_updated_at,pr.previewed_at into latest_preview
          from public.comp_rule_set_preview_runs pr
          where pr.rule_set_id=q.id order by pr.previewed_at desc limit 1;
          if latest_preview.previewed_at is null or latest_preview.supported is distinct from true or latest_preview.rule_updated_at is distinct from q.updated_at then
            v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','eligibility_rule_needs_preview','section','eligible','component_id',c.id,'component_name',c.name,'rule_set_id',q.id,'message',format('Check the current payment conditions for %s against real HubSpot data.',c.name)));
          end if;
        end if;
      end if;
    end if;
  end loop;

  if v_start is null then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','missing_effective_start','section','effective_period','message','Set an effective start date.')); end if;

  return jsonb_build_object(
    'plan_version_id',selected_plan_version_id,
    'status',v_status,
    'ready',jsonb_array_length(v_blockers)=0,
    'component_count',v_component_count,
    'draft_assignment_count',v_assignment_count,
    'blocker_count',jsonb_array_length(v_blockers),
    'warning_count',jsonb_array_length(v_warnings),
    'blockers',v_blockers,
    'warnings',v_warnings,
    'checked_at',pg_catalog.now()
  );
end;
$$;

revoke all on function public.validate_compensation_plan_version_readiness(uuid) from public,anon;
grant execute on function public.validate_compensation_plan_version_readiness(uuid) to authenticated;
