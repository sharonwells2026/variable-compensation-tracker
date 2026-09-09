update public.comp_rule_field_catalog
set data_type='enumeration',
    options='[{"label":"GovAffairs","value":"20788895"},{"label":"MEams","value":"56062501"}]'::jsonb,
    is_multi_value=false,
    updated_at=now()
where object_type='deal' and property_name='pipeline';

update public.comp_rule_field_catalog
set data_type='object_id',
    options='[]'::jsonb,
    is_multi_value=false,
    updated_at=now()
where object_type='deal' and property_name='hs_object_id';

update public.comp_rule_field_catalog
set data_type='enumeration',
    options='[{"label":"New Business","value":"newbusiness"},{"label":"Renewal","value":"Renewal"},{"label":"Existing Business","value":"existingbusiness"},{"label":"One-time Fees","value":"One-time Fees"},{"label":"Churn","value":"Churn"}]'::jsonb,
    is_multi_value=false,
    updated_at=now()
where object_type='deal' and property_name='dealtype';

update public.comp_rule_field_catalog
set is_active=false, updated_at=now()
where object_type='deal' and property_name in ('opportunity_type','customer_success_manager');
