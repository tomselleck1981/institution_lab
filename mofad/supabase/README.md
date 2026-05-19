# Supabase Backend

This folder holds the lightweight backend path for MoFAD.

## What It Provides

- Staff email/password login through Supabase Auth.
- Staff role/profile table.
- Editable book catalog table.
- Jewish Collection/subcollection candidate review table.
- Public-safe organization book request function.
- Staff-only request management tables.
- LLM/data audit run and finding tables.
- Explicit Data API grants for Supabase `anon` and `authenticated` roles.
- Row-level security policies.

## Setup

1. Create a Supabase project.
2. In Supabase Auth settings, keep staff accounts invite/admin-created for now.
3. Run `schema.sql` in the Supabase SQL editor.
4. Create the first staff user in Supabase Auth.
5. Add that user's profile:

```sql
insert into public.staff_profiles (user_id, email, display_name, role, status)
values (
  '<auth-user-uuid>',
  'person@mofad.org',
  'MoFAD Admin',
  'admin',
  'active'
);
```

## Data API Grants

Supabase projects created after May 30, 2026 require explicit table grants before
`supabase-js`, PostgREST, or GraphQL can access public-schema tables.

This schema grants:

- `anon`: schema usage and `select` on published catalog data in `books`.
- `anon`: execute on `submit_book_request(...)`; no direct request-table access.
- `authenticated`: table access needed by the staff dashboard, with RLS deciding
  the rows and operations each staff role can actually use.

When adding a new public-schema table, add a specific grant here. Do not rely on
broad anonymous default privileges for staff, request, review, or audit tables.

## Public Request Call Shape

The public site should call `submit_book_request(...)` with an item array:

```json
[
  {
    "book_id": "optional-book-uuid",
    "title": "The requested title",
    "notes": "Optional context"
  }
]
```

The function returns the request UUID. Anonymous users can execute the function, but cannot read request rows or staff notes.

## Staff Dashboard

The staff dashboard should use Supabase Auth on the client, then query:

- `books`
- `subcollection_candidates`
- `review_events`
- `book_requests`
- `book_request_items`
- `audit_runs`
- `audit_findings`

RLS policies decide what the logged-in staff member can see or modify.

## Static Public Site

The public site does not need to query Supabase for every catalog page. Prefer a build/export script that reads published rows and writes static JSON:

- `catalog.json`
- `search-index.json`
- `collections/*.json`

That preserves the audit's static-first principle while still giving staff a real editor.
