-- Sharon Wells compensation must evaluate qualifying company sales regardless of HubSpot deal owner.
-- Deal owner remains context and can affect the applicable rate, but it is not the eligibility gate.

update public.comp_plan_components
set description = case component_code
  when 'SHARON_GA_NEW_LOGO_OVERRIDE' then 'Company-wide compensation on qualifying GovAffairs new-logo ARR. Deal owner is contextual and may determine the applicable rate; ownership does not determine whether Sharon participates.'
  when 'SHARON_MEAMS_NEW_LOGO_OVERRIDE' then 'Company-wide compensation on qualifying MEams new-logo ARR. Deal owner is contextual and may determine the applicable rate; ownership does not determine whether Sharon participates.'
  else description end,
    rule_configuration = rule_configuration || jsonb_build_object(
      'credit_scope','company_wide',
      'owner_is_eligibility_gate',false,
      'owner_is_rate_context',true,
      'source_system','hubspot'
    ),
    updated_at = now()
where component_code in ('SHARON_GA_NEW_LOGO_OVERRIDE','SHARON_MEAMS_NEW_LOGO_OVERRIDE');

-- Register the HubSpot fields needed to classify and reproduce compensation calculations.
insert into public.comp_hubspot_user_fields
  (field_key,display_name,object_type,hubspot_property_name,description,is_active,calculation_order)
values
  ('deal_owner','Deal Owner','deal','hubspot_owner_id','Context/attribution field. Never use by itself to exclude Sharon from company-wide new-sales compensation.',true,10),
  ('solutions_advisor','Solutions Advisor','deal','sales_account_executive__multi_year_deals_','Identifies Sharon/other solution advisor participation when a plan uses owner or advisor context to choose a rate.',true,20),
  ('business_development_owner','Business Development Owner','deal','business_development_owner','Preserves business-development attribution context.',true,30),
  ('deal_type','Deal Type','deal','dealtype','Classifies New Business, Expansion, Renewal and One-time Fees.',true,40),
  ('opportunity_type','Opportunity Type','deal','opportunity_type','Secondary HubSpot sale classification used when deal type alone is insufficient.',true,50),
  ('closed_won','Closed Won','deal','hs_is_closed_won','Authoritative closed-won indicator for compensation event qualification.',true,60),
  ('close_date','Close Date','deal','closedate','Compensation earning/event date input.',true,70),
  ('amount','Deal Amount','deal','amount','Fallback/source amount when a component explicitly uses deal amount.',true,80),
  ('amount_home_currency','Amount in Home Currency','deal','amount_in_home_currency','Normalized currency amount for auditable calculations.',true,90),
  ('new_business_arr','New Business ARR','deal','new_business_arr','Preferred new-business ARR basis where populated.',true,100),
  ('first_year_arr','First Year ARR','deal','first_year_arr','First-year recurring revenue basis and validation field.',true,110),
  ('average_arr','Average ARR','deal','average_arr','ARR basis used by historical Sharon new-logo components.',true,120),
  ('expansion_arr','Expansion ARR','deal','expansion_arr','Expansion compensation basis.',true,130),
  ('renewal_arr','Renewal ARR','deal','renewal_arr','Renewal modeling/reconciliation basis.',true,140),
  ('non_recurring_revenue','Non-recurring Revenue','deal','nrr__non_recurring_revenue_','Non-recurring/implementation fee basis.',true,150),
  ('one_time_fee','One-time Fee','deal','one_time_fee','One-time fee basis when populated separately.',true,160),
  ('booked_revenue','Booked Revenue','deal','booked_revenue','Revenue cross-check for reconciliation.',true,170),
  ('modules','Engagifii Modules','deal','engagifii_modules_of_interest','Determines product/module context such as MEams versus GovAffairs when needed.',true,180),
  ('product_line','Product Line','deal','product_line','Product-family classification and reconciliation context.',true,190),
  ('contract_term','Contract Term','deal','contract_term_deal','Contract term used for multi-year calculation logic.',true,200),
  ('term_years','Term Length Years','deal','term_length__in_years_','Normalized multi-year term input.',true,210),
  ('payment_frequency','Payment Frequency','deal','contract_term','Preserves payment/contract cadence where HubSpot stores it in the contract-term field.',true,220),
  ('invoice_paid_date','Invoice Paid Date','deal','invoice_paid_date','Customer-payment evidence for eligibility when the plan requires payment received.',true,230),
  ('qdc_completed_date','QDC Completed Date','deal','qdc_completed_date','QDC evidence when a deal-level QDC field is available.',true,240),
  ('signed_contract','Signed Contract','deal','signed_contract','Contract-signature evidence/reference.',true,250)
on conflict (field_key) do update
set display_name=excluded.display_name,
    object_type=excluded.object_type,
    hubspot_property_name=excluded.hubspot_property_name,
    description=excluded.description,
    is_active=excluded.is_active,
    calculation_order=excluded.calculation_order,
    updated_at=now();
