-- MoFAD Rose Collection simple backend
-- Purpose: staff login/editing + public organization book requests without the full AWS CDK stack.
-- Target: Supabase Postgres with Supabase Auth email/password.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.staff_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  display_name text,
  role text not null default 'viewer'
    check (role in ('admin', 'curator', 'editor', 'viewer')),
  status text not null default 'invited'
    check (status in ('invited', 'active', 'disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists touch_staff_profiles_updated_at on public.staff_profiles;
create trigger touch_staff_profiles_updated_at
before update on public.staff_profiles
for each row execute function public.touch_updated_at();

create or replace function public.current_staff_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select sp.role
  from public.staff_profiles sp
  where sp.user_id = auth.uid()
    and sp.status = 'active'
  limit 1
$$;

create or replace function public.is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.staff_profiles sp
    where sp.user_id = auth.uid()
      and sp.status = 'active'
  )
$$;

create or replace function public.can_edit_catalog()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_staff_role() in ('admin', 'curator', 'editor')
$$;

create or replace function public.can_curate()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_staff_role() in ('admin', 'curator')
$$;

-- ---------------------------------------------------------------------------
-- Catalog
-- ---------------------------------------------------------------------------

create table if not exists public.books (
  id uuid primary key default gen_random_uuid(),
  public_id text unique,
  source_key text,
  title text not null,
  subtitle text,
  author_display text,
  author_first text,
  author_last text,
  original_pub_year integer,
  edition_year integer,
  shelf_code text,
  current_location text,
  description_short text,
  description_long text,
  subjects text[] not null default '{}',
  facets jsonb not null default '{}'::jsonb,
  external_ids jsonb not null default '{}'::jsonb,
  cover_url text,
  cover_status text not null default 'unknown'
    check (cover_status in ('unknown', 'available', 'missing', 'broken', 'rights_review')),
  publication_status text not null default 'draft'
    check (publication_status in ('draft', 'review', 'published', 'hidden')),
  private_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists books_publication_status_idx on public.books (publication_status);
create index if not exists books_title_idx on public.books using gin (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(subtitle, '') || ' ' || coalesce(author_display, '')));
create index if not exists books_facets_idx on public.books using gin (facets);

drop trigger if exists touch_books_updated_at on public.books;
create trigger touch_books_updated_at
before update on public.books
for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Subcollection review
-- ---------------------------------------------------------------------------

create table if not exists public.subcollection_candidates (
  id uuid primary key default gen_random_uuid(),
  book_id uuid references public.books(id) on delete set null,
  candidate_key text not null unique,
  subcollection_slug text not null,
  title text not null,
  author_display text,
  author_first text,
  author_last text,
  year integer,
  inclusion_basis text not null,
  confidence numeric(4, 2) not null check (confidence >= 0 and confidence <= 1),
  matched_terms text,
  evidence_quote text,
  negative_flags text,
  source_payload jsonb not null default '{}'::jsonb,
  review_status text not null default 'proposed'
    check (review_status in ('proposed', 'approved', 'rejected')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists subcollection_candidates_slug_status_idx
  on public.subcollection_candidates (subcollection_slug, review_status);
create index if not exists subcollection_candidates_confidence_idx
  on public.subcollection_candidates (confidence desc);

drop trigger if exists touch_subcollection_candidates_updated_at on public.subcollection_candidates;
create trigger touch_subcollection_candidates_updated_at
before update on public.subcollection_candidates
for each row execute function public.touch_updated_at();

create table if not exists public.review_events (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid references public.subcollection_candidates(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null check (action in ('approve', 'reject', 'reset', 'edit')),
  note text,
  before_status text,
  after_status text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Public book requests
-- ---------------------------------------------------------------------------

create table if not exists public.book_requests (
  id uuid primary key default gen_random_uuid(),
  organization_name text not null,
  contact_name text not null,
  contact_email text not null,
  contact_phone text,
  purpose text,
  requested_start_date date,
  requested_end_date date,
  message text,
  status text not null default 'new'
    check (status in ('new', 'reviewing', 'needs_followup', 'approved', 'declined', 'closed')),
  staff_notes text,
  assigned_to uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists book_requests_status_created_idx
  on public.book_requests (status, created_at desc);
create index if not exists book_requests_contact_email_idx
  on public.book_requests (lower(contact_email));

drop trigger if exists touch_book_requests_updated_at on public.book_requests;
create trigger touch_book_requests_updated_at
before update on public.book_requests
for each row execute function public.touch_updated_at();

create table if not exists public.book_request_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.book_requests(id) on delete cascade,
  book_id uuid references public.books(id) on delete set null,
  title_snapshot text not null,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists book_request_items_request_idx
  on public.book_request_items (request_id);

-- Public-facing submit function. The anonymous role can execute this function,
-- but cannot read or directly write the underlying request tables.
create or replace function public.submit_book_request(
  p_organization_name text,
  p_contact_name text,
  p_contact_email text,
  p_contact_phone text default null,
  p_purpose text default null,
  p_requested_start_date date default null,
  p_requested_end_date date default null,
  p_message text default null,
  p_items jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_id uuid;
  v_item jsonb;
  v_book_id uuid;
  v_title text;
  v_uuid_pattern text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if nullif(trim(p_organization_name), '') is null then
    raise exception 'organization_name is required';
  end if;

  if nullif(trim(p_contact_name), '') is null then
    raise exception 'contact_name is required';
  end if;

  if nullif(trim(p_contact_email), '') is null
     or p_contact_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'valid contact_email is required';
  end if;

  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'at least one requested book is required';
  end if;

  if jsonb_array_length(p_items) > 25 then
    raise exception 'a request can include at most 25 books';
  end if;

  insert into public.book_requests (
    organization_name,
    contact_name,
    contact_email,
    contact_phone,
    purpose,
    requested_start_date,
    requested_end_date,
    message
  )
  values (
    trim(p_organization_name),
    trim(p_contact_name),
    lower(trim(p_contact_email)),
    nullif(trim(coalesce(p_contact_phone, '')), ''),
    nullif(trim(coalesce(p_purpose, '')), ''),
    p_requested_start_date,
    p_requested_end_date,
    nullif(trim(coalesce(p_message, '')), '')
  )
  returning id into v_request_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_book_id := null;
    if (v_item ? 'book_id') and (v_item ->> 'book_id') ~* v_uuid_pattern then
      v_book_id := (v_item ->> 'book_id')::uuid;
    end if;

    v_title := nullif(trim(coalesce(v_item ->> 'title', '')), '');
    if v_title is null and v_book_id is not null then
      select title into v_title from public.books where id = v_book_id;
    end if;
    v_title := coalesce(v_title, 'Requested book');

    insert into public.book_request_items (
      request_id,
      book_id,
      title_snapshot,
      notes
    )
    values (
      v_request_id,
      v_book_id,
      v_title,
      nullif(trim(coalesce(v_item ->> 'notes', '')), '')
    );
  end loop;

  return v_request_id;
end;
$$;

grant execute on function public.submit_book_request(
  text, text, text, text, text, date, date, text, jsonb
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- LLM/data audit outputs
-- ---------------------------------------------------------------------------

create table if not exists public.audit_runs (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('deterministic', 'external_enrichment', 'llm')),
  model text,
  prompt_version text,
  source_file text,
  summary jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_findings (
  id uuid primary key default gen_random_uuid(),
  run_id uuid references public.audit_runs(id) on delete cascade,
  book_id uuid references public.books(id) on delete cascade,
  field_name text,
  severity text not null default 'info'
    check (severity in ('info', 'warning', 'error')),
  finding text not null,
  proposed_value jsonb,
  evidence jsonb not null default '[]'::jsonb,
  confidence numeric(4, 2) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  review_status text not null default 'proposed'
    check (review_status in ('proposed', 'accepted', 'rejected', 'superseded')),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Data API exposure
-- ---------------------------------------------------------------------------
-- Supabase projects created after 2026-05-30 do not expose new public-schema
-- tables to anon/authenticated API roles automatically. These grants make the
-- tables reachable through supabase-js/PostgREST/GraphQL; RLS below still
-- controls which rows and operations each role can actually use.

grant usage on schema public to anon, authenticated;

revoke all on
  public.staff_profiles,
  public.subcollection_candidates,
  public.review_events,
  public.book_requests,
  public.book_request_items,
  public.audit_runs,
  public.audit_findings
from anon;

grant select on
  public.books
to anon, authenticated;

grant select, insert, update, delete on
  public.staff_profiles,
  public.books,
  public.subcollection_candidates,
  public.review_events,
  public.book_requests,
  public.book_request_items,
  public.audit_runs,
  public.audit_findings
to authenticated;

alter default privileges in schema public
grant select, insert, update, delete on tables to authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.staff_profiles enable row level security;
alter table public.books enable row level security;
alter table public.subcollection_candidates enable row level security;
alter table public.review_events enable row level security;
alter table public.book_requests enable row level security;
alter table public.book_request_items enable row level security;
alter table public.audit_runs enable row level security;
alter table public.audit_findings enable row level security;

drop policy if exists "staff can read own profile" on public.staff_profiles;
create policy "staff can read own profile"
on public.staff_profiles
for select
to authenticated
using (user_id = auth.uid() or public.current_staff_role() = 'admin');

drop policy if exists "admins manage staff profiles" on public.staff_profiles;
create policy "admins manage staff profiles"
on public.staff_profiles
for all
to authenticated
using (public.current_staff_role() = 'admin')
with check (public.current_staff_role() = 'admin');

drop policy if exists "published books are public" on public.books;
create policy "published books are public"
on public.books
for select
to anon, authenticated
using (publication_status = 'published' or public.is_active_staff());

drop policy if exists "staff can edit books" on public.books;
create policy "staff can edit books"
on public.books
for all
to authenticated
using (public.can_edit_catalog())
with check (public.can_edit_catalog());

drop policy if exists "staff can read subcollection candidates" on public.subcollection_candidates;
create policy "staff can read subcollection candidates"
on public.subcollection_candidates
for select
to authenticated
using (public.is_active_staff());

drop policy if exists "curators can manage subcollection candidates" on public.subcollection_candidates;
create policy "curators can manage subcollection candidates"
on public.subcollection_candidates
for all
to authenticated
using (public.can_curate())
with check (public.can_curate());

drop policy if exists "staff can read review events" on public.review_events;
create policy "staff can read review events"
on public.review_events
for select
to authenticated
using (public.is_active_staff());

drop policy if exists "curators can write review events" on public.review_events;
create policy "curators can write review events"
on public.review_events
for insert
to authenticated
with check (public.can_curate());

drop policy if exists "staff can read book requests" on public.book_requests;
create policy "staff can read book requests"
on public.book_requests
for select
to authenticated
using (public.is_active_staff());

drop policy if exists "staff can update book requests" on public.book_requests;
create policy "staff can update book requests"
on public.book_requests
for update
to authenticated
using (public.is_active_staff())
with check (public.is_active_staff());

drop policy if exists "staff can read request items" on public.book_request_items;
create policy "staff can read request items"
on public.book_request_items
for select
to authenticated
using (public.is_active_staff());

drop policy if exists "staff can read audit runs" on public.audit_runs;
create policy "staff can read audit runs"
on public.audit_runs
for select
to authenticated
using (public.is_active_staff());

drop policy if exists "staff can write audit runs" on public.audit_runs;
create policy "staff can write audit runs"
on public.audit_runs
for insert
to authenticated
with check (public.can_edit_catalog());

drop policy if exists "staff can read audit findings" on public.audit_findings;
create policy "staff can read audit findings"
on public.audit_findings
for select
to authenticated
using (public.is_active_staff());

drop policy if exists "staff can manage audit findings" on public.audit_findings;
create policy "staff can manage audit findings"
on public.audit_findings
for all
to authenticated
using (public.can_edit_catalog())
with check (public.can_edit_catalog());
