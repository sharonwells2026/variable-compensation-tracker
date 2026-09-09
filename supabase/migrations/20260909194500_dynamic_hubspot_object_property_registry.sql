create table if not exists public.hubspot_object_definitions (
  hubspot_object_type text primary key,
  internal_object_key text not null unique,
  object_category text,
  description text,
  read_access text not null default 'UNKNOWN',
  write_access text not null default 'UNKNOWN',
  is_active boolean not null default true,
  source_system text not null default 'hubspot',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hubspot_property_definitions (
  id uuid primary key default gen_random_uuid(),
  hubspot_object_type text not null references public.hubspot_object_definitions(hubspot_object_type) on delete cascade,
  internal_object_key text not null,
  property_name text not null,
  display_label text not null,
  property_type text not null,
  field_type text,
  description text,
  group_name text,
  is_hidden boolean not null default false,
  is_archived boolean not null default false,
  is_calculated boolean not null default false,
  has_unique_value boolean not null default false,
  external_options boolean not null default false,
  options jsonb not null default '[]'::jsonb,
  raw_definition jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(hubspot_object_type,property_name)
);
create index if not exists hubspot_property_definitions_internal_idx on public.hubspot_property_definitions(internal_object_key,property_name);

alter table public.hubspot_object_definitions enable row level security;
alter table public.hubspot_property_definitions enable row level security;
revoke all on public.hubspot_object_definitions from public,anon,authenticated;
revoke all on public.hubspot_property_definitions from public,anon,authenticated;

insert into public.hubspot_object_definitions(hubspot_object_type,internal_object_key,object_category,description,read_access,write_access)
values
('p21125555_HCTIMELOG','p21125555_hctimelog','CUSTOM_OBJECTS',null,'AVAILABLE','AVAILABLE'),
('p21125555_events','p21125555_events','CUSTOM_OBJECTS','Conferences, meetings, and partnership events','AVAILABLE','AVAILABLE'),
('p21125555_meeting_records','p21125555_meeting_records','CUSTOM_OBJECTS','Structured record of each meeting with summary, outcomes, and next steps.','AVAILABLE','AVAILABLE'),
('APPOINTMENT','appointment','HUBSPOT_DEFINED_OBJECTS','Information about an encounter or service for an individual.','AVAILABLE','AVAILABLE'),
('BLOG_POST','blog_post','HUBSPOT_DEFINED_OBJECTS','Blog post content and metadata.','AVAILABLE','REQUIRES_PERMISSION_MODIFICATION'),
('CALL','call','HUBSPOT_DEFINED_OBJECTS','Log data on a single phone or video call.','AVAILABLE','AVAILABLE'),
('CAMPAIGN','campaign','HUBSPOT_DEFINED_OBJECTS','Strategic and time-bound marketing efforts.','AVAILABLE','AVAILABLE'),
('CART','cart','HUBSPOT_DEFINED_OBJECTS','Items within a customer cart.','AVAILABLE','NOT_AVAILABLE'),
('COMMERCE_PAYMENT','commerce_payment','HUBSPOT_DEFINED_OBJECTS','Track online and offline payments.','NOT_AVAILABLE','NOT_AVAILABLE'),
('COMPANY','company','HUBSPOT_DEFINED_OBJECTS','Any business with interactions related to a HubSpot user business.','AVAILABLE','AVAILABLE'),
('CONTACT','contact','HUBSPOT_DEFINED_OBJECTS','Any person who interacts with a HubSpot user business.','AVAILABLE','AVAILABLE'),
('CONTRACT','contract','HUBSPOT_DEFINED_OBJECTS','Committed revenue, products, billing, and payment terms.','NOT_AVAILABLE','NOT_AVAILABLE'),
('DEAL','deal','HUBSPOT_DEFINED_OBJECTS','Track progress, ownership, and details on a transaction.','AVAILABLE','AVAILABLE'),
('EMAIL','email','HUBSPOT_DEFINED_OBJECTS','One-to-one email communications.','AVAILABLE','AVAILABLE'),
('FORM','form','HUBSPOT_DEFINED_OBJECTS','Fields on a form.','AVAILABLE','NOT_AVAILABLE'),
('INVOICE','invoice','HUBSPOT_DEFINED_OBJECTS','Invoices issued to buyers.','AVAILABLE','NOT_AVAILABLE'),
('LANDING_PAGE','landing_page','HUBSPOT_DEFINED_OBJECTS','Landing page content and metadata.','AVAILABLE','AVAILABLE'),
('LEAD','lead','HUBSPOT_DEFINED_OBJECTS','Sales qualification leads.','AVAILABLE','AVAILABLE'),
('LINE_ITEM','line_item','HUBSPOT_DEFINED_OBJECTS','Products or services sold on transactions.','AVAILABLE','AVAILABLE'),
('MARKETING_EMAIL','marketing_email','HUBSPOT_DEFINED_OBJECTS','Bulk marketing emails.','AVAILABLE','AVAILABLE'),
('MARKETING_EVENT','marketing_event','HUBSPOT_DEFINED_OBJECTS','In-person or virtual promotional activities.','AVAILABLE','AVAILABLE'),
('MEETING_EVENT','meeting_event','HUBSPOT_DEFINED_OBJECTS','In-person and virtual meetings.','AVAILABLE','AVAILABLE'),
('NOTE','note','HUBSPOT_DEFINED_OBJECTS','Information stored alongside CRM records.','AVAILABLE','AVAILABLE'),
('OBJECT_LIST','object_list','HUBSPOT_DEFINED_OBJECTS','CRM record segments and lists.','AVAILABLE','NOT_AVAILABLE'),
('ORDER','order','HUBSPOT_DEFINED_OBJECTS','Finalized purchase transaction details.','NOT_AVAILABLE','NOT_AVAILABLE'),
('PARTNER_CLIENT','partner_client','HUBSPOT_DEFINED_OBJECTS','Partner and customer account relationships.','REQUIRES_ACCOUNT_MODIFICATION','NOT_AVAILABLE'),
('PAYMENT_LINK','payment_link','HUBSPOT_DEFINED_OBJECTS','Shareable links used to collect payments.','NOT_AVAILABLE','NOT_AVAILABLE'),
('PRODUCT','product','HUBSPOT_DEFINED_OBJECTS','Product catalog items.','AVAILABLE','AVAILABLE'),
('PROJECT','project','HUBSPOT_DEFINED_OBJECTS','Project management records.','AVAILABLE','AVAILABLE'),
('QUOTE','quote','HUBSPOT_DEFINED_OBJECTS','Proposed or actual line item prices.','AVAILABLE','NOT_AVAILABLE'),
('QUOTE_TEMPLATE','quote_template','HUBSPOT_DEFINED_OBJECTS','Quote formatting templates.','AVAILABLE','NOT_AVAILABLE'),
('SERVICE','service','HUBSPOT_DEFINED_OBJECTS','Intangible customer offerings.','AVAILABLE','AVAILABLE'),
('SITE_PAGE','site_page','HUBSPOT_DEFINED_OBJECTS','Website page content and metadata.','AVAILABLE','NOT_AVAILABLE'),
('SUBSCRIPTION','subscription','HUBSPOT_DEFINED_OBJECTS','Recurring revenue, billing, and payments.','AVAILABLE','NOT_AVAILABLE'),
('TASK','task','HUBSPOT_DEFINED_OBJECTS','Assignments and to-do items.','AVAILABLE','AVAILABLE'),
('TICKET','ticket','HUBSPOT_DEFINED_OBJECTS','Customer questions and support requests.','AVAILABLE','AVAILABLE'),
('USER','user','HUBSPOT_DEFINED_OBJECTS','HubSpot users.','AVAILABLE','NOT_AVAILABLE')
on conflict(hubspot_object_type) do update set
 internal_object_key=excluded.internal_object_key,object_category=excluded.object_category,description=excluded.description,
 read_access=excluded.read_access,write_access=excluded.write_access,is_active=true,last_seen_at=now(),updated_at=now();

create or replace function public.sync_hubspot_object_properties(target_hubspot_object_type text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $$
declare
 access jsonb;
 obj public.hubspot_object_definitions%rowtype;
 hubspot_key text;
 hubspot_response extensions.http_response;
 response_body jsonb;
 prop jsonb;
 opt jsonb;
 prop_count integer:=0;
 option_count integer:=0;
 prop_name text;
 prop_label text;
begin
 access:=public.get_current_user_access();
 if not private.can_edit_hubspot_comp_mapping(access) then raise exception 'Not authorized to refresh HubSpot property configuration'; end if;
 select * into obj from public.hubspot_object_definitions where hubspot_object_type=target_hubspot_object_type;
 if obj.hubspot_object_type is null then raise exception 'Unknown HubSpot object type %',target_hubspot_object_type; end if;
 if obj.read_access<>'AVAILABLE' then raise exception 'HubSpot object % is not readable with the current connection',target_hubspot_object_type; end if;
 select decrypted_secret into hubspot_key from vault.decrypted_secrets where name='hubspot_service_key' limit 1;
 if hubspot_key is null then raise exception 'The HubSpot service key was not found in Vault.'; end if;
 hubspot_response:=extensions.http((
   'GET','https://api.hubapi.com/crm/v3/properties/'||target_hubspot_object_type||'?archived=false',
   array[extensions.http_header('Authorization','Bearer '||hubspot_key),extensions.http_header('Accept','application/json')],null,null
 )::extensions.http_request);
 if hubspot_response.status<>200 then raise exception 'HubSpot returned HTTP % reading % properties: %',hubspot_response.status,target_hubspot_object_type,left(hubspot_response.content,500); end if;
 response_body:=hubspot_response.content::jsonb;
 update public.hubspot_property_definitions set is_active=false,updated_at=now() where hubspot_object_type=target_hubspot_object_type;

 for prop in select value from jsonb_array_elements(coalesce(response_body->'results','[]'::jsonb)) loop
   prop_name:=prop->>'name'; prop_label:=coalesce(nullif(prop->>'label',''),prop_name);
   insert into public.hubspot_property_definitions(
     hubspot_object_type,internal_object_key,property_name,display_label,property_type,field_type,description,group_name,
     is_hidden,is_archived,is_calculated,has_unique_value,external_options,options,raw_definition,is_active,first_seen_at,last_seen_at)
   values(obj.hubspot_object_type,obj.internal_object_key,prop_name,prop_label,coalesce(prop->>'type','string'),prop->>'fieldType',prop->>'description',prop->>'groupName',
     coalesce((prop->>'hidden')::boolean,false),coalesce((prop->>'archived')::boolean,false),coalesce((prop->>'calculated')::boolean,false),
     coalesce((prop->>'hasUniqueValue')::boolean,false),coalesce((prop->>'externalOptions')::boolean,false),coalesce(prop->'options','[]'::jsonb),prop,true,now(),now())
   on conflict(hubspot_object_type,property_name) do update set
     internal_object_key=excluded.internal_object_key,display_label=excluded.display_label,property_type=excluded.property_type,field_type=excluded.field_type,
     description=excluded.description,group_name=excluded.group_name,is_hidden=excluded.is_hidden,is_archived=excluded.is_archived,
     is_calculated=excluded.is_calculated,has_unique_value=excluded.has_unique_value,external_options=excluded.external_options,
     options=excluded.options,raw_definition=excluded.raw_definition,is_active=true,last_seen_at=now(),updated_at=now();
   prop_count:=prop_count+1;

   if prop_name not in ('pipeline','dealstage') then
     for opt in select value from jsonb_array_elements(coalesce(prop->'options','[]'::jsonb)) loop
       if coalesce(opt->>'value','')<>'' then
         insert into public.comp_hubspot_discovered_values(object_type,property_name,hubspot_value,display_label,context,is_active,first_seen_at,last_seen_at)
         values(obj.internal_object_key,prop_name,opt->>'value',coalesce(nullif(opt->>'label',''),opt->>'value'),'{}'::jsonb,not coalesce((opt->>'hidden')::boolean,false),now(),now())
         on conflict(object_type,property_name,hubspot_value,context) do update set
           display_label=excluded.display_label,is_active=excluded.is_active,last_seen_at=now();
         option_count:=option_count+1;
       end if;
     end loop;
   end if;
 end loop;
 update public.hubspot_object_definitions set last_seen_at=now(),updated_at=now() where hubspot_object_type=target_hubspot_object_type;
 return jsonb_build_object('hubspot_object_type',target_hubspot_object_type,'internal_object_key',obj.internal_object_key,'properties',prop_count,'enumeration_options',option_count,'synced_at',now());
end;
$$;
revoke all on function public.sync_hubspot_object_properties(text) from public,anon;
grant execute on function public.sync_hubspot_object_properties(text) to authenticated;

create or replace function public.get_hubspot_object_property_registry()
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare access jsonb; begin
 access:=public.get_current_user_access();
 if not private.can_view_hubspot_comp_mapping(access) then raise exception 'Not authorized to view HubSpot object/property registry'; end if;
 return jsonb_build_object(
  'objects',coalesce((select jsonb_agg(jsonb_build_object(
    'hubspot_object_type',o.hubspot_object_type,'internal_object_key',o.internal_object_key,'object_category',o.object_category,
    'description',o.description,'read_access',o.read_access,'write_access',o.write_access,'is_active',o.is_active,'last_seen_at',o.last_seen_at,
    'property_count',(select count(*) from public.hubspot_property_definitions p where p.hubspot_object_type=o.hubspot_object_type and p.is_active)
  ) order by o.object_category,o.hubspot_object_type) from public.hubspot_object_definitions o),'[]'::jsonb),
  'properties',coalesce((select jsonb_agg(jsonb_build_object(
    'hubspot_object_type',p.hubspot_object_type,'internal_object_key',p.internal_object_key,'property_name',p.property_name,
    'display_label',p.display_label,'property_type',p.property_type,'field_type',p.field_type,'description',p.description,'group_name',p.group_name,
    'is_hidden',p.is_hidden,'is_archived',p.is_archived,'external_options',p.external_options,'options',p.options,'is_active',p.is_active,'last_seen_at',p.last_seen_at
  ) order by p.hubspot_object_type,p.display_label) from public.hubspot_property_definitions p where p.is_active),'[]'::jsonb)
 );
end; $$;
revoke all on function public.get_hubspot_object_property_registry() from public,anon;
grant execute on function public.get_hubspot_object_property_registry() to authenticated;