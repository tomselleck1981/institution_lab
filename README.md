# Institution Lab

Sanitized source handoff for institution.art experiments and the MoFAD Rose Collection prototype.

## Included

- MoFAD Supabase schema and setup notes.
- Static catalog build and cover-audit scripts, with runtime secrets read from environment variables.
- A safe project index describing which local assets were intentionally left out.

## Deliberately Excluded

- API keys, service keys, passwords, local environment files, and cloud configs.
- Generated static deploy output.
- Catalog JSON/CSV exports, spreadsheet source files, and embedded candidate data.
- Screenshots, browser recordings, AWS source mirrors, and local crawl artifacts.
- Large HTML templates that currently depend on local/generated catalog data should be reviewed and parameterized before publication.

Runtime values should be supplied through environment variables, deployment secrets, or local files ignored by Git.
