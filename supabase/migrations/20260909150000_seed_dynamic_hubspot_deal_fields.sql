-- Seed currently synchronized HubSpot Deal properties into the rule catalog.
-- This is metadata only and does not change HubSpot or compensation earnings.
with property_values as (
  select e.key as property_name,e.value as property_value
  from public.hubspot_deals d
  cross join lateral jsonb_each_text(coalesce(d.raw_hubspot_data->'properties','{}'::jsonb)) e
  where e.key is not null and btrim(e.key)<>''
), inferred as (
  select property_name,
    count(*) filter(where property_value is not null and btrim(property_value)<>'') as populated_count,
    case
      when bool_and(property_value is null or btrim(property_value)='' or property_value ~ '^-?[0-9]+([.][0-9]+)?$') then 'number'
      when bool_and(property_value is null or btrim(property_value)='' or lower(property_value) in ('true','false')) then 'boolean'
      when property_name ilike '%date%' or property_name ilike '%time%' then 'datetime'
      else 'string'
    end as data_type
  from property_values group by property_name
)
insert into public.comp_rule_field_catalog(object_type,property_name,display_name,data_type,description,is_multi_value,is_active,source_system)
select 'deal',i.property_name,initcap(replace(replace(i.property_name,'__',' '),'_',' ')),i.data_type,
  'Discovered from the synchronized HubSpot deal property snapshot. Populated on '||i.populated_count||' local deal records.',false,true,'hubspot_snapshot'
from inferred i
on conflict(object_type,property_name) do update set is_active=true,updated_at=now();
