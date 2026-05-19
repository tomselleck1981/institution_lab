# Institution Lab

Institution Lab is a sanitized source handoff for institution.art experiments, beginning with a reusable museum collection prototype. The current project shows how a small cultural organization can publish a rich public catalog, give staff a lightweight editing and review workflow, and accept external collection requests without standing up a large CMS or expensive custom backend.

The repository is intentionally general. It does not contain partner-specific datasets, production credentials, generated deploy output, or private planning artifacts.

## Project Goal

The prototype is designed for a museum or archive with a bounded book or object collection that needs:

- a public, searchable collection experience;
- staff login with email/password;
- curator review queues for proposed subcollections or data corrections;
- an organization request flow for loans, visits, research access, or collaboration;
- deterministic and LLM-assisted audit workflows for metadata quality;
- a low-cost architecture that can start static-first and become more dynamic only where needed.

The guiding principle is simplicity: keep public pages fast and static where possible, put editable state in a small managed backend, and make every automated enrichment pass reviewable by staff before it affects public interpretation.

## Architecture

The project uses a static-first public site with Supabase as the lightweight backend.

- **Public catalog:** generated from local source data into static site/data artifacts.
- **Staff dashboard:** authenticated client that reads and edits catalog/review/request records through Supabase.
- **Database:** Postgres tables for books, staff profiles, subcollection candidates, review events, public requests, and audit findings.
- **Security:** Supabase Auth plus row-level security. Data API grants are explicit so post-May-30-2026 Supabase projects expose only intended tables and functions.
- **Audit/enrichment:** scripts can search external book sources for missing covers and write proposed findings for review.

## Repository Layout

```text
museum-collection/
  curator-ui/        Notes for a staff review interface
  docs/              Index of private/local docs that require review before publishing
  scripts/           Sanitized build and audit scripts
  site-mockup/       Notes for public static catalog templates
  supabase/          Database schema, RLS policies, and setup notes
```

## Included

- Generalized Supabase schema and setup notes.
- Explicit API grants and RLS policy patterns.
- Sanitized catalog build helper script.
- Sanitized cover-audit helper script.
- Notes explaining which generated or private assets are intentionally excluded.

## Deliberately Excluded

- API keys, service keys, passwords, local environment files, and cloud configs.
- Generated static deploy output.
- Catalog JSON/CSV exports, spreadsheet source files, and embedded candidate data.
- Screenshots, browser recordings, AWS source mirrors, and local crawl artifacts.
- Large HTML templates that currently depend on local/generated catalog data and need a separate parameterization pass before publication.

Runtime values should be supplied through environment variables, deployment secrets, or local files ignored by Git.

## Security Posture

This repository treats public source control as hostile by default.

- No production Supabase keys or database passwords are committed.
- Service-role operations are expected to run from trusted local or server environments only.
- Anonymous users should access public catalog data and safe RPC functions only.
- Staff-only tables are protected by both grants and row-level security policies.
- Generated data and partner-specific collection records stay out of the repository until explicitly reviewed and redacted.

## Current Status

This is an early source handoff, not a turnkey application. The schema and scripts capture the core implementation direction, while the public UI templates and real data remain local until they can be separated from partner-specific content.

Useful next steps:

1. Parameterize public and staff HTML templates so they can be safely committed without generated data.
2. Add example fixtures with fake records for local development.
3. Add a minimal setup guide for running the static build against fixture data.
4. Add CI checks for secret scanning and schema linting.
5. Decide whether this repository should remain a lab notebook or become the canonical application source.
