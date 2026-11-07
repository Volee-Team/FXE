-- next_update_1107.sql
--
-- Tara's "Next update (notes taken 11/6/26)", items 1, 2 and 6
-- (20261107000002). Item 5 lives in the apps.
--
--   1. message one player     admin_message_player: from a clinic it is kept on
--                             that clinic for that player only; from the
--                             Players tab it is a notification only. Only Tara.
--   2. invite anyone          admin_invite_player: Response Needed and "A spot
--                             opened in ... Accept or decline.", whatever the
--                             capacity; never someone already In, waiting or
--                             invited; never a draft. A decline ends it
--                             (canceled), not the Waitlist. Only Tara.
--   6. the pros' week         pro_week: pro_today's columns for today and the
--                             six days after; pro_assign_court on those You're
--                             In! rows only. Nobody but a pro.
--
-- Casey is the seed's pro. Expected values are written from the rule, by hand.

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
  THEO    constant uuid := '99999999-9999-9999-9999-999999999999';
  THEO_P  constant uuid := 'a0000000-0000-0000-0000-000000000008';
  GINA_P  constant uuid := 'a0000000-0000-0000-0000-000000000009';
  rob_canceled_before int;
  c_week uuid; c_full uuid; c_draft uuid; c_far uuid; c_today uuid;
  r_ken uuid; r_maria_pool uuid; r_rob uuid; r_dana uuid; r_far uuid;
  v public.registrations; err text; n int; got text;
begin
  -- Three days out, room for 8: Ken In, Maria on the Waitlist.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Next Week', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_week;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_week, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_week, MARIA_P, 'pool', 'self', 1800, true, 60) returning id into r_maria_pool;
  -- Full: one spot, Ken in it.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Full', 'coed', 'Clinic', 'probe', now() + interval '4 days', now() + interval '4 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 1, 'published', 60) returning id into c_full;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_full, KEN_P, 'in', 'self', 1800, true, 60);
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Draft', 'coed', 'Clinic', 'probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'draft', 60) returning id into c_draft;
  -- Ten days out: past the pros' week.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Far', 'coed', 'Clinic', 'probe', now() + interval '10 days', now() + interval '10 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_far;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_far, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_far;
  -- Later today (halfway to New York midnight).
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Today', 'coed', 'Clinic', 'probe',
          now() + ((((now() at time zone 'America/New_York')::date + 1)::timestamp at time zone 'America/New_York') - now()) / 2,
          now() + ((((now() at time zone 'America/New_York')::date + 1)::timestamp at time zone 'America/New_York') - now()) / 2 + interval '1 minute',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_today;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select h.canceled into rob_canceled_before from public.admin_player_history(ROB_P) h;

  -- ------------------------------------------------ 1. message one player
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_message_player(KEN_P, '  4:30 is full but 6:00 is open.  ', c_week);
  perform set_config('role', 'postgres', true);
  select count(*)::text || ' ' || min(entity_type) || ' ' || min(body) into got from public.notifications
   where account_id = KEN and type = 'clinic_message' and entity_id = c_week;
  insert into _probe_result values ('one_player_message_reaches_him', '1 clinic 4:30 is full but 6:00 is open.', got);
  select count(*) into n from public.notifications where type = 'clinic_message' and entity_id = c_week and account_id <> KEN;
  insert into _probe_result values ('one_player_message_reaches_nobody_else', '0', n::text);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select count(*) into n from public.my_clinic_messages where clinic_id = c_week;
  insert into _probe_result values ('he_reads_it_on_the_clinic', '1', n::text);
  -- Maria is on the same clinic's Waitlist and must not see it.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.my_clinic_messages where clinic_id = c_week;
  insert into _probe_result values ('the_rest_of_the_clinic_does_not', '0', n::text);

  -- From the Players tab: Rob is in nothing.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_message_player(ROB_P, 'Want to sub Thursday?');
  perform set_config('role', 'postgres', true);
  select count(*)::text || ' ' || min(entity_type) into got from public.notifications
   where account_id = ROB and type = 'clinic_message' and body = 'Want to sub Thursday?';
  insert into _probe_result values ('a_player_in_nothing_can_be_messaged', '1 player', got);
  perform set_config('role', 'authenticated', true);

  begin perform public.admin_message_player(ROB_P, '   '); err := 'sent';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('an_empty_message_is_refused', 'message_empty', err);
  begin perform public.admin_message_player(ROB_P, 'Not yours', c_far); err := 'sent';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_on_a_clinic_he_is_not_on', 'player_not_on_clinic', err);
  begin perform public.send_clinic_message(c_week, 'player', 'nobody'); err := 'sent';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('the_group_sender_refuses_one_player', 'invalid_audience', err);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin perform public.admin_message_player(ROB_P, 'hi'); err := 'sent';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_message_a_player', 'not_authorized', err);
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin perform public.admin_message_player(ROB_P, 'hi'); err := 'sent';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_pro_cannot_message_a_player', 'not_authorized', err);

  -- ------------------------------------------------ 2. invite anyone
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  v := public.admin_invite_player(c_week, ROB_P);
  r_rob := v.id;
  insert into _probe_result values ('an_invite_asks_them', 'response_needed invite t',
    v.status::text || ' ' || v.source::text || ' ' || (v.invited_at is not null)::text);
  perform set_config('role', 'postgres', true);
  select count(*)::text || ' ' || min(entity_type) || ' ' || min(body) into got from public.notifications
   where account_id = ROB and type = 'invitation_received' and entity_id = r_rob;
  insert into _probe_result values ('the_invite_is_her_words', '1 registration A spot opened in Probe Next Week. Accept or decline.', got);
  perform set_config('role', 'authenticated', true);

  -- Capacity never stops Tara: the full clinic still invites.
  v := public.admin_invite_player(c_full, DANA_P);
  insert into _probe_result values ('a_full_clinic_still_invites', 'response_needed', v.status::text);
  begin perform public.admin_invite_player(c_week, MARIA_P); err := 'invited';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('someone_waiting_is_not_invited_twice', 'already_registered', err);
  begin perform public.admin_invite_player(c_week, KEN_P); err := 'invited';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('someone_in_is_not_invited', 'already_registered', err);
  begin perform public.admin_invite_player(c_draft, ROB_P); err := 'invited';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_draft_cannot_invite', 'clinic_not_published', err);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin perform public.admin_invite_player(c_week, DANA_P); err := 'invited';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_invite', 'not_authorized', err);

  -- Rob declines: the invitation ends; he is not put on the Waitlist.
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  v := public.respond_to_invitation(r_rob, false);
  insert into _probe_result values ('a_decline_ends_it', 'canceled t', v.status::text || ' ' || (v.canceled_at is not null)::text);
  perform set_config('role', 'postgres', true);
  select body into got from public.notifications
   where account_id = TARA and type = 'invitation_declined' and entity_id = r_rob;
  insert into _probe_result values ('tara_hears_the_decline_without_the_waitlist', 'Rob Delgado declined Probe Next Week.', got);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select (h.canceled - rob_canceled_before)::text into got from public.admin_player_history(ROB_P) h;
  insert into _probe_result values ('a_declined_invite_is_not_a_cancel', '0', got);
  -- And Tara can ask him again.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  v := public.admin_invite_player(c_week, ROB_P);
  r_rob := v.id;
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  v := public.respond_to_invitation(r_rob, true);
  insert into _probe_result values ('asked_again_he_accepts', 'in', v.status::text);
  -- A Waitlist invitation still goes back to the Waitlist on a decline.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'postgres', true);
  update public.registrations set status = 'response_needed', invited_at = now() where id = r_maria_pool;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  v := public.respond_to_invitation(r_maria_pool, false);
  insert into _probe_result values ('a_waitlist_decline_still_waits', 'pool', v.status::text);

  -- Tara withdraws an invite: it ends, not the Waitlist (a Move In from
  -- there would put Gina straight in without her yes).
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  v := public.admin_invite_player(c_week, GINA_P);
  v := public.cancel_invitation(v.id);
  insert into _probe_result values ('a_withdrawn_invite_ends', 'canceled', v.status::text);
  -- Tara puts an invited player on the Waitlist herself: it is hers now, and
  -- a decline from there goes back to the Waitlist.
  v := public.admin_invite_player(c_week, PRIYA_P);
  v := public.place_player(c_week, PRIYA_P, 'pool');
  insert into _probe_result values ('placed_on_the_waitlist_it_is_hers', 'pool admin', v.status::text || ' ' || v.source::text);
  -- Never someone who has not signed the waiver: Accept would not ask.
  perform set_config('role', 'postgres', true);
  delete from public.waiver_acceptances where account_id = THEO;
  perform set_config('role', 'authenticated', true);
  begin perform public.admin_invite_player(c_week, THEO_P); err := 'invited';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('no_invite_without_the_waiver', 'waiver_required', err);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id = c_week and player_id = THEO_P;
  insert into _probe_result values ('and_no_row_for_him', '0', n::text);
  perform set_config('role', 'authenticated', true);

  -- ------------------------------------------------ 6. the pros' week
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  select string_agg(distinct clinic_name, ', ' order by clinic_name) into got from public.pro_week()
   where clinic_name like 'Probe %';
  insert into _probe_result values ('the_pro_sees_the_week', 'Probe Full, Probe Next Week, Probe Today', got);
  select string_agg(first_name, ', ' order by first_name) into got from public.pro_week()
   where clinic_id = c_week;
  insert into _probe_result values ('only_you_are_in_is_listed', 'Ken, Rob', got);
  -- Decision 0025: the column list is the contract. pro_week's must be
  -- pro_today's exactly (its output names; neither takes an argument).
  select string_agg(n2, ',') into got from (
    select unnest(proargnames) as n2 from pg_proc where proname = 'pro_week') y;
  insert into _probe_result values ('pro_week_has_pro_todays_columns',
    (select string_agg(n3, ',') from (select unnest(proargnames) as n3 from pg_proc where proname = 'pro_today') z), got);

  perform public.pro_assign_court(r_ken, 2::smallint);
  perform set_config('role', 'postgres', true);
  select court_number::text into got from public.registrations where id = r_ken;
  insert into _probe_result values ('the_pro_assigns_a_court', '2', got);
  perform set_config('role', 'authenticated', true);
  perform public.pro_assign_court(r_ken, null);
  perform set_config('role', 'postgres', true);
  select coalesce(court_number::text, 'none') into got from public.registrations where id = r_ken;
  insert into _probe_result values ('the_pro_clears_a_court', 'none', got);
  perform set_config('role', 'authenticated', true);
  begin perform public.pro_assign_court(r_far, 1::smallint); err := 'assigned';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_past_the_week', 'not_this_week', err);
  perform set_config('role', 'postgres', true);
  select coalesce(court_number::text, 'none') into got from public.registrations where id = r_far;
  insert into _probe_result values ('and_that_court_did_not_move', 'none', got);
  perform set_config('role', 'authenticated', true);
  begin perform public.pro_assign_court(r_maria_pool, 1::smallint); err := 'assigned';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_a_waitlist_row', 'not_this_week', err);
  begin perform public.pro_assign_court(r_ken, 0::smallint); err := 'assigned';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_court_zero', 'invalid_court', err);
  begin perform public.pro_assign_court(r_ken, 6::smallint); err := 'assigned';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_court_six', 'invalid_court', err);
  begin perform public.admin_invite_player(c_week, DANA_P); err := 'invited';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_pro_cannot_invite', 'not_authorized', err);

  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin perform count(*) from public.pro_week(); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_read_the_week', 'not_authorized', err);
  begin perform public.pro_assign_court(r_ken, 1::smallint); err := 'assigned';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_assign_a_court', 'not_authorized', err);
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
