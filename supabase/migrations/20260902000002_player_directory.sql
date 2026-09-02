-- Player directory: the three things Tara does to a person, not a registration.
--
-- WHAT WAS MISSING
-- ----------------
-- `player_notes` has existed since the first migration and RLS admits only
-- admins, but `authenticated` holds no privilege on it at all (revoked in
-- 20260728000002, never re-granted), and no RPC touched it. So Tara's private
-- notes had a table, a policy, and no way in. `search_players` even reports
-- `has_notes`, about notes nobody could write. Membership had the same shape:
-- Tara said "I can correct anyone's status on their profile" (for-tara.md,
-- question 5) and nothing let her.
--
-- WHY RPCs AND NOT A GRANT
-- ------------------------
-- The pattern everywhere else: tables are read through views or RPCs and
-- written only through RPCs, so every write is one auditable function that
-- starts with require_admin(). A direct UPDATE grant on `players` would also
-- expose columns Tara has no business editing from a directory (account_id,
-- kind, date_of_birth), and hard rule 8 is about exactly that kind of drift.
--
-- Notes are one of the nine hidden facts (information_hiding.sql, check 7):
-- a player must never see their own note. Reading goes through an admin-only
-- RPC, never a view a player could reach.

-- Read one player's note. Empty string when there is none, so the client
-- shows an empty box rather than handling "no row" as a special case.
create or replace function public.admin_player_note(p_player uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return coalesce((select n.body from public.player_notes n where n.player_id = p_player), '');
end;
$$;

-- Write it. Upsert, because a note is a property of the player, not an event.
-- Saving an empty note deletes the row so `has_notes` stays honest.
create or replace function public.admin_set_player_note(p_player uuid, p_body text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_body text := btrim(coalesce(p_body, ''));
begin
  perform public.require_admin();
  if not exists (select 1 from public.players p where p.id = p_player) then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;
  if v_body = '' then
    delete from public.player_notes where player_id = p_player;
    return;
  end if;
  insert into public.player_notes (player_id, body, updated_at)
  values (p_player, v_body, now())
  on conflict (player_id) do update set body = excluded.body, updated_at = now();
end;
$$;

-- Membership is self-reported at sign-up and corrected here. It decides which
-- registration window opens first and which published rate is shown, so it is
-- Tara's call and nobody else's (hard rule 2: nothing auto-promotes).
create or replace function public.admin_set_membership(p_player uuid, p_is_member boolean)
returns public.players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.players;
begin
  perform public.require_admin();
  update public.players set is_member = p_is_member where id = p_player
  returning * into v;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;
  return v;
end;
$$;

comment on function public.admin_player_note(uuid) is
  'Admin-only. Tara''s private note on a player; empty string when none. Never exposed to the player.';
comment on function public.admin_set_player_note(uuid, text) is
  'Admin-only upsert of the private note. Empty body deletes the row so has_notes stays honest.';
comment on function public.admin_set_membership(uuid, boolean) is
  'Admin-only. Corrects self-reported membership (for-tara.md question 5).';

-- Hard rule 11: revoke before grant, and from PUBLIC, not just anon.
revoke all on function public.admin_player_note(uuid) from public, anon, authenticated;
revoke all on function public.admin_set_player_note(uuid, text) from public, anon, authenticated;
revoke all on function public.admin_set_membership(uuid, boolean) from public, anon, authenticated;
grant execute on function public.admin_player_note(uuid) to authenticated;
grant execute on function public.admin_set_player_note(uuid, text) to authenticated;
grant execute on function public.admin_set_membership(uuid, boolean) to authenticated;
