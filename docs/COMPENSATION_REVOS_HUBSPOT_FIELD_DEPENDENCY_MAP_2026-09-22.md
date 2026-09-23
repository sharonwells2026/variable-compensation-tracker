# Compensation -> RevOS Core HubSpot Field Dependency Map — 2026-09-22

## Purpose
Define the exact HubSpot facts the Compensation engine depends on before any transport or data-layer consolidation into RevOS Core.

## Architecture rule
HubSpot remains authoritative for CRM facts. RevOS Core owns the shared HubSpot integration/read layer. Compensation must not carry a second permanent HubSpot sync subsystem into RevOS Core.

Compensation-specific rules, semantic mappings, attribution logic, plan configuration, earnings, approvals and history remain Compensation-owned.

## Required RevOS HubSpot Integration model
RevOS HubSpot Integration is intended to be dynamic and administrator-configurable, not a fixed schema contract limited to a predefined list of HubSpot fields.

Target behavior:
1. An administrator selects a HubSpot object in RevOS HubSpot Integration.
2. RevOS discovers the available HubSpot properties for that object.
3. All available properties for the selected object are represented in the shared integration field catalog.
4. Each property can be configured for use and independently shown or hidden in RevOS.
5. Modules such as Compensation consume the shared configured field catalog rather than maintaining their own permanent HubSpot property-discovery/sync system.
6. Adding a new HubSpot property should normally be an integration configuration change, not a Compensation code/schema redesign.
7. Typed columns may still exist for high-value shared fields used frequently by analytics or joins, but typed columns are an optimization/convenience layer, not the boundary of what RevOS can expose.
8. The raw synchronized HubSpot record and field catalog/mapping layer must preserve access to selected properties even when no dedicated typed column exists.

This dynamic configuration model is the long-term contract. The field list below is therefore a migration dependency list showing what Compensation currently uses, not a hard-coded permanent allowlist for RevOS.


## Compensation migration default profile
For the Compensation migration, use the current standalone Compensation HubSpot configuration as the **initial/default RevOS Compensation integration profile**.

This means:
- HubSpot objects currently enabled for Compensation should be enabled by default when Compensation is migrated.
- HubSpot properties currently exposed/eligible for Compensation should be enabled by default in the migrated Compensation profile.
- Existing Compensation field labels, mappings, rule-builder availability, attribution semantics and calculation dependencies should be preserved as the starting configuration.
- Existing hidden/not-used properties do not become permanently excluded; they remain discoverable through RevOS HubSpot Integration.
- Administrators can later enable, disable, show, hide, remap or add properties through RevOS HubSpot Integration without changing Compensation code.
- Future HubSpot objects and properties can be added to Compensation through the same RevOS configuration model.
- Changes that would affect an active Compensation rule, calculation, attribution, eligibility condition or historical interpretation should be validated and audited before taking effect.

The migrated configuration is therefore a **seed/default configuration**, not a hard-coded product constraint.

## Current shared coverage in RevOS Core
RevOS Core already contains shared caches/read models for:
- deals
- companies
- contacts
- meetings
- tasks
- events
- owners
- pipelines/stages
- deal/company/contact/meeting/task/event associations
- integration field catalog and mapping/version metadata

## Compensation dependencies already covered in Core
The following active Compensation dependencies are already represented in the Core integration catalog or typed caches:
- deal amount
- amount in home/company currency
- close date
- created date
- deal stage
- deal type
- pipeline
- HubSpot owner
- is closed won
- new business ARR
- expansion ARR
- renewal ARR
- product line
- QDC completed date
- standard deal/company owner references
- meeting activity type
- meeting outcome
- meeting start time
- meeting title
- meeting owner

## Compensation dependencies requiring explicit target treatment

### Deal monetary/contract fields
Compensation currently exposes or references:
- `average_arr`
- `first_year_arr`
- `current_tcv`
- `booked_revenue`
- `one_time_fee`
- `one_time_fees`
- `nrr__non_recurring_revenue_`
- `contract_term`
- `contract_term_deal`
- `contract_term_months`
- `term_length__in_years_`
- `contract_term_start_date`
- `contract_term_end_dates`
- `invoice_paid_date`
- `subscription_updated_date`
- `signed_contract`

Target rule:
1. If a field is used in active production calculations, eligibility, payment conditions or attribution, it must be selected/exposed through the shared Core HubSpot Integration configuration.
2. All HubSpot properties for the selected object remain discoverable through the shared field catalog, whether or not Compensation uses them today.
3. Show/hide is a RevOS presentation/configuration decision and must not imply deletion or loss of the underlying synchronized property.
4. Add a typed Core column only when typed access is operationally required for joins, high-volume analytics, indexing or other shared behavior.
5. Otherwise consume the authoritative HubSpot value through the shared raw record / integration field catalog / mapping layer.
6. Do not create a Compensation-only duplicate HubSpot deal table in Core.

### User attribution fields
Compensation currently has active user-field semantics for:
- Deal Owner -> `hubspot_owner_id`
- Business Development Owner -> `business_development_owner`
- Solutions Advisor -> `sales_account_executive__multi_year_deals_`
- Customer Experience Manager -> company `customer_experience_manager_id` / related CEM semantics

Current attribution behavior includes:
- Deal Owner for the majority of earning attribution
- Company CEM for renewal attribution in selected pipelines
- Company CEM for Book of Business metric attribution
- plan-component-specific pipeline and deal-type qualifiers

Target:
- Core transports/synchronizes the selected HubSpot owner/user facts through the common configurable integration.
- Compensation continues to own the meaning of those fields for credit and metric attribution.
- CEM/owner fields required by active logic must be selected and available through the Core integration contract before legacy Compensation HubSpot caches are retired.
- Future HubSpot owner/user properties should be selectable through HubSpot Integration without adding a Compensation-specific sync path.

### Deal rule dimensions
Active Compensation deal rules currently depend on specific:
- HubSpot pipeline IDs
- HubSpot stage IDs
- normalized deal types including new business, existing business, renewal and one-time fees

Target:
- retain IDs and normalized semantic values;
- map through the shared Core pipeline/stage layer;
- validate every active Compensation rule against the Core cache before cutover.

### Amount-source behavior
Active `comp_component_deal_rules` uses:
- `amount`
- `average_arr`

Important: `amount` is used under multiple business labels (renewal ARR, expansion amount, new-sale ARR/deal amount, one-time fee amount, deal amount). Therefore field identity alone is not enough to infer business meaning.

Target:
- preserve the component/rule configuration that supplies the semantic meaning;
- do not rewrite amount behavior simply because Core has more explicit ARR columns;
- any intentional remapping from generic `amount` to typed ARR fields requires behavioral parity evidence.

### Meeting/QDC evidence
Compensation's mapped meeting-event surface includes:
- `hs_activity_type`
- `hs_meeting_outcome`
- `hs_meeting_start_time`
- `hs_meeting_title`
- `hubspot_owner_id`
- `hs_timestamp`
- meeting change/calendar identity fields

Core already has the primary meeting facts, but Compensation's QDC logic also includes evidence/deduplication semantics and branch-only QDC migrations.

Target:
- reuse Core `hubspot_meetings` and associations as transport/read models;
- allow meeting properties to be configured through the shared HubSpot Integration in the same manner as other HubSpot objects;
- preserve Compensation QDC candidate/evidence/deduplication behavior;
- validate the branch-only QDC model separately before promotion.

## Active predicate fields observed in production
Current generic rule predicates reference:
- company `hubspot_owner_id`
- deal `closedate`
- deal `contract_term_deal`
- deal `dealstage`
- deal `dealtype`
- deal `hs_is_closed_won`
- deal `hubspot_owner_id`
- deal `invoice_paid_date`
- deal `pipeline`

These are minimum behavioral dependencies, not the complete RevOS HubSpot field universe. Eligible mapping fields are broader because they define what administrators can configure in the rule builder.

## Migration gate
The standalone Compensation HubSpot tables may not be retired until:
- each Compensation-required HubSpot object is available through RevOS HubSpot Integration;
- all relevant properties are discoverable in the shared field catalog;
- each currently active required property is selected/exposed in the target configuration;
- every active predicate field resolves from Core;
- every active amount source produces equivalent values;
- every active attribution rule produces equivalent ownership/credit results;
- pipeline/stage/deal-type behavior matches;
- meeting/QDC candidate results match;
- rule-builder field options remain functionally equivalent;
- show/hide configuration does not remove source data required by calculations;
- historical source snapshots remain preserved.

## Classification
- HubSpot-authoritative facts: all CRM source fields above and any future properties selected through HubSpot Integration
- Core synchronized cache/read model: shared HubSpot records, associations and configured properties
- RevOS integration configuration: selected HubSpot objects, selected properties, show/hide settings, mappings and versions
- Compensation configuration: rule predicates, amount-source semantics, attribution rules, mapping eligibility, plan/component logic
- Compensation derived behavior: candidate qualification, credit, attainment, earning eligibility
- Historical/audit: existing mapping snapshots, changes and compensation outcomes
