-- 20260928700001_calendar_feed.sql
--
-- A player's clinics as a subscribed calendar (decision 0029; the roadmap's
-- "Your clinics in your calendar, automatically"). Add to Calendar (decision
-- 0023) is one-shot: when Tara moves or cancels a clinic the entry it made is
-- wrong. A subscribed calendar is re-read by the phone every hour or so, so a
-- change on our side reaches it on its own.
--
-- How it fits together:
--
--   calendar_feeds          one row per account: the account's feed token.
--                           The token IS the credential: Apple's Calendar,
--                           Google and Outlook fetch the feed with a plain GET
--                           and can carry nothing else. No client role holds
--                           anything on the table.
--   my_calendar_feed_token  the signed-in account's token, made on first use
--                           (32 random bytes, hex). The app builds
--                           webcal://<project>/functions/v1/calendar-feed?t=<token>
--                           from it and hands that to iOS.
--   reset_my_calendar_feed  a new token; the old link stops working at once.
--   calendar_feed_events    the feed's content, for the calendar-feed edge
--                           function (service_role only): this account's
--                           You're In! and Response Needed registrations in
--                           published clinics that ended no more than 30 days
--                           ago. Name, start, end, status: nothing else, so
--                           none of the nine hidden facts (hard rule 1), and
--                           in particular no location (decision 10) and no
--                           court (decision 17), can reach a calendar.
--
-- The rule for what is in the feed lives HERE, not in the edge function, so
-- the probe (tests/sql/calendar_feed.sql) pins it with hand-worked rows; the
-- function only turns rows into iCalendar text (tests/calendar/run.sh).
--
-- Account deletion: a trigger on accounts.deleted_at removes the token, so a
-- deleted account's link answers 404 whichever path set deleted_at. It is a
-- trigger rather than a line inside delete_my_account() so that function is
-- not redefined here (a parallel branch redefining it would silently drop one
-- of the two changes), and so any future path that sets deleted_at is covered
-- too. A token is a credential, not history (the same reasoning as devices in
-- 20260921000003): deleting it is the point, and hard rule 4 does not apply.
-- A hard delete of the account cascades it away for the same reason.

-- ------------------------------------------------------------------ table ----

create table if not exists public.calendar_feeds (
  account_id uuid primary key references public.accounts (id) on delete cascade,
  token      text not null unique,
  -- When THIS token was made: a reset replaces the token and this stamp.
  created_at timestamptz not null default now(),
  -- 32 random bytes as lowercase hex, and nothing else. The edge function
  -- refuses any other shape before it reaches the database.
  constraint calendar_feed_token_shape check (token ~ '^[0-9a-f]{64}$')
);

comment on table public.calendar_feeds is
  'One calendar-feed token per account (decision 0029). The token is the credential for GET /functions/v1/calendar-feed?t=<token>. No client privilege; made and rotated by my_calendar_feed_token() / reset_my_calendar_feed(), read by calendar_feed_events() for the edge function, removed when the account is deleted.';

alter table public.calendar_feeds enable row level security;
-- No policy on purpose: even a future grant reads nothing until someone writes
-- one deliberately.

-- Hard rule 11: revoke before grant. Default privileges were revoked for
-- anon and authenticated on 2026-08-13; revoke anyway, because a grant you did
-- not write is still a grant.
revoke all on public.calendar_feeds from public, anon, authenticated;
-- service_role holds DML through the default privileges of 20260912000002;
-- written here so the grant is visible in the file that creates the table.
grant select, insert, update, delete on public.calendar_feeds to service_role;

-- ----------------------------------------------------- the account's token ----

create or replace function public.my_calendar_feed_token()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id    uuid := auth.uid();
  v_token text;
begin
  if v_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  -- A deleted account (or a sign-in with no profile) gets nothing: the same
  -- test and the same answer as record_card_consent (20260926000001).
  if not exists (select 1 from public.accounts where id = v_id and deleted_at is null) then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;

  select f.token into v_token from public.calendar_feeds f where f.account_id = v_id;
  if v_token is not null then
    return v_token;
  end if;

  -- First use. Two taps at once: the second insert finds the first one's row
  -- (account_id is the primary key), does nothing, and the read below, a new
  -- statement with a new snapshot, returns the winner's token to both.
  insert into public.calendar_feeds (account_id, token)
  values (v_id, encode(extensions.gen_random_bytes(32), 'hex'))
  on conflict (account_id) do nothing;

  select f.token into v_token from public.calendar_feeds f where f.account_id = v_id;
  return v_token;
end;
$$;

comment on function public.my_calendar_feed_token() is
  'The signed-in account''s calendar-feed token (decision 0029), made on first use: 32 random bytes as hex. The same token on every call until reset_my_calendar_feed(). account_not_found for a deleted account.';

revoke all on function public.my_calendar_feed_token() from public, anon;
grant execute on function public.my_calendar_feed_token() to authenticated;

create or replace function public.reset_my_calendar_feed()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id    uuid := auth.uid();
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  if v_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from public.accounts where id = v_id and deleted_at is null) then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;

  -- The old token is overwritten, not kept: a link someone else has should
  -- stop working, and nothing reads an old token back.
  insert into public.calendar_feeds as f (account_id, token)
  values (v_id, v_token)
  on conflict (account_id) do update
     set token = excluded.token, created_at = now()
  returning f.token into v_token;
  return v_token;
end;
$$;

comment on function public.reset_my_calendar_feed() is
  'Replaces the signed-in account''s calendar-feed token and returns the new one (decision 0029); the old link answers 404 from then on. Not offered in the app yet.';

revoke all on function public.reset_my_calendar_feed() from public, anon;
grant execute on function public.reset_my_calendar_feed() to authenticated;

-- ------------------------------------------------------- the feed's content ----

-- SECURITY INVOKER and executable by service_role only, like
-- stripe_record_dispute (20260928200001): the edge function's role holds
-- SELECT on the tables it reads and bypasses RLS by design; any other role
-- that somehow gained EXECUTE would still be stopped by the table grants.
create or replace function public.calendar_feed_events(p_token text)
returns table (
  registration_id uuid,
  status          registration_status,
  clinic_name     text,
  starts_at       timestamptz,
  ends_at         timestamptz
)
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_account uuid;
begin
  -- Unknown token, and a token whose account has been deleted, are the same
  -- answer: feed_not_found, which the edge function turns into a bare 404.
  select f.account_id into v_account
    from public.calendar_feeds f
    join public.accounts a on a.id = f.account_id
   where f.token = p_token
     and a.deleted_at is null;
  if v_account is null then
    raise exception 'feed_not_found' using errcode = 'P0002';
  end if;

  -- You're In! is a spot; Response Needed is Tara's invitation, shown as
  -- tentative. The Player Pool is not a spot and is left out, and so is a
  -- canceled registration. Only published clinics: a canceled clinic (or one
  -- taken back to draft) leaves the feed, and the phone drops the event at
  -- its next refresh. Clinics that ended up to 30 days ago stay, as history.
  return query
    select r.id, r.status, c.name, c.starts_at, c.ends_at
      from public.players p
      join public.registrations r on r.player_id = p.id
      join public.clinics c       on c.id = r.clinic_id
     where p.account_id = v_account
       and r.status in ('in', 'response_needed')
       and c.status = 'published'
       and c.ends_at >= now() - interval '30 days'
     order by c.starts_at, r.id;
end;
$$;

comment on function public.calendar_feed_events(text) is
  'Not a client RPC: service_role only (decision 0029). The calendar-feed edge function''s read: for a live token, the account''s You''re In! and Response Needed registrations in published clinics that ended at most 30 days ago, as registration id, status, clinic name, start and end, and nothing else. feed_not_found (P0002) for an unknown token or a deleted account.';

revoke all on function public.calendar_feed_events(text) from public, anon, authenticated;
grant execute on function public.calendar_feed_events(text) to service_role;

-- ------------------------------------------------ deletion removes the link ----

create or replace function public.calendar_feed_forget_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.calendar_feeds where account_id = new.id;
  return new;
end;
$$;

comment on function public.calendar_feed_forget_deleted_account() is
  'Trigger on accounts: when deleted_at is set, the account''s calendar-feed token goes, so its link answers 404 (decision 0029).';

-- Trigger functions get no EXECUTE grant: Postgres checks it at CREATE
-- TRIGGER, not when the trigger fires (20260902000001).
revoke all on function public.calendar_feed_forget_deleted_account() from public, anon, authenticated;

drop trigger if exists calendar_feed_forget_deleted_account on public.accounts;
create trigger calendar_feed_forget_deleted_account
  after update of deleted_at on public.accounts
  for each row
  when (new.deleted_at is not null)
  execute function public.calendar_feed_forget_deleted_account();
