-- registration_window_rule.sql
--
-- The date maths behind member_opens_at() / public_opens_at(), pinned against
-- the authoritative rule statement rather than against the implementation.
--
-- WHY THIS FILE EXISTS
--
-- The first implementation of this rule was wrong, and the first test passed
-- anyway, because the test was written by reading the function. It asserted
-- "the most recent Thursday strictly before the clinic date" against code that
-- computed the most recent Thursday strictly before the clinic date. Two copies
-- of one misunderstanding agreeing with each other is not evidence.
--
-- So every expected value below is TRANSCRIBED FROM THE RULE, not computed:
--
--   A clinic belongs to the service week containing it. A service week runs
--   Sunday through Saturday, America/New_York. Registration for every clinic in
--   that week opens at one pair of moments derived only from the anchor Sunday:
--     members 08:00 local on anchor_sunday - 3 (Thursday)
--     public  08:00 local on anchor_sunday - 2 (Friday)
--   A clinic's own weekday has no effect on its open time.
--
-- Tara's stated case: for the week of Sunday 2026-09-06, members open Thursday
-- 2026-09-03 and everyone else Friday 2026-09-04.
--
-- The literal dates and weekday names below were checked against the 2026 and
-- 2027 calendars before being written down.
--
-- THE LOAD-BEARING ROW is friday_clinic. The old naive rule agreed with this
-- one on five weekdays out of seven and broke on Friday and Saturday, which are
-- the two days where seats are scarcest. A rule that is right five days out of
-- seven survives casual testing and then quietly waitlists the members it was
-- meant to protect. If only one assertion in this file may survive, keep that one.
--
-- Expected: every row of the final result reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;

-- Cases, transcribed from the rule's weekday table and boundary table.
-- clinic_local is a NAIVE America/New_York wall clock, which is how a human
-- states a clinic time.
create temporary table _case (
  label        text,
  week_tag     text,
  clinic_local timestamp,
  exp_member   text,
  exp_public   text
) on commit drop;

insert into _case (label, week_tag, clinic_local, exp_member, exp_public) values
  -- All seven weekdays of the week Tara described. Every one of them must
  -- produce HER pair of dates, regardless of the clinic's own weekday.
  ('sunday_clinic',    'w0906', '2026-09-06 09:00', '2026-09-03 Thu 08:00', '2026-09-04 Fri 08:00'),
  ('monday_clinic',    'w0906', '2026-09-07 09:00', '2026-09-03 Thu 08:00', '2026-09-04 Fri 08:00'),
  ('tuesday_clinic',   'w0906', '2026-09-08 09:00', '2026-09-03 Thu 08:00', '2026-09-04 Fri 08:00'),
  ('wednesday_clinic', 'w0906', '2026-09-09 09:00', '2026-09-03 Thu 08:00', '2026-09-04 Fri 08:00'),
  ('thursday_clinic',  'w0906', '2026-09-10 06:15', '2026-09-03 Thu 08:00', '2026-09-04 Fri 08:00'),
  ('friday_clinic',    'w0906', '2026-09-11 19:45', '2026-09-03 Thu 08:00', '2026-09-04 Fri 08:00'),
  ('saturday_clinic',  'w0906', '2026-09-12 08:00', '2026-09-03 Thu 08:00', '2026-09-04 Fri 08:00'),

  -- Proximity is not membership. This Saturday is only four days before the
  -- 9/6 week's Sunday, and belongs to the PREVIOUS week regardless.
  ('previous_week_saturday', 'w0830', '2026-09-05 08:00', '2026-08-27 Thu 08:00', '2026-08-28 Fri 08:00'),

  -- The week rolls, once, cleanly.
  ('weekly_roll_next_sunday', 'w0913', '2026-09-13 09:00', '2026-09-10 Thu 08:00', '2026-09-11 Fri 08:00'),

  -- Anchor Sunday in August, clinic week spanning into September.
  ('month_straddle', 'w0830b', '2026-08-30 09:00', '2026-08-27 Thu 08:00', '2026-08-28 Fri 08:00'),

  -- DST. The wall clock must stay 08:00 on both sides of the fall-back; the UTC
  -- instant must move by an hour. UTC checked separately below.
  ('dst_fallback_week',     'wdst1', '2026-11-01 09:00', '2026-10-29 Thu 08:00', '2026-10-30 Fri 08:00'),
  ('dst_week_after',        'wdst2', '2026-11-08 09:00', '2026-11-05 Thu 08:00', '2026-11-06 Fri 08:00'),

  -- Year boundary, and both open days landing on holidays (Christmas Eve and
  -- Christmas Day). The rule has no holiday awareness: open question Q3.
  ('year_straddle_holiday', 'wny', '2027-01-01 09:00', '2026-12-24 Thu 08:00', '2026-12-25 Fri 08:00'),

  -- THE UTC TRAP. A Saturday 21:00 EDT clinic is Sunday 01:00 UTC. Anchoring
  -- off the UTC date pushes it into the next week and returns 2026-09-10
  -- instead of 2026-09-03: a full week late, on the busiest weekday.
  ('late_saturday_utc_trap', 'wtrap', '2026-09-12 21:00', '2026-09-03 Thu 08:00', '2026-09-04 Fri 08:00');

-- 1. Member open, per case.
insert into _probe_result
select 'member_open_' || label,
       exp_member,
       to_char(public.member_opens_at(clinic_local at time zone 'America/New_York')
                 at time zone 'America/New_York', 'YYYY-MM-DD Dy HH24:MI')
  from _case;

-- 2. Public open, per case.
insert into _probe_result
select 'public_open_' || label,
       exp_public,
       to_char(public.public_opens_at(clinic_local at time zone 'America/New_York')
                 at time zone 'America/New_York', 'YYYY-MM-DD Dy HH24:MI')
  from _case;

-- 3. The defining property of the whole model: one week, one open moment. If a
--    future change reintroduces per-clinic maths, the seven weekdays of the
--    9/6 week stop agreeing and this is what catches it.
insert into _probe_result
select 'one_open_moment_per_service_week', '1',
       count(distinct public.member_opens_at(clinic_local at time zone 'America/New_York'))::text
  from _case where week_tag = 'w0906';

insert into _probe_result
select 'one_public_moment_per_service_week', '1',
       count(distinct public.public_opens_at(clinic_local at time zone 'America/New_York'))::text
  from _case where week_tag = 'w0906';

-- 4. DST asserted on the UTC instant, which is the part a fixed-offset
--    implementation would get wrong. Same wall clock, different offset.
insert into _probe_result
select 'dst_member_open_is_edt_utc', '2026-10-29 12:00',
       to_char(public.member_opens_at(timestamp '2026-11-01 09:00' at time zone 'America/New_York')
                 at time zone 'UTC', 'YYYY-MM-DD HH24:MI');

insert into _probe_result
select 'dst_member_open_is_est_utc', '2026-11-05 13:00',
       to_char(public.member_opens_at(timestamp '2026-11-08 09:00' at time zone 'America/New_York')
                 at time zone 'UTC', 'YYYY-MM-DD HH24:MI');

-- 5. Sweep a full year of clinic dates. The member open must ALWAYS be a
--    Thursday and the public open must ALWAYS be a Friday. This is stated by
--    the Developer Guide independently of Tara's example, so it is worth
--    asserting independently of the example.
insert into _probe_result
select 'member_open_always_thursday', '0',
       count(*)::text
  from generate_series(date '2026-08-01', date '2027-08-01', interval '1 day') d
 where to_char(public.member_opens_at((d::date + time '10:00') at time zone 'America/New_York')
                 at time zone 'America/New_York', 'Dy') <> 'Thu';

insert into _probe_result
select 'public_open_always_friday', '0',
       count(*)::text
  from generate_series(date '2026-08-01', date '2027-08-01', interval '1 day') d
 where to_char(public.public_opens_at((d::date + time '10:00') at time zone 'America/New_York')
                 at time zone 'America/New_York', 'Dy') <> 'Fri';

-- 6. Members always lead by exactly 24 hours. Never zero, never negative, and
--    never the six-day INVERSION the old rule produced on a Friday clinic.
insert into _probe_result
select 'member_head_start_is_always_24h', '0',
       count(*)::text
  from generate_series(date '2026-08-01', date '2027-08-01', interval '1 day') d
 where public.public_opens_at((d::date + time '10:00') at time zone 'America/New_York')
     - public.member_opens_at((d::date + time '10:00') at time zone 'America/New_York')
       <> interval '24 hours';

-- 7. Both windows always open strictly before the clinic starts, over a year.
--    Member lead runs 3 days (Sunday clinic) to 9 days (Saturday clinic).
insert into _probe_result
select 'windows_always_precede_clinic', '0',
       count(*)::text
  from generate_series(date '2026-08-01', date '2027-08-01', interval '1 day') d
 where public.public_opens_at((d::date + time '10:00') at time zone 'America/New_York')
       >= (d::date + time '10:00') at time zone 'America/New_York';

insert into _probe_result
select 'member_lead_between_3_and_9_days', '3|9',
       min(extract(day from ((d::date + time '10:00') at time zone 'America/New_York'
             - public.member_opens_at((d::date + time '10:00') at time zone 'America/New_York'))))::int::text
       || '|' ||
       max(extract(day from ((d::date + time '10:00') at time zone 'America/New_York'
             - public.member_opens_at((d::date + time '10:00') at time zone 'America/New_York'))))::int::text
  from generate_series(date '2026-08-01', date '2027-08-01', interval '1 day') d;

-- 8. Positive assertion that the OLD naive rule is gone, not merely renamed.
--    The old formula is inlined here on purpose: this probe must not depend on
--    the buggy function still existing.
--
--    Naive rule: 08:00 on the most recent Thursday strictly before the clinic
--    date. It agrees with the correct rule on Sunday through Thursday, and
--    differs by exactly one week on Friday and Saturday.
insert into _probe_result
select 'naive_rule_still_agrees_sun_to_thu', '0', count(*)::text
  from generate_series(date '2026-08-01', date '2027-08-01', interval '1 day') d
 where extract(dow from d) between 0 and 4
   and public.member_opens_at((d::date + time '10:00') at time zone 'America/New_York')
       <> ((
             d::date - ((((extract(isodow from d)::int - 4 + 6) % 7) + 1))
           )::timestamp + time '08:00') at time zone 'America/New_York';

insert into _probe_result
select 'naive_rule_overruled_fri_and_sat', '0', count(*)::text
  from generate_series(date '2026-08-01', date '2027-08-01', interval '1 day') d
 where extract(dow from d) in (5, 6)
   and public.member_opens_at((d::date + time '10:00') at time zone 'America/New_York')
       = ((
             d::date - ((((extract(isodow from d)::int - 4 + 6) % 7) + 1))
           )::timestamp + time '08:00') at time zone 'America/New_York';

-- 9. And the specific historical defect, named: Tara's Friday clinic must not
--    open on 2026-09-10, which is where the old rule put it.
insert into _probe_result
select 'friday_clinic_not_a_week_late', 'not 2026-09-10',
       case when to_char(public.member_opens_at(timestamp '2026-09-11 19:45' at time zone 'America/New_York')
                           at time zone 'America/New_York', 'YYYY-MM-DD') = '2026-09-10'
            then 'REGRESSED to 2026-09-10'
            else 'not 2026-09-10' end;

-- 10. The service week anchor itself, spot-checked. Saturday must anchor to the
--     Sunday six days BEHIND it, not the one a day ahead.
insert into _probe_result
select 'anchor_of_saturday_is_prior_sunday', '2026-09-06',
       public.service_week_start(timestamp '2026-09-12 08:00' at time zone 'America/New_York')::text;

insert into _probe_result
select 'anchor_of_sunday_is_itself', '2026-09-06',
       public.service_week_start(timestamp '2026-09-06 09:00' at time zone 'America/New_York')::text;

-- 11. INTEGRATION, not just arithmetic. The values Tara's admin screen actually
--     stores on the clinic row have to be the corrected ones. A correct
--     function wired to nothing would still fail her.
do $$
declare v public.clinics;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', '11111111-1111-1111-1111-111111111111')::text, true);

  -- Friday clinic, from a template, through the real admin RPC.
  v := public.create_clinic_from_template(
         'b0000000-0000-0000-0000-000000000001',
         timestamp '2026-09-11 19:45' at time zone 'America/New_York');

  insert into _probe_result values (
    'created_clinic_stores_member_open', '2026-09-03 Thu 08:00',
    to_char(v.member_opens_at at time zone 'America/New_York', 'YYYY-MM-DD Dy HH24:MI'));

  insert into _probe_result values (
    'created_clinic_stores_public_open', '2026-09-04 Fri 08:00',
    to_char(v.public_opens_at at time zone 'America/New_York', 'YYYY-MM-DD Dy HH24:MI'));

  -- 12. Tara's per-clinic override must still be possible. The functions supply
  --     a default; they do not own the column.
  update public.clinics
     set member_opens_at = timestamp '2026-09-01 06:00' at time zone 'America/New_York',
         public_opens_at = timestamp '2026-09-02 06:00' at time zone 'America/New_York'
   where id = v.id;

  insert into _probe_result
  select 'admin_can_override_stored_window', '2026-09-01 Tue 06:00',
         to_char(member_opens_at at time zone 'America/New_York', 'YYYY-MM-DD Dy HH24:MI')
    from public.clinics where id = v.id;
end $$;

select
  check_name,
  expected,
  actual,
  case
    when actual = expected then 'PASS'
    -- Substring matching exists for checks whose `actual` is a server error
    -- message wrapping the expected error name. It is deliberately NOT allowed
    -- for numeric expectations. The original comparison used
    -- `actual like '%' || expected || '%'`, under which an actual count of 105
    -- PASSED against an expected 0, because "105" contains "0". That silently
    -- greened a real assertion failure. LIKE also treated `_` in an expected
    -- error name as a wildcard, so strpos is used instead.
    when expected ~ '[A-Za-z]' and strpos(actual, expected) > 0 then 'PASS'
    else 'FAIL'
  end as result
from _probe_result
order by check_name;

rollback;
