# Production migration history snapshot

This directory contains SQL reconstructed directly from the live Supabase
`supabase_migrations.schema_migrations` ledger on 2026-09-22.

Purpose: preserve production backend history that was not present as a matching
migration file on GitHub `main`.

These files are **reference/history only**. Do not execute them as a migration
set. The normal deployable migration path remains `supabase/migrations/`.

Each filename uses the live migration version and live migration name.
