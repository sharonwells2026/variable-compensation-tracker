alter function public.validate_compensation_plan_version_readiness(uuid)
  rename to validate_compensation_plan_version_readiness_pre_generic_metric_fields;

create or replace function public.validate_compensation_plan_version_readiness(selected_plan_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  base jsonb;
  blockers jsonb;
begin
  base:=public.validate_compensation_plan_version_readiness_pre_generic_metric_fields(selected_plan_version_id);

  select coalesce(jsonb_agg(b),'[]'::jsonb)
  into blockers
  from jsonb_array_elements(coalesce(base->'blockers','[]'::jsonb)) b
  where not (
    b->>'code'='invalid_metric_value_field'
    and exists(
      select 1
      from public.comp_plan_components c
      where c.id=nullif(b->>'component_id','')::uuid
        and public.is_comp_metric_numeric_value_field(
          coalesce(nullif(c.rule_configuration->'aggregate'->>'value_field',''),'amount')
        )
    )
  );

  base:=jsonb_set(base,'{blockers}',blockers);
  base:=jsonb_set(base,'{blocker_count}',to_jsonb(jsonb_array_length(blockers)));
  base:=jsonb_set(base,'{ready}',to_jsonb(jsonb_array_length(blockers)=0));
  return base;
end;
$$;

revoke all on function public.validate_compensation_plan_version_readiness(uuid) from public,anon;
grant execute on function public.validate_compensation_plan_version_readiness(uuid) to authenticated;