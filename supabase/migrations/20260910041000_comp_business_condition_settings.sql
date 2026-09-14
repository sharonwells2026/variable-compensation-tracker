create table if not exists public.comp_business_condition_settings (
  business_concept text primary key,
  display_name text not null,
  description text,
  configuration jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.comp_business_condition_settings enable row level security;

insert into public.comp_business_condition_settings(business_concept,display_name,description,configuration)
select 'customer_payment_received','The customer has paid','Defines the approved synchronized HubSpot evidence used to determine when an Earned item becomes Eligible because the customer has paid.',
       jsonb_build_object(
         'logic','AND',
         'signals',jsonb_build_array(
           jsonb_build_object('object_type','deal','property_name','dealstage','operator_key','is','value',dv.hubspot_value,'label',dv.display_label),
           jsonb_build_object('object_type','deal','property_name','invoice_paid_date','operator_key','is_known','label','Invoice Paid Date is known')
         )
       )
from public.comp_hubspot_discovered_values dv
where dv.object_type='deal' and dv.property_name='dealstage' and dv.is_active
  and lower(dv.display_label) like '%paid%'
order by case when lower(dv.display_label) like '%closed won%paid%' then 0 else 1 end, dv.display_label
limit 1
on conflict (business_concept) do nothing;

create or replace function public.get_comp_business_condition_settings()
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare access jsonb;
begin
 access:=public.get_current_user_access();
 if coalesce((access->>'authenticated')::boolean,false) is not true
    or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
   raise exception 'Not authorized to view compensation business conditions' using errcode='42501';
 end if;
 return coalesce((select jsonb_agg(to_jsonb(s) order by s.display_name) from public.comp_business_condition_settings s where s.is_active),'[]'::jsonb);
end;$$;

create or replace function public.save_comp_business_condition_setting(selected_business_concept text, selected_display_name text, selected_description text, selected_configuration jsonb)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare access jsonb; oldrow jsonb;
begin
 access:=public.get_current_user_access();
 if coalesce((access->>'authenticated')::boolean,false) is not true
    or not (coalesce(access->'permissions','[]'::jsonb) ? 'settings.manage') then
   raise exception 'Not authorized to edit compensation business conditions' using errcode='42501';
 end if;
 select to_jsonb(s) into oldrow from public.comp_business_condition_settings s where s.business_concept=selected_business_concept;
 insert into public.comp_business_condition_settings(business_concept,display_name,description,configuration,updated_by,updated_at)
 values (selected_business_concept,btrim(selected_display_name),nullif(btrim(coalesce(selected_description,'')),''),coalesce(selected_configuration,'{}'::jsonb),(select auth.uid()),now())
 on conflict(business_concept) do update set display_name=excluded.display_name,description=excluded.description,configuration=excluded.configuration,updated_by=excluded.updated_by,updated_at=now();
 insert into public.app_access_audit_events(actor_user_id,event_type,event_reason,old_state,new_state)
 values ((select auth.uid()),'comp_business_condition_setting_updated','Workspace compensation business-condition guidance/configuration was updated.',oldrow,(select to_jsonb(s) from public.comp_business_condition_settings s where s.business_concept=selected_business_concept));
 return (select to_jsonb(s) from public.comp_business_condition_settings s where s.business_concept=selected_business_concept);
end;$$;

revoke all on function public.get_comp_business_condition_settings() from public,anon;
revoke all on function public.save_comp_business_condition_setting(text,text,text,jsonb) from public,anon;
grant execute on function public.get_comp_business_condition_settings() to authenticated;
grant execute on function public.save_comp_business_condition_setting(text,text,text,jsonb) to authenticated;
