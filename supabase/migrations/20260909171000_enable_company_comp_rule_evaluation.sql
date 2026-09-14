update public.comp_rule_object_catalog
set is_active = case when object_type in ('deal','company') then true else false end;

insert into public.comp_rule_field_catalog(object_type,property_name,display_name,data_type,description,options,is_multi_value,is_active,source_system)
values
 ('company','hubspot_company_id','Company ID','object_id','HubSpot company record ID','[]'::jsonb,false,true,'hubspot'),
 ('company','company_name','Company Name','string','Associated HubSpot company name','[]'::jsonb,false,true,'hubspot'),
 ('company','hubspot_owner_id','Company Owner','user','HubSpot owner ID for the associated company','[]'::jsonb,false,true,'hubspot'),
 ('company','customer_experience_manager_id','Customer Experience Manager','user','Customer Experience Manager ID on the associated company','[]'::jsonb,false,true,'hubspot'),
 ('company','customer_since','Customer Since','date','Date the associated company became a customer','[]'::jsonb,false,true,'hubspot'),
 ('company','customer_status','Customer Status','string','Customer status for the associated company','[]'::jsonb,false,true,'hubspot'),
 ('company','current_customer','Current Customer','string','Current customer value for the associated company','[]'::jsonb,false,true,'hubspot'),
 ('company','total_arr','Total ARR','number','Total ARR on the associated company','[]'::jsonb,false,true,'hubspot'),
 ('company','arr_2025','2025 ARR','number','2025 ARR on the associated company','[]'::jsonb,false,true,'hubspot'),
 ('company','annual_renewal_date','Annual Renewal Date','date','Annual renewal date for the associated company','[]'::jsonb,false,true,'hubspot'),
 ('company','cancellation_date','Cancellation Date','date','Cancellation date for the associated company','[]'::jsonb,false,true,'hubspot'),
 ('company','customer_end_date','Customer End Date','date','Customer end date for the associated company','[]'::jsonb,false,true,'hubspot')
on conflict (object_type,property_name) do update
set display_name=excluded.display_name,
    data_type=excluded.data_type,
    description=excluded.description,
    options=excluded.options,
    is_multi_value=excluded.is_multi_value,
    is_active=true,
    source_system=excluded.source_system,
    updated_at=now();

create or replace function public.comp_rule_company_property(target_company_record_id uuid,target_property_name text)
returns text
language plpgsql
stable security definer
set search_path=''
as $$
declare c public.hubspot_companies%rowtype;
begin
  select * into c from public.hubspot_companies where id=target_company_record_id;
  if c.id is null then return null; end if;
  return case target_property_name
    when 'hubspot_company_id' then c.hubspot_company_id
    when 'company_name' then c.company_name
    when 'hubspot_owner_id' then c.hubspot_owner_id
    when 'customer_experience_manager_id' then c.customer_experience_manager_id
    when 'customer_since' then c.customer_since::text
    when 'customer_status' then c.customer_status
    when 'current_customer' then c.current_customer
    when 'total_arr' then c.total_arr::text
    when 'arr_2025' then c.arr_2025::text
    when 'annual_renewal_date' then c.annual_renewal_date::text
    when 'cancellation_date' then c.cancellation_date::text
    when 'customer_end_date' then c.customer_end_date::text
    else null
  end;
end;
$$;
revoke all on function public.comp_rule_company_property(uuid,text) from public,anon,authenticated;

create or replace function public.comp_rule_evaluate_deal_node(target_node_id uuid,target_deal_record_id uuid)
returns boolean
language plpgsql
stable security definer
set search_path=''
as $$
declare
  n public.comp_rule_expression_nodes%rowtype;
  p public.comp_rule_predicates%rowtype;
  child record;
  company_record record;
  result boolean;
  child_result boolean;
  actual_value text;
  total_companies integer:=0;
  matched_companies integer:=0;
begin
  select * into n from public.comp_rule_expression_nodes where id=target_node_id;
  if n.id is null then return false; end if;

  if n.node_type='predicate' then
    select * into p from public.comp_rule_predicates where id=n.predicate_id;
    if p.id is null then return false; end if;
    if jsonb_array_length(coalesce(p.association_path,'[]'::jsonb))>0 then return false; end if;

    if p.object_type='deal' then
      actual_value:=public.comp_rule_deal_property(target_deal_record_id,p.property_name);
      result:=public.comp_rule_compare_value(actual_value,p.comparison_value_type,p.operator_key,p.comparison_value,p.case_sensitive,p.include_null_as_match);
    elsif p.object_type='company' then
      for company_record in
        select c.id
        from public.hubspot_deals d
        join public.hubspot_deal_company_associations a on a.hubspot_deal_id=d.hubspot_deal_id
        join public.hubspot_companies c on c.hubspot_company_id=a.hubspot_company_id
        where d.id=target_deal_record_id
      loop
        total_companies:=total_companies+1;
        actual_value:=public.comp_rule_company_property(company_record.id,p.property_name);
        if public.comp_rule_compare_value(actual_value,p.comparison_value_type,p.operator_key,p.comparison_value,p.case_sensitive,p.include_null_as_match) then
          matched_companies:=matched_companies+1;
        end if;
      end loop;
      result:=case coalesce(p.association_quantifier,'any')
        when 'all' then total_companies>0 and matched_companies=total_companies
        when 'none' then matched_companies=0
        else matched_companies>0
      end;
    else
      result:=false;
    end if;
  else
    if n.logical_operator='AND' then
      result:=true;
      for child in select id from public.comp_rule_expression_nodes where parent_node_id=n.id order by sort_order,created_at loop
        child_result:=public.comp_rule_evaluate_deal_node(child.id,target_deal_record_id);
        if not child_result then result:=false; exit; end if;
      end loop;
    else
      result:=false;
      for child in select id from public.comp_rule_expression_nodes where parent_node_id=n.id order by sort_order,created_at loop
        child_result:=public.comp_rule_evaluate_deal_node(child.id,target_deal_record_id);
        if child_result then result:=true; exit; end if;
      end loop;
    end if;
  end if;

  if n.negate then return not coalesce(result,false); end if;
  return coalesce(result,false);
end;
$$;

create or replace function public.preview_comp_rule_set(target_rule_set_id uuid, max_results integer default 25)
returns jsonb
language plpgsql
volatile security definer
set search_path=''
as $$
declare
  access jsonb;
  s public.comp_rule_sets%rowtype;
  root_id uuid;
  unsupported integer;
  d record;
  scanned integer:=0;
  matched integer:=0;
  samples jsonb:='[]'::jsonb;
  result jsonb;
  limit_count integer:=greatest(1,least(coalesce(max_results,25),100));
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to preview compensation plan rules';
  end if;
  select * into s from public.comp_rule_sets where id=target_rule_set_id;
  if s.id is null then raise exception 'Rule set not found'; end if;

  select count(*) into unsupported
  from public.comp_rule_predicates
  where rule_set_id=target_rule_set_id
    and (object_type not in ('deal','company') or jsonb_array_length(coalesce(association_path,'[]'::jsonb))>0);

  if unsupported>0 then
    result:=jsonb_build_object('supported',false,'reason','This preview currently supports Deal predicates and directly associated Company predicates only.','unsupported_predicates',unsupported);
    insert into public.comp_rule_set_preview_runs(rule_set_id,previewed_by,rule_updated_at,supported,result)
    values(s.id,(select auth.uid()),s.updated_at,false,result);
    return result;
  end if;

  select id into root_id from public.comp_rule_expression_nodes where rule_set_id=target_rule_set_id and parent_node_id is null limit 1;
  if root_id is null then raise exception 'Rule set has no root expression'; end if;

  for d in select id,hubspot_deal_id,deal_name,close_date,hubspot_deal_type,amount,hubspot_stage_id,hubspot_owner_id,hubspot_record_url from public.hubspot_deals order by close_date desc nulls last,deal_name loop
    scanned:=scanned+1;
    if public.comp_rule_evaluate_deal_node(root_id,d.id) then
      matched:=matched+1;
      if jsonb_array_length(samples)<limit_count then
        samples:=samples||jsonb_build_array(jsonb_build_object('hubspot_deal_id',d.hubspot_deal_id,'deal_name',d.deal_name,'close_date',d.close_date,'deal_type',d.hubspot_deal_type,'amount',d.amount,'stage_id',d.hubspot_stage_id,'owner_id',d.hubspot_owner_id,'record_url',d.hubspot_record_url));
      end if;
    end if;
  end loop;

  result:=jsonb_build_object('supported',true,'scanned_count',scanned,'matched_count',matched,'sample_count',jsonb_array_length(samples),'samples',samples);
  insert into public.comp_rule_set_preview_runs(rule_set_id,previewed_by,rule_updated_at,supported,scanned_count,matched_count,sample_count,result)
  values(s.id,(select auth.uid()),s.updated_at,true,scanned,matched,jsonb_array_length(samples),result);
  return result;
end;
$$;
revoke all on function public.preview_comp_rule_set(uuid,integer) from public,anon;
grant execute on function public.preview_comp_rule_set(uuid,integer) to authenticated;
