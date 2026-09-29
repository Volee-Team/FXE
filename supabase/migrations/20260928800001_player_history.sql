-- 20260928800001_player_history.sql
--
-- A player's history at a glance, so choosing from the Player Pool takes one
-- look (decision 0027 §1). Tara picks every invitation by hand (hard rule 2);
-- today she remembers who comes and who does not. This puts the record beside
-- the name and decides nothing: no ranking, no sort, no suggestion.
--
-- admin_player_history(p_player uuid default null)
--   One row per player: every player when p_player is null (the web admin's
--   Player Pool lists and Players tab, and the phone's Pool rows, one call per
--   render), that one player otherwise (the phone's player page), and no row
--   for an id that is no player. Every player, not only those with a history:
--   a row of zeros is the answer "New", and absence would be ambiguous with
--   "not asked".
--
--   played          You're In! (status 'in'), not marked a no-show, in a clinic
--                   that is not canceled and has ended (ends_at <= now()). This
--                   is the board report's ATTENDED (20260926000010), reused
--                   word for word: two definitions of "came" would drift.
--   no_shows        The same rows with no_show set: Tara marked them as not
--                   having come. Only once the clinic has ended, like played,
--                   so the two partition one set of rows (and a flag she flips
--                   back during the clinic never shows here).
--   late_cancels    Canceled inside the cutoff (late_cancel, status
--                   'canceled'), by the player or recorded by Tara, in a clinic
--                   that is not canceled. Counted as soon as it happens: a late
--                   cancel is final once made.
--   last_played_at  The start of the most recent played clinic, or null.
--
-- A CANCELED CLINIC DID NOT HAPPEN, so nothing in it counts: cancel_clinic
-- leaves every registration's status as it was, so without that condition a
-- rained-out clinic would read as played, and a late cancel from a clinic she
-- later called off (which Charge clinic never charges) would count against the
-- player. A Pool entry, an invitation, a cancel before the cutoff, and a clinic
-- still to come count as nothing.
--
-- HIDDEN FROM PLAYERS (hard rule 1: never return a count of anything to a
-- player). SECURITY DEFINER because it reads registrations and clinics, which
-- no client can; require_admin() first, so a member gets not_authorized, never
-- a row of zeros; search_path pinned; revoked from PUBLIC and anon before the
-- grant (hard rule 11: revoke from anon alone is decoration while PUBLIC holds
-- EXECUTE). Pinned by tests/sql/player_history.sql.

create or replace function public.admin_player_history(p_player uuid default null)
returns table (
  player_id      uuid,
  played         integer,
  no_shows       integer,
  late_cancels   integer,
  last_played_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- Every column reference below is qualified: in plpgsql the RETURNS TABLE
-- names are variables, and an unqualified column of the same name would be
-- ambiguous (the board report's note, 20260926000010).
begin
  perform public.require_admin();

  return query
  with facts as (
    select r.player_id as pid,
           case
             when r.status = 'in' and c.ends_at <= now() and not r.no_show then 'played'
             when r.status = 'in' and c.ends_at <= now() and r.no_show     then 'no_show'
             when r.status = 'canceled' and r.late_cancel                   then 'late_cancel'
           end as kind,
           c.starts_at as clinic_starts_at
      from public.registrations r
      join public.clinics c on c.id = r.clinic_id
     where c.status <> 'canceled'
       and (p_player is null or r.player_id = p_player)
  )
  select pl.id,
         (count(*) filter (where f.kind = 'played'))::integer,
         (count(*) filter (where f.kind = 'no_show'))::integer,
         (count(*) filter (where f.kind = 'late_cancel'))::integer,
         max(f.clinic_starts_at) filter (where f.kind = 'played')
    from public.players pl
    left join facts f on f.pid = pl.id
   where p_player is null or pl.id = p_player
   group by pl.id
   order by pl.id;
end;
$$;

comment on function public.admin_player_history(uuid) is
  'Admin only (decision 0027 §1). Per player: clinics played (the board report''s '
  'attended: You''re In!, not a no-show, clinic ended and not canceled), no-shows '
  '(the same rows, flagged), late cancellations (in a clinic not canceled), and the '
  'start of the last clinic played. Every player when p_player is null.';

revoke all on function public.admin_player_history(uuid) from public, anon, authenticated;
grant execute on function public.admin_player_history(uuid) to authenticated;
