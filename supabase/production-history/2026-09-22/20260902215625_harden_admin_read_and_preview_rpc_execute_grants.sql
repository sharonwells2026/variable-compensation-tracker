revoke all on function public.get_admin_earnings_data() from public, anon;
revoke all on function public.get_admin_audit_activity(integer) from public, anon;
grant execute on function public.get_admin_earnings_data() to authenticated;
grant execute on function public.get_admin_audit_activity(integer) to authenticated;

revoke all on function public.get_user_preview_targets() from public, anon;
revoke all on function public.begin_user_preview(uuid) from public, anon;
revoke all on function public.end_user_preview(uuid) from public, anon;
grant execute on function public.get_user_preview_targets() to authenticated;
grant execute on function public.begin_user_preview(uuid) to authenticated;
grant execute on function public.end_user_preview(uuid) to authenticated;