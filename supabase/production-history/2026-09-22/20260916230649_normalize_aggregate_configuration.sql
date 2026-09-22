create or replace function private.normalize_comp_aggregate_configuration()
returns trigger
language plpgsql
set search_path=''
as $$
declare
  cfg jsonb:=coalesce(new.rule_configuration,'{}'::jsonb);
  old_cfg jsonb:='{}'::jsonb;
  incoming_agg jsonb:=coalesce(cfg->'aggregate','{}'::jsonb);
  old_agg jsonb:='{}'::jsonb;
  use_legacy boolean:=false;
  sources jsonb;
  baseline numeric;
  benchmark numeric;
  payout numeric;
  comparison_key text;
  period_key text;
begin
  if tg_op='UPDATE' then
    old_cfg:=coalesce(old.rule_configuration,'{}'::jsonb);
    old_agg:=coalesce(old_cfg->'aggregate','{}'::jsonb);
  end if;

  if new.measurement_source<>'book_of_business' or new.calculation_type<>'threshold_bonus' then
    return new;
  end if;

  if tg_op='UPDATE' then
    use_legacy:=incoming_agg=old_agg and (
      cfg->'aggregate_component_codes' is distinct from old_cfg->'aggregate_component_codes'
      or cfg->>'aggregate_fixed_uplift' is distinct from old_cfg->>'aggregate_fixed_uplift'
      or cfg->>'threshold_amount' is distinct from old_cfg->>'threshold_amount'
      or cfg->>'bonus_amount' is distinct from old_cfg->>'bonus_amount'
      or cfg->>'comparison' is distinct from old_cfg->>'comparison'
      or new.measurement_period is distinct from old.measurement_period
    );
  end if;

  if use_legacy then
    sources:=coalesce(cfg->'aggregate_component_codes','[]'::jsonb);
    baseline:=coalesce(nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
    benchmark:=nullif(cfg->>'threshold_amount','')::numeric;
    payout:=nullif(cfg->>'bonus_amount','')::numeric;
    comparison_key:=coalesce(nullif(cfg->>'comparison',''),'greater_than');
    period_key:=coalesce(nullif(new.measurement_period,''),'annual');
  else
    sources:=coalesce(incoming_agg->'source_component_codes',cfg->'aggregate_component_codes','[]'::jsonb);
    baseline:=coalesce(nullif(incoming_agg->>'baseline_amount','')::numeric,nullif(cfg->>'aggregate_fixed_uplift','')::numeric,0);
    benchmark:=coalesce(nullif(incoming_agg->>'benchmark_amount','')::numeric,nullif(cfg->>'threshold_amount','')::numeric);
    payout:=coalesce(nullif(incoming_agg->>'payout_amount','')::numeric,nullif(cfg->>'bonus_amount','')::numeric);
    comparison_key:=coalesce(nullif(incoming_agg->>'comparison',''),nullif(cfg->>'comparison',''),'greater_than');
    period_key:=coalesce(nullif(incoming_agg->>'period',''),nullif(new.measurement_period,''),'annual');
  end if;

  cfg:=jsonb_set(cfg,'{aggregate_component_codes}',coalesce(sources,'[]'::jsonb),true);
  cfg:=jsonb_set(cfg,'{aggregate_fixed_uplift}',to_jsonb(coalesce(baseline,0)),true);
  if benchmark is not null then cfg:=jsonb_set(cfg,'{threshold_amount}',to_jsonb(benchmark),true); end if;
  if payout is not null then cfg:=jsonb_set(cfg,'{bonus_amount}',to_jsonb(payout),true); end if;
  cfg:=jsonb_set(cfg,'{comparison}',to_jsonb(comparison_key),true);
  cfg:=jsonb_set(cfg,'{aggregate}',jsonb_build_object(
    'function','sum',
    'period',period_key,
    'source_component_codes',coalesce(sources,'[]'::jsonb),
    'baseline_amount',coalesce(baseline,0),
    'benchmark_amount',benchmark,
    'comparison',comparison_key,
    'payout_amount',payout
  ),true);

  new.rule_configuration:=cfg;
  new.measurement_period:=period_key;
  return new;
end;
$$;

revoke all on function private.normalize_comp_aggregate_configuration() from public, anon, authenticated;

drop trigger if exists normalize_comp_aggregate_configuration on public.comp_plan_components;
create trigger normalize_comp_aggregate_configuration
before insert or update on public.comp_plan_components
for each row execute function private.normalize_comp_aggregate_configuration();

update public.comp_plan_components c
set rule_configuration=c.rule_configuration
from public.comp_plan_versions pv
where pv.id=c.plan_version_id
  and pv.status='draft'
  and c.measurement_source='book_of_business'
  and c.calculation_type='threshold_bonus';