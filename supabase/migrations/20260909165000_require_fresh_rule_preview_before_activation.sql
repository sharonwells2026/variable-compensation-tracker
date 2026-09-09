-- Require a successful, fresh HubSpot preview before a rule version can be activated.

create table if not exists public.comp_rule_set_preview_runs (
  id uuid primary key default gen_random_uuid(),
  rule_set_id uuid not null references public.comp_rule_sets(id) on delete cascade,
  previewed_by uuid,
  rule_updated_at timestamptz not null,
  supported boolean not null,
  scanned_count integer,
  matched_count integer,
  sample_count integer,
  result jsonb not null default '{}'::jsonb,
  previewed_at timestamptz not null default now()
);

create index if not exists comp_rule_set_preview_runs_rule_set_previewed_idx
  on public.comp_rule_set_preview_runs(rule_set_id, previewed_at desc);

alter table public.comp_rule_set_preview_runs enable row level security;
revoke all on table public.comp_rule_set_preview_runs from public, anon, authenticated;

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
    and (object_type<>'deal' or jsonb_array_length(coalesce(association_path,'[]'::jsonb))>0);

  if unsupported>0 then
    result:=jsonb_build_object(
      'supported',false,
      'reason','This preview currently supports Deal predicates only. Associated-object predicates are saved correctly but require the association evaluator.',
      'unsupported_predicates',unsupported
    );
    insert into public.comp_rule_set_preview_runs(rule_set_id,previewed_by,rule_updated_at,supported,result)
    values(s.id,(select auth.uid()),s.updated_at,false,result);
    return result;
  end if;

  select id into root_id
  from public.comp_rule_expression_nodes
  where rule_set_id=target_rule_set_id and parent_node_id is null
  limit 1;
  if root_id is null then raise exception 'Rule set has no root expression'; end if;

  for d in
    select id,hubspot_deal_id,deal_name,close_date,hubspot_deal_type,amount,hubspot_stage_id,hubspot_owner_id,hubspot_record_url
    from public.hubspot_deals
    order by close_date desc nulls last,deal_name
  loop
    scanned:=scanned+1;
    if public.comp_rule_evaluate_deal_node(root_id,d.id) then
      matched:=matched+1;
      if jsonb_array_length(samples)<limit_count then
        samples:=samples||jsonb_build_array(jsonb_build_object(
          'hubspot_deal_id',d.hubspot_deal_id,
          'deal_name',d.deal_name,
          'close_date',d.close_date,
          'deal_type',d.hubspot_deal_type,
          'amount',d.amount,
          'stage_id',d.hubspot_stage_id,
          'owner_id',d.hubspot_owner_id,
          'record_url',d.hubspot_record_url
        ));
      end if;
    end if;
  end loop;

  result:=jsonb_build_object(
    'supported',true,
    'scanned_count',scanned,
    'matched_count',matched,
    'sample_count',jsonb_array_length(samples),
    'samples',samples
  );

  insert into public.comp_rule_set_preview_runs(
    rule_set_id,previewed_by,rule_updated_at,supported,scanned_count,matched_count,sample_count,result
  ) values(
    s.id,(select auth.uid()),s.updated_at,true,scanned,matched,jsonb_array_length(samples),result
  );

  return result;
end;
$$;

revoke all on function public.preview_comp_rule_set(uuid,integer) from public,anon;
grant execute on function public.preview_comp_rule_set(uuid,integer) to authenticated;

create or replace function public.validate_comp_rule_set_for_activation(target_rule_set_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  access jsonb;
  s public.comp_rule_sets%rowtype;
  issues jsonb := '[]'::jsonb;
  root_count integer;
  predicate_count integer;
  referenced_count integer;
  invalid_field_count integer;
  invalid_operator_count integer;
  latest_preview public.comp_rule_set_preview_runs%rowtype;
  preview_ready boolean:=false;
begin
  access:=public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to validate compensation plan rules';
  end if;

  select * into s from public.comp_rule_sets where id=target_rule_set_id;
  if s.id is null then raise exception 'Rule set not found'; end if;

  select count(*) into predicate_count from public.comp_rule_predicates where rule_set_id=s.id;
  select count(*) into root_count from public.comp_rule_expression_nodes where rule_set_id=s.id and parent_node_id is null;
  select count(distinct predicate_id) into referenced_count from public.comp_rule_expression_nodes where rule_set_id=s.id and node_type='predicate';
  select count(*) into invalid_field_count
    from public.comp_rule_predicates p
    left join public.comp_rule_field_catalog f on f.object_type=p.object_type and f.property_name=p.property_name and f.is_active
    where p.rule_set_id=s.id and f.id is null;
  select count(*) into invalid_operator_count
    from public.comp_rule_predicates p
    left join public.comp_rule_operator_catalog o on o.operator_key=p.operator_key and o.is_active
    where p.rule_set_id=s.id and o.operator_key is null;

  if predicate_count=0 then issues:=issues||jsonb_build_array('At least one predicate is required.'); end if;
  if root_count<>1 then issues:=issues||jsonb_build_array('Exactly one root expression group is required.'); end if;
  if referenced_count=0 then issues:=issues||jsonb_build_array('The expression must reference at least one predicate.'); end if;
  if referenced_count<predicate_count then issues:=issues||jsonb_build_array('Every defined predicate must be referenced by the expression.'); end if;
  if invalid_field_count>0 then issues:=issues||jsonb_build_array(invalid_field_count||' predicate(s) use an unavailable field.'); end if;
  if invalid_operator_count>0 then issues:=issues||jsonb_build_array(invalid_operator_count||' predicate(s) use an unavailable operator.'); end if;

  select * into latest_preview
  from public.comp_rule_set_preview_runs
  where rule_set_id=s.id
  order by previewed_at desc
  limit 1;

  if latest_preview.id is null or latest_preview.rule_updated_at < s.updated_at then
    issues:=issues||jsonb_build_array('Preview this version against current HubSpot data after the latest edit.');
  elsif latest_preview.supported is not true then
    issues:=issues||jsonb_build_array('The latest preview cannot evaluate all predicates yet.');
  elsif coalesce(latest_preview.scanned_count,0)=0 then
    issues:=issues||jsonb_build_array('The latest preview scanned no synced HubSpot deals.');
  else
    preview_ready:=true;
  end if;

  return jsonb_build_object(
    'rule_set_id',s.id,
    'version',s.version,
    'is_active',s.is_active,
    'ready',jsonb_array_length(issues)=0,
    'issues',issues,
    'predicate_count',predicate_count,
    'referenced_predicate_count',referenced_count,
    'root_count',root_count,
    'preview_ready',preview_ready,
    'previewed_at',case when latest_preview.id is null then null else latest_preview.previewed_at end,
    'preview_scanned_count',case when latest_preview.id is null then null else latest_preview.scanned_count end,
    'preview_matched_count',case when latest_preview.id is null then null else latest_preview.matched_count end
  );
end;
$$;

revoke all on function public.validate_comp_rule_set_for_activation(uuid) from public,anon;
grant execute on function public.validate_comp_rule_set_for_activation(uuid) to authenticated;
