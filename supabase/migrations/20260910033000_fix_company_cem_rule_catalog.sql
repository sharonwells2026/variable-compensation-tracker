update public.comp_hubspot_user_fields
set hubspot_property_name = 'customer_experience_manager_id',
    display_name = 'Customer Experience Manager',
    updated_at = now()
where field_key = 'company_cem';

update public.comp_rule_field_catalog target
set data_type = 'user',
    display_name = 'Customer Experience Manager',
    options = source.options,
    description = 'Customer Experience Manager assigned to the company associated with the deal.',
    updated_at = now()
from public.comp_rule_field_catalog source
where target.object_type = 'company'
  and target.property_name = 'customer_experience_manager_id'
  and source.object_type = 'deal'
  and source.property_name = 'hubspot_owner_id'
  and jsonb_array_length(coalesce(source.options,'[]'::jsonb)) > 0;

update public.comp_rule_field_catalog
set is_active = false,
    updated_at = now()
where object_type = 'deal'
  and property_name = 'customer_success_manager'
  and source_system = 'hubspot_snapshot';
