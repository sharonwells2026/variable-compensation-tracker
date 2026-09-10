revoke execute on function public.save_comp_plan_draft_assignment(uuid,uuid,date,date,numeric,integer,text) from public, anon;
revoke execute on function public.delete_comp_plan_draft_assignment(uuid) from public, anon;
grant execute on function public.save_comp_plan_draft_assignment(uuid,uuid,date,date,numeric,integer,text) to authenticated;
grant execute on function public.delete_comp_plan_draft_assignment(uuid) to authenticated;
