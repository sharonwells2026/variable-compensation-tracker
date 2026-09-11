update public.comp_business_condition_settings
set
  display_name='Invoice Paid Date is known',
  description='An Earned item becomes Eligible for Payment when the HubSpot Deal Invoice Paid Date has a value.',
  configuration=jsonb_build_object(
    'logic','AND',
    'signals',jsonb_build_array(
      jsonb_build_object(
        'label','Invoice Paid Date is known',
        'object_type','deal',
        'operator_key','is_known',
        'property_name','invoice_paid_date'
      )
    )
  ),
  updated_at=now()
where business_concept='customer_payment_received';
