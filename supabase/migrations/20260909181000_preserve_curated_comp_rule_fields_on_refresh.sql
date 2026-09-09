update public.comp_rule_field_catalog
set source_system='hubspot_curated', updated_at=now()
where object_type='deal' and property_name in ('pipeline','hs_object_id','dealtype','opportunity_type');

create or replace function public.refresh_comp_rule_deal_field_catalog()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare access jsonb; discovered integer:=0;
begin
 access:=public.get_current_user_access();
 if coalesce((access->>'authenticated')::boolean,false) is not true
    or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
   raise exception 'Not authorized to refresh compensation rule fields';
 end if;

 with property_values as (
  select e.key property_name,e.value property_value
  from public.hubspot_deals d
  cross join lateral jsonb_each_text(coalesce(d.raw_hubspot_data->'properties','{}'::jsonb)) e
  where e.key is not null and btrim(e.key)<>''
 ), inferred as (
  select property_name,
         count(*) filter(where property_value is not null and btrim(property_value)<>'') populated_count,
         case
           when bool_and(property_value is null or btrim(property_value)='' or property_value ~ '^-?[0-9]+([.][0-9]+)?$') then 'number'
           when bool_and(property_value is null or btrim(property_value)='' or lower(property_value) in ('true','false')) then 'boolean'
           when property_name ilike '%date%' or property_name ilike '%time%' then 'datetime'
           else 'string'
         end data_type
  from property_values
  group by property_name
 ), inserted as (
  insert into public.comp_rule_field_catalog(
    object_type,property_name,display_name,data_type,description,is_multi_value,is_active,source_system
  )
  select 'deal',i.property_name,
         initcap(replace(replace(i.property_name,'__',' '),'_',' ')),
         i.data_type,
         'Discovered from the synchronized HubSpot deal property snapshot. Populated on '||i.populated_count||' local deal records.',
         false,true,'hubspot_snapshot'
  from inferred i
  where i.populated_count>0
  on conflict(object_type,property_name) do update
    set is_active=case
          when public.comp_rule_field_catalog.source_system='hubspot_snapshot' then true
          else public.comp_rule_field_catalog.is_active
        end,
        data_type=case
          when public.comp_rule_field_catalog.source_system='hubspot_snapshot' then excluded.data_type
          else public.comp_rule_field_catalog.data_type
        end,
        description=case
          when public.comp_rule_field_catalog.source_system='hubspot_snapshot' then excluded.description
          else public.comp_rule_field_catalog.description
        end,
        updated_at=now()
  returning id
 ) select count(*) into discovered from inserted;

 return jsonb_build_object(
   'catalog_count',(select count(*) from public.comp_rule_field_catalog where object_type='deal' and is_active),
   'discovered_or_refreshed',discovered,
   'source','local synchronized HubSpot deal snapshot'
 );
end;
$$;

revoke all on function public.refresh_comp_rule_deal_field_catalog() from public,anon;
grant execute on function public.refresh_comp_rule_deal_field_catalog() to authenticated;
