# Compensation → RevOS Core Target Mapping

## Purpose
Define the target architecture before any Compensation data is moved.

## Shared HubSpot layer

### Current Compensation state
The standalone Compensation backend contains its own copies of HubSpot business data and integration metadata, including:
- `hubspot_deals`
- `hubspot_companies`
- `hubspot_pipelines`
- deal/company associations
- generic HubSpot records and associations
- property definitions
- object definitions
- sync runs/settings
- Compensation-specific HubSpot mapping/config tables

### RevOS Core state
RevOS Core already contains the shared HubSpot read layer:
- `hubspot_deals`
- `hubspot_companies`
- `hubspot_contacts`
- `hubspot_meetings`
- `hubspot_tasks`
- `hubspot_events`
- shared deal/contact/company/meeting/task/event associations
- `hubspot_pipelines`
- `hubspot_deal_stages`
- shared integration registry/checkpoints/field catalog/mappings

## Target rule
Do **not** copy the Compensation HubSpot sync subsystem into RevOS Core as a second sync system.

Instead:
1. identify every Compensation calculation that reads a local HubSpot field;
2. map that field to the shared RevOS Core HubSpot cache or integration field catalog;
3. add missing shared fields to the existing RevOS integration contract when genuinely required;
4. preserve Compensation-specific semantic mappings/rules separately from transport/sync;
5. prove equivalent candidate/calculation results before retiring the old Compensation cache.

## Known field-shape differences

### Deals
Standalone Compensation has domain-oriented fields not yet all typed in Core, including:
- average ARR
- first-year ARR
- TCV
- one-time fee / non-recurring revenue
- contract term label/years/months
- contract start/end
- payment frequency
- contract URL
- subscription updated date
- invoice paid date
- solutions advisor
- business development owner

RevOS Core already has typed:
- amount
- new business ARR
- expansion ARR
- renewal ARR
- contraction ARR
- churn ARR
- current ARR
- close date
- pipeline/stage/deal type
- QDC/demo/proposal fields
- purchased/modules in scope
- raw HubSpot payload

Target: extend the shared field catalog/cache only where Compensation genuinely requires typed access. Otherwise consume the authoritative value from the shared raw payload/mapping layer. Do not create a Compensation-only duplicate deal table in Core.

### Companies
Standalone Compensation has:
- customer experience manager
- total ARR / 2025 ARR
- annual renewal date
- cancellation/end dates
- current customer text state

RevOS Core already has:
- customer status/current-customer boolean
- customer since
- health
- vertical
- modules
- owner
- domain/website/phone
- raw HubSpot payload

Target: add only required shared typed fields after dependency analysis.

## Compensation-owned domains
These remain Compensation domain models even inside RevOS Core:
- plans / versions / components
- rule trees and predicates
- employee plan assignment
- book-of-business configuration
- attribution rules
- calculations
- credits
- earnings and lifecycle
- approval workflows
- agreements
- payroll
- disputes/corrections
- reconciliation
- historical records

## Shared RevOS domains
These should converge to shared Core services:
- authentication/session
- module access and permissions
- HubSpot ingestion and cache
- common audit infrastructure where compatible
- environment/UAT safeguards
- AI runtime/config where needed
- navigation/module registry
- writeback governance

## Migration sequencing
1. Shared identity/permission mapping
2. Shared HubSpot field dependency mapping
3. Read-only Compensation calculation against shared HubSpot cache
4. Rule/candidate parity
5. Core copy of Compensation-owned configuration/history
6. Financial calculation parity
7. approval/payroll parity
8. native RevOS UX
9. dual run
10. cutover

No current production table is dropped as part of steps 1–8.
