-- HubSpot-aware field metadata for the compensation rule builder.
-- Makes the UI type-aware and allows select/multi-select controls to use real portal values.

with field_updates(property_name,display_name,data_type,is_multi_value,options) as (
  values
    ('dealtype','Deal Type','enumeration',false,'[{"value":"newbusiness","label":"New Business"},{"value":"Renewal","label":"Renewal"},{"value":"existingbusiness","label":"Expansion"},{"value":"One-time Fees","label":"One-time Fees"},{"value":"Contraction","label":"Contraction"},{"value":"Churn","label":"Churn"},{"value":"Funding / Capital Investment","label":"Funding / Capital Investment"}]'::jsonb),
    ('opportunity_type','Opportunity Type','enumeration',false,'[{"value":"New Business","label":"New Business"},{"value":"Outyear","label":"Outyear"},{"value":"Renewal","label":"Renewal"}]'::jsonb),
    ('product_line','Product Line','enumeration',false,'[{"value":"Engagifii","label":"Engagifii"},{"value":"Capitol Impact","label":"Capitol Impact"},{"value":"Embr","label":"Embr"}]'::jsonb),
    ('contract_term_deal','Contract Term','enumeration',false,'[{"value":"1 Year","label":"1 Year"},{"value":"2 Years","label":"2 Years"},{"value":"3 Years","label":"3 Years"},{"value":"4 Years","label":"4 Years"},{"value":"5 Years","label":"5 Years"},{"value":"6 Years","label":"6 Years"},{"value":"7 Years","label":"7 Years"},{"value":"8 Years","label":"8 Years"},{"value":"9 Years","label":"9 Years"},{"value":"10 Years","label":"10 Years"},{"value":"One-Time Service","label":"One-Time Service"},{"value":"No Contract","label":"No Contract"}]'::jsonb),
    ('contract_term','Payment Frequency','enumeration',false,'[{"value":"Annual","label":"Paid Annually"},{"value":"Every 2 Years","label":"Every 2 Years"},{"value":"Every 3 Years","label":"Every 3 Years"},{"value":"Every 4 Years","label":"Every 4 Years"},{"value":"Every 5 Years","label":"Every 5 Years"},{"value":"Every 6 Years","label":"Every 6 Years"},{"value":"Monthly","label":"Monthly"},{"value":"Quarterly","label":"Quarterly"},{"value":"One-time payment","label":"One-time payment"}]'::jsonb),
    ('hs_is_closed_won','Is Closed Won','boolean',false,'[{"value":"true","label":"True"},{"value":"false","label":"False"}]'::jsonb),
    ('dealstage','Deal Stage','enumeration',false,'[{"value":"110553179","label":"Closed Won [Pending]"},{"value":"110577979","label":"Closed Won [Finance]"},{"value":"110609073","label":"Closed Won [Invoiced]"},{"value":"110691177","label":"Closed Won [Paid]"},{"value":"50124064","label":"Closed Lost"}]'::jsonb),
    ('hubspot_owner_id','Deal Owner','user',false,'[{"value":"144058288","label":"Sharon Wells"},{"value":"138861187","label":"Namit Bhatia"},{"value":"138329130","label":"Ben Laughter"},{"value":"672606066","label":"Matt Asevedo"},{"value":"460735627","label":"Monique Euell"},{"value":"84019989","label":"Wes Morris"},{"value":"95822372","label":"Rebecca Knight"}]'::jsonb),
    ('sales_account_executive__multi_year_deals_','Solutions Advisor','user',false,'[{"value":"144058288","label":"Sharon Wells"},{"value":"138861187","label":"Namit Bhatia"},{"value":"138329130","label":"Ben Laughter"},{"value":"672606066","label":"Matt Asevedo"},{"value":"460735627","label":"Monique Euell"},{"value":"84019989","label":"Wes Morris"},{"value":"95822372","label":"Rebecca Knight"}]'::jsonb),
    ('business_development_owner','Business Development Owner','user',false,'[{"value":"144058288","label":"Sharon Wells"},{"value":"138861187","label":"Namit Bhatia"},{"value":"138329130","label":"Ben Laughter"},{"value":"672606066","label":"Matt Asevedo"},{"value":"460735627","label":"Monique Euell"},{"value":"84019989","label":"Wes Morris"},{"value":"95822372","label":"Rebecca Knight"}]'::jsonb),
    ('engagifii_modules_of_interest','Purchased Modules','multi_enumeration',true,'[{"value":"Engagifii Relationships","label":"Engagifii Relationships"},{"value":"Engagifii Communications","label":"Engagifii Communications"},{"value":"Engagifii Revenue","label":"Engagifii Revenue"},{"value":"Engagifii Library","label":"Engagifii Library"},{"value":"Engagifii Events","label":"Engagifii Events"},{"value":"Engagifii Accreditation","label":"Engagifii Accreditation"},{"value":"Engagifii Legislative Tracking","label":"Engagifii Legislative Tracking"},{"value":"Engagifii Dues & Services","label":"Engagifii Dues & Services"},{"value":"Engagifii Legislative Tracking - Federal","label":"Engagifii Legislative Tracking - Federal"},{"value":"Engagifii Bill Compare","label":"Engagifii Bill Compare"},{"value":"Engagifii Geocoding","label":"Engagifii GeoConnect"},{"value":"Implementation","label":"Implementation"},{"value":"Integration - Constant Contact","label":"Integration - Constant Contact"},{"value":"Integration - Quickbooks","label":"Integration - Quickbooks"},{"value":"Integration - TalentLMS","label":"Integration - TalentLMS"}]'::jsonb)
)
update public.comp_rule_field_catalog f
set display_name=u.display_name,
    data_type=u.data_type,
    is_multi_value=u.is_multi_value,
    options=u.options,
    updated_at=now()
from field_updates u
where f.object_type='deal' and f.property_name=u.property_name;

-- Add commonly used HubSpot fields if they were not part of the earlier compensation field seed.
insert into public.comp_rule_field_catalog(object_type,property_name,display_name,data_type,description,options,is_multi_value,source_system)
values
 ('deal','dealstage','Deal Stage','enumeration','HubSpot deal stage.','[{"value":"110553179","label":"Closed Won [Pending]"},{"value":"110577979","label":"Closed Won [Finance]"},{"value":"110609073","label":"Closed Won [Invoiced]"},{"value":"110691177","label":"Closed Won [Paid]"},{"value":"50124064","label":"Closed Lost"}]'::jsonb,false,'hubspot'),
 ('deal','hs_is_closed_won','Is Closed Won','boolean','True when HubSpot considers the deal Closed Won.','[{"value":"true","label":"True"},{"value":"false","label":"False"}]'::jsonb,false,'hubspot')
on conflict (object_type,property_name) do update set
 display_name=excluded.display_name,data_type=excluded.data_type,description=excluded.description,
 options=excluded.options,is_multi_value=excluded.is_multi_value,is_active=true,updated_at=now();
