# Institution Lab

Sanitized source handoff for institution.art experiments and the MoFAD Rose Collection prototype.

## Included

- MoFAD Supabase schema and setup notes.
- Static catalog build and cover-audit scripts.
- Public-site and curator-review HTML templates where they do not embed live data.
- Architecture, backend, design, and audit notes where they are safe to publish.

## Deliberately Excluded

- API keys, service keys, passwords, local environment files, and cloud configs.
- Generated static deploy output.
- Catalog JSON/CSV exports, spreadsheet source files, and embedded candidate data.
- Screenshots, browser recordings, AWS source mirrors, and local crawl artifacts.

Runtime values should be supplied through environment variables, deployment secrets, or local files ignored by Git.
