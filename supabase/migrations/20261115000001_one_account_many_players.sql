-- 20261115000001_one_account_many_players.sql
--
-- Juniors, phase 0 (`docs/juniors/plan.md`, decision 0057). Today every
-- account has exactly one players row, the adult. A parent is about to own
-- junior rows too, and an audit of every account-to-player lookup (2026-11-14)
-- found the places that would break, pick the wrong row, or open a hole.
-- This migration makes the database safe for that BEFORE any child row can
-- exist. Nothing here creates a child: INSERT on players stays revoked from
-- clients, and the add-a-child function comes in phase 1.
--
-- THE RULE: an app already on someone's phone sees exactly what it sees
-- today. 1.0.3 and 1.0.4 read `players` and `my_registrations` and take the
-- first row as "me" and a clinic's registration as "mine"; with a child on
-- the account they would become the child, or cancel the child's spot. So
-- what those apps read keeps returning the adult's rows only, and the family
-- is read through new functions the 1.0.5 app and the members' site call
-- (phase 1 and 2).
--
--   1. One adult per account (a unique index). Every account keeps its adult
--      row, a parent who never plays included, so "me" is always well
--      defined. Hosted, 2026-11-15: 372 accounts, each with exactly one
--      adult, no juniors.
--   2. A member's SELECT and UPDATE on players reach the adult row only.
--      Tara (admin) still reads and writes every row.
--   3. my_registrations and my_past_clinics: the adult's rows only.
--   4. clinics_public: no juniors clinics (they cannot be registered for
--      from these apps), and the Ladies / Men rule reads the ADULT's gender,
--      never a child's. With any player on the account, a mother with a son would
--      have seen Men's clinics, and a child with no answer (null opens both)
--      would have opened every one.
--   5. A junior plays only in a juniors clinic, and an adult never in one,
--      unless Tara places them (wrong_player_kind). This also closes the
--      level-check hole of 2026-11-05: level_ok passes an unrated row, and a
--      child is an unrated row.
--   6. The calendar feed names a child's clinics ("Sam: Red Dot"), so two
--      children in one clinic are two events and a parent knows whose it is.
--   7. delete_my_account blanks every player's birthday, which the
--      junior_has_dob check refused for a child row, so a parent could not
--      delete their account. A birthday is required while the row is active;
--      deleting sets is_active false in the same statement.
--
-- Probe: tests/sql/one_account_many_players.sql (red first on every item).

-- 1. ----------------------------------------------------------------------
create unique index if not exists players_one_adult_per_account
  on public.players (account_id) where kind = 'adult';

-- 2. ----------------------------------------------------------------------
drop policy if exists players_own on public.players;
create policy players_own on public.players
  for select using ((account_id = auth.uid() and kind = 'adult') or public.is_admin());

-- An update through the table reaches the adult row only as well: with a
-- WHERE clause the read policy already hides a child, but an update with
-- none would write the granted columns onto every row of the account. A
-- child is edited through phase 1's functions.
drop policy if exists players_update_own on public.players;
create policy players_update_own on public.players
  for update
  using      ((account_id = auth.uid() and kind = 'adult') or public.is_admin())
  with check ((account_id = auth.uid() and kind = 'adult') or public.is_admin());

-- 3. ----------------------------------------------------------------------
create or replace view public.my_registrations as
  select id, clinic_id, player_id, status, paid, registered_at, invited_at, responded_at, canceled_at,
         late_cancel, courtesy_used, player_note
    from public.registrations r
   where exists (select 1 from public.players p
                  where p.id = r.player_id and p.account_id = auth.uid() and p.kind = 'adult');

revoke all on public.my_registrations from public, anon, authenticated;
grant select on public.my_registrations to authenticated;

create or replace view public.my_past_clinics as
SELECT r.id AS registration_id,
    c.id AS clinic_id,
    c.name,
    c.starts_at,
    c.ends_at,
    c.duration_minutes,
    c.category,
    c.audience,
    r.status,
    r.no_show,
    r.late_cancel,
    r.canceled_at,
    r.price_cents_charged,
    r.paid,
    (c.status = 'canceled'::clinic_status) AS clinic_canceled
   FROM (registrations r
     JOIN clinics c ON ((c.id = r.clinic_id)))
  WHERE (EXISTS (SELECT 1 FROM players p
                  WHERE p.id = r.player_id AND p.account_id = auth.uid() AND p.kind = 'adult')
     -- Only spots she held or gave up: a Player Pool spot never picked or an
     -- invitation never answered is not a clinic she played (audit 2026-10-12:
     -- it read "Played, $18").
     AND r.status IN ('in'::registration_status, 'canceled'::registration_status) AND ((c.status = 'published'::clinic_status) OR ((c.status = 'canceled'::clinic_status) AND (c.published_at IS NOT NULL))) AND (c.ends_at <= now()));

revoke all on public.my_past_clinics from public, anon, authenticated;
grant select on public.my_past_clinics to authenticated;

-- 4. ----------------------------------------------------------------------
create or replace view public.clinics_public as
  select id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         status, canceled_at, member_price_cents, nonmember_price_cents,
         duration_minutes,
         (case when public.level_check_enabled() then min_rating end)::numeric(2,1) as min_rating
    from public.clinics c
   where (c.status = 'published'
          or (c.status = 'canceled' and c.published_at is not null))
     and c.ends_at > now()
     -- Juniors clinics are read through the family functions (phase 1 and
     -- 2): an app that cannot register a child would only show a Register
     -- button that wrong_player_kind refuses.
     and c.audience <> 'juniors'
     and (
       c.audience not in ('ladies', 'men')
       or not exists (select 1 from public.players p
                       where p.account_id = auth.uid() and p.kind = 'adult')
       or exists (select 1 from public.players p
                   where p.account_id = auth.uid() and p.kind = 'adult'
                     and public.audience_open_to(c.audience, p.gender))
       or exists (select 1 from public.registrations r
                    join public.players p on p.id = r.player_id
                   where r.clinic_id = c.id and p.account_id = auth.uid() and p.kind = 'adult')
     );

revoke all on public.clinics_public from public, anon, authenticated;
grant select on public.clinics_public to authenticated;

-- 5. ----------------------------------------------------------------------
create or replace function public.guard_player_kind()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_audience public.clinic_audience;
  v_kind     public.player_kind;
begin
  -- Tara places anyone anywhere (a strong 15-year-old in an adult drill is
  -- her call); migrations, seeds and server jobs have no signed-in user.
  -- The same exemption as guard_clinic_audience (20261030000001).
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  select audience into v_audience from public.clinics where id = new.clinic_id;
  select kind     into v_kind     from public.players where id = new.player_id;
  if (v_kind = 'junior') <> (v_audience = 'juniors') then
    raise exception 'wrong_player_kind' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_player_kind() from public, anon, authenticated;

drop trigger if exists guard_registration_player_kind on public.registrations;
create trigger guard_registration_player_kind
  before insert or update of clinic_id, player_id on public.registrations
  for each row execute function public.guard_player_kind();

drop trigger if exists guard_late_request_player_kind on public.late_requests;
create trigger guard_late_request_player_kind
  before insert or update of clinic_id, player_id on public.late_requests
  for each row execute function public.guard_player_kind();

-- 6. ----------------------------------------------------------------------
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
  -- A child's clinic carries the child's first name (20261115000001), so
  -- the parent knows whose it is and two children are two events.
  return query
    select r.id, r.status,
           case when p.kind = 'junior' then p.first_name || ': ' || c.name else c.name end,
           c.starts_at, c.ends_at
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
  'Not a client RPC: service_role only (decision 0029). The calendar-feed edge function''s read: for a live token, the account''s You''re In! and Response Needed registrations in published clinics that ended at most 30 days ago, as registration id, status, clinic name (a child''s prefixed with the child''s first name, 20261115000001), start and end, and nothing else. feed_not_found (P0002) for an unknown token or a deleted account.';

revoke all on function public.calendar_feed_events(text) from public, anon, authenticated;
grant execute on function public.calendar_feed_events(text) to service_role;

-- 7. ----------------------------------------------------------------------
alter table public.players drop constraint if exists junior_has_dob;
alter table public.players add constraint junior_has_dob
  check (kind <> 'junior' or date_of_birth is not null or not is_active);
