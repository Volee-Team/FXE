-- 20260928800002_copy_week.sql
--
-- Copy this week to next week, as drafts: Tara's weekly setup in one click
-- (decision 0027 §2). She runs much the same clinics every week; today each
-- one is typed again by hand. The copies are DRAFTS, invisible to players
-- (clinics_public shows published and canceled only), so nothing reaches a
-- member until she has looked and pressed Publish on each (hard rule 2's
-- spirit: the app prepares, Tara decides).
--
-- admin_copy_week(p_week_start date) returns (created, skipped)
--
--   p_week_start  the Sunday of a service week (Sunday 00:00 to Saturday
--                 23:59:59, America/New_York; decision 0001). Anything that is
--                 not a Sunday is refused (not_a_sunday), and so is null.
--   the week      every clinic whose service_week_start(starts_at) is that
--                 Sunday, the helper the registration windows use, so the
--                 "which week" rule lives in one place (it applies AT TIME
--                 ZONE before taking the weekday: a Saturday 9 pm clinic is
--                 Sunday in UTC and still belongs to its Saturday's week).
--                 Canceled clinics are not copied; drafts and published are.
--   the copy      one new clinic per source clinic, status 'draft', seven days
--                 later ON THE SAME NEW YORK WALL CLOCK: the local timestamp
--                 plus 7 days, converted back. Never plus 168 hours, which is
--                 an hour off across a daylight-saving change (9:00 AM
--                 Saturday 2026-10-31 EDT is 13:00 UTC; 9:00 AM Saturday
--                 2026-11-07 EST is 14:00 UTC, 169 hours later). ends_at moves
--                 the same way.
--   copied        name, audience, category, description, duration_minutes,
--                 internal_capacity, template_id. A copy, not a reference
--                 (hard rule 7's instinct one level down): editing a copy or
--                 its source later changes nothing on the other.
--   recomputed    member_opens_at / public_opens_at from the rule for the NEW
--                 date (member_opens_at(), public_opens_at()), and closes_at
--                 left null so apply_default_clinic_close fills it: an
--                 override on the source clinic was a one-off for that week,
--                 and carrying it forward would open next week's clinic at
--                 this week's moment. Prices left null so
--                 apply_default_clinic_pricing fills them from the length,
--                 exactly as for any new clinic: prices are never a parameter
--                 (20260826000001 note 4), and copying them would carry an
--                 old price forward week after week after the table changed.
--   never copied  registrations, courts, messages, notes, payments: they
--                 belong to the week that happened.
--
-- IDEMPOTENT. A source clinic whose copy already exists in the target week
-- (same name, same start, not canceled) is skipped, so a double click creates
-- nothing twice; created + skipped is the number of source clinics. Two
-- clinics with the same name at the same time (two groups on one morning) are
-- two copies: the n-th one is skipped only when n copies already exist.
-- Checked under a transaction advisory lock keyed on the target week, because
-- a check followed by an insert is two steps: two simultaneous calls would
-- both see no copy and both insert (hard rule 3's lesson for inserts; the
-- one_fee lock in 20260927100001 is the same shape). Pinned by
-- tests/sql/copy_week_race.sh, red without the lock.
--
-- GUARDS: require_admin() first; SECURITY DEFINER (clinics is unreadable and
-- unwritable to clients); search_path pinned; revoked from PUBLIC and anon
-- before the grant (hard rule 11). Pinned by tests/sql/copy_week.sql.

create or replace function public.admin_copy_week(p_week_start date)
returns table (created integer, skipped integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_created integer;
  v_sources integer;
begin
  perform public.require_admin();

  if p_week_start is null or extract(dow from p_week_start) <> 0 then
    raise exception 'not_a_sunday' using errcode = '22023';
  end if;

  -- One copy into a given week at a time. Taken before any read, so a second
  -- call waits here and then reads what the first committed.
  perform pg_advisory_xact_lock(hashtextextended('copy_week:' || (p_week_start + 7)::text, 0));

  with src as (
    select c.template_id, c.name, c.audience, c.category, c.description,
           c.duration_minutes, c.internal_capacity,
           ((c.starts_at at time zone 'America/New_York') + interval '7 days')
             at time zone 'America/New_York' as new_starts,
           ((c.ends_at at time zone 'America/New_York') + interval '7 days')
             at time zone 'America/New_York' as new_ends,
           row_number() over (partition by c.name, c.starts_at order by c.created_at, c.id) as nth
      from public.clinics c
     where public.service_week_start(c.starts_at) = p_week_start
       and c.status <> 'canceled'
  ),
  todo as (
    select s.*
      from src s
     where s.nth > (select count(*) from public.clinics x
                     where x.name = s.name
                       and x.starts_at = s.new_starts
                       and x.status <> 'canceled')
  ),
  ins as (
    insert into public.clinics (
      template_id, name, audience, category, description,
      starts_at, ends_at, duration_minutes, internal_capacity,
      member_opens_at, public_opens_at, status)
    select t.template_id, t.name, t.audience, t.category, t.description,
           t.new_starts, t.new_ends, t.duration_minutes, t.internal_capacity,
           public.member_opens_at(t.new_starts), public.public_opens_at(t.new_starts),
           'draft'
      from todo t
    returning 1
  )
  select (select count(*) from ins), (select count(*) from src)
    into v_created, v_sources;

  return query select v_created, v_sources - v_created;
end;
$$;

comment on function public.admin_copy_week(date) is
  'Admin only (decision 0027 §2). Copies every clinic of the service week that '
  'starts on p_week_start (a Sunday), except canceled ones, to the next week as '
  'drafts on the same New York wall clock; windows, close and prices recomputed '
  'for the new date; registrations never copied. Skips a clinic whose copy exists '
  '(same name, same start, not canceled). Returns (created, skipped).';

revoke all on function public.admin_copy_week(date) from public, anon, authenticated;
grant execute on function public.admin_copy_week(date) to authenticated;
