-- Restrict sensitive compensation RPCs to authenticated/service callers only.
-- Function bodies still enforce granular app permissions and actor scope.

revoke all on function public.accept_comp_earning_for_pay_period(uuid,date,date,text,text) from public, anon;
revoke all on function public.assign_comp_earning_pay_period(uuid,date,date,text,text) from public, anon;
revoke all on function public.mark_comp_earning_paid(uuid,date,text,text,text) from public, anon;
revoke all on function public.get_compensation_employee_data(uuid) from public, anon;
revoke all on function public.get_finance_payment_workspace_data() from public, anon;
revoke all on function public.get_my_comp_earning_handoff_tasks(boolean) from public, anon;

grant execute on function public.accept_comp_earning_for_pay_period(uuid,date,date,text,text) to authenticated, service_role;
grant execute on function public.assign_comp_earning_pay_period(uuid,date,date,text,text) to authenticated, service_role;
grant execute on function public.mark_comp_earning_paid(uuid,date,text,text,text) to authenticated, service_role;
grant execute on function public.get_compensation_employee_data(uuid) to authenticated, service_role;
grant execute on function public.get_finance_payment_workspace_data() to authenticated, service_role;
grant execute on function public.get_my_comp_earning_handoff_tasks(boolean) to authenticated, service_role;
