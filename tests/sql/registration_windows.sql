-- registration_windows.sql
--
-- The entire registration table from the Developer Guide, section 6, exercised
-- through the real RPC as real authenticated users. This is the business rule
-- most likely to be quietly broken by a future change, and the one Tara will
-- notice first if it is.
--
--   Member,     inside priority window, room available -> You're In!
--   Member,     inside priority window, clinic full    -> Player Pool
--   Member,     after priority window                  -> Player Pool
--   Non-member, after public opening                   -> Player Pool
--   Non-member, inside member-only window              -> rejected
--   Anyone,     before member opening                  -> rejected
--   Anyone,     after registration closes              -> rejected
--   Same player twice                                  -> rejected, one row only
--
-- Clinics are constructed with windows placed relative to now(), so the probe
-- controls which phase it is testing without needing to freeze the clock.
--
-- Expected: every row of the final result reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;

do $$
declare
  MARIA constant uuid := 'a0000000-0000-0000-0000-000000000001'; -- member
  KEN   constant uuid := 'a0000000-0000-0000-0000-000000000002'; -- member
  ROB   constant uuid := 'a0000000-0000-0000-0000-000000000003'; -- NON-member
  DANA  constant uuid := 'a0000000-0000-0000-0000-000000000004'; -- member
  MARIA_ACC constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN_ACC   constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB_ACC   constant uuid := '44444444-4444-4444-4444-444444444444';
  DANA_ACC  constant uuid := '66666666-6666-6666-6666-666666666666';
  c_priority uuid; c_full uuid; c_open uuid; c_early uuid; c_closed uuid;
  r public.registrations;
  v_status text;
begin
  -- Phase: member priority window is open, public opening is still 12h away.
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('Priority Window', 'coed', now() + interval '3 days', now() + interval '3 days 1 hour',
      now() - interval '1 hour', now() + interval '12 hours', 2, 'published')
  returning id into c_priority;

  -- Same phase, but capacity 1 and already taken.
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('Priority Full', 'coed', now() + interval '3 days', now() + interval '3 days 1 hour',
      now() - interval '1 hour', now() + interval '12 hours', 1, 'published')
  returning id into c_full;

  -- Phase: both windows open (public opening has passed).
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('Fully Open', 'coed', now() + interval '3 days', now() + interval '3 days 1 hour',
      now() - interval '2 days', now() - interval '1 day', 10, 'published')
  returning id into c_open;

  -- Phase: nothing is open yet.
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('Not Yet Open', 'coed', now() + interval '10 days', now() + interval '10 days 1 hour',
      now() + interval '5 days', now() + interval '6 days', 10, 'published')
  returning id into c_early;

  -- Phase: open, but registration has closed.
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status)
  values ('Closed', 'coed', now() + interval '1 day', now() + interval '1 day 1 hour',
      now() - interval '3 days', now() - interval '2 days', now() - interval '1 hour', 10, 'published')
  returning id into c_closed;

  -- 1. Member inside the priority window, room available -> in
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  r := public.register_for_clinic(c_priority, MARIA);
  insert into _probe_result values ('member_in_priority_window_gets_in', 'in', r.status::text);

  -- 2. Member inside the priority window, clinic full -> pool
  r := public.register_for_clinic(c_full, MARIA);   -- takes the only seat
  perform set_config('request.jwt.claims', json_build_object('sub', KEN_ACC)::text, true);
  r := public.register_for_clinic(c_full, KEN);
  insert into _probe_result values ('member_when_full_goes_to_pool', 'pool', r.status::text);

  -- 3. Late member (public window already open) -> pool
  r := public.register_for_clinic(c_open, KEN);
  insert into _probe_result values ('late_member_goes_to_pool', 'pool', r.status::text);

  -- 4. Non-member after public opening -> pool
  perform set_config('request.jwt.claims', json_build_object('sub', ROB_ACC)::text, true);
  r := public.register_for_clinic(c_open, ROB);
  insert into _probe_result values ('non_member_goes_to_pool', 'pool', r.status::text);

  -- 5. Non-member inside the member-only window -> rejected
  begin
    r := public.register_for_clinic(c_priority, ROB);
    insert into _probe_result values ('non_member_blocked_in_member_window', 'registration_not_open', 'allowed:' || r.status::text);
  exception when others then
    insert into _probe_result values ('non_member_blocked_in_member_window', 'registration_not_open', sqlerrm);
  end;

  -- 6. Before anything opens -> rejected
  perform set_config('request.jwt.claims', json_build_object('sub', DANA_ACC)::text, true);
  begin
    r := public.register_for_clinic(c_early, DANA);
    insert into _probe_result values ('before_opening_rejected', 'registration_not_open', 'allowed:' || r.status::text);
  exception when others then
    insert into _probe_result values ('before_opening_rejected', 'registration_not_open', sqlerrm);
  end;

  -- 7. After registration closes -> rejected
  begin
    r := public.register_for_clinic(c_closed, DANA);
    insert into _probe_result values ('after_close_rejected', 'registration_closed', 'allowed:' || r.status::text);
  exception when others then
    insert into _probe_result values ('after_close_rejected', 'registration_closed', sqlerrm);
  end;

  -- 8. Registering twice -> rejected, and exactly one live row survives.
  --    This is also the retry-after-timeout path.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  begin
    r := public.register_for_clinic(c_priority, MARIA);
    insert into _probe_result values ('duplicate_rejected', 'already_registered', 'allowed:' || r.status::text);
  exception when others then
    insert into _probe_result values ('duplicate_rejected', 'already_registered', sqlerrm);
  end;

  select count(*)::text into v_status from public.registrations
    where clinic_id = c_priority and player_id = MARIA and status <> 'canceled';
  insert into _probe_result values ('duplicate_leaves_one_live_row', '1', v_status);

  -- 9. Capacity is respected: the full clinic still has exactly one You're In!.
  select count(*)::text into v_status from public.registrations
    where clinic_id = c_full and status = 'in';
  insert into _probe_result values ('capacity_respected', '1', v_status);
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
