-- 20261105000002_level_approval.sql — decision 0048.
--
-- Tara, email of 2026-10-15 (decision 0041, item 4), not built until now:
--   "For a 2.5 player who hasn't been approved, please show: 'You're currently
--    rated 2.5. You can request approval from Tara to attend Ladies 3.0+
--    clinics. Once approved, you can sign up without requesting again.'
--    Button: Request Approval for Ladies 3.0+ ... The request should come to
--    me for approval. Requesting approval does not confirm them for a clinic.
--    I also want to be able to go directly into someone's profile and approve
--    them myself. Their actual rating should stay 2.5 ... That approval stays
--    until I remove it, and they should be notified when approved."
-- and by text, 2026-11-04:
--   "someone as a 2.5 level can request a spot in the 3.0+ clinic. I'd have to
--    approve. Same for 4.0 clinic, 3.5 player needs to ask. And that it's a
--    one time approval. Doesn't need to happen every time"
--
-- THE MODEL
--   A clinic's level is the NTRP number in its name ("Ladies 3.0+", "Men's
--   3.0+", "4.0 Clinic"): clinics.min_rating, a stored generated column, so
--   Tara sets it by naming the clinic the way she already does, every path
--   that creates or renames a clinic (laptop, phone, templates, copy_week)
--   gets it for free, and no RPC signature changes. No number, no gate.
--
--   A player whose own rating is below that number needs an approval at that
--   level or higher. One approval per player per level (level_approvals), so
--   "3.0+" covers every 3.0+ clinic, Ladies or Men's, for good, until Tara
--   removes it. Their rating is never touched.
--
--   Refused at the database, not only hidden (hard rule 1's instinct): a
--   before-insert trigger on registrations and late_requests, beside the
--   audience trigger of decision 0044 and for the same reason (every insert
--   path is covered and register_for_clinic is not copied again). Tara is
--   exempt: she places anyone anywhere (decision 4), and an invitation she
--   sends is accepted with an UPDATE, which this does not touch.
--
-- DEFAULTS until Tara says otherwise (questions in docs/questions-for-tara.md)
--   * A player with no rating is not gated (nothing to compare).
--   * A player two or more levels below may still ask (2.5 for a 4.0 clinic);
--     Tara decides.
--   * Declining a request and removing an approval are the same act: the row
--     goes, and the player can ask again.

-- ── the clinic's level ──────────────────────────────────────────────────────

create or replace function public.clinic_level_from_name(p_name text)
returns numeric
language sql
immutable
set search_path = public, pg_temp
as $$
  -- The first NTRP-shaped number (2.0 to 5.0 in half steps) not glued to
  -- other digits: "Ladies 3.0+" -> 3.0, "105" -> null, "All-Level" -> null.
  select substring(coalesce(p_name, '') from '(?:^|[^0-9.])([2-5]\.[05])(?![0-9])')::numeric(2,1);
$$;
comment on function public.clinic_level_from_name(text) is
  'Decision 0048. The NTRP level written in a clinic''s name, or null.';

alter table public.clinics
  add column min_rating numeric(2,1)
  generated always as (public.clinic_level_from_name(name)) stored;

comment on column public.clinics.min_rating is
  'Decision 0048. The level in the clinic''s name. A player rated below it '
  'registers only with a level_approvals row at this level or above.';

-- Both views gain the column at the end (create or replace may only append).
create or replace view public.clinics_admin as
  select id, template_id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         internal_capacity, status, canceled_at, created_at,
         member_price_cents, nonmember_price_cents, duration_minutes,
         min_rating
    from public.clinics
   where public.is_admin();

create or replace view public.clinics_public as
  select id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         status, canceled_at, member_price_cents, nonmember_price_cents,
         duration_minutes, min_rating
    from public.clinics c
   where (c.status = 'published'
          or (c.status = 'canceled' and c.published_at is not null))
     and c.ends_at > now()
     and (
       c.audience not in ('ladies', 'men')
       or not exists (select 1 from public.players p where p.account_id = auth.uid())
       or exists (select 1 from public.players p
                   where p.account_id = auth.uid()
                     and public.audience_open_to(c.audience, p.gender))
       or exists (select 1 from public.registrations r
                    join public.players p on p.id = r.player_id
                   where r.clinic_id = c.id and p.account_id = auth.uid())
     );

revoke all on public.clinics_admin from public, anon, authenticated;
grant select on public.clinics_admin to authenticated;
revoke all on public.clinics_public from public, anon, authenticated;
grant select on public.clinics_public to authenticated;

-- ── approvals ───────────────────────────────────────────────────────────────

create table public.level_approvals (
  player_id    uuid not null references public.players(id) on delete cascade,
  level        numeric(2,1) not null
               check (level between 2.5 and 5.0 and level * 2 = trunc(level * 2)),
  status       text not null check (status in ('requested', 'approved')),
  requested_at timestamptz,
  approved_at  timestamptz,
  primary key (player_id, level)
);

comment on table public.level_approvals is
  'Decision 0048. A player''s request for, or Tara''s approval of, clinics at '
  'a level above their rating. Written only through request_level_approval '
  'and admin_set_level_approval.';

alter table public.level_approvals enable row level security;

create policy level_approvals_read on public.level_approvals
  for select to authenticated
  using (public.owns_player(player_id) or public.is_admin());

-- Read only. No client writes the table: the two RPCs below are the paths.
revoke all on public.level_approvals from public, anon, authenticated;
grant select (player_id, level, status, requested_at, approved_at)
  on public.level_approvals to authenticated;

-- May this player sign up for a clinic at this level without asking?
create or replace function public.level_ok(p_player uuid, p_min_rating numeric)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_min_rating is null
      or coalesce((select p.adult_rating is null or p.adult_rating >= p_min_rating
                     from public.players p where p.id = p_player), true)
      or exists (select 1 from public.level_approvals a
                  where a.player_id = p_player
                    and a.status = 'approved'
                    and a.level >= p_min_rating);
$$;
comment on function public.level_ok(uuid, numeric) is
  'Decision 0048. True when the clinic has no level, the player has no rating '
  'or is rated at or above it, or Tara approved them at that level or above.';

create or replace function public.guard_clinic_level()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_min numeric;
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  select min_rating into v_min from public.clinics where id = new.clinic_id;
  if not public.level_ok(new.player_id, v_min) then
    raise exception 'level_approval_required' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_clinic_level() from public, anon, authenticated;

create trigger guard_registration_level
  before insert on public.registrations
  for each row execute function public.guard_clinic_level();

create trigger guard_late_request_level
  before insert on public.late_requests
  for each row execute function public.guard_clinic_level();

-- How an approval reads on a profile: Tara's two examples were "Ladies 3.0+"
-- and "Men's 3.0+", so the player's own gender picks the word.
create or replace function public.level_approval_label(p_level numeric, p_gender public.player_gender)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case p_gender
           when 'female' then 'Ladies ' || to_char(p_level, 'FM9.0') || '+'
           when 'male'   then 'Men''s ' || to_char(p_level, 'FM9.0') || '+'
           else to_char(p_level, 'FM9.0') || '+'
         end;
$$;

-- ── the player asks ─────────────────────────────────────────────────────────

create or replace function public.request_level_approval(p_player uuid, p_level numeric)
returns public.level_approvals
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v        public.level_approvals;
  v_admin  uuid;
begin
  if not public.owns_player(p_player) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  if p_level is null or p_level < 2.5 or p_level > 5.0 or p_level * 2 <> trunc(p_level * 2) then
    raise exception 'invalid_level' using errcode = '22023';
  end if;
  select * into v_player from public.players where id = p_player;
  if public.level_ok(p_player, p_level) then
    raise exception 'approval_not_needed' using errcode = 'P0001';
  end if;

  -- Conditional (hard rule 3): a second tap, or a request after Tara already
  -- approved, changes nothing and tells nobody.
  insert into public.level_approvals (player_id, level, status, requested_at)
  values (p_player, p_level::numeric(2,1), 'requested', now())
  on conflict (player_id, level) do nothing
  returning * into v;

  if found then
    for v_admin in select public.admin_account_ids() loop
      perform public.notify_account(v_admin, 'level_request', 'player', p_player,
        v_player.first_name || ' ' || v_player.last_name
        || ' (' || to_char(v_player.adult_rating, 'FM9.0') || ') asked to attend '
        || to_char(p_level, 'FM9.0') || '+ clinics.');
    end loop;
  else
    select * into v from public.level_approvals
     where player_id = p_player and level = p_level;
  end if;
  return v;
end;
$$;
comment on function public.request_level_approval(uuid, numeric) is
  'Decision 0048. The player asks Tara for clinics at a level above their '
  'rating. Does not register them for anything. Idempotent.';

-- ── Tara approves, declines or removes ──────────────────────────────────────

create or replace function public.admin_set_level_approval(p_player uuid, p_level numeric, p_approved boolean)
returns public.level_approvals
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v        public.level_approvals;
  v_was    text;
begin
  perform public.require_admin();
  if p_level is null or p_level < 2.5 or p_level > 5.0 or p_level * 2 <> trunc(p_level * 2) then
    raise exception 'invalid_level' using errcode = '22023';
  end if;
  -- Locks the player so two taps (phone and laptop) send one notification.
  select * into v_player from public.players where id = p_player for update;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  if not coalesce(p_approved, false) then
    delete from public.level_approvals
     where player_id = p_player and level = p_level
    returning * into v;
    return v;
  end if;

  select status into v_was from public.level_approvals
   where player_id = p_player and level = p_level;

  insert into public.level_approvals (player_id, level, status, approved_at)
  values (p_player, p_level::numeric(2,1), 'approved', now())
  on conflict (player_id, level) do update
     set status = 'approved',
         approved_at = coalesce(public.level_approvals.approved_at, now())
  returning * into v;

  if v_was is distinct from 'approved' then
    perform public.notify_account(v_player.account_id, 'level_approved', 'player', p_player,
      -- Question 123's sentence, until Tara changes it.
      'You''re approved to attend ' || public.level_approval_label(p_level, v_player.gender)
      || ' clinics.');
  end if;
  return v;
end;
$$;
comment on function public.admin_set_level_approval(uuid, numeric, boolean) is
  'Admin-only (decision 0048). true approves (from a request or directly on '
  'the profile) and notifies the player once; false declines a request or '
  'removes an approval.';

-- Tara's list: every request and approval, with who it is.
create or replace function public.admin_level_approvals()
returns table (
  player_id uuid, first_name text, last_name text, adult_rating numeric,
  gender public.player_gender, level numeric, status text,
  requested_at timestamptz, approved_at timestamptz, label text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
    select a.player_id, p.first_name, p.last_name, p.adult_rating, p.gender,
           a.level, a.status, a.requested_at, a.approved_at,
           public.level_approval_label(a.level, p.gender)
      from public.level_approvals a
      join public.players p on p.id = a.player_id
     order by (a.status = 'requested') desc, a.requested_at, p.last_name, p.first_name;
end;
$$;

-- ── the rating is Tara's once it is set ─────────────────────────────────────
-- Since 2026-09-02 a player could change their own rating on Edit details,
-- which would make this whole gate one edit deep: a 2.5 types 3.0 and walks
-- in. Tara: "Their actual rating should stay 2.5". So the rating becomes what
-- membership became on 2026-09-21: the player gives it at sign-up (or once,
-- if it was never given), and after that it is Tara's (hard rule 8).
--
-- A trigger, not a revoked column grant: the 1.0.x app in the store sends
-- adult_rating with every Edit details save, and a revoked grant would make
-- that whole save fail (name and phone too) even when the rating is
-- unchanged. The trigger refuses only an actual change.

create or replace function public.guard_player_rating()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.adult_rating is not null
     and new.adult_rating is distinct from old.adult_rating
     and auth.uid() is not null
     and not public.is_admin() then
    raise exception 'rating_set_by_tara' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_player_rating() from public, anon, authenticated;

create trigger guard_player_rating
  before update of adult_rating on public.players
  for each row execute function public.guard_player_rating();

create or replace function public.admin_set_player_rating(p_player uuid, p_rating numeric)
returns public.players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.players;
begin
  perform public.require_admin();
  -- The column's own check (adult_rating_is_ntrp_bucket) refuses anything
  -- that is not 2.0 to 5.0 in half steps.
  update public.players set adult_rating = p_rating where id = p_player
  returning * into v;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;
  return v;
end;
$$;
comment on function public.admin_set_player_rating(uuid, numeric) is
  'Admin-only (decision 0048). Tara corrects a player''s rating; the player '
  'cannot change it once set (guard_player_rating).';

-- ── no second player row ────────────────────────────────────────────────────
-- The sql-auditor, 2026-11-05: a 2.5 could insert a second players row on her
-- own account, rated 3.0 (or unrated), and register that row. No client
-- inserts players (sign-up is create_my_account, which runs as the owner), so
-- the table-level INSERT, which no migration ever granted but a database can
-- hold by default, is taken away explicitly.
revoke insert on public.players from anon, authenticated;

-- ── grants ──────────────────────────────────────────────────────────────────

revoke all on function public.clinic_level_from_name(text) from public, anon;
revoke all on function public.level_ok(uuid, numeric) from public, anon, authenticated;
revoke all on function public.level_approval_label(numeric, public.player_gender) from public, anon;
revoke all on function public.request_level_approval(uuid, numeric) from public, anon, authenticated;
revoke all on function public.admin_set_level_approval(uuid, numeric, boolean) from public, anon, authenticated;
revoke all on function public.admin_level_approvals() from public, anon, authenticated;
revoke all on function public.admin_set_player_rating(uuid, numeric) from public, anon, authenticated;
grant execute on function public.clinic_level_from_name(text) to authenticated;
grant execute on function public.level_approval_label(numeric, public.player_gender) to authenticated;
grant execute on function public.request_level_approval(uuid, numeric) to authenticated;
grant execute on function public.admin_set_level_approval(uuid, numeric, boolean) to authenticated;
grant execute on function public.admin_level_approvals() to authenticated;
grant execute on function public.admin_set_player_rating(uuid, numeric) to authenticated;
