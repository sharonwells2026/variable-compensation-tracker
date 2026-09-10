update public.comp_rule_field_catalog
set display_name='Deal Type',
    description='The HubSpot deal type used to distinguish renewals, new business, expansions, and other deal categories.'
where object_type='deal' and property_name='dealtype';
