# Variable Compensation Tracker

Private application for managing Engagifii variable compensation plans, HubSpot-sourced earnings, eligibility, approvals, payments, reconciliation, and audit history.

## Current status

- HubSpot synchronization is connected through Supabase.
- Deal, company, owner, pipeline, stage, and association data are synchronized.
- Wes Morris's retention calculation has been validated and posted:
  - 23 earned deals
  - 15 eligible for payment
  - 8 earned and awaiting payment eligibility
- Candidate calculations, duplicate protection, lifecycle logging, and refresh-delta detection are in place.
- Sharon Wells's component-based plan design is represented in the application UI; its database configuration and calculation engines are still in progress.

## Architecture

- **Frontend:** React/TypeScript dashboard currently published through ChatGPT Sites
- **Database:** Supabase/PostgreSQL
- **CRM source:** HubSpot service-key integration
- **Source control:** GitHub
- **Future hosting option:** Netlify after the application is ready for company deployment

## Security

Do not commit HubSpot service keys, Supabase service-role keys, passwords, access tokens, or local environment files. Secrets belong in Supabase Vault or deployment environment variables.

## Data notice

This private repository contains exact internal dashboard source, including employee names and compensation figures displayed by the application. Access should remain restricted to authorized Engagifii personnel.

## Next implementation milestone

Apply refresh deltas safely to current earnings while preserving lifecycle events, management review requirements, reversals, and chargeback history.
