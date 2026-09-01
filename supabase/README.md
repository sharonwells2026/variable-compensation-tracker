# Supabase database

Supabase provides the PostgreSQL database, authentication, row-level security, HubSpot synchronization functions, compensation calculation data, approvals, payments, reconciliation, and lifecycle audit history.

## Project

- Name: Variable Compensation Tracker
- Project reference: `bwdtbsqojtxfbeyfkang`
- Region: `us-east-1`

## Security

Never commit database passwords, Supabase service-role keys, HubSpot service keys, personal access tokens, or local environment files.

Browser-safe publishable configuration is supplied through deployment environment variables. Server-only secrets belong in Supabase Vault or protected deployment environment variables.

## Change process

1. Write each schema change as a numbered SQL migration.
2. Review the migration before applying it.
3. Apply it to Supabase.
4. Verify the result.
5. Commit the same migration to GitHub.
6. Regenerate `database.types.ts` whenever the schema changes.

## Baseline status

The existing database was created through validated SQL snippets before formal migration tracking was enabled. The generated TypeScript definitions in this folder capture the current tables, views, functions, relationships, and enums for application development. Future schema changes must be stored in `supabase/migrations/`.
