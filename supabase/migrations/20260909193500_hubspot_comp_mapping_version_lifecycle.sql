create or replace function public.create_hubspot_comp_mapping_version(source_mapping_version_id uuid default null, note text default null)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
 access jsonb;
 source_id uuid;
 new_id uuid;
 next_version integer;
 f record;
 new_field_id uuid;
begin
 access:=public.get_current_user_access();
 if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then raise exception 'Not authorized'; end if;
 if exists(select 1 from public.comp_hubspot_mapping_versions where status='draft') then raise exception 'A draft HubSpot compensation mapping already exists. Finish or retire it before creating another.'; end if;
 source_id:=source_mapping_version_id;
 if source_id is null then
   select id into source_id from public.comp_hubspot_mapping_versions where status='active' order by version_number desc limit 1;
   if source_id is null then select id into source_id from public.comp_hubspot_mapping_versions order by version_number desc limit 1; end if;
 end if;
 select coalesce(max(version_number),0)+1 into next_version from public.comp_hubspot_mapping_versions;
 insert into public.comp_hubspot_mapping_versions(version_number,status,notes,created_by)
 values(next_version,'draft',note,(select auth.uid())) returning id into new_id;
 if source_id is not null then
   insert into public.comp_hubspot_object_mappings(mapping_version_id,object_type,hubspot_object_type,is_eligible)
   select new_id,object_type,hubspot_object_type,is_eligible from public.comp_hubspot_object_mappings where mapping_version_id=source_id;
   for f in select * from public.comp_hubspot_field_mappings where mapping_version_id=source_id loop
     insert into public.comp_hubspot_field_mappings(mapping_version_id,object_type,property_name,is_eligible,value_policy)
     values(new_id,f.object_type,f.property_name,f.is_eligible,f.value_policy) returning id into new_field_id;
     insert into public.comp_hubspot_value_mappings(field_mapping_id,hubspot_value,context,is_eligible)
     select new_field_id,hubspot_value,context,is_eligible from public.comp_hubspot_value_mappings where field_mapping_id=f.id;
   end loop;
 end if;
 return new_id;
end;
$$;
revoke all on function public.create_hubspot_comp_mapping_version(uuid,text) from public,anon;
grant execute on function public.create_hubspot_comp_mapping_version(uuid,text) to authenticated;

create or replace function public.activate_hubspot_comp_mapping_version(target_mapping_version_id uuid, effective_at timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 access jsonb;
 target public.comp_hubspot_mapping_versions%rowtype;
 prior public.comp_hubspot_mapping_versions%rowtype;
 blocking integer;
begin
 access:=public.get_current_user_access();
 if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then raise exception 'Not authorized'; end if;
 select * into target from public.comp_hubspot_mapping_versions where id=target_mapping_version_id for update;
 if target.id is null then raise exception 'Mapping version not found'; end if;
 if target.status<>'draft' then raise exception 'Only draft mapping versions can be activated'; end if;
 select count(*) into blocking from public.comp_hubspot_config_changes where review_status='open' and severity in ('critical','action_required');
 if blocking>0 then raise exception 'Resolve % critical/action-required HubSpot configuration change(s) before activating this mapping version',blocking; end if;
 if not exists(select 1 from public.comp_hubspot_object_mappings where mapping_version_id=target.id and is_eligible) then raise exception 'At least one HubSpot object must be eligible'; end if;
 if not exists(select 1 from public.comp_hubspot_field_mappings where mapping_version_id=target.id and is_eligible) then raise exception 'At least one HubSpot field must be eligible'; end if;
 select * into prior from public.comp_hubspot_mapping_versions where status='active' order by version_number desc limit 1 for update;
 if prior.id is not null then
   update public.comp_hubspot_mapping_versions set status='retired',effective_to=effective_at where id=prior.id;
 end if;
 update public.comp_hubspot_mapping_versions set status='active',effective_from=effective_at,effective_to=null,activated_by=(select auth.uid()),activated_at=now() where id=target.id;
 return jsonb_build_object('activated_mapping_version_id',target.id,'version_number',target.version_number,'effective_from',effective_at,'retired_mapping_version_id',prior.id);
end;
$$;
revoke all on function public.activate_hubspot_comp_mapping_version(uuid,timestamptz) from public,anon;
grant execute on function public.activate_hubspot_comp_mapping_version(uuid,timestamptz) to authenticated;

create or replace function public.retire_hubspot_comp_mapping_draft(target_mapping_version_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare access jsonb; target public.comp_hubspot_mapping_versions%rowtype; begin
 access:=public.get_current_user_access();
 if coalesce((access->>'authenticated')::boolean,false) is not true or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then raise exception 'Not authorized'; end if;
 select * into target from public.comp_hubspot_mapping_versions where id=target_mapping_version_id for update;
 if target.id is null then raise exception 'Mapping version not found'; end if;
 if target.status<>'draft' then raise exception 'Only draft mapping versions can be retired without activation'; end if;
 update public.comp_hubspot_mapping_versions set status='retired',effective_to=now(),notes=concat_ws(E'\n',notes,case when reason is null then null else 'Retired draft: '||reason end) where id=target.id;
 return jsonb_build_object('retired_mapping_version_id',target.id,'version_number',target.version_number);
end;
$$;
revoke all on function public.retire_hubspot_comp_mapping_draft(uuid,text) from public,anon;
grant execute on function public.retire_hubspot_comp_mapping_draft(uuid,text) to authenticated;
