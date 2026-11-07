-- clinic_price_and_rain.sql
--
-- Decision 0053 (20261107000004), Tara's question 143: change a clinic's rate
-- any time, and "charge half" when it rains. From the rule, by hand:
--
--   a new rate        the clinic's two prices, and every registration on it
--                     nobody has paid or been charged for (You're In!,
--                     Waitlist, Response Needed alike), by member status
--   rain half         everyone You're In! who came owes half of the clinic's
--                     price, rounded to the cent; a no-show and a late cancel
--                     pay in full (question 103); marked a no-show while it is
--                     on goes back to full; added while it is on owes half;
--                     off puts the full price back; a new rate stays half
--   never             a registration marked Paid, or one holding a charge
--   only Tara         a player and a pro are refused; the reprice is internal
--
-- Fixture: a 90-minute clinic at $22 member / $28 non-member. Maria (member)
-- and Rob (non-member) In, Ken (member) on the Waitlist, Dana (non-member) In
-- and marked Paid, Priya (member) In and charged $22.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';
  PRIYA   constant uuid := '55555555-5555-5555-5555-555555555555';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  THEO_P  constant uuid := 'a0000000-0000-0000-0000-000000000008';
  LENA_P  constant uuid := 'a0000000-0000-0000-0000-000000000007';
  GINA_P  constant uuid := 'a0000000-0000-0000-0000-000000000009';
  c uuid; r_maria uuid; r_rob uuid; r_ken uuid; r_dana uuid; r_priya uuid; r_theo uuid; r_lena uuid; r_gina uuid;
  r public.registrations;
  n int; got text; err text;
begin
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes,
      member_price_cents, nonmember_price_cents)
  values ('Probe Rain', 'coed', 'Clinic', 'probe', now() - interval '2 hours', now() - interval '30 minutes',
          now() - interval '5 days', now() - interval '4 days', 8, 'published', 90, 2200, 2800) returning id into c;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c, MARIA_P, 'in', 'self', 2200, true, 90) returning id into r_maria;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c, ROB_P, 'in', 'self', 2800, false, 90) returning id into r_rob;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c, KEN_P, 'pool', 'self', 2200, true, 90) returning id into r_ken;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, paid)
  values (c, DANA_P, 'in', 'self', 2800, false, 90, true) returning id into r_dana;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c, PRIYA_P, 'in', 'self', 2200, true, 90) returning id into r_priya;
  -- Theo (non-member) a no-show; Lena (member) a late cancel.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, no_show)
  values (c, THEO_P, 'in', 'self', 2800, false, 90, true) returning id into r_theo;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, late_cancel, canceled_at)
  values (c, LENA_P, 'canceled', 'self', 2200, true, 90, true, now() - interval '3 hours') returning id into r_lena;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode)
  values (r_priya, PRIYA, 'clinic_fee', 2200, 'succeeded', true);

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);

  -- ---------------------------------------------------------- a new rate
  n := public.admin_set_clinic_prices(c, 2000, 2500);
  insert into _probe_result values ('a_new_rate_reprices_five', '5', n::text);
  perform set_config('role', 'postgres', true);
  select string_agg(price_cents_charged::text, ' ' order by x) into got from (
    select price_cents_charged, case id when r_maria then 1 when r_rob then 2 when r_ken then 3 when r_dana then 4 else 5 end x
      from public.registrations where id in (r_maria, r_rob, r_ken, r_dana, r_priya)) y;
  -- Maria, Rob, Ken (Waitlist), Dana (Paid), Priya (charged)
  insert into _probe_result values ('everyone_unpaid_owes_the_new_rate', '2000 2500 2000 2800 2200', got);
  select member_price_cents || '/' || nonmember_price_cents into got from public.clinics where id = c;
  insert into _probe_result values ('the_clinic_shows_the_new_rate', '2000/2500', got);
  perform set_config('role', 'authenticated', true);
  n := public.admin_set_clinic_prices(c, 2000, 2500);
  insert into _probe_result values ('the_same_rate_again_moves_nothing', '0', n::text);

  -- ---------------------------------------------------------- rain half
  n := public.admin_set_rain_half(c, true);
  perform set_config('role', 'postgres', true);
  select string_agg(price_cents_charged::text, ' ' order by x) into got from (
    select price_cents_charged, case id when r_maria then 1 when r_rob then 2 when r_ken then 3 when r_dana then 4 else 5 end x
      from public.registrations where id in (r_maria, r_rob, r_ken, r_dana, r_priya)) y;
  insert into _probe_result values ('rain_half_halves_who_came', '1000 1250 2000 2800 2200', got);
  perform set_config('role', 'authenticated', true);
  select rain_half::text into got from public.clinics_admin where id = c;
  insert into _probe_result values ('she_sees_it_is_on', 'true', got);
  perform set_config('role', 'postgres', true);
  select (select price_cents_charged from public.registrations where id = r_theo) || ' '
      || (select price_cents_charged from public.registrations where id = r_lena) into got;
  insert into _probe_result values ('a_no_show_and_a_late_cancel_pay_in_full', '2500 2000', got);
  -- Marked a no-show while it rains: full; unmarked: half again.
  update public.registrations set no_show = true where id = r_maria;
  select price_cents_charged::text into got from public.registrations where id = r_maria;
  insert into _probe_result values ('marked_a_no_show_goes_back_to_full', '2000', got);
  update public.registrations set no_show = false where id = r_maria;
  select price_cents_charged::text into got from public.registrations where id = r_maria;
  insert into _probe_result values ('unmarked_is_half_again', '1000', got);
  -- Added while it rains: half.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c, GINA_P, 'in', 'admin', 2000, true, 90) returning id into r_gina;
  select price_cents_charged::text into got from public.registrations where id = r_gina;
  insert into _probe_result values ('added_while_it_rains_owes_half', '1000', got);
  -- Dana's Paid unticked while it rains: she owes half, not the full price.
  update public.registrations set paid = false where id = r_dana;
  select price_cents_charged::text into got from public.registrations where id = r_dana;
  insert into _probe_result values ('paid_unticked_while_raining_owes_half', '1250', got);
  update public.registrations set paid = true, price_cents_charged = 2800 where id = r_dana;
  -- Tara's own No-show RPC, not a raw update: full, then half again.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_set_no_show(r_rob, true);
  perform set_config('role', 'postgres', true);
  select price_cents_charged::text into got from public.registrations where id = r_rob;
  insert into _probe_result values ('her_no_show_mark_is_full', '2500', got);
  perform set_config('role', 'authenticated', true);
  perform public.admin_set_no_show(r_rob, false);
  perform set_config('role', 'postgres', true);
  select price_cents_charged::text into got from public.registrations where id = r_rob;
  insert into _probe_result values ('her_unmark_is_half', '1250', got);
  -- The length cannot change while it rains.
  begin update public.clinics set duration_minutes = 60 where id = c; err := 'changed';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('no_new_length_while_raining', 'rain_half_on', err);
  perform set_config('role', 'authenticated', true);

  -- A new rate while it rains: half of the new rate, to the cent.
  perform public.admin_set_clinic_prices(c, 2300, 2900);
  perform set_config('role', 'postgres', true);
  select string_agg(price_cents_charged::text, ' ' order by x) into got from (
    select price_cents_charged, case id when r_maria then 1 when r_rob then 2 else 3 end x
      from public.registrations where id in (r_maria, r_rob)) y;
  insert into _probe_result values ('a_new_rate_while_raining_stays_half', '1150 1450', got);
  perform set_config('role', 'authenticated', true);

  n := public.admin_set_rain_half(c, false);
  perform set_config('role', 'postgres', true);
  select string_agg(price_cents_charged::text, ' ' order by x) into got from (
    select price_cents_charged, case id when r_maria then 1 when r_rob then 2 when r_ken then 3 when r_dana then 4 else 5 end x
      from public.registrations where id in (r_maria, r_rob, r_ken, r_dana, r_priya)) y;
  insert into _probe_result values ('off_puts_the_full_rate_back', '2300 2900 2300 2800 2200', got);
  perform set_config('role', 'authenticated', true);

  -- ---------------------------------------------------------- refused
  begin perform public.admin_set_clinic_prices(c, 0, 2500); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_zero_rate_is_refused', 'invalid_price', err);
  perform set_config('role', 'postgres', true);
  select member_price_cents::text into got from public.clinics where id = c;
  insert into _probe_result values ('and_nothing_moved', '2300', got);
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin perform public.admin_set_rain_half(c, true); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_call_rain', 'not_authorized', err);
  begin perform public.admin_set_clinic_prices(c, 100, 100); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_set_a_rate', 'not_authorized', err);
  perform set_config('role', 'postgres', true);
  select member_price_cents::text into got from public.clinics where id = c;
  insert into _probe_result values ('and_the_rate_did_not_move', '2300', got);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin perform public.admin_set_rain_half(c, true); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_pro_cannot_call_rain', 'not_authorized', err);
  perform set_config('role', 'postgres', true);
  select rain_half::text into got from public.clinics where id = c;
  insert into _probe_result values ('and_it_is_still_off', 'false', got);
  insert into _probe_result values ('the_reprice_is_internal', 'false',
    has_function_privilege('authenticated', 'public.reprice_clinic(uuid)', 'EXECUTE')::text);
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
