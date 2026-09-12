-- When was this note last edited?
--
-- Why: a private note with no date is a note Tara cannot trust. "Prefers
-- court 2" from March reads the same as one from yesterday. `player_notes`
-- already carries updated_at; nothing exposed it. Same shape as
-- admin_player_note (20260902000002): SECURITY DEFINER, require_admin() first,
-- pinned search_path, no privilege for anyone but authenticated.
-- Returns null when there is no note, which the page shows as nothing.

create or replace function public.admin_player_note_edited(p_player uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return (select n.updated_at from public.player_notes n where n.player_id = p_player);
end;
$$;

comment on function public.admin_player_note_edited(uuid) is
  'updated_at of the admin''s private note on a player, or null. Admin only.';

-- Hard rule 11: revoke before grant, and from PUBLIC, not just anon.
revoke all on function public.admin_player_note_edited(uuid) from public, anon, authenticated;
grant execute on function public.admin_player_note_edited(uuid) to authenticated;
