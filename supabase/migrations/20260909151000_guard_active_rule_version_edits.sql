-- Defense in depth: active rule logic cannot be mutated through direct table access or future RPCs.
create or replace function public.guard_active_comp_rule_version_mutation()
returns trigger language plpgsql set search_path='' as $$
declare active_flag boolean; target_set uuid;
begin
 target_set:=case when tg_op='DELETE' then old.rule_set_id else new.rule_set_id end;
 select is_active into active_flag from public.comp_rule_sets where id=target_set;
 if coalesce(active_flag,false) then raise exception 'Active rule versions are immutable. Create a new inactive version before changing rule logic.'; end if;
 return case when tg_op='DELETE' then old else new end;
end; $$;
drop trigger if exists guard_active_rule_predicate_mutation on public.comp_rule_predicates;
create trigger guard_active_rule_predicate_mutation before insert or update or delete on public.comp_rule_predicates for each row execute function public.guard_active_comp_rule_version_mutation();
drop trigger if exists guard_active_rule_expression_mutation on public.comp_rule_expression_nodes;
create trigger guard_active_rule_expression_mutation before insert or update or delete on public.comp_rule_expression_nodes for each row execute function public.guard_active_comp_rule_version_mutation();

create or replace function public.guard_active_comp_rule_set_update()
returns trigger language plpgsql set search_path='' as $$
begin
 if old.is_active and (
   new.plan_component_id is distinct from old.plan_component_id or new.name is distinct from old.name or
   new.purpose is distinct from old.purpose or new.description is distinct from old.description or
   new.evaluation_scope is distinct from old.evaluation_scope or new.version is distinct from old.version or
   new.stop_on_match is distinct from old.stop_on_match or new.outcome_configuration is distinct from old.outcome_configuration
 ) then raise exception 'Active rule versions are immutable. Create a new inactive version before editing configuration.'; end if;
 return new;
end; $$;
drop trigger if exists guard_active_rule_set_update on public.comp_rule_sets;
create trigger guard_active_rule_set_update before update on public.comp_rule_sets for each row execute function public.guard_active_comp_rule_set_update();
