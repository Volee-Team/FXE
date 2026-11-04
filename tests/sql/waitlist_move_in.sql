-- waitlist_move_in.sql
--
-- Tara, 2026-11-04 (decision 0047): "when I move them to the clinic they
-- automatically are moved and get notification they're in, UNLESS it's the
-- same day of clinic in which case they have to accept the invitiation."
-- One button on a Waitlist row (invite_from_pool), two outcomes, decided by
-- the clinic's day in New York:
--
--   clinic day after today         -> 'in' at once, #1 in her words, no invitation
--   clinic day is today            -> 'response_needed', #2, as before
--   clinic day already past        -> 'response_needed' (never straight into a
--                                     clinic that has ended: it would be charged)
--   after today, but inside the    -> 'response_needed': a spot they never said
--   3-hour cancel cutoff              yes to must not start as a late cancel
--   a draft, after today           -> 'in', and nobody told (players can't see it)
--   a second tap                   -> not_in_pool, nothing sent twice
--   a player pressing it           -> not_authorized
--
-- The day boundary is checked at both edges, in New York, at any hour: a
-- clinic at 12:30 AM tomorrow is "after today" (unless it is inside the
-- cutoff, then it is an invitation either way, so that row expects whichever
-- the rule gives at run time: worked out from the clock, not the code); one
-- later today (halfway to midnight) and one at 11:30 PM today are "today".
-- 11:30 PM New York is always tomorrow in UTC, so a rule that compared UTC
-- dates goes red on that row at the hours the midnight row cannot catch (the
-- sql-auditor, 2026-11-04). Expected values are worked out by hand.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA  constant uuid := '11111111-1111-1111-1111-111111111111';
  ROB   constant uuid := '44444444-4444-4444-4444-444444444444';
  KEN   constant uuid := '33333333-3333-3333-3333-333333333333';
  KEN_P constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P constant uuid := 'a0000000-0000-0000-0000-000000000003';
  -- Next week's Thursday, 9:00 AM New York, built from the wall clock.
  monday timestamp := date_trunc('week', now() at time zone 'America/New_York');
  YOURE_IN constant text := 'You''re all set for Probe Move Thursday on Thursday at 9:00 AM. Looking forward to seeing you on court!';
  today_later timestamptz := now() + ((((now() at time zone 'America/New_York')::date + 1)::timestamp at time zone 'America/New_York') - now()) / 2;
  tomorrow_early timestamptz := (((now() at time zone 'America/New_York')::date + 1) + interval '30 minutes') at time zone 'America/New_York';
  today_late timestamptz := ((now() at time zone 'America/New_York')::date + time '23:30') at time zone 'America/New_York';
  c_thu uuid; c_today uuid; c_ended uuid; c_draft uuid; c_midnight uuid; c_late uuid; c_cutoff uuid;
  r_thu uuid; r_today uuid; r_ended uuid; r_draft uuid; r_midnight uuid; r_rob uuid; r_late uuid; r_cutoff uuid;
  v public.registrations; err text; n int; got text;
begin
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Move Thursday', 'coed', 'Clinic', 'probe',
          (monday + interval '10 days 9 hours') at time zone 'America/New_York',
          (monday + interval '10 days 10 hours') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into c_thu;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Move Today', 'coed', 'Clinic', 'probe', today_later, today_later + interval '1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into c_today;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Move Ended', 'coed', 'Clinic', 'probe', now() - interval '26 hours', now() - interval '25 hours',
          now() - interval '9 days', now() - interval '8 days', 8, 'published', 60)
  returning id into c_ended;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Move Draft', 'coed', 'Clinic', 'probe', now() + interval '12 days', now() + interval '12 days 1 hour',
          now() + interval '8 days', now() + interval '9 days', 8, 'draft', 60)
  returning id into c_draft;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Move Midnight', 'coed', 'Clinic', 'probe', tomorrow_early, tomorrow_early + interval '1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into c_midnight;

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Move Late Tonight', 'coed', 'Clinic', 'probe', today_late, today_late + interval '1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into c_late;
  -- Tomorrow in New York but under 3 hours away: only exists late at night,
  -- so it is placed at the later of 1 hour from now and 12:10 AM tomorrow,
  -- and checked only when that is both tomorrow and inside the cutoff.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Move Cutoff', 'coed', 'Clinic', 'probe',
          greatest(now() + interval '1 hour', tomorrow_early - interval '20 minutes'),
          greatest(now() + interval '1 hour', tomorrow_early - interval '20 minutes') + interval '1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into c_cutoff;

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_thu, KEN_P, 'pool', 'self', 1800, true, 60) returning id into r_thu;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_late, KEN_P, 'pool', 'self', 1800, true, 60) returning id into r_late;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_cutoff, KEN_P, 'pool', 'self', 1800, true, 60) returning id into r_cutoff;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_today, KEN_P, 'pool', 'self', 1800, true, 60) returning id into r_today;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_ended, KEN_P, 'pool', 'self', 1800, true, 60) returning id into r_ended;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_draft, KEN_P, 'pool', 'self', 1800, true, 60) returning id into r_draft;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_midnight, KEN_P, 'pool', 'self', 1800, true, 60) returning id into r_midnight;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_thu, ROB_P, 'pool', 'self', 2300, false, 60) returning id into r_rob;

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  -- 1. Before clinic day: straight in, #1 in her words, no invitation.
  v := public.invite_from_pool(r_thu);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('before_clinic_day_moves_straight_in', 'in|null',
    v.status::text || '|' || coalesce(v.invited_at::text, 'null'));
  select count(*), max(body) into n, got from public.notifications
   where account_id = KEN and entity_id = r_thu and type = 'youre_in';
  insert into _probe_result values ('before_clinic_day_sends_her_youre_in', '1|' || YOURE_IN, n || '|' || coalesce(got, ''));
  select count(*) into n from public.notifications where entity_id = r_thu and type = 'invitation_received';
  insert into _probe_result values ('before_clinic_day_sends_no_invitation', '0', n::text);
  select count(*) into n from public.notifications where entity_id = r_thu;
  insert into _probe_result values ('before_clinic_day_sends_one_row_only', '1', n::text);

  -- 2. A second tap: refused, nothing more sent.
  perform set_config('role', 'authenticated', true);
  begin
    perform public.invite_from_pool(r_thu); err := 'moved again';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('second_tap_is_refused', 'not_in_pool', err);
  select count(*) into n from public.notifications where entity_id = r_thu;
  insert into _probe_result values ('second_tap_sends_nothing', '1', n::text);

  -- 3. Clinic day: an invitation, as before.
  perform set_config('role', 'authenticated', true);
  v := public.invite_from_pool(r_today);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('on_clinic_day_invites', 'response_needed|stamped',
    v.status::text || '|' || case when v.invited_at is not null then 'stamped' else 'null' end);
  select string_agg(type || ':' || body, ' ; ') into got from public.notifications where entity_id = r_today;
  insert into _probe_result values ('on_clinic_day_sends_the_invitation',
    'invitation_received:A spot opened in Probe Move Today. Accept or decline.', coalesce(got, ''));

  -- 4. The day after today begins at New York midnight: 12:30 AM tomorrow
  --    moves in (while it is more than 3 hours away), 11:30 PM today invites.
  perform set_config('role', 'authenticated', true);
  v := public.invite_from_pool(r_midnight);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('half_past_midnight_tomorrow_is_before_clinic_day',
    case when tomorrow_early - now() >= interval '3 hours' then 'in' else 'response_needed' end, v.status::text);
  perform set_config('role', 'authenticated', true);
  v := public.invite_from_pool(r_late);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('half_past_eleven_tonight_is_clinic_day', 'response_needed', v.status::text);

  -- 4b. Tomorrow, but inside the 3-hour cancel cutoff: an invitation. The
  --     fixture is only tomorrow-and-inside late at night; otherwise the row
  --     records that the case could not be built at this hour.
  perform set_config('role', 'authenticated', true);
  v := public.invite_from_pool(r_cutoff);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('tomorrow_inside_the_cutoff_invites',
    case when (select (starts_at at time zone 'America/New_York')::date > (now() at time zone 'America/New_York')::date
                  and starts_at - now() < interval '3 hours' from public.clinics where id = c_cutoff)
         then 'response_needed' else 'not buildable at this hour' end,
    case when (select (starts_at at time zone 'America/New_York')::date > (now() at time zone 'America/New_York')::date
                  and starts_at - now() < interval '3 hours' from public.clinics where id = c_cutoff)
         then v.status::text else 'not buildable at this hour' end);

  -- 5. A clinic whose day has passed: never straight in.
  perform set_config('role', 'authenticated', true);
  v := public.invite_from_pool(r_ended);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('past_clinic_day_still_invites', 'response_needed', v.status::text);

  -- 6. A draft: in, and nobody told (players cannot see a draft).
  perform set_config('role', 'authenticated', true);
  v := public.invite_from_pool(r_draft);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where entity_id = r_draft;
  insert into _probe_result values ('draft_moves_in_and_tells_nobody', 'in|0', v.status::text || '|' || n);

  -- 7. A player cannot press it.
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.invite_from_pool(r_rob); err := 'moved';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('player_cannot_move_anyone', 'not_authorized', err);
  insert into _probe_result values ('player_attempt_moves_nothing', 'pool',
    (select status::text from public.registrations where id = r_rob));
end $$;

select check_name, expected, actual,
  case
    when actual = expected then 'PASS'
    -- Substring matching only for an expected error name inside a server
    -- message, never for numbers (the 105-contains-0 lesson).
    when expected ~ '[A-Za-z]' and strpos(actual, expected) > 0 then 'PASS'
    else 'FAIL'
  end as result
from _probe_result
order by check_name;

rollback;
