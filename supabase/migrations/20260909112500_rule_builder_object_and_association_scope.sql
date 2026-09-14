-- Extend the rule builder so rules are not Deal-only and can express associated-object semantics.
create table if not exists public.comp_rule_object_catalog (
  object_type text primary key,
  display_name text not null,
  hubspot_object_type text not null,
  supports_associations boolean not null default true,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 100
);

insert into public.comp_rule_object_catalog(object_type,display_name,hubspot_object_type,supports_associations,description,sort_order)
values
 ('deal','Deal','DEAL',true,'HubSpot deal/opportunity record.',10),
 ('company','Company','COMPANY',true,'HubSpot company/account record.',20),
 ('contact','Contact','CONTACT',true,'HubSpot contact record.',30),
 ('ticket','Ticket','TICKET',true,'HubSpot ticket/service record.',40),
 ('meeting','Meeting','MEETING',true,'HubSpot meeting/activity record, including QDC-style activity evidence.',50),
 ('call','Call','CALL',true,'HubSpot call/activity record.',60),
 ('task','Task','TASK',true,'HubSpot task/activity record.',70),
 ('custom_object','Custom Object','CUSTOM_OBJECT',true,'HubSpot custom object; concrete object type is stored in association/configuration metadata.',90)
on conflict (object_type) do update set display_name=excluded.display_name,hubspot_object_type=excluded.hubspot_object_type,supports_associations=excluded.supports_associations,description=excluded.description,is_active=true,sort_order=excluded.sort_order;

alter table public.comp_rule_predicates add column if not exists association_quantifier text not null default 'any';
alter table public.comp_rule_predicates add column if not exists aggregate_function text;
alter table public.comp_rule_predicates add column if not exists aggregate_window jsonb;

alter table public.comp_rule_predicates drop constraint if exists comp_rule_predicates_association_quantifier_check;
alter table public.comp_rule_predicates add constraint comp_rule_predicates_association_quantifier_check check (association_quantifier in ('any','all','none','record'));

alter table public.comp_rule_object_catalog enable row level security;
revoke all on public.comp_rule_object_catalog from anon,authenticated;

create or replace function public.get_comp_rule_builder_catalog(target_plan_component_id uuid default null)
returns jsonb
language plpgsql
stable security definer
set search_path=''
as $$
declare access jsonb;
begin
  access := public.get_current_user_access();
  if coalesce((access->>'authenticated')::boolean,false) is not true
     or not (coalesce(access->'permissions','[]'::jsonb) ? 'plans.view') then
    raise exception 'Not authorized to view compensation plan rules';
  end if;
  return jsonb_build_object(
    'objects',coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order) from public.comp_rule_object_catalog x where x.is_active),'[]'::jsonb),
    'fields',coalesce((select jsonb_agg(to_jsonb(f) order by f.object_type,f.display_name) from public.comp_rule_field_catalog f where f.is_active),'[]'::jsonb),
    'operators',coalesce((select jsonb_agg(to_jsonb(o) order by o.sort_order) from public.comp_rule_operator_catalog o where o.is_active),'[]'::jsonb),
    'rule_sets',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'plan_component_id',s.plan_component_id,'name',s.name,'purpose',s.purpose,'description',s.description,
      'evaluation_scope',s.evaluation_scope,'version',s.version,'is_active',s.is_active,'stop_on_match',s.stop_on_match,
      'outcome_configuration',s.outcome_configuration,
      'predicates',coalesce((select jsonb_agg(to_jsonb(p) order by p.rule_key) from public.comp_rule_predicates p where p.rule_set_id=s.id),'[]'::jsonb),
      'nodes',coalesce((select jsonb_agg(to_jsonb(n) order by n.parent_node_id nulls first,n.sort_order,n.created_at) from public.comp_rule_expression_nodes n where n.rule_set_id=s.id),'[]'::jsonb)
    ) order by s.purpose,s.name) from public.comp_rule_sets s where target_plan_component_id is null or s.plan_component_id=target_plan_component_id),'[]'::jsonb)
  );
end;
$$;
