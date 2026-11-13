-- 20261111000002_pro_rounds.sql — decision 0056.
--
-- Tara, 2026-11-11, relayed by John: "Currently, my pros can't put people on
-- a court... Just wanna make sure that they can position people on the
-- courts like I can do now", and on the 105 rounds: "I think can change the
-- rounds. That's totally fine. Probably need it in case I'm out of town".
-- John approved it for 1.0.4.
--
-- A pro could already give a You're In! player a court in their week
-- (pro_assign_court, decision 0051). What was missing is the 105 rounds:
-- since decision 0054 Tara wrote them (admin_set_round_court) and a pro only
-- read them (clinic_rounds).
--
-- THE RULE: a pro writes a 105's rounds exactly where they already read
-- them, a clinic in their week. Tara (is_admin) as before, or a pro for a
-- clinic that is published and starts on today's New York date or one of the
-- six after it: clinic_rounds' window, pro_week's window. Anything outside it
-- (a clinic eight days out, a draft, a canceled clinic, an id that is no
-- clinic) is one answer, not_this_week, so a pro learns nothing about a
-- clinic they cannot see. A player is refused not_authorized, as before.
--
--   admin_set_round_court: redefined. A pro passes require_pro() instead of
--     require_admin(); then the clinic's FOR UPDATE lock, and the week test
--     under it. Every other check and refusal is the one Tara already gets
--     (invalid_round, invalid_court, invalid_people, already_in_round,
--     not_105, clinic_canceled, not_in_clinic, clinic_not_found for her). The
--     name keeps its admin_ prefix: renaming it would break the 1.0.3 app and
--     the laptop, which call it by name.
--   clinic_round_people: new. The roster a round is picked from, which Tara's
--     screens build from her own reads (registrations_admin, guests) and a
--     pro could not: You're In! registrations (the registration id, the
--     player's first and last name) and guests not removed (the guest id and
--     names), ordered by last name, then first. The ids are the ones
--     admin_set_round_court takes. Names only: nothing financial, no notes,
--     no phone or email, no count beyond the list itself, which a pro already
--     has from pro_week. Same access as clinic_rounds; players never.
--
-- Pinned by tests/sql/pro_rounds.sql; tests/sql/tara_items_0054.sql's "a pro
-- cannot set rounds" row now reads the new rule.

create or replace function public.admin_set_round_court(
  p_clinic uuid, p_round integer, p_court integer, p_people uuid[])
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.clinics;
  i integer;
  v_id uuid;
  v_reg uuid;
  v_guest uuid;
  v_admin boolean := public.is_admin();
begin
  -- Tara, or a pro (decision 0056); a pro's clinic is checked below.
  if not v_admin then
    perform public.require_pro();
  end if;
  if p_round is null or p_round not between 1 and 3 then
    raise exception 'invalid_round' using errcode = 'P0001';
  end if;
  if p_court is null or p_court not between 1 and 5 then
    raise exception 'invalid_court' using errcode = 'P0001';
  end if;
  if p_people is null or cardinality(p_people) <> 6 or array_ndims(p_people) <> 1 then
    raise exception 'invalid_people' using errcode = 'P0001';
  end if;
  if (select count(*) from unnest(p_people) x where x is not null)
     <> (select count(distinct x) from unnest(p_people) x where x is not null) then
    raise exception 'already_in_round' using errcode = 'P0001';
  end if;
  -- The clinic's lock: two devices saving the same court (hers, or hers and
  -- a pro's) are one after the other, and nobody leaves the clinic halfway
  -- through.
  select * into c from public.clinics where id = p_clinic for update;
  if not found then
    if v_admin then
      raise exception 'clinic_not_found' using errcode = 'P0002';
    end if;
    raise exception 'not_this_week' using errcode = 'P0001';
  end if;
  -- A pro: one answer for anything outside the week, as clinic_rounds and
  -- pro_assign_court.
  if not v_admin
     and (c.status <> 'published'
          or public.new_york_date(c.starts_at) not between public.new_york_date(now())
                                                       and public.new_york_date(now()) + 6) then
    raise exception 'not_this_week' using errcode = 'P0001';
  end if;
  if not public.is_105(c.name, c.category) then
    raise exception 'not_105' using errcode = 'P0001';
  end if;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;

  delete from public.clinic_round_spots
   where clinic_id = p_clinic and round_number = p_round and court_number = p_court;

  for i in 1..6 loop
    v_id := p_people[i];
    continue when v_id is null;
    v_reg := null; v_guest := null;
    select id into v_reg from public.registrations
     where id = v_id and clinic_id = p_clinic and status = 'in';
    if v_reg is null then
      select id into v_guest from public.clinic_guests
       where id = v_id and clinic_id = p_clinic and removed_at is null;
    end if;
    if v_reg is null and v_guest is null then
      raise exception 'not_in_clinic' using errcode = 'P0001';
    end if;
    -- On another court of this round: moved here.
    delete from public.clinic_round_spots
     where clinic_id = p_clinic and round_number = p_round
       and (registration_id = v_reg or guest_id = v_guest);
    insert into public.clinic_round_spots
      (clinic_id, round_number, court_number, side, slot, registration_id, guest_id)
    values (p_clinic, p_round, p_court, ((i - 1) / 3) + 1, ((i - 1) % 3) + 1, v_reg, v_guest);
  end loop;
end;
$$;
revoke all on function public.admin_set_round_court(uuid, integer, integer, uuid[]) from public, anon;
grant execute on function public.admin_set_round_court(uuid, integer, integer, uuid[]) to authenticated;

-- Who a round can be picked from: You're In! then live guests, by last name.
-- person_id is the registration's id or the guest's, what
-- admin_set_round_court takes. Tara, and a pro for a 105 in their week;
-- nobody else. Positional ORDER BY: the output names are also this
-- function's OUT parameters, which plpgsql would read as ambiguous.
create or replace function public.clinic_round_people(p_clinic uuid)
returns table(person_id uuid, first_name text, last_name text, is_guest boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  c public.clinics;
begin
  if not public.is_admin() then
    perform public.require_pro();
    select * into c from public.clinics where id = p_clinic;
    -- One answer for anything outside the week, as clinic_rounds.
    if not found or c.status <> 'published'
       or public.new_york_date(c.starts_at) not between public.new_york_date(now())
                                                    and public.new_york_date(now()) + 6 then
      raise exception 'not_this_week' using errcode = 'P0001';
    end if;
    -- Rounds are a 105 thing: a pro's other clinics already show their
    -- players (pro_week), never their guests, so this is no wider than that.
    if not public.is_105(c.name, c.category) then
      raise exception 'not_105' using errcode = 'P0001';
    end if;
  end if;
  return query
    select r.id, p.first_name, p.last_name, false
      from public.registrations r
      join public.players p on p.id = r.player_id
     where r.clinic_id = p_clinic and r.status = 'in'
    union all
    select g.id, g.first_name, g.last_name, true
      from public.clinic_guests g
     where g.clinic_id = p_clinic and g.removed_at is null
    order by 3, 2, 1;
end;
$$;
revoke all on function public.clinic_round_people(uuid) from public, anon;
grant execute on function public.clinic_round_people(uuid) to authenticated;
