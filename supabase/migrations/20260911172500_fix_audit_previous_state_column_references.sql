-- Normalize lingering audit writes to the canonical previous_state column.
-- This fixes draft Earning Type payment-condition saves that still referenced
-- the removed old_state column on app_access_audit_events.
do $$
declare r record; def text;
begin
  for r in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where p.prokind='f'
      and n.nspname='public'
      and pg_get_functiondef(p.oid) like '%old_state%'
  loop
    def := pg_get_functiondef(r.oid);
    def := replace(def, 'old_state', 'previous_state');
    execute def;
  end loop;
end $$;
