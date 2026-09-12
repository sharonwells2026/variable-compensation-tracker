create or replace function private.evaluate_hubspot_user_attribution(selected_employee_id uuid, selected_hubspot_deal_id text, selected_field_keys jsonb, selected_match_logic text default 'any')
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
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
  normalized_deal_owner text;
  normalized_solutions_advisor text;
  normalized_business_development_owner text;
  normalized_company_cem text;
  field_results jsonb := '[]'::jsonb;
  final_match boolean;
begin
  if selected_match_logic not in ('any','all','none') then raise exception 'Unsupported attribution match logic: %', selected_match_logic using errcode='22023'; end if;
  if jsonb_typeof(selected_fields) <> 'array' then raise exception 'HubSpot user field keys must be a JSON array.' using errcode='22023'; end if;
  select e.hubspot_owner_id into employee_owner_id from public.employees e where e.id=selected_employee_id and e.is_active=true;
  if employee_owner_id is null then return jsonb_build_object('matched',false,'status','missing_employee_hubspot_owner','employee_id',selected_employee_id); end if;
  select d.raw_hubspot_data->'properties',d.hubspot_owner_id,d.solutions_advisor_id,d.business_development_owner_id into deal_properties,normalized_deal_owner,normalized_solutions_advisor,normalized_business_development_owner from public.hubspot_deals d where d.hubspot_deal_id=selected_hubspot_deal_id;
  if deal_properties is null then return jsonb_build_object('matched',false,'status','deal_not_found','hubspot_deal_id',selected_hubspot_deal_id); end if;
  select association.hubspot_company_id into associated_company_id from public.hubspot_deal_company_associations association where association.hubspot_deal_id=selected_hubspot_deal_id order by association.is_primary desc,association.last_synced_at desc limit 1;
  if associated_company_id is not null then select company.raw_hubspot_data->'properties',company.customer_experience_manager_id into company_properties,normalized_company_cem from public.hubspot_companies company where company.hubspot_company_id=associated_company_id; end if;
  selected_field_count := jsonb_array_length(selected_fields);
  if selected_field_count=0 then return jsonb_build_object('matched',true,'status','no_user_field_requirement','match_logic',selected_match_logic,'employee_hubspot_owner_id',employee_owner_id,'field_results','[]'::jsonb); end if;
  for field_record in select registry.field_key,registry.display_name,registry.object_type,registry.hubspot_property_name from public.comp_hubspot_user_fields registry join jsonb_array_elements_text(selected_fields) selected on selected.value=registry.field_key where registry.is_active=true order by registry.calculation_order loop
    field_value := case field_record.field_key when 'deal_owner' then coalesce(normalized_deal_owner,deal_properties->>field_record.hubspot_property_name) when 'solutions_advisor' then coalesce(normalized_solutions_advisor,deal_properties->>field_record.hubspot_property_name) when 'business_development_owner' then coalesce(normalized_business_development_owner,deal_properties->>field_record.hubspot_property_name) when 'company_cem' then coalesce(normalized_company_cem,company_properties->>field_record.hubspot_property_name) else case when field_record.object_type='deal' then deal_properties->>field_record.hubspot_property_name when field_record.object_type='company' then company_properties->>field_record.hubspot_property_name else null end end;
    field_matched := field_value is not null and (field_value=employee_owner_id or employee_owner_id = any(regexp_split_to_array(field_value,'[;,]')));
    if field_matched then matched_field_count := matched_field_count+1; end if;
    field_results := field_results || jsonb_build_array(jsonb_build_object('field_key',field_record.field_key,'display_name',field_record.display_name,'object_type',field_record.object_type,'hubspot_property_name',field_record.hubspot_property_name,'hubspot_value',field_value,'employee_hubspot_owner_id',employee_owner_id,'matched',field_matched));
  end loop;
  if jsonb_array_length(field_results)<>selected_field_count then return jsonb_build_object('matched',false,'status','invalid_user_field_configuration','selected_field_count',selected_field_count,'recognized_field_count',jsonb_array_length(field_results),'field_results',field_results); end if;
  if selected_match_logic='all' then final_match := matched_field_count=selected_field_count; elsif selected_match_logic='none' then final_match := matched_field_count=0; else final_match := matched_field_count>0; end if;
  return jsonb_build_object('matched',final_match,'status','evaluated','match_logic',selected_match_logic,'selected_field_count',selected_field_count,'matched_field_count',matched_field_count,'employee_hubspot_owner_id',employee_owner_id,'hubspot_deal_id',selected_hubspot_deal_id,'hubspot_company_id',associated_company_id,'field_results',field_results);
end;
$$;
