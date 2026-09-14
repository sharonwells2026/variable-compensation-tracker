# Round 2 architecture decisions

These decisions reconcile the Round 2 UI/UX prototype with the current compensation tracker backend.

## Lifecycle

The business lifecycle is:

**Earned -> Eligible -> Approved -> Paid**

- **Earned**: the source activity/transaction satisfies the compensation component's qualification rules and produces compensation credit.
- **Eligible**: any additional condition required before payment has been satisfied.
- **Approved**: required compensation approvals have completed.
- **Paid**: the approved compensation has actually been paid to the employee.

Operational UI states such as waiting, blocked, rejected, or needs action are separate from these lifecycle statuses.

## 1. Eligibility conditions

`customer payment received` should be presented as a first-class business-language eligibility option in the UI, but it must not be implemented as a hardcoded HubSpot field/value.

The underlying source of truth is configurable. The condition must resolve to synchronized source data and/or an approved compensation rule so changes to HubSpot fields, pipelines, stages, or invoice objects do not require application code changes.

Supported eligibility patterns should include:

- no additional condition (Earned and Eligible together)
- customer payment received (business-language template backed by configured source evidence)
- waiting period after earned date
- custom compensation rule

Each earning snapshots the eligibility condition/evidence used so later source changes do not silently rewrite historical compensation.

## 2. Multiple plans/components matching one activity

Multiple compensation components may legitimately pay from the same source activity. The engine must therefore not globally deduplicate by source record.

Default behavior: qualifying components can stack and each produces its own earning.

Configuration must also be able to prevent unintended overlap. Activation/readiness should warn when the same employee/source activity can match multiple components or plans. A future exclusive/priority policy may be added without changing the basic earning model.

Paid earnings are never silently replaced because a later configuration changes overlap behavior.

## 3. Assignment history

Plan assignment is effective-dated.

An employee only earns under a plan/component for source activity whose earning date falls within the employee's effective assignment window. Activity before the assignment start date does not automatically generate earnings.

Backdated assignment or historical recalculation must be an explicit governed action with impact review/corrections rather than an implicit consequence of editing the current assignment.

Existing earnings retain the plan version and assignment context under which they were calculated.

## 4. Estimated next payment

The product must distinguish a known schedule from an estimate.

- If Finance has assigned an earning to a payment schedule/pay period, My Compensation may show the scheduled pay period/date.
- If no schedule exists but an expected pay period/date is available, label it as estimated/expected rather than guaranteed.
- If neither exists, do not invent a next-payment date. Show the approved/eligible amount and explain that Finance has not scheduled it yet.

Partial payments must use remaining approved balance when presenting future payment expectations.

## 5. Employee questions

There is no dedicated earning comment/question workflow in v1. Do not ship an `Ask a question` action that implies an in-app thread exists.

The employee earning detail should instead expose the explanation, source/calculation, lifecycle history, and any existing review/correction action that is genuinely supported. A dedicated question/comment workflow can be added later as its own auditable feature.

## 6. Approval chains

The current approval architecture is employee/workflow based and effective-dated. Approval requests snapshot the chain used for an earning.

For v1, components inherit the applicable employee/workflow approval chain. Do not imply that every plan component owns an independent approval chain unless the backend is extended to support that deliberately.

A component may still declare requirements that affect the workflow (for example executive approval required), but the UI should show the resolved/inherited approval path and its source.

Component-level approval-chain overrides are a future extension, not a hidden JSON convention.

## Related architecture rules

- HubSpot Integration controls which objects and records are synchronized.
- Compensation Mapping controls which synchronized fields/options compensation configuration may use.
- Rule Builder defines qualification/condition logic using approved mapped data.
- HubSpot remains read-only for v1.
- Sync-scope reductions require impact analysis and preserve historical synchronized records.
- Paid compensation is never automatically recalculated because source configuration, mappings, filters, plans, or rules change.
- Navigation is permission-driven, not persona-hardcoded.
