-- membership_reprice.sql
--
-- 20261111000001. Tara: "[a player] is a member and getting charged
-- nonmember prices". THE RULE: when Tara changes a player's membership,
-- every registration of theirs not yet charged (not Paid, no live fee:
-- pending, processing or succeeded) that can still owe, on a clinic not
-- canceled and not yet over, takes the new answer: was_member and the
-- clinic's price for it, the rain half included. Money already taken stays
-- (a refund, not a reprice). A clinic that has ended keeps what it was,
-- charged or not (decisions 0002 and 0055). A price she typed keeps its
-- amount. Only Tara may change it.
--
-- Rob is seeded a non-member. Clinics are $18 members, $23 non-members.
-- Expected values are written from the rule, not copied from a run.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  ROB   constant uuid := '44444444-4444-4444-4444-444444444444';
  ROB_P constant uuid := 'a0000000-0000-0000-0000-000000000003';
  c_open uuid; c_paid uuid; c_fee uuid; c_typed uuid; c_left uuid; c_wait uuid; c_gone uuid; c_rain uuid; c_late uuid;
  c_past uuid; c_pend uuid;
  r_open uuid; r_paid uuid; r_fee uuid; r_typed uuid; r_left uuid; r_wait uuid; r_gone uuid; r_rain uuid; r_late uuid;
  r_past uuid; r_pend uuid;
  err text; got text;
begin
  -- Nine clinics, Rob on each at the non-member price.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, member_price_cents, nonmember_price_cents)
  select 'Probe M' || i, 'coed', 'Clinic', 'probe', now() + make_interval(days => i), now() + make_interval(days => i, hours => 1),
         now() - interval '2 days', now() - interval '1 day', 8, 'published', 60, 1800, 2300
    from generate_series(1, 9) i;
  select id into c_open  from public.clinics where name = 'Probe M1';
  select id into c_paid  from public.clinics where name = 'Probe M2';
  select id into c_fee   from public.clinics where name = 'Probe M3';
  select id into c_typed from public.clinics where name = 'Probe M4';
  select id into c_left  from public.clinics where name = 'Probe M5';
  select id into c_wait  from public.clinics where name = 'Probe M6';
  select id into c_gone  from public.clinics where name = 'Probe M7';
  select id into c_rain  from public.clinics where name = 'Probe M8';
  select id into c_late  from public.clinics where name = 'Probe M9';
  update public.clinics set rain_half = true where id = c_rain;

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_open, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_open;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, paid)
  values (c_paid, ROB_P, 'in', 'self', 2300, false, 60, true) returning id into r_paid;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_fee, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_fee;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode)
  values (r_fee, ROB, 'clinic_fee', 2300, 'processing', true);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, price_set_by_admin)
  values (c_typed, ROB_P, 'in', 'self', 1400, false, 60, true) returning id into r_typed;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, canceled_at, canceled_by)
  values (c_left, ROB_P, 'canceled', 'self', 2300, false, 60, now(), ROB) returning id into r_left;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_wait, ROB_P, 'pool', 'self', 2300, false, 60) returning id into r_wait;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_gone, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_gone;
  update public.clinics set status = 'canceled' where id = c_gone;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_rain, ROB_P, 'in', 'self', 1150, false, 60) returning id into r_rain;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, canceled_at, canceled_by, late_cancel)
  values (c_late, ROB_P, 'canceled', 'self', 2300, false, 60, now(), ROB, true) returning id into r_late;

  -- A clinic that ended 40 days ago, never charged; and one with a charge
  -- just asked for (pending).
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, member_price_cents, nonmember_price_cents)
  values ('Probe M Past', 'coed', 'Clinic', 'probe', now() - interval '40 days', now() - interval '40 days' + interval '1 hour',
          now() - interval '45 days', now() - interval '44 days', 8, 'published', 60, 1800, 2300) returning id into c_past;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_past, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_past;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, member_price_cents, nonmember_price_cents)
  values ('Probe M Pending', 'coed', 'Clinic', 'probe', now() + interval '10 days', now() + interval '10 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60, 1800, 2300) returning id into c_pend;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_pend, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_pend;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_pend, ROB, 'clinic_fee', 2300, 'pending');

  -- A player may not.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  err := null;
  begin perform public.admin_set_membership(ROB_P, true); exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_change_membership', 'not_authorized', coalesce(err, 'no error'));
  perform set_config('role', 'postgres', true);
  select price_cents_charged::text into got from public.registrations where id = r_open;
  insert into _probe_result values ('a_refused_call_changes_nothing', '2300', got);

  -- Tara makes Rob a member.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_set_membership(ROB_P, true);
  perform set_config('role', 'postgres', true);

  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_open;
  insert into _probe_result values ('in_not_charged_takes_member_price', '1800 true', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_wait;
  insert into _probe_result values ('waitlist_takes_member_price', '1800 true', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_rain;
  insert into _probe_result values ('rain_half_of_member_price', '900 true', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_late;
  insert into _probe_result values ('late_cancel_owes_member_price', '1800 true', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_paid;
  insert into _probe_result values ('marked_paid_is_left_alone', '2300 false', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_fee;
  insert into _probe_result values ('charged_is_left_alone', '2300 false', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_typed;
  insert into _probe_result values ('typed_price_keeps_amount', '1400 true', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_left;
  insert into _probe_result values ('canceled_is_left_alone', '2300 false', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_gone;
  insert into _probe_result values ('canceled_clinic_is_left_alone', '2300 false', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_past;
  insert into _probe_result values ('ended_clinic_keeps_its_history', '2300 false', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_pend;
  insert into _probe_result values ('pending_charge_is_left_alone', '2300 false', got);

  -- And back: a non-member again owes the non-member price.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_set_membership(ROB_P, false);
  perform set_config('role', 'postgres', true);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_open;
  insert into _probe_result values ('back_to_non_member_price', '2300 false', got);
  select price_cents_charged || ' ' || was_member into got from public.registrations where id = r_rain;
  insert into _probe_result values ('back_to_non_member_rain_half', '1150 false', got);

  -- A second call changes nothing (a retry).
  select public.follow_membership(ROB_P)::text into got;
  insert into _probe_result values ('a_second_call_changes_nothing', '0', got);

  -- The helper is internal: asked, not called (a denied call can take the
  -- local backend down, CLAUDE.md).
  insert into _probe_result values ('helper_not_callable', 'false',
    has_function_privilege('authenticated', 'public.follow_membership(uuid)', 'EXECUTE')::text);
end $$;

select check_name, expected, actual,
  case
    when actual = expected then 'PASS'
    when expected ~ '[A-Za-z]' and strpos(actual, expected) > 0 then 'PASS'
    else 'FAIL'
  end as result
from _probe_result
order by check_name;

rollback;
