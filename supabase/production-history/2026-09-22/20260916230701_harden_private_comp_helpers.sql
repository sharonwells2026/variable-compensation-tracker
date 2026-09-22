revoke all on function private.compute_comp_component_attainment(uuid,uuid,integer) from public, anon, authenticated;
revoke all on function private.install_plan_approval_workflows(uuid,uuid) from public, anon, authenticated;

-- These helpers are invoked only from trigger or definer-controlled compensation workflows.
-- Removing direct client execution keeps the public authenticated RPC layer as the only supported entry point.