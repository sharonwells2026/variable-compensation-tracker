# Compensation Production Schema Inventory — 2026-09-22

## Snapshot
Production Supabase: `bwdtbsqojtxfbeyfkang` (Variable Compensation Tracker)

Verified live:
- 95 public base tables
- 13 public views
- 108 public relations total
- 184 public functions
- 69 public triggers
- 180 applied Supabase migrations
- 0 deployed Edge Functions in the Compensation Supabase project

The exact SQL for every live migration is now preserved in source control either in the normal migration path or under `supabase/production-history/2026-09-22/`. The production-history directory is reference-only and must not be replayed wholesale.

## Domain classification

### Core compensation configuration
`comp_plans`
`comp_plan_versions`
`comp_plan_components`
`comp_component_deal_rules`
`comp_credit_rules`
`comp_business_condition_settings`
`comp_periods`
`comp_rule_sets`
`comp_rule_expression_nodes`
`comp_rule_predicates`
`comp_rule_field_catalog`
`comp_rule_object_catalog`
`comp_rule_operator_catalog`
`comp_rule_set_preview_runs`
`comp_user_attribution_rules`

Target: preserve as Compensation-owned RevOS configuration/rules.

### Employee / assignment / book-of-business
`employees`
`employee_plan_assignments`
`employee_books`
`employee_book_accounts`
`employee_org_assignments`
`employee_job_roles`
`job_roles`
`organization_units`
`management_scopes`

Target: preserve Compensation business-domain state; reconcile employee identity with shared RevOS identity/permissions rather than duplicating authentication.

### Credits / calculations / earnings
`comp_calculations`
`comp_earnings`
`deal_credit_allocations`
`comp_deal_credit_reviews`
`comp_credit_correction_requests`
`comp_earning_lifecycle_events`
`earning_adjustments`
`earning_disputes`
`earning_eligibility_events`
`earning_payment_schedules`
`missing_earning_claims`

Target: Compensation-owned financial calculation and ledger domain. Earned outcomes require immutability/appended corrections; no destructive rewrite during migration.

### Approval / agreement / payroll
`comp_plan_approval_steps`
`comp_plan_agreements`
`plan_version_acknowledgments`
`approval_requests`
`approval_actions`
`approval_request_messages`
`employee_approval_chains`
`employee_approval_workflow_versions`
`employee_post_approval_steps`
`payroll_batches`
`payroll_payment_items`
`comp_earning_handoff_tasks`

Target: preserve independent plan approval, earning approval, payment eligibility and payment states.

### Historical / reconciliation / audit
`historical_comp_records`
`historical_source_catalog`
`reconciliation_actions`
`reconciliation_boundaries`
`compensation_review_batches`
`compensation_review_batch_items`
`app_access_audit_events`

Target: migrate intact as historical/audit evidence; never collapse into mutable current-state tables.

### HubSpot synchronization and mapping
`hubspot_deals`
`hubspot_companies`
`hubspot_deal_company_associations`
`hubspot_generic_records`
`hubspot_generic_associations`
`hubspot_object_definitions`
`hubspot_object_sync_settings`
`hubspot_property_definitions`
`hubspot_pipelines`
`hubspot_pipeline_stages`
`hubspot_record_changes`
`hubspot_sync_runs`
`hubspot_integration_resync_runs`
`comp_hubspot_object_mappings`
`comp_hubspot_field_mappings`
`comp_hubspot_value_mappings`
`comp_hubspot_mapping_versions`
`comp_hubspot_mapping_change_log`
`comp_hubspot_discovered_values`
`comp_hubspot_config_snapshots`
`comp_hubspot_config_changes`
`comp_hubspot_user_fields`

Target: do not create a second permanent HubSpot sync layer inside RevOS Core. Preserve Compensation-specific mapping semantics, but converge record ingestion onto RevOS Core shared HubSpot caches/integration infrastructure.

### Access / notifications / settings
`profiles`
`organization_settings`
`user_access_roles`
`user_settings`
`user_setting_definitions`
`app_notifications`
`notification_types`
`user_notification_preferences`
`app_user_invitations`
`app_user_drafts`

Target: classify item-by-item as shared RevOS identity/permissions vs Compensation-local preference/configuration before migration.

### Contract grouping / other business structures
`contract_groups`
`contract_group_deals`
`contract_payout_overrides`
`customer_accounts`
`revenue_classifications`
`comp_import_batches`

Target: preserve until behavioral dependency review is complete; do not delete because current row counts may be zero.

## Important live analytical views
- `comp_deal_earning_candidates`
- `comp_deal_earning_candidates_v2`
- `comp_deal_earning_refresh_delta`
- `comp_milestone_reconciliation_exceptions_v1`
- `comp_new_logo_attribution_conflicts_v1`
- `comp_qdc_data_quality_exceptions_v2`
- `comp_qdc_deal_candidates_v3`
- `comp_qdc_earning_candidates_v1`
- `comp_qdc_earning_candidates_v2`
- `comp_qdc_meeting_candidates_v2`
- `hubspot_compensation_deals`
- `hubspot_deal_scope`
- `hubspot_qdc_meeting_events_v1`

These views are part of the behavior surface and must be included in parity testing, not treated as disposable reporting artifacts.

## Migration rule
No Compensation object is moved, renamed, consolidated or dropped solely because a similar RevOS Core object exists. Every overlap requires:
1. authoritative-data classification;
2. dependency analysis;
3. source/target mapping;
4. row parity;
5. behavioral parity;
6. rollback path;
7. explicit cutover approval.
