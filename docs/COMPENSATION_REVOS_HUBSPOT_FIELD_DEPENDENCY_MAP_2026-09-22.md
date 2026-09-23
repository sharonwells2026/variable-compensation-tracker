# Compensation -> RevOS Core HubSpot Field Dependency Map — 2026-09-22

## Purpose
Define the exact HubSpot facts the Compensation engine depends on before any transport or data-layer consolidation into RevOS Core.

## Architecture rule
HubSpot remains authoritative for CRM facts. RevOS Core owns the shared HubSpot integration/read layer. Compensation must not carry a second permanent HubSpot sync subsystem into RevOS Core.

Compensation-specific rules, semantic mappings, attribution logic, plan configuration, earnings, approvals and history remain Compensation-owned.

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
1. If a field is used in active production calculations, eligibility, payment conditions or attribution, it must be available through the shared Core integration layer.
2. Add a typed Core column only when typed access is operationally required.
3. Otherwise consume the authoritative HubSpot value through Core raw payload / integration field catalog.
4. Do not create a Compensation-only duplicate HubSpot deal table in Core.

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
- Core transports/synchronizes the source HubSpot owner/user facts.
- Compensation continues to own the meaning of those fields for credit and metric attribution.
- CEM/owner fields required by active logic must be added to or exposed through the Core integration contract before legacy Compensation HubSpot caches are retired.

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

These are minimum behavioral dependencies. Eligible mapping fields are broader because they define what administrators can configure in the rule builder.

## Migration gate
The standalone Compensation HubSpot tables may not be retired until:
- every active predicate field resolves from Core;
- every active amount source produces equivalent values;
- every active attribution rule produces equivalent ownership/credit results;
- pipeline/stage/deal-type behavior matches;
- meeting/QDC candidate results match;
- rule-builder field options remain functionally equivalent;
- historical source snapshots remain preserved.

## Classification
- HubSpot-authoritative facts: all CRM source fields above
- Core synchronized cache/read model: shared HubSpot records and associations
- Compensation configuration: rule predicates, amount-source semantics, attribution rules, mapping eligibility, plan/component logic
- Compensation derived behavior: candidate qualification, credit, attainment, earning eligibility
- Historical/audit: existing mapping snapshots, changes and compensation outcomes
