-- Tara's review page saves to our database.
--
-- Until today her answers on the review page (docs/tara-review/index.html,
-- a claude.ai artifact) lived only in her browser's localStorage, and she
-- had to redo them once when the browser lost them. The page moves to the
-- web admin site (web/review.html) and saves as she types, through the
-- review-submit edge function, which runs as service_role.
--
-- Two tables and two admin RPCs:
--
--   review_links      one row per link Alex hands out. The token IS the
--                     credential: Tara has no account and opens the page from
--                     a text message, so the token in the URL is the only
--                     thing that says "this is Tara". 24 random bytes,
--                     URL-safe base64, minted only by an admin. revoked_at
--                     retires a link without deleting what it collected
--                     (hard rule 4); the edge function refuses a revoked
--                     token.
--   review_responses  one row per (link, page version): the answers as one
--                     jsonb blob, replaced on every save, updated_at bumped
--                     by trigger so the client cannot forget to.
--
-- No client role reads or writes either table (hard rule 11: revoke before
-- grant, from public AND anon). Only service_role (the edge function) and
-- the two SECURITY DEFINER RPCs below touch them. Both tables carry RLS with
-- no policies, so even a future grant reads zero rows until someone writes
-- a policy on purpose.

create table if not exists public.review_links (
  token      text primary key,
  label      text not null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table if not exists public.review_responses (
  id           uuid primary key default gen_random_uuid(),
  token        text not null references public.review_links(token),
  page_version text not null,
  answers      jsonb not null,
  -- clock_timestamp(), not now(): now() is the transaction's start time, so
  -- two writes in one transaction would carry one stamp and the "newest
  -- first" order would be a tie. The probe found this on its first run.
  updated_at   timestamptz not null default clock_timestamp(),
  unique (token, page_version)
);

comment on table public.review_links is
  'Links to Tara''s review page (web/review.html?t=<token>). The token is the credential; minted by admin_create_review_link, retired by revoked_at, never deleted.';
comment on table public.review_responses is
  'Her answers on the review page, one jsonb blob per (link, page version), written only by the review-submit edge function as service_role.';

alter table public.review_links     enable row level security;
alter table public.review_responses enable row level security;

-- Hard rule 11. Supabase's default privileges were revoked on 2026-08-13, so
-- these tables should be born with nothing for anon/authenticated; revoke
-- anyway, because a grant you did not write is still a grant.
revoke all on public.review_links     from public, anon, authenticated;
revoke all on public.review_responses from public, anon, authenticated;

-- service_role holds DML through the default privileges of 20260912000002;
-- written out here so the grant is visible in the file that creates the table.
grant select, insert, update, delete on public.review_links     to service_role;
grant select, insert, update, delete on public.review_responses to service_role;

-- updated_at is the "when" Alex sees on the Responses list, and the tie-break
-- when the page merges a server copy with a local one. Set by the database on
-- every write, so the edge function cannot leave it stale.
create or replace function public.review_responses_touch()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists review_responses_touch on public.review_responses;
create trigger review_responses_touch
  before update on public.review_responses
  for each row execute function public.review_responses_touch();

-- Trigger functions get no EXECUTE grant: Postgres checks it at CREATE
-- TRIGGER, not when the trigger fires (20260902000001).
revoke all on function public.review_responses_touch() from public, anon, authenticated;

-- ---------------------------------------------------------------- admin RPCs

create or replace function public.admin_create_review_link(p_label text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t text;
begin
  perform public.require_admin();
  if p_label is null or btrim(p_label) = '' then
    raise exception 'label_required' using errcode = '22023';
  end if;
  -- 24 random bytes -> 32 base64 characters, made URL-safe: + and / become
  -- - and _, and = is dropped (24 is a multiple of 3, so there is none).
  -- pgcrypto lives in the extensions schema on Supabase, and search_path is
  -- pinned, so it is named in full.
  t := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/=', '-_');
  insert into public.review_links (token, label) values (t, btrim(p_label));
  return t;
end;
$$;

comment on function public.admin_create_review_link(text) is
  'Admin-only. Mints a review link: 32-character URL-safe random token, stored with a label so Alex knows which link is which. Returns the token.';

create or replace function public.admin_review_responses()
returns table (
  token        text,
  label        text,
  page_version text,
  answers      jsonb,
  updated_at   timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  -- Revoked links are listed too: revoking stops new saves, it does not
  -- throw away what she already answered (hard rule 4).
  return query
    select r.token, l.label, r.page_version, r.answers, r.updated_at
      from public.review_responses r
      join public.review_links l on l.token = r.token
     order by r.updated_at desc;
end;
$$;

comment on function public.admin_review_responses() is
  'Admin-only. Every saved review response with its link''s label, newest first; responses on revoked links included.';

revoke all on function public.admin_create_review_link(text) from public, anon, authenticated;
grant execute on function public.admin_create_review_link(text) to authenticated;

revoke all on function public.admin_review_responses() from public, anon, authenticated;
grant execute on function public.admin_review_responses() to authenticated;
