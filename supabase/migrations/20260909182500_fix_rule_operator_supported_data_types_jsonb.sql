-- Fix rule operator compatibility checks to treat supported_data_types as jsonb.
-- The catalog stores supported types as a JSON array, not a Postgres text array.

do $$
declare ddl text;
begin
  select pg_get_functiondef('public.save_comp_rule_set(jsonb)'::regprocedure) into ddl;
  ddl := replace(ddl, 'supported_types text[];', 'supported_types jsonb;');
  ddl := replace(ddl, 'if not (field_type = any(supported_types)) then', 'if not (supported_types ? field_type) then');
  execute ddl;

  select pg_get_functiondef('public.validate_comp_rule_set_for_activation(uuid)'::regprocedure) into ddl;
  ddl := replace(ddl, 'not (f.data_type = any(o.supported_data_types))', 'not (o.supported_data_types ? f.data_type)');
  execute ddl;
end $$;
