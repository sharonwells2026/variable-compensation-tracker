create or replace function private.backfill_comp_rule_fields_for_mapped_object(
  target_object_type text,
  target_hubspot_object_type text
)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare affected integer:=0;
begin
  insert into public.comp_rule_field_catalog(
    object_type,property_name,display_name,data_type,description,options,is_multi_value,is_active,source_system
  )
  select p.internal_object_key,p.property_name,coalesce(nullif(p.display_label,''),initcap(replace(p.property_name,'_',' '))),
    case p.property_type when 'bool' then 'boolean' when 'date' then 'date' when 'datetime' then 'datetime' when 'number' then 'number' when 'enumeration' then case when p.field_type in ('checkbox','multiplecheckbox') then 'multi_enumeration' else 'enumeration' end else 'string' end,
    p.description,coalesce(p.options,'[]'::jsonb),p.field_type in ('checkbox','multiplecheckbox'),p.is_active,'hubspot_sync_auto'
  from public.hubspot_property_definitions p
  where p.internal_object_key=target_object_type and p.hubspot_object_type=target_hubspot_object_type and p.is_active=true
  on conflict(object_type,property_name) do update set is_active=true,updated_at=now();
  get diagnostics affected=row_count;
  return affected;
end;
$$;

revoke all on function private.backfill_comp_rule_fields_for_mapped_object(text,text) from public,anon,authenticated;

create or replace function private.sync_comp_rule_fields_when_object_mapped()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.is_eligible=true and new.hubspot_object_type is not null then
    perform private.backfill_comp_rule_fields_for_mapped_object(new.object_type,new.hubspot_object_type);
  end if;
  return new;
end;
$$;

revoke all on function private.sync_comp_rule_fields_when_object_mapped() from public,anon,authenticated;

drop trigger if exists sync_comp_rule_fields_when_object_mapped on public.comp_hubspot_object_mappings;
create trigger sync_comp_rule_fields_when_object_mapped
after insert or update of object_type,hubspot_object_type,is_eligible
on public.comp_hubspot_object_mappings
for each row execute function private.sync_comp_rule_fields_when_object_mapped();