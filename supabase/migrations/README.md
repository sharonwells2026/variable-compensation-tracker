# Database migrations

Place every future Supabase schema change in this directory before or at the same time it is applied.

## Naming

Use a timestamp and clear description:

```
YYYYMMDDHHMMSS_description.sql
```

Example:

```
20260829010000_apply_compensation_earning_refresh.sql
```

## Rules

- Never include credentials or live record exports.
- Prefer idempotent SQL where practical.
- Preserve compensation and audit history.
- Never silently alter approved or paid earnings.
- Validate each migration in Supabase after it is applied.
