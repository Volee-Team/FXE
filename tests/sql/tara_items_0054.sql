-- tara_items_0054.sql
--
-- Tara's updated "Next update" list, items 7, 8, 10 and 11 (20261109000001,
-- decision 0054). Written from her words and answers, by hand:
--
--    7. same-day decline   "If someone is invited to same day clinic and
--                          denies it, don't put them back on waitlist. Their
--                          name can be removed": a decline on the clinic's
--                          own day is canceled, not the Waitlist, and is not
--                          a cancel in her history line. A day earlier, the
--                          Waitlist, as before.
--   11. the cap            "Warn me!": Tara is never stopped. A player's
--                          Accept into a clinic that is now full (You're In!
--                          plus guests) is refused, clinic_full, unless the
--                          clinic was already full when she invited them.
--   10. one price          "I would type amount": admin_set_registration_price,
--                          kept through a clinic price change and the rain
--                          half, put back with null; never on Paid or a
--                          charged row. Only Tara.
--    8. 105 rounds         "Just me and pros for rounds", "pick from roster":
--                          admin_set_round_court (Tara only, 105s only, from
--                          You're In! and guests, one place per round) and
--                          clinic_rounds (Tara, and a pro in their week).
--                          Players never.
--
-- Expected values are written from the rule, not copied from a run.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  DANA    constant uuid := '66666666-6666-6666-6666-666666666666';
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  GINA_P  constant uuid := 'a0000000-0000-0000-0000-000000000009';
  later_today timestamptz;
  maria_canceled_before int;
  c_today uuid; c_week uuid; c_full uuid; c_two uuid; c_today_full uuid;
  c_price uuid; c_105 uuid; c_plain uuid; c_far105 uuid;
  r_maria_today uuid; r_ken_week uuid; r_dana uuid; r_rob uuid; r_gina uuid;
  r_ken_p uuid; r_maria_p uuid; r_rob_p uuid; r_priya_p uuid; r_dana_p uuid;
  r_ken_105 uuid; r_maria_105 uuid; r_rob_105 uuid; r_dana_pool uuid; r_ken_far uuid;
  g_two uuid; g_105 uuid;
  v public.registrations; err text; n int; got text;
begin
  later_today := now() + ((((now() at time zone 'America/New_York')::date + 1)::timestamp
                           at time zone 'America/New_York') - now()) / 2;

  -- ------------------------------------------------------------- fixtures
  -- 7: later today, and three days out. Room for 8 each.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Today', 'coed', 'Clinic', 'probe', later_today, later_today + interval '1 minute',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_today;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_today, MARIA_P, 'pool', 'self', 1800, true, 60) returning id into r_maria_today;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Week', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_week;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_week, KEN_P, 'pool', 'self', 1800, true, 60) returning id into r_ken_week;

  -- 11: one spot, Ken in it; two spots, Ken in one; later today, one spot,
  -- Ken in it and Gina waiting.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Full', 'coed', 'Clinic', 'probe', now() + interval '4 days', now() + interval '4 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 1, 'published', 60) returning id into c_full;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_full, KEN_P, 'in', 'self', 1800, true, 60);
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Two', 'coed', 'Clinic', 'probe', now() + interval '4 days', now() + interval '4 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 2, 'published', 60) returning id into c_two;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_two, KEN_P, 'in', 'self', 1800, true, 60);
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Today Full', 'coed', 'Clinic', 'probe', later_today, later_today + interval '1 minute',
          now() - interval '2 days', now() - interval '1 day', 1, 'published', 60) returning id into c_today_full;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_today_full, KEN_P, 'in', 'self', 1800, true, 60);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_today_full, GINA_P, 'pool', 'self', 1800, true, 60) returning id into r_gina;

  -- 10: $18 members, $23 non-members.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes,
      member_price_cents, nonmember_price_cents)
  values ('Probe Price', 'coed', 'Clinic', 'probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60, 1800, 2300) returning id into c_price;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_price, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken_p;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_price, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_maria_p;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, paid)
  values (c_price, ROB_P, 'in', 'self', 2300, false, 60, true) returning id into r_rob_p;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_price, PRIYA_P, 'in', 'self', 2300, false, 60) returning id into r_priya_p;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
                                    canceled_at, canceled_by)
  values (c_price, DANA_P, 'canceled', 'self', 1800, true, 60, now(), DANA) returning id into r_dana_p;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode)
  values (r_priya_p, '55555555-5555-5555-5555-555555555555', 'clinic_fee', 2300, 'succeeded', true);

  -- 8: a 105 in the week (Ken, Maria, Rob in; Dana waiting; a guest), a
  -- plain clinic, and a 105 past the pros' week.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Coed "105"', 'coed', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 24, 'published', 60) returning id into c_105;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_105, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken_105;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_105, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_maria_105;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_105, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_rob_105;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_105, DANA_P, 'pool', 'self', 1800, true, 60) returning id into r_dana_pool;
  insert into public.clinic_guests (clinic_id, first_name, last_name) values (c_105, 'Pat', 'Visitor') returning id into g_105;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Ladies', 'coed', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_plain;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Far "105"', 'coed', 'Clinic', 'probe', now() + interval '10 days', now() + interval '10 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 24, 'published', 60) returning id into c_far105;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_far105, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken_far;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select h.canceled into maria_canceled_before from public.admin_player_history(MARIA_P) h;

  -- ------------------------------------------------ 7. same-day decline
  -- On the day, Tara's Waitlist tap is an invitation (decision 0047).
  v := public.invite_from_pool(r_maria_today);
  insert into _probe_result values ('today_the_waitlist_tap_invites', 'response_needed', v.status::text);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  v := public.respond_to_invitation(r_maria_today, false);
  insert into _probe_result values ('a_same_day_decline_is_removed', 'canceled t', v.status::text || ' ' || (v.canceled_at is not null)::text);
  perform set_config('role', 'postgres', true);
  select status::text || ' ' || coalesce(canceled_by::text, 'nobody') into got from public.registrations where id = r_maria_today;
  insert into _probe_result values ('not_counted_as_her_cancel', 'canceled nobody', got);
  select body into got from public.notifications
   where account_id = TARA and type = 'invitation_declined' and entity_id = r_maria_today;
  insert into _probe_result values ('tara_hears_it_without_the_waitlist', 'Maria Alvarez declined Probe Today.', got);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select (h.canceled - maria_canceled_before)::text into got from public.admin_player_history(MARIA_P) h;
  insert into _probe_result values ('her_history_shows_no_cancel', '0', got);

  -- Three days out: the Waitlist, as before. (Tara's tap that far out is a
  -- Move In, so the invitation is set up directly.)
  perform set_config('role', 'postgres', true);
  update public.registrations set status = 'response_needed', invited_at = now() where id = r_ken_week;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  v := public.respond_to_invitation(r_ken_week, false);
  insert into _probe_result values ('a_decline_days_ahead_still_waits', 'pool', v.status::text);
  perform set_config('role', 'postgres', true);
  select body into got from public.notifications
   where account_id = TARA and type = 'invitation_declined' and entity_id = r_ken_week;
  insert into _probe_result values ('and_tara_hears_it_is_back_on_the_waitlist',
    'Ken Whitfield declined Probe Week and is back on the Waitlist.', got);
  perform set_config('role', 'authenticated', true);

  -- ------------------------------------------------------- 11. the cap
  -- Invited while full: Tara saw "Your clinic is full" and chose to, so the
  -- Accept goes through.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  v := public.admin_invite_player(c_full, DANA_P);
  r_dana := v.id;
  insert into _probe_result values ('invited_while_full_is_stamped', 'true', v.invited_when_full::text);
  perform set_config('request.jwt.claims', json_build_object('sub', DANA)::text, true);
  v := public.respond_to_invitation(r_dana, true);
  insert into _probe_result values ('invited_while_full_accepts', 'in', v.status::text);

  -- Invited with room; the clinic fills (a guest); the Accept is refused and
  -- the invitation stays open.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  v := public.admin_invite_player(c_two, ROB_P);
  r_rob := v.id;
  insert into _probe_result values ('invited_with_room_is_not_stamped', 'false', v.invited_when_full::text);
  select (public.admin_add_guest(c_two, 'Pat', 'Visitor')).id into g_two;
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  begin perform public.respond_to_invitation(r_rob, true); err := 'accepted';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_guest_fills_it_and_accept_is_refused', 'clinic_full', err);
  perform set_config('role', 'postgres', true);
  select status::text into got from public.registrations where id = r_rob;
  insert into _probe_result values ('the_invitation_stays_open', 'response_needed', got);
  select count(*)::text into got from public.registrations where clinic_id = c_two and status = 'in';
  insert into _probe_result values ('and_nobody_went_over', '1', got);
  perform set_config('role', 'authenticated', true);
  -- He can still say no.
  -- A spot opens (the guest removed): now he can accept.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_remove_guest(g_two);
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  v := public.respond_to_invitation(r_rob, true);
  insert into _probe_result values ('a_spot_opens_and_he_accepts', 'in', v.status::text);

  -- The Waitlist tap on a full clinic today: stamped, like the invite.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  v := public.invite_from_pool(r_gina);
  insert into _probe_result values ('a_waitlist_invite_into_full_is_stamped', 'response_needed true',
    v.status::text || ' ' || v.invited_when_full::text);
  -- Tara is never stopped: Add player on a full clinic still adds.
  v := public.place_player(c_full, PRIYA_P, 'in');
  insert into _probe_result values ('tara_still_adds_to_a_full_clinic', 'in', v.status::text);
  -- place_player straight into Response Needed is stamped too.
  v := public.place_player(c_two, MARIA_P, 'response_needed');
  insert into _probe_result values ('place_player_invite_into_full_is_stamped', 'true', v.invited_when_full::text);

  -- ------------------------------------------------------ 10. one price
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  v := public.admin_set_registration_price(r_ken_p, 1400);
  insert into _probe_result values ('tara_types_his_amount', '1400 true', v.price_cents_charged::text || ' ' || v.price_set_by_admin::text);
  select price_cents_charged::text || ' ' || price_set_by_admin::text into got
    from public.registrations_admin where id = r_ken_p;
  insert into _probe_result values ('her_roster_shows_it', '1400 true', got);
  -- A new clinic rate moves everyone else, not him.
  perform public.admin_set_clinic_prices(c_price, 2000, 2500);
  perform set_config('role', 'postgres', true);
  select string_agg(price_cents_charged::text, ' ' order by id = r_maria_p desc) into got
    from public.registrations where id in (r_ken_p, r_maria_p);
  insert into _probe_result values ('a_rate_change_keeps_his_amount', '2000 1400', got);
  perform set_config('role', 'authenticated', true);
  -- Rain: everyone else who came pays half; he keeps his amount.
  perform public.admin_set_rain_half(c_price, true);
  perform set_config('role', 'postgres', true);
  select string_agg(price_cents_charged::text, ' ' order by id = r_maria_p desc) into got
    from public.registrations where id in (r_ken_p, r_maria_p);
  insert into _probe_result values ('the_rain_half_keeps_his_amount', '1000 1400', got);
  -- Marked a no-show while rained out: the rain rule does not touch him.
  update public.registrations set no_show = true where id = r_ken_p;
  select price_cents_charged::text into got from public.registrations where id = r_ken_p;
  insert into _probe_result values ('the_rain_trigger_leaves_his_amount', '1400', got);
  update public.registrations set no_show = false where id = r_ken_p;
  perform set_config('role', 'authenticated', true);
  -- Put back: the clinic's price now, which is half while it rains.
  v := public.admin_set_registration_price(r_ken_p, null);
  insert into _probe_result values ('put_back_to_the_clinic_price', '1000 false', v.price_cents_charged::text || ' ' || v.price_set_by_admin::text);

  begin perform public.admin_set_registration_price(r_rob_p, 1000); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('never_a_paid_row', 'already_paid', err);
  begin perform public.admin_set_registration_price(r_priya_p, 1000); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('never_a_charged_row', 'charged_refund_first', err);
  begin perform public.admin_set_registration_price(r_dana_p, 1000); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_a_plain_cancel', 'nothing_owed', err);
  begin perform public.admin_set_registration_price(r_maria_p, 0); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_zero', 'invalid_price', err);
  begin perform public.admin_set_registration_price(r_maria_p, 100001); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_over_a_thousand', 'invalid_price', err);
  perform set_config('role', 'postgres', true);
  select string_agg(price_cents_charged::text, ' ' order by id) into got from public.registrations where id in (r_rob_p, r_priya_p);
  insert into _probe_result values ('the_refused_rows_did_not_move', '2300 2300', got);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin perform public.admin_set_registration_price(r_ken_p, 100); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_set_a_price', 'not_authorized', err);
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin perform public.admin_set_registration_price(r_ken_p, 100); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_pro_cannot_set_a_price', 'not_authorized', err);

  -- ----------------------------------------------------- 8. 105 rounds
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_set_round_court(c_105, 1, 1, array[r_ken_105, r_maria_105, null, r_rob_105, g_105, null]::uuid[]);
  select string_agg(court_number || ':' || side || ':' || slot || ' ' || first_name, ', '
                    order by court_number, side, slot) into got
    from public.clinic_rounds(c_105) where round_number = 1;
  insert into _probe_result values ('tara_picks_a_court_from_the_roster',
    '1:1:1 Ken, 1:1:2 Maria, 1:2:1 Rob, 1:2:2 Pat', got);
  select string_agg(first_name || '=' || is_guest::text, ' ' order by first_name) into got
    from public.clinic_rounds(c_105) where first_name in ('Pat', 'Rob');
  insert into _probe_result values ('a_guest_is_marked', 'Pat=true Rob=false', got);
  -- Picked onto court 2 of the same round: moved, not doubled.
  perform public.admin_set_round_court(c_105, 1, 2, array[r_ken_105, null, null, null, null, null]::uuid[]);
  select string_agg(court_number::text, ',' order by court_number) into got
    from public.clinic_rounds(c_105) where round_number = 1 and first_name = 'Ken';
  insert into _probe_result values ('one_place_per_round', '2', got);
  -- Round 2 is its own.
  perform public.admin_set_round_court(c_105, 2, 1, array[r_ken_105, null, null, r_maria_105, null, null]::uuid[]);
  select count(*)::text into got from public.clinic_rounds(c_105) where first_name = 'Ken';
  insert into _probe_result values ('ken_plays_both_rounds', '2', got);
  -- All empty clears the court.
  perform public.admin_set_round_court(c_105, 1, 2, array[null, null, null, null, null, null]::uuid[]);
  select count(*)::text into got from public.clinic_rounds(c_105) where round_number = 1 and court_number = 2;
  insert into _probe_result values ('an_empty_court_clears', '0', got);

  begin perform public.admin_set_round_court(c_105, 1, 3, array[r_ken_105, null, null, r_ken_105, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_twice_on_one_court', 'already_in_round', err);
  begin perform public.admin_set_round_court(c_105, 1, 3, array[r_dana_pool, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_someone_waiting', 'not_in_clinic', err);
  begin perform public.admin_set_round_court(c_105, 1, 3, array[r_ken_p, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_someone_from_another_clinic', 'not_in_clinic', err);
  begin perform public.admin_set_round_court(c_plain, 1, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('only_a_105', 'not_105', err);
  begin perform public.admin_set_round_court(c_105, 4, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('three_rounds_at_most', 'invalid_round', err);
  begin perform public.admin_set_round_court(c_105, 1, 6, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('courts_one_to_five', 'invalid_court', err);
  begin perform public.admin_set_round_court(c_105, 1, 1, array[r_ken_105]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('six_spots_a_court', 'invalid_people', err);

  -- A pro reads the week's rounds; never writes, never past the week.
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  select count(*)::text into got from public.clinic_rounds(c_105);
  insert into _probe_result values ('a_pro_reads_the_rounds', '5', got);
  begin perform public.admin_set_round_court(c_105, 3, 1, array[r_ken_105, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_pro_cannot_set_rounds', 'not_authorized', err);
  begin perform count(*) from public.clinic_rounds(c_far105); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_pro_reads_only_the_week', 'not_this_week', err);

  -- Players never: not through the function, not through the table.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin perform count(*) from public.clinic_rounds(c_105); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_read_rounds', 'not_authorized', err);
  begin perform public.admin_set_round_court(c_105, 3, 1, array[r_ken_105, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_set_rounds', 'not_authorized', err);
  begin perform count(*) from public.clinic_round_spots; err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_read_the_table', 'permission denied', err);

  -- Someone leaves after being placed: the spot stays, marked gone.
  perform set_config('role', 'postgres', true);
  update public.registrations set status = 'canceled', canceled_at = now(), canceled_by = MARIA where id = r_maria_105;
  update public.clinic_guests set removed_at = now() where id = g_105;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select string_agg(first_name || '=' || gone::text, ' ' order by first_name) into got
    from public.clinic_rounds(c_105) where round_number = 1;
  insert into _probe_result values ('who_left_is_marked_gone', 'Maria=true Pat=true Rob=false', got);
  perform set_config('role', 'postgres', true);
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
