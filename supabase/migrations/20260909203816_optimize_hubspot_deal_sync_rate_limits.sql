create or replace function public.sync_hubspot_deals()
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions','vault'
as $$
declare
  hubspot_key text;
  sync_run_id uuid;
  request_item record;
  hubspot_response extensions.http_response;
  response_body jsonb;
  deal_record jsonb;
  deal_properties jsonb;
  after_cursor text;
  request_body jsonb;
  received_count integer := 0;
  created_count integer := 0;
  updated_count integer := 0;
  change_count integer := 0;
  deal_already_exists boolean;
  retry_count integer;
begin
  select decrypted_secret into hubspot_key
  from vault.decrypted_secrets
  where name = 'hubspot_service_key'
  limit 1;

  if hubspot_key is null then
    raise exception 'The HubSpot service key was not found in Vault.';
  end if;

  insert into public.hubspot_sync_runs (sync_type,status,started_at)
  values ('deals','running',now())
  returning id into sync_run_id;

  perform set_config('app.hubspot_sync_run_id',sync_run_id::text,true);

  for request_item in
    select deal_year,make_date(deal_year,1,1) as start_date,make_date(deal_year+1,1,1) as end_date
    from generate_series(2025,extract(year from current_date)::integer) as years(deal_year)
  loop
    after_cursor := null;
    loop
      request_body := jsonb_build_object(
        'filterGroups',jsonb_build_array(jsonb_build_object('filters',jsonb_build_array(
          jsonb_build_object('propertyName','closedate','operator','GTE','value',request_item.start_date::text || 'T00:00:00Z'),
          jsonb_build_object('propertyName','closedate','operator','LT','value',request_item.end_date::text || 'T00:00:00Z')
        ))),
        'properties',jsonb_build_array(
          'dealname','hubspot_owner_id','pipeline','dealstage','dealtype','opportunity_type','amount','amount_in_home_currency',
          'average_arr','first_year_arr','new_business_arr','expansion_arr','renewal_arr','nrr__non_recurring_revenue_','current_tcv','one_time_fee','one_time_fees','booked_revenue',
          'contract_term_deal','contract_term_months','contract_term_start_date','contract_term_end_dates','contract_term','term_length__in_years_',
          'signed_contract','subscription_updated_date','invoice_paid_date','closedate','hs_is_closed_won','engagifii_modules_of_interest','product_line',
          'sales_account_executive__multi_year_deals_','business_development_owner','qdc_completed_date'
        ),
        'sorts',jsonb_build_array('hs_object_id'),'limit',200
      );

      if after_cursor is not null then
        request_body := request_body || jsonb_build_object('after',after_cursor);
      end if;

      retry_count := 0;
      loop
        hubspot_response := extensions.http((
          'POST','https://api.hubapi.com/crm/v3/objects/deals/search',
          array[
            extensions.http_header('Authorization','Bearer ' || hubspot_key),
            extensions.http_header('Accept','application/json'),
            extensions.http_header('Content-Type','application/json')
          ],'application/json',request_body::text
        )::extensions.http_request);

        exit when hubspot_response.status = 200;
        if hubspot_response.status = 429 and retry_count < 5 then
          retry_count := retry_count + 1;
          perform pg_catalog.pg_sleep(least(8.0, power(2::numeric,retry_count-1)::numeric)::double precision);
        else
          raise exception 'HubSpot returned HTTP %: %',hubspot_response.status,left(hubspot_response.content,500);
        end if;
      end loop;

      response_body := hubspot_response.content::jsonb;

      for deal_record in select value from jsonb_array_elements(coalesce(response_body->'results','[]'::jsonb))
      loop
        deal_properties := coalesce(deal_record->'properties','{}'::jsonb);
        select exists(select 1 from public.hubspot_deals where hubspot_deal_id=deal_record->>'id') into deal_already_exists;

        insert into public.hubspot_deals (
          hubspot_deal_id,deal_name,hubspot_owner_id,hubspot_pipeline_id,hubspot_stage_id,hubspot_deal_type,amount,
          average_arr,first_year_arr,new_business_arr,expansion_arr,renewal_arr,non_recurring_revenue,opportunity_type,purchased_modules,
          solutions_advisor_id,business_development_owner_id,qdc_completed_date,is_closed_won,total_contract_value,one_time_fee,
          contract_term_label,contract_term_years,contract_term_months,contract_start_date,contract_end_date,payment_frequency,contract_url,
          subscription_updated_date,invoice_paid_date,close_date,raw_hubspot_data,hubspot_created_at,hubspot_updated_at,last_synced_at,source_fingerprint
        ) values (
          deal_record->>'id',coalesce(nullif(deal_properties->>'dealname',''),'(Unnamed deal)'),nullif(deal_properties->>'hubspot_owner_id',''),
          nullif(deal_properties->>'pipeline',''),nullif(deal_properties->>'dealstage',''),nullif(deal_properties->>'dealtype',''),
          nullif(deal_properties->>'amount','')::numeric,nullif(deal_properties->>'average_arr','')::numeric,
          nullif(deal_properties->>'first_year_arr','')::numeric,nullif(deal_properties->>'new_business_arr','')::numeric,
          nullif(deal_properties->>'expansion_arr','')::numeric,nullif(deal_properties->>'renewal_arr','')::numeric,
          nullif(deal_properties->>'nrr__non_recurring_revenue_','')::numeric,nullif(deal_properties->>'opportunity_type',''),
          nullif(deal_properties->>'engagifii_modules_of_interest',''),nullif(deal_properties->>'sales_account_executive__multi_year_deals_',''),
          nullif(deal_properties->>'business_development_owner',''),nullif(deal_properties->>'qdc_completed_date','')::date,
          case when lower(coalesce(deal_properties->>'hs_is_closed_won','false'))='true' then true else false end,
          nullif(deal_properties->>'current_tcv','')::numeric,
          coalesce(nullif(deal_properties->>'one_time_fee','')::numeric,nullif(deal_properties->>'one_time_fees','')::numeric),
          nullif(deal_properties->>'contract_term_deal',''),
          coalesce(
            case when nullif(deal_properties->>'contract_term_months','') is not null then (deal_properties->>'contract_term_months')::numeric/12 end,
            nullif(deal_properties->>'term_length__in_years_','')::numeric
          ),
          nullif(deal_properties->>'contract_term_months','')::integer,nullif(deal_properties->>'contract_term_start_date','')::date,
          nullif(deal_properties->>'contract_term_end_dates','')::date,nullif(deal_properties->>'contract_term',''),nullif(deal_properties->>'signed_contract',''),
          nullif(deal_properties->>'subscription_updated_date','')::date,nullif(deal_properties->>'invoice_paid_date','')::date,
          case when nullif(deal_properties->>'closedate','') is not null then (deal_properties->>'closedate')::timestamptz::date end,
          deal_record,nullif(deal_record->>'createdAt','')::timestamptz,nullif(deal_record->>'updatedAt','')::timestamptz,now(),md5(deal_record::text)
        )
        on conflict (hubspot_deal_id) do update set
          deal_name=excluded.deal_name,hubspot_owner_id=excluded.hubspot_owner_id,hubspot_pipeline_id=excluded.hubspot_pipeline_id,
          hubspot_stage_id=excluded.hubspot_stage_id,hubspot_deal_type=excluded.hubspot_deal_type,amount=excluded.amount,
          average_arr=excluded.average_arr,first_year_arr=excluded.first_year_arr,new_business_arr=excluded.new_business_arr,
          expansion_arr=excluded.expansion_arr,renewal_arr=excluded.renewal_arr,non_recurring_revenue=excluded.non_recurring_revenue,
          opportunity_type=excluded.opportunity_type,purchased_modules=excluded.purchased_modules,solutions_advisor_id=excluded.solutions_advisor_id,
          business_development_owner_id=excluded.business_development_owner_id,qdc_completed_date=excluded.qdc_completed_date,is_closed_won=excluded.is_closed_won,
          total_contract_value=excluded.total_contract_value,one_time_fee=excluded.one_time_fee,contract_term_label=excluded.contract_term_label,
          contract_term_years=excluded.contract_term_years,contract_term_months=excluded.contract_term_months,contract_start_date=excluded.contract_start_date,
          contract_end_date=excluded.contract_end_date,payment_frequency=excluded.payment_frequency,contract_url=excluded.contract_url,
          subscription_updated_date=excluded.subscription_updated_date,invoice_paid_date=excluded.invoice_paid_date,close_date=excluded.close_date,
          raw_hubspot_data=excluded.raw_hubspot_data,hubspot_created_at=excluded.hubspot_created_at,hubspot_updated_at=excluded.hubspot_updated_at,
          last_synced_at=excluded.last_synced_at,source_fingerprint=excluded.source_fingerprint,updated_at=now();

        received_count := received_count + 1;
        if deal_already_exists then updated_count := updated_count + 1; else created_count := created_count + 1; end if;
      end loop;

      after_cursor := response_body->'paging'->'next'->>'after';
      exit when after_cursor is null;
      perform pg_catalog.pg_sleep(0.25);
    end loop;
  end loop;

  select count(*) into change_count from public.hubspot_record_changes
  where hubspot_record_changes.sync_run_id = nullif(current_setting('app.hubspot_sync_run_id',true),'')::uuid;

  update public.hubspot_sync_runs set status='completed',completed_at=now(),deals_received=received_count,deals_created=created_count,
    deals_updated=updated_count,changes_detected=change_count where id=sync_run_id;

  return jsonb_build_object('sync_run_id',sync_run_id,'status','completed','deals_received',received_count,'deals_created',created_count,
    'deals_updated',updated_count,'changes_detected',change_count);
exception when others then
  if sync_run_id is not null then update public.hubspot_sync_runs set status='failed',completed_at=now(),error_message=sqlerrm where id=sync_run_id; end if;
  raise;
end;
$$;