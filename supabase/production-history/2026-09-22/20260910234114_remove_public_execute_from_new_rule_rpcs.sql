revoke execute on function public.apply_comp_business_condition_to_eligibility(uuid,text) from public, anon;
revoke execute on function public.save_simple_comp_qualification(uuid,text,jsonb) from public, anon;
grant execute on function public.apply_comp_business_condition_to_eligibility(uuid,text) to authenticated;
grant execute on function public.save_simple_comp_qualification(uuid,text,jsonb) to authenticated;