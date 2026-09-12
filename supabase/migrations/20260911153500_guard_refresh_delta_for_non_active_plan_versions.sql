-- Keep non-active plan versions available to preview/evaluate without allowing
-- the generic earnings refresh to classify their candidates as postable earnings.
-- Active-plan behavior is unchanged.

do $$
declare
  v text;
  old_change text;
  new_change text;
  old_review text;
  new_review text;
begin
  v := pg_get_viewdef('public.comp_deal_earning_refresh_delta'::regclass, true);

  if position('plan_not_active_preview_only' in v) > 0 then
    return;
  end if;

  old_change := $x$CASE
                    WHEN comparison.comp_earning_id IS NULL AND comparison.candidate_key IS NOT NULL AND comparison.current_earned_date > CURRENT_DATE THEN 'future_forecast_only'::text$x$;
  new_change := $x$CASE
                    WHEN comparison.candidate_key IS NOT NULL AND coalesce((select pv.status::text from public.comp_plan_components pc join public.comp_plan_versions pv on pv.id=pc.plan_version_id where pc.id=comparison.plan_component_id), 'draft') <> 'active' THEN 'plan_not_active_preview_only'::text
                    WHEN comparison.comp_earning_id IS NULL AND comparison.candidate_key IS NOT NULL AND comparison.current_earned_date > CURRENT_DATE THEN 'future_forecast_only'::text$x$;

  old_review := $x$CASE
                    WHEN comparison.candidate_key IS NOT NULL AND comparison.calculation_status <> 'ready'::text THEN true$x$;
  new_review := $x$CASE
                    WHEN comparison.candidate_key IS NOT NULL AND coalesce((select pv.status::text from public.comp_plan_components pc join public.comp_plan_versions pv on pv.id=pc.plan_version_id where pc.id=comparison.plan_component_id), 'draft') <> 'active' THEN false
                    WHEN comparison.candidate_key IS NOT NULL AND comparison.calculation_status <> 'ready'::text THEN true$x$;

  if position(old_change in v)=0 or position(old_review in v)=0 then
    raise exception 'Expected refresh-delta clauses not found; migration stopped safely.';
  end if;

  v := replace(v, old_change, new_change);
  v := replace(v, old_review, new_review);
  execute 'create or replace view public.comp_deal_earning_refresh_delta with (security_invoker=true) as ' || v;
end $$;
