-- Canonical mutually-exclusive new-logo attribution treatment for Sharon historical stress testing.
-- Prevent direct-AE and company override double counting on the same deal.
create or replace view public.comp_new_logo_attribution_conflicts_v1
with (security_invoker=true)
as
select d.hubspot_deal_id,d.deal_name,d.close_date,d.hubspot_pipeline_id,d.hubspot_owner_id,
       e.id employee_id,e.full_name,
       case when d.hubspot_pipeline_id='20788895' and d.hubspot_owner_id=e.hubspot_owner_id then 'direct_ae'
            when d.hubspot_pipeline_id='20788895' then 'company_override_non_ae'
            when d.hubspot_pipeline_id='56062501' then 'company_override' end intended_treatment,
       case when d.hubspot_pipeline_id='20788895' and d.hubspot_owner_id=e.hubspot_owner_id
              then array['SHARON_NON_MEAMS_AE_NEW_LOGO']
            when d.hubspot_pipeline_id='20788895' then array['SHARON_GA_NEW_LOGO_OVERRIDE']
            when d.hubspot_pipeline_id='56062501' then array['SHARON_MEAMS_NEW_LOGO_OVERRIDE'] end allowed_components,
       'New-logo components are mutually exclusive per employee/deal. Direct AE credit replaces the GovAffairs non-AE override; MEams uses its own company-wide override.' review_rule
from public.hubspot_deals d cross join public.employees e
where e.id='a7bc17fb-3e03-4be6-b614-f81b278d4713'
and d.hubspot_deal_type='newbusiness'
and d.hubspot_pipeline_id in ('20788895','56062501')
and d.hubspot_stage_id in ('110553179','110577979','110609073','110691177','111910703','111970621','111910704','111910705')
and d.close_date>='2023-04-01';

comment on view public.comp_new_logo_attribution_conflicts_v1 is
'Mutually-exclusive new-logo attribution treatment. Direct AE credit replaces GovAffairs non-AE override on the same employee/deal.';
grant select on public.comp_new_logo_attribution_conflicts_v1 to authenticated;
