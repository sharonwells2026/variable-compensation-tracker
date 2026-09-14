-- Keep plan versioning unambiguous: one in-progress draft per plan.
create unique index if not exists comp_plan_versions_one_draft_per_plan_idx
on public.comp_plan_versions (comp_plan_id)
where status = 'draft'::public.plan_version_status;

-- These browser-facing SECURITY DEFINER RPCs perform their own authenticated
-- permission checks. They must not inherit Postgres' default PUBLIC execute grant.
revoke execute on function public.apply_comp_business_condition_to_eligibility(uuid,text) from public, anon;
revoke execute on function public.save_simple_comp_qualification(uuid,text,jsonb) from public, anon;
grant execute on function public.apply_comp_business_condition_to_eligibility(uuid,text) to authenticated;
grant execute on function public.save_simple_comp_qualification(uuid,text,jsonb) to authenticated;
