-- Decision 0049: a beginner clinic's number is not a minimum.
--
-- Tara, by text, 2026-11-05: "Beginner clinics can be open to anyone up to a
-- 3.0, I guess, even though it says beginner to 2.5". Decision 0048 reads the
-- number in a clinic's name as its minimum, so "Ladies Beginner - 2.5" refused
-- players rated 2.0 from the clinic meant for them. Only a minimum is removed
-- here. Whether a 3.5 is kept out (her "up to a 3.0") is question 142; nothing
-- enforces a ceiling until she answers.
--
-- The app and the members' site read clinics.min_rating, so neither changes.

create or replace function public.clinic_level_from_name(p_name text)
returns numeric
language sql
immutable
set search_path = public, pg_temp
as $$
  -- The first NTRP-shaped number (2.0 to 5.0 in half steps) not glued to
  -- other digits: "Ladies 3.0+" -> 3.0, "105" -> null, "All-Level" -> null.
  -- A beginner clinic has no minimum: "Ladies Beginner - 2.5" -> null.
  select case
    when coalesce(p_name, '') ~* 'beginner' then null
    else substring(coalesce(p_name, '') from '(?:^|[^0-9.])([2-5]\.[05])(?![0-9])')::numeric(2,1)
  end;
$$;
comment on function public.clinic_level_from_name(text) is
  'Decisions 0048 and 0049. The NTRP level written in a clinic''s name, or null; a beginner clinic has none.';

-- min_rating is stored, so clinics that already exist keep the old value until
-- their row is rewritten. Writing the name to itself recomputes it and changes
-- nothing else (stamp_clinic_published keeps a published_at once it is set).
update public.clinics set name = name
 where name ~* 'beginner' and min_rating is not null;
