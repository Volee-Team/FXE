-- copy_week.sql
--
-- admin_copy_week (20260928800002, decision 0027 §2): copy one service week
-- to the next as drafts. Every expected time below is worked out by hand from
-- the rule, never read off the function:
--
--   the week   Sunday 00:00 to Saturday 23:59:59, America/New_York (0001)
--   the copy   same New York wall clock, seven days later; never +168 hours
--   windows    the rule's values for the NEW date (members 08:00 the Thursday
--              before its week, everyone 08:00 the Friday), whatever the
--              source had; closes 3 hours before the start (decision 0013)
--   prices     from the length, as for any new clinic: 60 min $18 / $23,
--              90 min $22 / $28
--
-- The source week is Sunday 2026-10-25; the target, Sunday 2026-11-01, is the
-- day daylight saving ends (02:00 EDT becomes 01:00 EST), so every copy in it
-- is on a different UTC offset from its source. By hand, target week anchor
-- Sunday Nov 1: members open Thursday Oct 29 08:00 EDT = 12:00 UTC, everyone
-- Friday Oct 30 08:00 EDT = 12:00 UTC.
--
--   source (published unless said)          copy, UTC
--   Copy Sat Morning  Sat Oct 31 09:00 EDT  Sat Nov 7 09:00 EST = 14:00 (not 13:00)
--     90 min, its own windows, close and      ends 15:30; windows Oct 29/30 12:00;
--     prices (999 / 1999), Maria on court 2,  closes 11:00; 2200 / 2800; draft;
--     a message                               nobody in it, no message
--   Copy Tue Evening  Tue Oct 27 18:30 EDT  Tue Nov 3 18:30 EST = 23:30, ends Nov 4 00:30,
--                                           closes 20:30
--   Copy Sat Late     Sat Oct 31 21:00 EDT  Sat Nov 7 21:00 EST = Nov 8 02:00, ends 03:00
--     (already Sunday Nov 1 in UTC: still this week's, by the New York date)
--   Copy Twin x2      Thu Oct 29 09:00 EDT  two copies, Thu Nov 5 14:00
--   Copy Draft Source Fri Oct 30 12:00 EDT, a draft   Fri Nov 6 17:00
--   Copy Canceled     Wed Oct 28, canceled  no copy
--   Copy Prev Saturday Sat Oct 24 (the week before)  not copied
--   Copy Next Sunday  Sun Nov 1 10:00 EST (the target week itself)  not copied
--
--   first call: 6 created, 0 skipped. Second call: 0 created, 6 skipped.
--
-- The seed's clinics sit a few days to six weeks from "now", so on some run
-- dates one of them falls in the source week. Every clinic in the two weeks
-- that this probe did not create is set aside (canceled) inside the probe's
-- transaction first, so the counts are the fixture's on any date.
--
-- Drafts are invisible to players: asserted on the target week above, and,
-- because that week will one day be in the past (and so hidden for another
-- reason), again on a week two weeks from whenever the probe runs.
--
-- Expected: every row reads PASS.

begin;
set local timezone to 'UTC';
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  DRILL   constant uuid := 'b0000000-0000-0000-0000-000000000001';
  SRC     constant date := '2026-10-25';
  TGT     constant date := '2026-11-01';
  sat uuid; tue uuid; copy_sat uuid; copy_tue uuid;
  far_week date; far_src uuid;
  v text; n int; total int; st text;
begin
  -- -------------------------------------------------------------- fixture
  update public.clinics set status = 'canceled', canceled_at = now()
   where public.service_week_start(starts_at) in (SRC, TGT) and status <> 'canceled';

  insert into public.clinics (template_id, name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes,
      member_price_cents, nonmember_price_cents)
  values (DRILL, 'Copy Sat Morning', 'ladies', 'Clinic', 'Probe Saturday.',
          '2026-10-31 13:00:00+00', '2026-10-31 14:30:00+00',
          '2026-10-20 12:00:00+00', '2026-10-21 12:00:00+00', '2026-10-31 12:00:00+00',
          8, 'published', 90, 999, 1999)
  returning id into sat;
  insert into public.registrations (clinic_id, player_id, status, court_number, paid)
  values (sat, MARIA_P, 'in', 2, true);
  insert into public.clinic_messages (clinic_id, body, audience) values (sat, 'Probe message.', 'everyone');

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Copy Tue Evening', 'men', 'Clinic', 'Probe Tuesday.', '2026-10-27 22:30:00+00', '2026-10-27 23:30:00+00',
          '2026-10-22 12:00:00+00', '2026-10-23 12:00:00+00', 10, 'published', 60)
  returning id into tue;

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values
    ('Copy Sat Late',      'coed', 'Clinic', 'probe', '2026-11-01 01:00:00+00', '2026-11-01 02:00:00+00',
     '2026-10-22 12:00:00+00', '2026-10-23 12:00:00+00', 8, 'published', 60),
    ('Copy Twin',          'coed', 'Clinic', 'probe', '2026-10-29 13:00:00+00', '2026-10-29 14:00:00+00',
     '2026-10-22 12:00:00+00', '2026-10-23 12:00:00+00', 8, 'published', 60),
    ('Copy Twin',          'coed', 'Clinic', 'probe', '2026-10-29 13:00:00+00', '2026-10-29 14:00:00+00',
     '2026-10-22 12:00:00+00', '2026-10-23 12:00:00+00', 8, 'published', 60),
    ('Copy Draft Source',  'coed', 'Clinic', 'probe', '2026-10-30 16:00:00+00', '2026-10-30 17:00:00+00',
     '2026-10-22 12:00:00+00', '2026-10-23 12:00:00+00', 8, 'draft', 60),
    ('Copy Prev Saturday', 'coed', 'Clinic', 'probe', '2026-10-24 13:00:00+00', '2026-10-24 14:00:00+00',
     '2026-10-15 12:00:00+00', '2026-10-16 12:00:00+00', 8, 'published', 60),
    ('Copy Next Sunday',   'coed', 'Clinic', 'probe', '2026-11-01 15:00:00+00', '2026-11-01 16:00:00+00',
     '2026-10-29 12:00:00+00', '2026-10-30 12:00:00+00', 8, 'published', 60);
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, canceled_at, duration_minutes)
  values ('Copy Canceled', 'coed', 'Clinic', 'probe', '2026-10-28 14:00:00+00', '2026-10-28 15:00:00+00',
          '2026-10-22 12:00:00+00', '2026-10-23 12:00:00+00', 8, 'canceled', now(), 60);

  -- ---------------------------------------------------- as Tara: first copy
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select r.created || '|' || r.skipped into v from public.admin_copy_week(SRC) r;
  insert into _probe_result values ('first_call_created_skipped', '6|0', v);
  perform set_config('role', 'postgres', true);

  select count(*) into n from public.clinics
   where name like 'Copy %' and public.service_week_start(starts_at) = TGT and status = 'draft';
  insert into _probe_result values ('six_drafts_in_the_target_week', '6', n::text);

  -- Copy Sat Morning: across the change, its own overrides not carried.
  select id into copy_sat from public.clinics where name = 'Copy Sat Morning' and starts_at > '2026-11-01';
  select starts_at || '|' || ends_at into v from public.clinics where id = copy_sat;
  insert into _probe_result values ('sat_morning_same_wall_clock_across_dst',
    '2026-11-07 14:00:00+00|2026-11-07 15:30:00+00', v);
  select member_opens_at || '|' || public_opens_at || '|' || closes_at into v from public.clinics where id = copy_sat;
  insert into _probe_result values ('sat_morning_windows_and_close_from_the_rule_not_the_source',
    '2026-10-29 12:00:00+00|2026-10-30 12:00:00+00|2026-11-07 11:00:00+00', v);
  select member_price_cents || '|' || nonmember_price_cents into v from public.clinics where id = copy_sat;
  insert into _probe_result values ('sat_morning_prices_from_the_length_not_the_source', '2200|2800', v);
  select '[' || template_id || '|' || name || '|' || audience || '|' || category || '|' || description
         || '|' || duration_minutes || '|' || internal_capacity || '|' || status || ']' into v
    from public.clinics where id = copy_sat;
  insert into _probe_result values ('sat_morning_copies_the_clinic_itself_as_a_draft',
    '[b0000000-0000-0000-0000-000000000001|Copy Sat Morning|ladies|Clinic|Probe Saturday.|90|8|draft]', v);
  select (select count(*) from public.registrations where clinic_id = copy_sat) || '|'
      || (select count(*) from public.clinic_messages where clinic_id = copy_sat) into v;
  insert into _probe_result values ('nobody_and_no_message_carried_over', '0|0', v);
  select '[' || status || '|' || member_opens_at || '|' || member_price_cents || '|'
      || (select court_number || ' ' || paid from public.registrations where clinic_id = sat) || ']' into v
    from public.clinics where id = sat;
  insert into _probe_result values ('the_source_is_untouched',
    '[published|2026-10-20 12:00:00+00|999|2 true]', v);

  select id, starts_at || '|' || ends_at || '|' || closes_at into copy_tue, v
    from public.clinics where name = 'Copy Tue Evening' and starts_at > '2026-11-01';
  insert into _probe_result values ('tue_evening_same_wall_clock_across_dst',
    '2026-11-03 23:30:00+00|2026-11-04 00:30:00+00|2026-11-03 20:30:00+00', v);

  select string_agg(starts_at || '|' || ends_at, ',') into v
    from public.clinics where name = 'Copy Sat Late' and starts_at > '2026-11-02';
  insert into _probe_result values ('sat_late_belongs_to_its_new_york_week',
    '2026-11-08 02:00:00+00|2026-11-08 03:00:00+00', coalesce(v, 'NOT COPIED'));

  select count(*) into n from public.clinics where name = 'Copy Twin' and starts_at = '2026-11-05 14:00:00+00';
  insert into _probe_result values ('two_same_name_same_time_clinics_are_two_copies', '2', n::text);
  select count(*) into n from public.clinics where name = 'Copy Draft Source' and starts_at = '2026-11-06 17:00:00+00' and status = 'draft';
  insert into _probe_result values ('a_draft_source_is_copied_too', '1', n::text);
  select count(*) into n from public.clinics where name = 'Copy Canceled';
  insert into _probe_result values ('a_canceled_clinic_is_not_copied', '1', n::text);
  select count(*) into n from public.clinics where name = 'Copy Prev Saturday';
  insert into _probe_result values ('the_week_before_is_not_copied', '1', n::text);
  select count(*) into n from public.clinics where name = 'Copy Next Sunday';
  insert into _probe_result values ('the_target_week_itself_is_not_copied', '1', n::text);

  -- ------------------------------------------------ a second click: nothing
  perform set_config('role', 'authenticated', true);
  select r.created || '|' || r.skipped into v from public.admin_copy_week(SRC) r;
  insert into _probe_result values ('second_call_created_skipped', '0|6', v);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics
   where name like 'Copy %' and public.service_week_start(starts_at) = TGT and status = 'draft';
  insert into _probe_result values ('still_six_drafts_after_the_second_call', '6', n::text);

  -- -------------------------------------------- drafts are invisible to players
  -- Asserted before any copy is canceled: clinics_public shows canceled
  -- clinics (a player sees her canceled clinic as Canceled), and so shows a
  -- draft Tara cancels too, which it should not (docs/backlog.md, 2026-09-28).
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  -- Every copy starts after Sunday Nov 1 00:00 EDT (04:00 UTC); Copy Next
  -- Sunday is published and is left out by name, not by status, which
  -- clinics_public never shows a player.
  select count(*) into n from public.clinics_public
   where name in ('Copy Sat Morning', 'Copy Tue Evening', 'Copy Sat Late', 'Copy Twin', 'Copy Draft Source')
     and starts_at > '2026-11-01 04:00:00+00';
  insert into _probe_result values ('maria_sees_no_draft_in_the_target_week', '0', n::text);
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);

  -- A canceled copy does not count as a copy (the key is name, start and
  -- not canceled): canceling one draft and copying again brings that one back.
  update public.clinics set status = 'canceled', canceled_at = now() where id = copy_tue;
  perform set_config('role', 'authenticated', true);
  select r.created || '|' || r.skipped into v from public.admin_copy_week(SRC) r;
  insert into _probe_result values ('a_canceled_copy_is_copied_again', '1|5', v);
  perform set_config('role', 'postgres', true);

  -- -------------------------------------------- drafts are invisible, again
  -- The same, on a week two weeks from today, which is in the future on
  -- any run date: the published source is visible (so the query can see a
  -- row) and its copy is not.
  far_week := public.service_week_start(now()) + 14;
  update public.clinics set status = 'canceled', canceled_at = now()
   where public.service_week_start(starts_at) = far_week and status <> 'canceled';
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Copy Visible Source', 'coed', 'Clinic', 'probe',
          ((far_week + 3)::timestamp + time '10:00') at time zone 'America/New_York',
          ((far_week + 3)::timestamp + time '11:00') at time zone 'America/New_York',
          public.member_opens_at(((far_week + 3)::timestamp + time '10:00') at time zone 'America/New_York'),
          public.public_opens_at(((far_week + 3)::timestamp + time '10:00') at time zone 'America/New_York'),
          8, 'published', 60)
  returning id into far_src;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select r.created || '|' || r.skipped into v from public.admin_copy_week(far_week) r;
  insert into _probe_result values ('far_week_copied', '1|0', v);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select '[' || string_agg(status::text, ',') || ']' into v from public.clinics_public where name = 'Copy Visible Source';
  insert into _probe_result values ('maria_sees_the_published_source_and_not_its_draft', '[published]', coalesce(v, '[]'));
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------ refusals, by state
  select count(*) into total from public.clinics;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  st := null;
  begin
    perform public.admin_copy_week('2026-10-26');   -- a Monday
  exception when others then st := sqlstate || ' ' || sqlerrm;
  end;
  insert into _probe_result values ('a_monday_is_refused', '[22023 not_a_sunday]', '[' || coalesce(st, 'ACCEPTED') || ']');
  st := null;
  begin
    perform public.admin_copy_week(null);
  exception when others then st := sqlstate || ' ' || sqlerrm;
  end;
  insert into _probe_result values ('no_date_is_refused', '[22023 not_a_sunday]', '[' || coalesce(st, 'ACCEPTED') || ']');

  -- A member tries. What matters is the resulting state: no clinic created.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  st := null;
  begin
    perform public.admin_copy_week('2026-10-18');
  exception when others then st := sqlstate || ' ' || sqlerrm;
  end;
  insert into _probe_result values ('member_is_refused', '[42501 not_authorized]', '[' || coalesce(st, 'ACCEPTED') || ']');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics;
  insert into _probe_result values ('refusals_created_nothing', total::text, n::text);

  -- ------------------------------------------------------------ grant surface
  insert into _probe_result values ('anon_cannot_execute', 'false',
    has_function_privilege('anon', 'public.admin_copy_week(date)', 'EXECUTE')::text);
  insert into _probe_result values ('public_holds_no_execute', '0',
    (select count(*) from pg_proc p, aclexplode(p.proacl) a
      where p.oid = 'public.admin_copy_week(date)'::regprocedure
        and a.grantee = 0 and a.privilege_type = 'EXECUTE')::text);
  insert into _probe_result values ('acl_is_explicit_not_default', 'true',
    ((select proacl from pg_proc where oid = 'public.admin_copy_week(date)'::regprocedure) is not null)::text);
  insert into _probe_result values ('authenticated_can_execute', 'true',
    has_function_privilege('authenticated', 'public.admin_copy_week(date)', 'EXECUTE')::text);
  insert into _probe_result values ('definer_pins_search_path', 'true',
    (select prosecdef and exists (select 1 from unnest(proconfig) cfg where cfg like 'search_path=%')
       from pg_proc where oid = 'public.admin_copy_week(date)'::regprocedure)::text);
end $$;

-- The skip key is name AND start (sql-auditor, 2026-09-28): the block above
-- passes under a name-only or a start-only key. Its own weeks, far from any
-- seed date: source Sunday 2027-01-10, target Sunday 2027-01-17 (EST, no
-- daylight change, so copies are +7 days at the same UTC time).
--   source  Skip Ladies  Tue Jan 12 18:00 EST = 23:00Z   -> Tue Jan 19 23:00Z
--           Skip Ladies  Thu Jan 14 18:00 EST = 23:00Z   -> Thu Jan 21 23:00Z
--   target, already there before the copy:
--           Skip Ladies  Tue Jan 19 10:00 EST = 15:00Z   same name, other time: blocks nothing
--           Other Name   Thu Jan 21 18:00 EST = 23:00Z   same time, other name: blocks nothing
--   first call 2|0 (name-only reads 0|2, start-only 1|1); second 0|2;
--   cancel the Thursday copy, third call 1|1.
do $$
declare
  TARA constant uuid := '11111111-1111-1111-1111-111111111111';
  v text; thu_copy uuid;
begin
  insert into public.clinics (name, audience, starts_at, ends_at, member_opens_at, public_opens_at,
      internal_capacity, status, duration_minutes) values
    ('Skip Ladies', 'ladies', '2027-01-12 23:00+00', '2027-01-13 00:00+00', '2027-01-07 13:00+00', '2027-01-08 13:00+00', 8, 'published', 60),
    ('Skip Ladies', 'ladies', '2027-01-14 23:00+00', '2027-01-15 00:00+00', '2027-01-07 13:00+00', '2027-01-08 13:00+00', 8, 'published', 60),
    ('Skip Ladies', 'ladies', '2027-01-19 15:00+00', '2027-01-19 16:00+00', '2027-01-14 13:00+00', '2027-01-15 13:00+00', 8, 'published', 60),
    ('Other Name',  'ladies', '2027-01-21 23:00+00', '2027-01-22 00:00+00', '2027-01-14 13:00+00', '2027-01-15 13:00+00', 8, 'published', 60);

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select r.created || '|' || r.skipped into v from public.admin_copy_week('2027-01-10') r;
  insert into _probe_result values ('skip_key_first_call_one_name_two_days', '2|0', v);
  select r.created || '|' || r.skipped into v from public.admin_copy_week('2027-01-10') r;
  insert into _probe_result values ('skip_key_second_call', '0|2', v);

  perform set_config('role', 'postgres', true);
  select id into thu_copy from public.clinics
   where name = 'Skip Ladies' and starts_at = '2027-01-21 23:00+00' and status = 'draft';
  update public.clinics set status = 'canceled', canceled_at = now() where id = thu_copy;
  perform set_config('role', 'authenticated', true);
  select r.created || '|' || r.skipped into v from public.admin_copy_week('2027-01-10') r;
  insert into _probe_result values ('skip_key_canceled_copy_made_again', '1|1', v);
  perform set_config('role', 'postgres', true);
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
