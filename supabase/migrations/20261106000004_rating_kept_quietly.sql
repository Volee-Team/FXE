-- 20261106000004_rating_kept_quietly.sql — decision 0048, amended.
--
-- Since 20261105000002 a player's rating is Tara's once set, and
-- guard_player_rating refused any change with rating_set_by_tara. The 1.0.1 app
-- in the store still lets a player edit the rating on Edit details and sends
-- it with the name and level note in one update, so the refusal threw away the
-- whole save and the app said "That didn't save. Check your connection and try
-- again." Hosted logged 13 such refusals on 11-06, nine from one player inside
-- a minute.
--
-- Now the guard keeps the old rating and lets the rest of the update through.
-- The rule is unchanged: only Tara (admin_set_player_rating, or any admin
-- session) moves a rating once it is set; a missing rating can still be given
-- once. 1.0.2 shows the rating read-only and the members' site never sends it
-- once set, so this only changes what a 1.0.1 player sees: the save lands and
-- the rating reads Tara's number again.

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
    new.adult_rating := old.adult_rating;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_player_rating() from public, anon, authenticated;
comment on function public.guard_player_rating() is
  'Decision 0048: once set, a player''s rating is Tara''s. A player''s change to it is dropped quietly (the rest of the update saves) since 20261106000004.';
