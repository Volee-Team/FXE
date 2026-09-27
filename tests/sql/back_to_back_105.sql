-- back_to_back_105.sql
--
-- Decision 0015 §13. Tara, 2026-09-26, verbatim: "members can sign up for
-- back to back 105's (same day back to back) but nonmembers cannot until 48
-- [hours] priors to start time of clinic. For example: Sunday Sept 27 430-6pm
-- 105 6-7pm 105 Nonmembers cannot sign up for both 105's (only one when
-- registration opens for them) until Friday Sept 25 4:30pm."
--
-- Expected values come from her sentence and her example, worked by hand:
-- Sunday 2026-09-27 16:30 New York minus 48 hours is Friday 2026-09-25 16:30
-- New York, whichever of the two she took first. Nothing below was read off
-- the function.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  far_day date := ((now() + interval '4 days') at time zone 'America/New_York')::date;
  near_day date := ((now() + interval '1 day') at time zone 'America/New_York')::date;
  x1 uuid; x2 uuid; nx uuid; y1 uuid; y2 uuid; other_day uuid;
  r public.registrations; v text; rx1 uuid;
  z1 uuid; z2 uuid; w1 uuid; w2 uuid; s1 uuid; s2 uuid; t_mark timestamptz;
  PRIYA   constant uuid := '55555555-5555-5555-5555-555555555555';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  function_exists boolean;
begin
  -- ------------------------------------------ her example, as literals
  insert into _probe_result values ('taras_example_opens_friday_430',
    '2026-09-25 16:30',
    to_char(public.back_to_back_105_opens_at('2026-09-27 16:30 America/New_York', '2026-09-27 18:00 America/New_York')
            at time zone 'America/New_York', 'YYYY-MM-DD HH24:MI'));
  insert into _probe_result values ('taras_example_either_order',
    '2026-09-25 16:30',
    to_char(public.back_to_back_105_opens_at('2026-09-27 18:00 America/New_York', '2026-09-27 16:30 America/New_York')
            at time zone 'America/New_York', 'YYYY-MM-DD HH24:MI'));

  -- Clock time across daylight saving (question 60's default): two days
  -- earlier at the same New York time, not 48 elapsed hours.
  insert into _probe_result values ('fall_back_weekend_same_clock_time', '2026-10-30 16:30',
    to_char(public.back_to_back_105_opens_at('2026-11-01 16:30 America/New_York', '2026-11-01 18:00 America/New_York')
            at time zone 'America/New_York', 'YYYY-MM-DD HH24:MI'));
  insert into _probe_result values ('spring_forward_weekend_same_clock_time', '2027-03-12 16:30',
    to_char(public.back_to_back_105_opens_at('2027-03-14 16:30 America/New_York', '2027-03-14 18:00 America/New_York')
            at time zone 'America/New_York', 'YYYY-MM-DD HH24:MI'));

  -- ------------------------------------ what a 105 is (her real names)
  insert into _probe_result values ('coed_105_is_a_105', 'true', public.is_105('Coed 105', null)::text);
  insert into _probe_result values ('level_105_is_a_105', 'true', public.is_105('level 4.0+ 105', 'Clinic')::text);
  insert into _probe_result values ('category_105_is_a_105', 'true', public.is_105('Sunday Social', '105')::text);
  insert into _probe_result values ('ladies_clinic_is_not', 'false', public.is_105('Tuesday Ladies 3.0+', 'Clinic')::text);

  -- ------------------------------------------------------ fixtures
  -- Far pair: back to back on a day four days out, so the earlier start
  -- minus 48 hours is still in the future. Near pair: tomorrow evening, so
  -- the 48 hours have already begun. All open to everyone since yesterday.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe Coed 105 early', 'coed', '105', 'probe',
          (far_day + time '16:30') at time zone 'America/New_York', (far_day + time '18:00') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (far_day + time '13:30') at time zone 'America/New_York',
          8, 'published', 90) returning id into x1;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe Coed 105 late', 'coed', '105', 'probe',
          (far_day + time '18:00') at time zone 'America/New_York', (far_day + time '19:00') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (far_day + time '15:00') at time zone 'America/New_York',
          8, 'published', 60) returning id into x2;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe Ladies 3.0+ same day', 'ladies', 'Clinic', 'probe',
          (far_day + time '19:30') at time zone 'America/New_York', (far_day + time '20:30') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (far_day + time '16:30') at time zone 'America/New_York',
          8, 'published', 60) returning id into nx;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe 105 tomorrow early', 'coed', '105', 'probe',
          (near_day + time '18:00') at time zone 'America/New_York', (near_day + time '19:30') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (near_day + time '15:00') at time zone 'America/New_York',
          8, 'published', 90) returning id into y1;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe 105 tomorrow late', 'coed', '105', 'probe',
          (near_day + time '19:30') at time zone 'America/New_York', (near_day + time '20:30') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (near_day + time '16:30') at time zone 'America/New_York',
          8, 'published', 60) returning id into y2;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe 105 the next day', 'coed', '105', 'probe',
          (far_day + 1 + time '16:30') at time zone 'America/New_York', (far_day + 1 + time '18:00') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (far_day + 1 + time '13:30') at time zone 'America/New_York',
          8, 'published', 90) returning id into other_day;

  -- UTC-date trap: 19:00 and 20:30 New York are one New York day but two
  -- UTC days (EDT 23:00Z and 00:30Z next day), two days after far_day.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe 105 evening', 'coed', '105', 'probe',
          (far_day + 2 + time '19:00') at time zone 'America/New_York', (far_day + 2 + time '20:00') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (far_day + 2 + time '16:00') at time zone 'America/New_York',
          8, 'published', 60) returning id into z1;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe 105 late evening', 'coed', '105', 'probe',
          (far_day + 2 + time '20:30') at time zone 'America/New_York', (far_day + 2 + time '21:30') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (far_day + 2 + time '17:30') at time zone 'America/New_York',
          8, 'published', 60) returning id into z2;
  -- A day whose first 105 will be canceled by Tara.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe 105 to be canceled', 'coed', '105', 'probe',
          (far_day + 3 + time '16:30') at time zone 'America/New_York', (far_day + 3 + time '18:00') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (far_day + 3 + time '13:30') at time zone 'America/New_York',
          8, 'published', 90) returning id into w1;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe 105 after the canceled one', 'coed', '105', 'probe',
          (far_day + 3 + time '18:00') at time zone 'America/New_York', (far_day + 3 + time '19:00') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', (far_day + 3 + time '15:00') at time zone 'America/New_York',
          8, 'published', 60) returning id into w2;
  -- Straddling the mark: one minute before and one minute after the moment
  -- that is exactly two days from now on the New York clock, same day.
  t_mark := ((now() at time zone 'America/New_York') + interval '2 days') at time zone 'America/New_York';
  if ((t_mark - interval '1 minute') at time zone 'America/New_York')::date
     <> ((t_mark + interval '1 minute') at time zone 'America/New_York')::date then
    t_mark := t_mark + interval '10 minutes';   -- keep both on one New York day
  end if;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe 105 just inside', 'coed', '105', 'probe', t_mark - interval '1 minute', t_mark + interval '59 minutes',
          now() - interval '2 days', now() - interval '1 day', t_mark - interval '3 hours 1 minute', 8, 'published', 60)
  returning id into s1;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe 105 just outside', 'coed', '105', 'probe', t_mark + interval '1 minute', t_mark + interval '61 minutes',
          now() - interval '2 days', now() - interval '1 day', t_mark - interval '2 hours 59 minutes', 8, 'published', 60)
  returning id into s2;

  -- ---------------------------------------------------- as Rob, non-member
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);

  -- 1. "only one when registration opens for them": the first 105 goes in.
  r := public.register_for_clinic(x1, ROB_P); rx1 := r.id;
  insert into _probe_result values ('nonmember_first_105_ok', 'pool', r.status::text);

  -- 2. The second 105 the same day, before Friday-4:30-equivalent: refused.
  begin
    perform public.register_for_clinic(x2, ROB_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('nonmember_second_105_same_day_refused', 'back_to_back_105', v);

  -- 3. A non-105 the same day is not her rule.
  begin
    perform public.register_for_clinic(nx, ROB_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('nonmember_other_clinic_same_day_ok', 'registered', v);

  -- 4. A 105 the next day is not back to back.
  begin
    perform public.register_for_clinic(other_day, ROB_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('nonmember_105_next_day_ok', 'registered', v);

  -- 5. Inside 48 hours of the earlier start, both 105s are allowed.
  begin
    perform public.register_for_clinic(y1, ROB_P);
    perform public.register_for_clinic(y2, ROB_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('nonmember_both_105s_inside_48h_ok', 'registered', v);

  -- 6. Leaving the first frees the day: a canceled spot is not a spot.
  perform public.leave_pool(rx1);
  begin
    perform public.register_for_clinic(x2, ROB_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('after_leaving_first_the_second_is_ok', 'registered', v);

  -- 7. The same New York day even when the two UTC dates differ.
  perform public.register_for_clinic(z1, ROB_P);
  begin
    perform public.register_for_clinic(z2, ROB_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('same_ny_day_across_utc_midnight_refused', 'back_to_back_105', v);

  -- 8. A held 105 whose clinic Tara canceled does not count.
  perform public.register_for_clinic(w1, ROB_P);
  perform set_config('role', 'postgres', true);
  update public.clinics set status = 'canceled', canceled_at = now() where id = w1;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(w2, ROB_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('canceled_clinic_frees_the_day', 'registered', v);

  -- 9. The EARLIER start decides. Rob takes the later one first, then the
  --    earlier (one minute inside the mark): allowed, because the mark is
  --    already past for the earlier start. A rule using the later start, or
  --    only the clinic being booked, would refuse one of the two orders.
  begin
    perform public.register_for_clinic(s2, ROB_P);
    perform public.register_for_clinic(s1, ROB_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('earlier_start_decides_later_first', 'registered', v);

  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  begin
    perform public.register_for_clinic(s1, PRIYA_P);
    perform public.register_for_clinic(s2, PRIYA_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('earlier_start_decides_earlier_first', 'registered', v);

  -- ------------------------------------------------ as Maria, member
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.register_for_clinic(x1, MARIA_P);
    perform public.register_for_clinic(x2, MARIA_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('member_back_to_back_105s_ok', 'registered', v);

  -- ------------------------------------------- as Tara, placing Rob
  -- Rob now holds x2 live; Tara putting him in x1 too is her call.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  begin
    perform public.register_for_clinic(x1, ROB_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('tara_is_not_bound_by_it', 'registered', v);

  perform set_config('role', 'postgres', true);

  -- 10. Grants: the helpers are internal (only register_for_clinic calls them).
  insert into _probe_result values ('is_105_is_internal', 'false false',
    has_function_privilege('anon', 'public.is_105(text, text)', 'EXECUTE')::text || ' ' ||
    has_function_privilege('authenticated', 'public.is_105(text, text)', 'EXECUTE')::text);
  insert into _probe_result values ('b2b_helper_is_internal', 'false false',
    has_function_privilege('anon', 'public.back_to_back_105_opens_at(timestamptz, timestamptz)', 'EXECUTE')::text || ' ' ||
    has_function_privilege('authenticated', 'public.back_to_back_105_opens_at(timestamptz, timestamptz)', 'EXECUTE')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
