# Compensation Function & Trigger Dependency Inventory — Phase 1

## Live production footprint
Verified in production Supabase:
- 184 public functions
- 69 public trigger event bindings

These functions/triggers are part of the application behavior contract and must be included in RevOS parity testing.

## Functional groups

### Plan lifecycle / readiness
Representative functions:
- create_compensation_plan
- create_compensation_plan_version
- create_compensation_plan_version_from_source
- update_compensation_plan_draft_version
- validate_compensation_plan_version_readiness
- validate_compensation_plan_version_readiness_core
- approve_compensation_plan_version
- activate_compensation_plan_version
- retire_compensation_plan_version
- delete_compensation_plan_draft
- preview_comp_plan_draft_delete

Critical triggers:
- comp_plan_versions_enforce_immutability
- guard_comp_plan_activation_engine_readiness
- comp_plan_components_enforce_editability

Migration implication: active/approved versions cannot be treated as ordinary mutable configuration rows.

### Rule engine
Representative functions:
- evaluate_compensation_rule
- comp_rule_evaluate_deal_node
- comp_rule_evaluate_generic_node
- preview_comp_rule_set
- save_comp_rule_set
- validate_comp_rule_set_for_activation
- set_comp_rule_set_active
- compare_comp_rule_set_versions

Critical triggers:
- guard_active_rule_expression_mutation
- guard_active_rule_predicate_mutation
- guard_active_rule_set_update
- sync_simple_qualification_to_deal_rules

Migration implication: nested rule semantics and active-version immutability are runtime logic, not just schema.

### Aggregate attainment
Representative functions:
- get_comp_component_attainment
- preview_comp_component_aggregate
- refresh_comp_aggregate_earnings

Critical trigger:
- normalize_comp_aggregate_configuration

Migration implication: aggregate components require separate parity coverage from fixed/unit deal components.

### Attribution / HubSpot evidence
Representative functions:
- get_comp_component_attribution_config
- save_comp_component_attribution
- sync_hubspot_companies
- sync_hubspot_deals
- sync_hubspot_generic_object_records
- refresh_hubspot_compensation_data
- apply_hubspot_object_record_filter_change

Critical triggers:
- capture_hubspot_company_changes_trigger
- capture_hubspot_deal_changes_trigger
- classify_hubspot_change_trigger
- sync_comp_rule_field_from_hubspot_property

Migration implication: transport/sync converges to RevOS Core, but Compensation-specific attribution and rule semantics must be preserved.

### Earnings / eligibility / corrections
Representative functions:
- preview_comp_earning_eligibility
- refresh_comp_earning_eligibility
- apply_comp_business_condition_to_eligibility
- submit_my_comp_earning_for_approval
- act_on_comp_earning_approval
- request_comp_credit_correction
- preview_comp_credit_correction_replacement
- process_comp_credit_correction
- apply_comp_credit_correction_replacement
- unapprove_comp_earning

Critical triggers:
- trg_apply_reconciliation_boundary_to_new_earning
- comp_earnings_set_updated_at

Migration implication: earning lifecycle states and corrections must remain append/reconciliation oriented; never recalculate away historical approved state.

### Agreements / approvals / workflow
Representative functions:
- save_comp_plan_agreement
- acknowledge_my_compensation_plan
- create_employee_approval_workflow
- replace_employee_approval_workflow
- preview_employee_approval_workflow
- get_approval_workflow_admin_data

Critical triggers:
- employee_approval_chains_validate
- employee_approval_workflow_versions_validate
- employee_plan_assignments_validate

### Payroll / finance
Representative functions:
- create_comp_payroll_batch
- assign_comp_earning_pay_period
- add_comp_earning_to_payroll_batch
- schedule_comp_payroll_batch
- mark_comp_payroll_batch_paid
- mark_comp_earning_paid
- accept_comp_earning_for_pay_period
- get_finance_payment_workspace_data

Critical trigger:
- payroll_payment_items_enforce_editability

Migration implication: finance acceptance, payment eligibility and paid state stay independent.

### Administration / permissions / preview
Representative functions:
- get_current_user_access
- get_access_control_admin_data
- admin_set_user_role
- admin_set_user_permission_override
- begin_user_preview
- end_user_preview
- get_user_preview_targets

Target: converge identity/module authorization onto shared RevOS permissions while preserving Compensation scopes and read-only preview behavior.

## Parity rule
A table-level row-count match is insufficient. Each business-critical function/trigger category above requires behavioral test cases against the current production implementation before cutover.
