-- Robust compensation rule builder.
-- Supports reusable named predicates plus arbitrarily nested AND/OR/NOT expression trees.
-- Example: (Rule 1 AND Rule 2) OR (Rule 1 AND NOT Rule 3).

create table if not exists public.comp_rule_field_catalog (
  id uuid primary key default gen_random_uuid(),
  object_type text not null,
  property_name text not null,
  display_name text not null,
  data_type text not null default 'string',
  description text,
  options jsonb not null default '[]'::jsonb,
  is_multi_value boolean not null default false,
  is_active boolean not null default true,
  source_system text not null default 'hubspot',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(object_type,property_name)
);

create table if not exists public.comp_rule_operator_catalog (
  operator_key text primary key,
  display_name text not null,
  value_arity text not null check (value_arity in ('none','single','multiple','range')),
  supported_data_types jsonb not null default '[]'::jsonb,
  description text,
  sort_order integer not null default 100,
  is_active boolean not null default true
);

create table if not exists public.comp_rule_sets (
  id uuid primary key default gen_random_uuid(),
  plan_component_id uuid not null references public.comp_plan_components(id) on delete cascade,
  name text not null,
  purpose text not null check (purpose in ('qualification','rate_selection','calculation','eligibility','credit','payout','exception')),
  description text,
  evaluation_scope text not null default 'record' check (evaluation_scope in ('record','associated_records','aggregate')),
  version integer not null default 1,
  is_active boolean not null default true,
  stop_on_match boolean not null default false,
  outcome_configuration jsonb not null default '{}'::jsonb,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(plan_component_id,name,version)
);

create table if not exists public.comp_rule_predicates (
  id uuid primary key default gen_random_uuid(),
  rule_set_id uuid not null references public.comp_rule_sets(id) on delete cascade,
  rule_key text not null,
  display_name text not null,
  object_type text not null,
  association_path jsonb not null default '[]'::jsonb,
  property_name text not null,
  operator_key text not null references public.comp_rule_operator_catalog(operator_key),
  comparison_value jsonb,
  comparison_value_type text,
  case_sensitive boolean not null default false,
  include_null_as_match boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(rule_set_id,rule_key)
);

create table if not exists public.comp_rule_expression_nodes (
  id uuid primary key default gen_random_uuid(),
  rule_set_id uuid not null references public.comp_rule_sets(id) on delete cascade,
  parent_node_id uuid references public.comp_rule_expression_nodes(id) on delete cascade,
  node_type text not null check (node_type in ('group','predicate')),
  predicate_id uuid references public.comp_rule_predicates(id) on delete cascade,
  logical_operator text check (logical_operator in ('AND','OR')),
  negate boolean not null default false,
  sort_order integer not null default 0,
  label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (node_type='group' and predicate_id is null and logical_operator is not null)
    or
    (node_type='predicate' and predicate_id is not null and logical_operator is null)
  )
);

create index if not exists idx_comp_rule_sets_component on public.comp_rule_sets(plan_component_id,purpose,is_active);
create index if not exists idx_comp_rule_predicates_set on public.comp_rule_predicates(rule_set_id);
create index if not exists idx_comp_rule_nodes_set_parent on public.comp_rule_expression_nodes(rule_set_id,parent_node_id,sort_order);

insert into public.comp_rule_operator_catalog(operator_key,display_name,value_arity,supported_data_types,description,sort_order)
values
 ('is','is','single','["string","number","boolean","date","datetime","enumeration","user","object_id"]','Exact equality.',10),
 ('is_not','is not','single','["string","number","boolean","date","datetime","enumeration","user","object_id"]','Exact inequality.',20),
 ('is_any_of','is any of','multiple','["string","number","enumeration","user","object_id"]','Matches any selected value.',30),
 ('is_none_of','is none of','multiple','["string","number","enumeration","user","object_id"]','Excludes all selected values.',40),
 ('contains','contains','single','["string","multi_enumeration"]','Text or multi-value field contains a value.',50),
 ('does_not_contain','does not contain','single','["string","multi_enumeration"]','Text or multi-value field excludes a value.',60),
 ('contains_any_of','contains any of','multiple','["string","multi_enumeration"]','Contains at least one selected value.',70),
 ('contains_all_of','contains all of','multiple','["multi_enumeration"]','Contains every selected value.',80),
 ('starts_with','starts with','single','["string"]','Text starts with value.',90),
 ('ends_with','ends with','single','["string"]','Text ends with value.',100),
 ('is_known','is known','none','["string","number","boolean","date","datetime","enumeration","multi_enumeration","user","object_id"]','Field has a value.',110),
 ('is_unknown','is unknown','none','["string","number","boolean","date","datetime","enumeration","multi_enumeration","user","object_id"]','Field is empty/null.',120),
 ('greater_than','is greater than','single','["number","date","datetime"]','Numeric/date greater-than comparison.',130),
 ('greater_than_or_equal','is greater than or equal to','single','["number","date","datetime"]','Numeric/date greater-than-or-equal comparison.',140),
 ('less_than','is less than','single','["number","date","datetime"]','Numeric/date less-than comparison.',150),
 ('less_than_or_equal','is less than or equal to','single','["number","date","datetime"]','Numeric/date less-than-or-equal comparison.',160),
 ('between','is between','range','["number","date","datetime"]','Inclusive range comparison.',170),
 ('before','is before','single','["date","datetime"]','Date occurs before value.',180),
 ('after','is after','single','["date","datetime"]','Date occurs after value.',190),
 ('within_last','is within last','single','["date","datetime"]','Relative-time comparison; value includes quantity and unit.',200),
 ('not_within_last','is not within last','single','["date","datetime"]','Relative-time exclusion.',210),
 ('matches_regex','matches pattern','single','["string"]','Advanced regular-expression match.',220),
 ('does_not_match_regex','does not match pattern','single','["string"]','Advanced regular-expression exclusion.',230)
on conflict (operator_key) do update set
 display_name=excluded.display_name,value_arity=excluded.value_arity,supported_data_types=excluded.supported_data_types,
 description=excluded.description,sort_order=excluded.sort_order,is_active=true;

-- Seed HubSpot deal fields already registered for compensation.
insert into public.comp_rule_field_catalog(object_type,property_name,display_name,data_type,description,is_multi_value)
select 'deal',f.hubspot_property_name,f.display_name,
 case
   when f.field_key in ('amount','amount_home_currency','new_business_arr','first_year_arr','average_arr','expansion_arr','renewal_arr','non_recurring_revenue','one_time_fee','booked_revenue','term_years') then 'number'
   when f.field_key in ('close_date','invoice_paid_date','qdc_completed_date') then 'date'
   when f.field_key='closed_won' then 'boolean'
   when f.field_key='modules' then 'multi_enumeration'
   else 'string'
 end,
 f.description,
 (f.field_key='modules')
from public.comp_hubspot_user_fields f
where f.is_active
on conflict (object_type,property_name) do update set
 display_name=excluded.display_name,data_type=excluded.data_type,description=excluded.description,
 is_multi_value=excluded.is_multi_value,is_active=true,updated_at=now();

alter table public.comp_rule_field_catalog enable row level security;
alter table public.comp_rule_operator_catalog enable row level security;
alter table public.comp_rule_sets enable row level security;
alter table public.comp_rule_predicates enable row level security;
alter table public.comp_rule_expression_nodes enable row level security;

revoke all on public.comp_rule_field_catalog from anon,authenticated;
revoke all on public.comp_rule_operator_catalog from anon,authenticated;
revoke all on public.comp_rule_sets from anon,authenticated;
revoke all on public.comp_rule_predicates from anon,authenticated;
revoke all on public.comp_rule_expression_nodes from anon,authenticated;

create or replace function public.get_comp_rule_builder_catalog(target_plan_component_id uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare
  access jsonb;
begin
  access := public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to view compensation plan rules';
  end if;

  return jsonb_build_object(
    'fields',coalesce((select jsonb_agg(to_jsonb(f) order by f.object_type,f.display_name) from public.comp_rule_field_catalog f where f.is_active),'[]'::jsonb),
    'operators',coalesce((select jsonb_agg(to_jsonb(o) order by o.sort_order) from public.comp_rule_operator_catalog o where o.is_active),'[]'::jsonb),
    'rule_sets',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,'plan_component_id',s.plan_component_id,'name',s.name,'purpose',s.purpose,'description',s.description,
        'evaluation_scope',s.evaluation_scope,'version',s.version,'is_active',s.is_active,'stop_on_match',s.stop_on_match,
        'outcome_configuration',s.outcome_configuration,
        'predicates',coalesce((select jsonb_agg(to_jsonb(p) order by p.rule_key) from public.comp_rule_predicates p where p.rule_set_id=s.id),'[]'::jsonb),
        'nodes',coalesce((select jsonb_agg(to_jsonb(n) order by n.parent_node_id nulls first,n.sort_order,n.created_at) from public.comp_rule_expression_nodes n where n.rule_set_id=s.id),'[]'::jsonb)
      ) order by s.purpose,s.name)
      from public.comp_rule_sets s
      where target_plan_component_id is null or s.plan_component_id=target_plan_component_id
    ),'[]'::jsonb)
  );
end;
$$;

create or replace function public.save_comp_rule_set(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  access jsonb;
  set_id uuid;
  pred jsonb;
  node jsonb;
  pred_id uuid;
begin
  access := public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.edit') then
    raise exception 'Not authorized to edit compensation plan rules';
  end if;

  if payload->>'plan_component_id' is null or payload->>'name' is null or payload->>'purpose' is null then
    raise exception 'plan_component_id, name and purpose are required';
  end if;

  if payload->>'id' is null then
    insert into public.comp_rule_sets(plan_component_id,name,purpose,description,evaluation_scope,version,is_active,stop_on_match,outcome_configuration,created_by,updated_by)
    values ((payload->>'plan_component_id')::uuid,payload->>'name',payload->>'purpose',payload->>'description',coalesce(payload->>'evaluation_scope','record'),coalesce((payload->>'version')::int,1),coalesce((payload->>'is_active')::boolean,true),coalesce((payload->>'stop_on_match')::boolean,false),coalesce(payload->'outcome_configuration','{}'::jsonb),(select auth.uid()),(select auth.uid()))
    returning id into set_id;
  else
    set_id := (payload->>'id')::uuid;
    update public.comp_rule_sets set
      name=payload->>'name',purpose=payload->>'purpose',description=payload->>'description',evaluation_scope=coalesce(payload->>'evaluation_scope','record'),
      is_active=coalesce((payload->>'is_active')::boolean,true),stop_on_match=coalesce((payload->>'stop_on_match')::boolean,false),
      outcome_configuration=coalesce(payload->'outcome_configuration','{}'::jsonb),updated_by=(select auth.uid()),updated_at=now()
    where id=set_id;
    delete from public.comp_rule_expression_nodes where rule_set_id=set_id;
    delete from public.comp_rule_predicates where rule_set_id=set_id;
  end if;

  create temporary table if not exists _rule_pred_map(client_key text primary key,predicate_id uuid) on commit drop;
  truncate _rule_pred_map;

  for pred in select * from jsonb_array_elements(coalesce(payload->'predicates','[]'::jsonb)) loop
    insert into public.comp_rule_predicates(rule_set_id,rule_key,display_name,object_type,association_path,property_name,operator_key,comparison_value,comparison_value_type,case_sensitive,include_null_as_match,notes)
    values (set_id,pred->>'rule_key',coalesce(pred->>'display_name',pred->>'rule_key'),pred->>'object_type',coalesce(pred->'association_path','[]'::jsonb),pred->>'property_name',pred->>'operator_key',pred->'comparison_value',pred->>'comparison_value_type',coalesce((pred->>'case_sensitive')::boolean,false),coalesce((pred->>'include_null_as_match')::boolean,false),pred->>'notes')
    returning id into pred_id;
    insert into _rule_pred_map(client_key,predicate_id) values (pred->>'client_key',pred_id);
  end loop;

  -- Nodes are supplied parent-before-child with stable client_key/parent_client_key references.
  create temporary table if not exists _rule_node_map(client_key text primary key,node_id uuid) on commit drop;
  truncate _rule_node_map;
  for node in select * from jsonb_array_elements(coalesce(payload->'nodes','[]'::jsonb)) loop
    insert into public.comp_rule_expression_nodes(rule_set_id,parent_node_id,node_type,predicate_id,logical_operator,negate,sort_order,label)
    values (
      set_id,
      (select node_id from _rule_node_map where client_key=node->>'parent_client_key'),
      node->>'node_type',
      (select predicate_id from _rule_pred_map where client_key=node->>'predicate_client_key'),
      node->>'logical_operator',coalesce((node->>'negate')::boolean,false),coalesce((node->>'sort_order')::int,0),node->>'label'
    ) returning id into pred_id;
    insert into _rule_node_map(client_key,node_id) values (node->>'client_key',pred_id);
  end loop;

  if (select count(*) from public.comp_rule_expression_nodes where rule_set_id=set_id and parent_node_id is null) <> 1 then
    raise exception 'A rule set must contain exactly one root expression node';
  end if;

  return set_id;
end;
$$;

revoke all on function public.get_comp_rule_builder_catalog(uuid) from public,anon;
grant execute on function public.get_comp_rule_builder_catalog(uuid) to authenticated,service_role;
revoke all on function public.save_comp_rule_set(jsonb) from public,anon;
grant execute on function public.save_comp_rule_set(jsonb) to authenticated,service_role;
