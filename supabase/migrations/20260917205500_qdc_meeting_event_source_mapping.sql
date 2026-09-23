-- Promote HubSpot MEETING_EVENT to the authoritative QDC source.
-- The generic HubSpot sync prioritizes eligible mapped fields; these mappings ensure
-- QDC type/outcome/date/identity fields are fetched on the next authorized HubSpot resync.

insert into public.comp_hubspot_field_mappings(
  mapping_version_id,object_type,property_name,is_eligible,value_policy
)
select mv.id,'meeting_event',v.property_name,true,'all'
from public.comp_hubspot_mapping_versions mv
cross join (values
 ('hs_activity_type'),('hs_meeting_outcome'),('hs_meeting_start_time'),
 ('hs_timestamp'),('hubspot_owner_id'),('hs_meeting_calendar_event_hash'),
 ('hs_meeting_change_id'),('hs_meeting_title')
) v(property_name)
where mv.status='active'
on conflict(mapping_version_id,object_type,property_name)
do update set is_eligible=true,value_policy='all',updated_at=now();

comment on view public.comp_qdc_earning_candidates_v1 is
'Legacy QDC candidate bridge using deal.qdc_completed_date. Do not use as authoritative payout source after MEETING_EVENT fields are synchronized; meeting-level QDC candidates supersede this bridge.';
