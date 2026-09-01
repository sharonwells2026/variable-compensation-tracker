-- 100C - Generic HubSpot User Attribution Framework

create table if not exists public.comp_hubspot_user_fields (
  field_key text primary key,
  display_name text not null,
  object_type text not null check (object_type in ('deal','company')),
  hubspot_property_name text not null,
  description text,
  is_active boolean not null default true,
  calculation_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comp_hubspot_user_fields_order_check check (calculation_order > 0)
);

insert into public.comp_hubspot_user_fields(field_key,display_name,object_type,hubspot_property_name,description,calculation_order)
values
('deal_owner','Deal Owner','deal','hubspot_owner_id','Employee matches the HubSpot owner assigned directly to the deal.',10),
('company_cem','Company CEM','company','customer_success_manager','Employee matches the Customer Experience Manager on the company associated with the deal.',20)
on conflict (field_key) do update set
  display_name=excluded.display_name,
  object_type=excluded.object_type,
  hubspot_property_name=excluded.hubspot_property_name,
  description=excluded.description,
  calculation_order=excluded.calculation_order,
  updated_at=now();

create table if not exists public.comp_user_attribution_rules (
  id uuid primary key default gen_random_uuid(),
  plan_component_id uuid not null references public.comp_plan_components(id) on delete cascade,
  attribution_purpose text not null default 'earning' check (attribution_purpose in ('earning','metric')),
  metric_key text,
  hubspot_user_field_keys jsonb not null default '[]'::jsonb,
  match_logic text not null default 'any' check (match_logic in ('any','all')),
  credit_percentage numeric not null default 100,
  qualifying_pipeline_ids jsonb not null default '[]'::jsonb,
  qualifying_deal_types jsonb not null default '[]'::jsonb,
  priority integer not null default 100,
  allow_stacking boolean not null default false,
  rule_configuration jsonb not null default '{}'::jsonb,
  effective_start_date date not null default current_date,
  effective_end_date date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comp_user_attribution_rules_credit_check check (credit_percentage >= 0 and credit_percentage <= 100),
  constraint comp_user_attribution_rules_priority_check check (priority > 0),
  constraint comp_user_attribution_rules_dates_check check (effective_end_date is null or effective_end_date >= effective_start_date),
  constraint comp_user_attribution_rules_fields_array_check check (jsonb_typeof(hubspot_user_field_keys)='array'),
  constraint comp_user_attribution_rules_pipeline_array_check check (jsonb_typeof(qualifying_pipeline_ids)='array'),
  constraint comp_user_attribution_rules_deal_type_array_check check (jsonb_typeof(qualifying_deal_types)='array')
);

create index if not exists idx_comp_user_attribution_rules_component
on public.comp_user_attribution_rules(plan_component_id,attribution_purpose,is_active,priority);

create or replace function private.evaluate_hubspot_user_attribution(
  selected_employee_id uuid,
  selected_hubspot_deal_id text,
  selected_field_keys jsonb,
  selected_match_logic text default 'any'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  employee_owner_id text;
  selected_fields jsonb := coalesce(selected_field_keys,'[]'::jsonb);
  selected_field_count integer;
  matched_field_count integer := 0;
  field_record record;
  field_value text;
  field_matched boolean;
  associated_company_id text;
  deal_properties jsonb;
  company_properties jsonb;
  field_results jsonb := '[]'::jsonb;
  final_match boolean;
begin
  if selected_match_logic not in ('any','all') then
    raise exception 'Unsupported attribution match logic: %', selected_match_logic using errcode='22023';
  end if;
  if jsonb_typeof(selected_fields) <> 'array' then
    raise exception 'HubSpot user field keys must be a JSON array.' using errcode='22023';
  end if;
  select e.hubspot_owner_id into employee_owner_id
  from public.employees e where e.id=selected_employee_id and e.is_active=true;
  if employee_owner_id is null then
    return jsonb_build_object('matched',false,'status','missing_employee_hubspot_owner','employee_id',selected_employee_id);
  end if;
  select d.raw_hubspot_data->'properties' into deal_properties
  from public.hubspot_deals d where d.hubspot_deal_id=selected_hubspot_deal_id;
  if deal_properties is null then
    return jsonb_build_object('matched',false,'status','deal_not_found','hubspot_deal_id',selected_hubspot_deal_id);
  end if;
  select association.hubspot_company_id into associated_company_id
  from public.hubspot_deal_company_associations association
  where association.hubspot_deal_id=selected_hubspot_deal_id
  order by association.is_primary desc, association.last_synced_at desc limit 1;
  if associated_company_id is not null then
    select company.raw_hubspot_data->'properties' into company_properties
    from public.hubspot_companies company where company.hubspot_company_id=associated_company_id;
  end if;
  selected_field_count := jsonb_array_length(selected_fields);
  if selected_field_count=0 then
    return jsonb_build_object('matched',true,'status','no_user_field_requirement','match_logic',selected_match_logic,'employee_hubspot_owner_id',employee_owner_id,'field_results','[]'::jsonb);
  end if;
  for field_record in
    select registry.field_key,registry.display_name,registry.object_type,registry.hubspot_property_name
    from public.comp_hubspot_user_fields registry
    join jsonb_array_elements_text(selected_fields) selected on selected.value=registry.field_key
    where registry.is_active=true order by registry.calculation_order
  loop
    if field_record.object_type='deal' then
      field_value := deal_properties->>field_record.hubspot_property_name;
    elsif field_record.object_type='company' then
      field_value := company_properties->>field_record.hubspot_property_name;
    else
      field_value := null;
    end if;
    field_matched := field_value is not null and (field_value=employee_owner_id or employee_owner_id = any(regexp_split_to_array(field_value,'[;,]')));
    if field_matched then matched_field_count := matched_field_count + 1; end if;
    field_results := field_results || jsonb_build_array(jsonb_build_object(
      'field_key',field_record.field_key,'display_name',field_record.display_name,'object_type',field_record.object_type,
      'hubspot_property_name',field_record.hubspot_property_name,'hubspot_value',field_value,
      'employee_hubspot_owner_id',employee_owner_id,'matched',field_matched));
  end loop;
  if jsonb_array_length(field_results) <> selected_field_count then
    return jsonb_build_object('matched',false,'status','invalid_user_field_configuration','selected_field_count',selected_field_count,'recognized_field_count',jsonb_array_length(field_results),'field_results',field_results);
  end if;
  if selected_match_logic='all' then final_match := matched_field_count=selected_field_count; else final_match := matched_field_count>0; end if;
  return jsonb_build_object('matched',final_match,'status','evaluated','match_logic',selected_match_logic,
    'selected_field_count',selected_field_count,'matched_field_count',matched_field_count,
    'employee_hubspot_owner_id',employee_owner_id,'hubspot_deal_id',selected_hubspot_deal_id,
    'hubspot_company_id',associated_company_id,'field_results',field_results);
end;
$function$;

revoke all on function private.evaluate_hubspot_user_attribution(uuid,text,jsonb,text) from public, anon, authenticated;
alter table public.comp_hubspot_user_fields enable row level security;
alter table public.comp_user_attribution_rules enable row level security;
