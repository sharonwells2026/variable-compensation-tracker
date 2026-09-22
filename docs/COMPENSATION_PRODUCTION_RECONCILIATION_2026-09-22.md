# Compensation Production Reconciliation — 2026-09-22

## Purpose

Preserve the production Compensation backend exactly as it exists before any migration into RevOS Core or further UI consolidation.

## Current systems

- Production application repo: `sharonwells2026/variable-compensation-tracker`
- Production Netlify site: `engagifii-compensation`
- Production Netlify commit: `c2acc474d7e4b790e4379d28c508625a6f6ba3c3` on `main`
- Production Supabase project: `bwdtbsqojtxfbeyfkang` (`Variable Compensation Tracker`)
- Live Supabase migration history: 180 applied migrations
- Live Edge Functions in the Compensation project: none

## Important finding

The production Supabase migration history is materially ahead of the SQL migration files on GitHub `main`.

This does **not** mean production is wrong. It means source control is incomplete relative to the authoritative deployed backend state.

The live `supabase_migrations.schema_migrations` table retains the exact SQL statements for applied migrations. This reconciliation branch preserves missing live migrations under:

`supabase/production-history/2026-09-22/`

These files are **historical records of what production actually executed**. They are not placed into the normal executable `supabase/migrations` path, because doing so could cause old production migrations to be re-applied by a future deployment tool.

## Branch state

Several development branches contain work not currently deployed to production. Most importantly:

- `plan-builder-v2` is 113 commits ahead of production `main`.
- `comp-tracker-development` diverges substantially from `main`.
- Older production-fix/UI branches are already behind `main`.

Do not merge or deploy these branches merely because they are newer. Compensation has mature production business logic and must be reconciled feature-by-feature before promotion.

## Preservation rule

Before any Compensation migration to RevOS Core:

1. Preserve all production database objects and migration history.
2. Reconcile production schema against GitHub source.
3. Reconcile `plan-builder-v2` / other active branches against production.
4. Prove behavior parity for plans, versions, components, rules, books of business, QDC attribution, credits, earnings, approvals, payroll, agreements, disputes, corrections, and historical records.
5. Establish rollback.
6. Only then move runtime ownership into RevOS Core.

No destructive cleanup is authorized by this reconciliation.
