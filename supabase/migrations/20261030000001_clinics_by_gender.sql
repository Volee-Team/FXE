-- 20261030000001_clinics_by_gender.sql
--
-- Decision 0044. Tara, 2026-10-30 (relayed by John): "if you're a man, you
-- should only be able to see the registration for coed or men's league. You
-- shouldn't be able to see any ladies clinics." Same for women: Ladies and
-- Coed only. Asked at sign-up, and once of every existing player.
--
-- What this adds:
--   1. players.gender, nullable. NULL means "not answered yet", and a player
--      who has not answered sees and may register for everything (the 1.0.0
--      app in the store has no question, decision 0044 question 132).
--   2. audience_open_to(audience, gender): the one place the rule lives.
--   3. clinics_public hides a Ladies clinic from an account whose players are
--      all men, and a Men clinic from one whose players are all women. A
--      clinic the account already has a registration in stays visible, so a
--      spot Tara placed by hand never vanishes from My Clinics. Tara's own
--      screens read clinics_admin, which is unchanged.
--   4. A trigger on registrations and late_requests refuses a player's own
--      insert for a clinic not open to them (audience_mismatch). A trigger,
--      not a line inside register_for_clinic, so every path that inserts is
--      covered and register_for_clinic's body is not copied again. Tara (an
--      admin) and server jobs with no signed-in user are exempt: she places
--      anyone anywhere (decision 4).
--   5. set_my_gender: the player answers once. Changing an answer is Tara's,
--      through admin_set_player_gender (the web admin's Players tab). There is
--      no column grant, so a player cannot write the column directly, and a
--      trigger backstops any future path (hard rule 8's three layers).
--   6. search_players returns gender for the Players tab.

-- 1. The column ---------------------------------------------------------------
create type public.player_gender as enum ('female', 'male');

alter table public.players add column gender public.player_gender;

comment on column public.players.gender is
  'Decision 0044. Which audience-restricted clinics the player sees: female sees Ladies and Coed, male sees Men and Coed. NULL = not answered yet, sees everything. Set once by the player (set_my_gender); changed only by an admin (admin_set_player_gender).';

-- 2. The rule -----------------------------------------------------------------
create or replace function public.audience_open_to(p_audience public.clinic_audience, p_gender public.player_gender)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select p_gender is null
      or p_audience is null
      or p_audience not in ('ladies', 'men')
      or (p_audience = 'ladies' and p_gender = 'female')
      or (p_audience = 'men'    and p_gender = 'male');
$$;
comment on function public.audience_open_to(public.clinic_audience, public.player_gender) is
  'Decision 0044: may a player of this gender see and register for a clinic of this audience. Coed and Juniors are open to everyone; an unanswered gender is open to everything.';

-- 3. The view -----------------------------------------------------------------
-- Same columns, same order as 20260929000001 (CREATE OR REPLACE keeps the
-- grants); only the WHERE grows. The view runs with its owner's rights (hard
-- rule 11: never security_invoker), so it reads players and registrations
-- directly; auth.uid() is still the caller.
create or replace view public.clinics_public as
  select id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         status, canceled_at, member_price_cents, nonmember_price_cents,
         duration_minutes
    from public.clinics c
   where (c.status = 'published'
          or (c.status = 'canceled' and c.published_at is not null))
     and c.ends_at > now()
     and (
       c.audience not in ('ladies', 'men')
       -- No is_admin() here: Tara's screens read clinics_admin, and a view
       -- that names is_admin() is one pro_role.sql expects to be admin-only.
       -- No player row yet (mid sign-up): nothing to decide by.
       or not exists (select 1 from public.players p where p.account_id = auth.uid())
       -- Any of the account's players may attend it.
       or exists (select 1 from public.players p
                   where p.account_id = auth.uid()
                     and public.audience_open_to(c.audience, p.gender))
       -- Already holds a registration in it (Tara placed them, or it predates
       -- the answer): their own clinic never disappears.
       or exists (select 1 from public.registrations r
                    join public.players p on p.id = r.player_id
                   where r.clinic_id = c.id and p.account_id = auth.uid())
     );

revoke all on public.clinics_public from public, anon, authenticated;
grant select on public.clinics_public to authenticated;

-- 4. Enforcement on the write paths ------------------------------------------
create or replace function public.guard_clinic_audience()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_audience public.clinic_audience;
  v_gender   public.player_gender;
begin
  -- Tara places anyone anywhere; migrations, seeds and server jobs have no
  -- signed-in user.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  select audience into v_audience from public.clinics where id = new.clinic_id;
  select gender   into v_gender   from public.players where id = new.player_id;
  if not public.audience_open_to(v_audience, v_gender) then
    raise exception 'audience_mismatch' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_clinic_audience() from public, anon, authenticated;

create trigger guard_registration_audience
  before insert on public.registrations
  for each row execute function public.guard_clinic_audience();

create trigger guard_late_request_audience
  before insert on public.late_requests
  for each row execute function public.guard_clinic_audience();

-- 5. Who writes the answer ----------------------------------------------------
-- The player, once. Every adult player on the caller's account that has no
-- answer yet gets this one (v1 is one adult per account, decision 0004).
create or replace function public.set_my_gender(p_player uuid, p_gender public.player_gender)
returns public.players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.players;
begin
  if p_gender is null then
    raise exception 'gender_required' using errcode = '22023';
  end if;
  if not public.owns_player(p_player) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  -- Conditional (hard rule 3): only an unanswered row. A second answer, or
  -- the same answer twice, changes nothing and says so.
  update public.players set gender = p_gender
   where id = p_player and gender is null
  returning * into v;
  if not found then
    select * into v from public.players where id = p_player;
    if v.gender is distinct from p_gender then
      raise exception 'gender_already_set' using errcode = 'P0001';
    end if;
  end if;
  return v;
end;
$$;
comment on function public.set_my_gender(uuid, public.player_gender) is
  'Decision 0044. The player answers once (sign-up, or the one-time prompt). Repeating the same answer is a no-op; a different one is refused: changes are Tara''s (admin_set_player_gender).';

-- Tara, any time, including back to "not answered" (NULL).
create or replace function public.admin_set_player_gender(p_player uuid, p_gender public.player_gender)
returns public.players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.players;
begin
  perform public.require_admin();
  update public.players set gender = p_gender where id = p_player
  returning * into v;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;
  return v;
end;
$$;
comment on function public.admin_set_player_gender(uuid, public.player_gender) is
  'Admin-only. Corrects a player''s answer, or clears it (decision 0044).';

-- Layer 3, the backstop: once answered, only an admin (or a migration, with
-- no signed-in user) changes it, whatever path a future change arrives by.
create or replace function public.guard_player_gender()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.gender is not null
     and new.gender is distinct from old.gender
     and auth.uid() is not null
     and not public.is_admin() then
    raise exception 'gender_already_set' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_player_gender() from public, anon, authenticated;

create trigger guard_player_gender
  before update of gender on public.players
  for each row execute function public.guard_player_gender();

-- A new player row arrives without an answer unless an admin writes it:
-- INSERT on players is the owner's (players_insert_own), and an answer
-- chosen there would skip set_my_gender's once-only rule.
create or replace function public.guard_player_gender_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.gender is not null and auth.uid() is not null and not public.is_admin() then
    new.gender := null;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_player_gender_insert() from public, anon, authenticated;

create trigger guard_player_gender_insert
  before insert on public.players
  for each row execute function public.guard_player_gender_insert();

-- Hard rule 11: revoke before grant, from PUBLIC and anon.
revoke all on function public.audience_open_to(public.clinic_audience, public.player_gender) from public, anon;
revoke all on function public.set_my_gender(uuid, public.player_gender) from public, anon, authenticated;
revoke all on function public.admin_set_player_gender(uuid, public.player_gender) from public, anon, authenticated;
grant execute on function public.audience_open_to(public.clinic_audience, public.player_gender) to authenticated;
grant execute on function public.set_my_gender(uuid, public.player_gender) to authenticated;
grant execute on function public.admin_set_player_gender(uuid, public.player_gender) to authenticated;

-- 6. The Players tab reads the answer -----------------------------------------
-- Same body as 20260921000002 plus the last column.
drop function public.search_players(text, boolean);
create function public.search_players(p_query text, p_include_inactive boolean default false)
returns table (
  id uuid, first_name text, last_name text, kind public.player_kind,
  age integer, adult_rating numeric, is_member boolean, is_active boolean,
  has_notes boolean, level_note text, waiver_accepted boolean,
  gender public.player_gender
)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
    select p.id, p.first_name, p.last_name, p.kind,
           public.player_age(p.date_of_birth), p.adult_rating,
           p.is_member, p.is_active,
           exists (select 1 from public.player_notes n
                    where n.player_id = p.id and n.body <> ''),
           p.level_note,
           public.waiver_accepted(p.account_id),
           p.gender
      from public.players p
     where (p_include_inactive or p.is_active)
       and (
         p_query is null or p_query = ''
         or p.first_name ilike '%' || p_query || '%'
         or p.last_name  ilike '%' || p_query || '%'
       )
     order by p.last_name, p.first_name;
end;
$$;
revoke all on function public.search_players(text, boolean) from public, anon;
grant execute on function public.search_players(text, boolean) to authenticated;
