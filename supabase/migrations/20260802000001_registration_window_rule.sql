-- FXE Tennis: correct the registration window rule.
--
-- WHAT WAS WRONG
--
-- The original member_opens_at() computed "8:00 AM on the most recent Thursday
-- STRICTLY BEFORE the clinic date". That is a per-CLINIC rule, and it is not
-- what Tara described. It is wrong on 2 of the 7 weekdays, and one of the two
-- is the exact case she spelled out.
--
-- Tara gave two different open dates for one identical date range. That is only
-- coherent if the registrable unit is the WEEK and the two dates are the two
-- audiences. Registration is per service week, not per clinic.
--
-- The naive rule, on a clinic on Friday 2026-09-11:
--     member  -> Thu 2026-09-10   (Tara says Thu 2026-09-03: off by a week)
--     public  -> Fri 2026-09-04   (six days BEFORE the members: an inversion)
-- That inversion is the sharpest disproof of the per-clinic reading. It also
-- lands on the two weekdays where seats are scarcest.
--
-- THE RULE (authoritative)
--
--   A clinic belongs to the service week containing it. A service week runs
--   Sunday 00:00 through Saturday 23:59, America/New_York.
--
--   Registration for EVERY clinic in that week opens at one pair of moments
--   derived only from the week's anchor Sunday:
--
--     members : 08:00 local on anchor_sunday - 3 days  (the Thursday before)
--     public  : 08:00 local on anchor_sunday - 2 days  (the Friday before)
--
--   A clinic's own weekday has no effect on its open time. Members keep access
--   after the public window opens: Friday widens the audience, it does not
--   transfer it. Member lead time runs from 3 days (Sunday clinic) to 9 days
--   (Saturday clinic).
--
-- Checked against Tara's sentence: anchor Sunday 2026-09-06 minus 3 is Thursday
-- 2026-09-03 (her first date); minus 2 is Friday 2026-09-04 (her second).
--
-- TWO READINGS THAT LOOK IDENTICAL ON A FULL WEEK, AND WHY THIS ONE
--
--  1. Week length. Tara's range names Sunday to Friday, which is the clinic
--     FOOTPRINT, not the boundary of a registration block. A 6-day week leaves
--     Saturday in no week at all and makes week_of(date) a partial function,
--     which cannot be implemented. Sunday-Saturday is used here. If FXE runs
--     Saturday clinics, confirm with Tara: the two readings put a Saturday
--     clinic's open a FULL WEEK apart. See CLAUDE.md open question Q1.
--
--  2. Anchor point. Tara's example cannot distinguish week-START-anchored
--     (Sunday - 3) from week-END-anchored (last clinic day - 8): both give 9/3
--     for a full week. Start-anchored is used here because end-anchoring only
--     agrees with the Developer Guide's "Thursday / Friday" on full weeks. On a
--     Sunday-to-Wednesday holiday week it would open on a Tuesday and a
--     Wednesday, contradicting the Guide. See CLAUDE.md open question Q2.
--
-- Both functions stay STORED as columns on clinics, so Tara can still override
-- any single clinic by editing the row. These functions only supply the default.

-- ------------------------------------------------------------ week anchor ----

-- The Sunday on or before the clinic's LOCAL calendar date.
--
-- Two traps are deliberately avoided here.
--
--  * `AT TIME ZONE` must be applied BEFORE taking the day of week. A Saturday
--    2026-09-12 21:00 EDT clinic is Sunday 2026-09-13 01:00 UTC; anchoring off
--    the UTC value pushes it into the next week and returns Thu 2026-09-10
--    instead of Thu 2026-09-03. Pinned by tests/sql/registration_window_rule.sql.
--
--  * Do NOT reach for date_trunc('week', ...). That is ISO, Monday-anchored,
--    and would shift every Sunday clinic a full week early. Postgres DOW is
--    0 = Sunday, which is exactly the offset back to the anchor.
--
-- STABLE rather than IMMUTABLE: timestamptz AT TIME ZONE depends on the tz
-- database, so Postgres marks it stable and so must anything built on it.
create or replace function public.service_week_start(p_starts_at timestamptz)
returns date
language sql
stable
as $$
  select (p_starts_at at time zone 'America/New_York')::date
       - extract(dow from (p_starts_at at time zone 'America/New_York'))::int;
$$;

comment on function public.service_week_start(timestamptz) is
  'Anchor Sunday of the America/New_York service week containing this instant. '
  'Service weeks run Sunday through Saturday. Registration windows derive from '
  'this and nothing else.';

-- ----------------------------------------------------------- open windows ----

-- Attaching 08:00 as a naive wall-clock time and only then converting with
-- AT TIME ZONE is what makes this DST-correct: the same expression yields
-- 12:00 UTC before the November fall-back and 13:00 UTC after, because the club
-- means 8:00 on the clock either way. A stored fixed UTC offset would open the
-- doors an hour off for roughly half the year.
create or replace function public.member_opens_at(p_starts_at timestamptz)
returns timestamptz
language sql
stable
as $$
  select ((public.service_week_start(p_starts_at) - 3)::timestamp + time '08:00')
           at time zone 'America/New_York';
$$;

-- Derived from the anchor independently rather than as member + 1 day. The two
-- agree today (no US DST transition ever falls between a Thursday and the
-- following Friday), but deriving both from the same anchor means the pair
-- cannot drift if one is ever edited.
create or replace function public.public_opens_at(p_starts_at timestamptz)
returns timestamptz
language sql
stable
as $$
  select ((public.service_week_start(p_starts_at) - 2)::timestamp + time '08:00')
           at time zone 'America/New_York';
$$;

comment on function public.member_opens_at(timestamptz) is
  'Default member registration open: 08:00 America/New_York on the Thursday '
  'three days before the clinic''s anchor Sunday. Per service week, NOT per '
  'clinic: every clinic in a week shares one open time.';

comment on function public.public_opens_at(timestamptz) is
  'Default public registration open: 08:00 America/New_York on the Friday two '
  'days before the clinic''s anchor Sunday. Exactly 24 hours after the member '
  'open. Members keep access afterwards; this widens the audience.';

grant execute on function public.service_week_start(timestamptz) to authenticated;

-- --------------------------------------------------------------- backfill ----

-- Rows already carrying the OLD naive values are corrected. Rows whose stored
-- values differ from the old formula were overridden by hand and are left
-- exactly as they are: hard rule 6, never silently revert someone's work.
--
-- The old formula is inlined here rather than referenced, because the function
-- that produced it no longer exists in this shape.
with old_rule as (
  select
    c.id,
    (
      (
        (c.starts_at at time zone 'America/New_York')::date
        - ((((extract(isodow from c.starts_at at time zone 'America/New_York')::int - 4 + 6) % 7) + 1))
      )::timestamp + time '08:00'
    ) at time zone 'America/New_York' as old_member
  from public.clinics c
)
update public.clinics c
   set member_opens_at = public.member_opens_at(c.starts_at),
       public_opens_at = public.public_opens_at(c.starts_at)
  from old_rule o
 where o.id = c.id
   and c.member_opens_at = o.old_member
   and c.public_opens_at = o.old_member + interval '1 day';
