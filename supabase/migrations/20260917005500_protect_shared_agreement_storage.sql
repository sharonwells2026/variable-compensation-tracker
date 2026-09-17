create or replace function public.delete_comp_plan_agreement(selected_agreement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  agreement_record public.comp_plan_agreements%rowtype;
  version_status public.plan_version_status;
  remaining_reference_count integer:=0;
  deletable_storage_path text;
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

  if version_status <> 'draft' then
    raise exception 'Agreements may only be removed from a draft plan version.' using errcode='42501';
  end if;

  delete from public.comp_plan_agreements where id=selected_agreement_id;

  select count(*) into remaining_reference_count
  from public.comp_plan_agreements
  where storage_path=agreement_record.storage_path;

  deletable_storage_path:=case when remaining_reference_count=0 then agreement_record.storage_path else null end;

  insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,new_state)
  values(
    auth.uid(),
    'comp_plan_agreement_removed',
    'A compensation agreement link was removed from a draft plan. Shared private storage is deleted only after the last agreement reference is removed.',
    jsonb_build_object(
      'agreement_id',selected_agreement_id,
      'plan_version_id',agreement_record.plan_version_id,
      'employee_id',agreement_record.employee_id,
      'file_name',agreement_record.file_name,
      'storage_path',agreement_record.storage_path,
      'remaining_storage_reference_count',remaining_reference_count,
      'delete_storage_object',remaining_reference_count=0
    )
  );

  return jsonb_build_object(
    'status','deleted',
    'storage_path',deletable_storage_path,
    'remaining_storage_reference_count',remaining_reference_count
  );
end;
$$;
