-- court_reservations.sql
--
-- Court reservations, step 1: the server (20261116000001, decision 0058).
-- Written from the plan (docs/courts/plan.md) and John's words, 2026-11-16,
-- "lets get court reservatiosn up asap", before the migration existed. Every
-- default is Tara's to change (questions 156 to 165).
--
-- THE RULE, as checked below:
--   d   The defaults: not live; 60 or 90 minutes on :00 or :30; 7 days ahead,
--       a day opening at 7:00 AM New York; 1 a day and 2 upcoming per
--       account; members only; 4 players to a court. Courts 1 to 5, open
--       7:00 AM to 9:00 PM every day.
--   l   Until Tara switches it on (courts_live), a member can neither book
--       nor read a day; Tara can.
--   m   A non-member is refused (members_only), and nothing is written.
--   b   No double booking on a court; back to back is fine.
--   r   The shape: length, start minute, hours, the window, the past.
--   lim The limits: 1 a day, 2 upcoming; a cancel frees both.
--   c   A member cancels their own booking before it starts, never someone
--       else's, never a past one; a canceled slot can be booked again.
--   h   A published clinic holds its courts from start to end: the courts
--       Tara assigned on its You're In! rows, else one court per 4 spots
--       counted down from court 5. A draft or canceled clinic holds nothing.
--   k   Tara's blocks hold a court (or every court); a block over bookings
--       lists them and cancels nothing; a removed block frees the court;
--       a member cannot block.
--   v   court_day: what a member reads. Taken or free, never who, never why
--       (a clinic, a block and a booking look the same); the member's own
--       booking is marked. Hidden fact 5 (other players' names).
--   y   my_court_bookings: the caller's upcoming bookings only.
--   a   Tara's side: names, booking for anyone outside the member rules but
--       never over another booking, cancelling anyone's, the settings with
--       validation. Every admin function refuses a member.
--   x   Deleting an account cancels its upcoming bookings (a trigger, so
--       every path that deletes is covered).
--   g   Grants: anon calls nothing; RLS on every new table; no client grant
--       on any of them.
--
-- This attacks (hard rule 9): every refusal is followed by a read of the
-- table as the owner, because a refused write must also leave nothing.
-- Expected values are written from the rule, not copied from a run.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

-- Runs one statement as a signed-in user and returns 'ok:<value>' or
-- 'err:<message>', so one refusal (or, before the migration, one missing
-- function) fails one row instead of aborting the whole probe.
create function pg_temp.as_user(p_uid uuid, p_sql text) returns text
language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    execute p_sql into r;
    r := 'ok:' || coalesce(r, '');
  exception when others then
    r := 'err:' || sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  return r;
end $$;

-- The same as the owner, for reading state back.
create function pg_temp.q(p_sql text) returns text
language plpgsql as $$
declare r text;
begin
  execute p_sql into r;
  return coalesce(r, '<null>');
exception when others then
  return 'err:' || sqlerrm;
end $$;

-- The id or the JSON in an 'ok:' answer, or null for a refusal.
create function pg_temp.idof(t text) returns uuid
language plpgsql as $$
begin
  return case when t like 'ok:%' then nullif(substr(t, 4), '')::uuid end;
exception when others then return null;
end $$;
create function pg_temp.jof(t text) returns jsonb
language plpgsql as $$
begin
  return case when t like 'ok:%' then nullif(substr(t, 4), '')::jsonb end;
exception when others then return null;
end $$;

do $$
declare
  NY      constant text := 'America/New_York';
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';   -- not a member
  PRIYA   constant uuid := '55555555-5555-5555-5555-555555555555';
  DANA    constant uuid := '66666666-6666-6666-6666-666666666666';
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';   -- the seeded pro, a member
  LENA    constant uuid := '88888888-8888-8888-8888-888888888888';
  THEO    constant uuid := '99999999-9999-9999-9999-999999999999';
  GINA    constant uuid := 'abababab-abab-abab-abab-abababababab';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  d0 date := (now() at time zone 'America/New_York')::date;
  got text; v text;
  b_maria2 uuid; b_maria3 uuid; b_ken2 uuid; b_ken3 uuid; b_past uuid;
  c_hold uuid; c_assigned uuid; c_draft uuid; c_canceled uuid;
  k_rain uuid; k_all uuid;
  fns text[] := array[
    'court_day(date)', 'book_court(integer,timestamp with time zone,integer,text)',
    'cancel_court_booking(uuid)', 'my_court_bookings()',
    'admin_court_day(date)', 'admin_block_courts(integer,timestamp with time zone,timestamp with time zone,text)',
    'admin_remove_court_block(uuid)',
    'admin_book_court(uuid,integer,timestamp with time zone,timestamp with time zone,text)',
    'admin_cancel_court_booking(uuid)', 'admin_set_court_settings(jsonb)',
    'admin_set_court_hours(integer,time without time zone,time without time zone)'];
begin
  -- ----------------------------------------------------------- d, defaults
  got := pg_temp.q($q$
    select string_agg(key || '=' || value, ';' order by key) from public.app_settings
     where key like 'court\_%' or key = 'courts_live'$q$);
  insert into _probe_result values ('d1_defaults_are_the_plans',
    'court_advance_days=7;court_day_opens_at=07:00;court_lengths=60,90;court_max_per_day=1;'
    || 'court_max_upcoming=2;court_members_only=true;court_players_per_court=4;'
    || 'court_start_step=30;courts_live=false', got);
  got := pg_temp.q($q$select string_agg(number::text || ':' || is_active::text, ',' order by number) from public.courts$q$);
  insert into _probe_result values ('d2_courts_1_to_5', '1:true,2:true,3:true,4:true,5:true', got);
  got := pg_temp.q($q$select count(*)::text from public.court_hours
                       where opens = time '07:00' and closes = time '21:00'$q$);
  insert into _probe_result values ('d3_open_7am_to_9pm_every_day', '7', got);

  -- ----------------------------------------------------- l, not live yet
  got := pg_temp.as_user(MARIA, format(
    'select public.book_court(1, %L, 60)', ((d0 + 2) + time '10:00') at time zone NY));
  insert into _probe_result values ('l1_not_live_member_refused', 'err:courts_not_live', got);
  got := pg_temp.as_user(MARIA, format('select public.court_day(%L)', d0 + 2));
  insert into _probe_result values ('l2_not_live_day_refused', 'err:courts_not_live', got);
  got := pg_temp.q('select count(*)::text from public.court_bookings');
  insert into _probe_result values ('l3_not_live_nothing_written', '0', got);
  -- Tara can, before the switch: she books for Rob (a non-member) on day 9
  -- at 6:00 for 45 minutes, outside every member rule (a3, below, too).
  got := left(pg_temp.as_user(TARA, format(
    'select public.admin_book_court(%L, 3, %L, %L, %L)', ROB,
    ((d0 + 9) + time '06:00') at time zone NY, ((d0 + 9) + time '06:45') at time zone NY, 'probe')), 3);
  insert into _probe_result values ('l4_not_live_tara_books_anyone_any_rule', 'ok:', got);
  got := pg_temp.as_user(TARA, format('select (public.admin_court_day(%L) is not null)::text', d0 + 2));
  insert into _probe_result values ('l5_not_live_tara_reads_a_day', 'ok:true', got);

  -- Switch on, through Tara's own setting (a6 checks it refuses members).
  got := pg_temp.as_user(TARA, $q$select public.admin_set_court_settings('{"courts_live":"true"}')$q$);
  insert into _probe_result values ('l6_tara_switches_it_on', 'ok:', left(got, 3));
  -- Two more members for the checks below (inside this transaction only).
  update public.players set is_member = true where account_id in (PRIYA, THEO);

  -- --------------------------------------------------------- m, members only
  got := pg_temp.as_user(ROB, format(
    'select public.book_court(1, %L, 60)', ((d0 + 2) + time '08:00') at time zone NY));
  insert into _probe_result values ('m1_non_member_refused', 'err:members_only', got);
  got := pg_temp.as_user(ROB, format('select public.court_day(%L)', d0 + 2));
  insert into _probe_result values ('m2_non_member_reads_no_day', 'err:members_only', got);
  got := pg_temp.q(format('select count(*)::text from public.court_bookings where account_id = %L and starts_at < now() + interval ''8 days''', ROB));
  insert into _probe_result values ('m3_non_member_nothing_written', '0', got);

  -- ------------------------------------------------------- b, no double booking
  got := pg_temp.as_user(MARIA, format(
    'select public.book_court(1, %L, 60)', ((d0 + 2) + time '10:00') at time zone NY));
  insert into _probe_result values ('b1_member_books', 'ok:', left(got, 3));
  b_maria2 := pg_temp.idof(got);
  got := pg_temp.q(format('select status || '' '' || court::text from public.court_bookings where id = %L', b_maria2));
  insert into _probe_result values ('b1_member_books_row', 'booked 1', got);
  got := pg_temp.as_user(KEN, format(
    'select public.book_court(1, %L, 60)', ((d0 + 2) + time '10:30') at time zone NY));
  insert into _probe_result values ('b2_overlap_refused', 'err:court_taken', got);
  got := pg_temp.q(format('select count(*)::text from public.court_bookings where account_id = %L', KEN));
  insert into _probe_result values ('b2_overlap_nothing_written', '0', got);
  got := pg_temp.as_user(KEN, format(
    'select public.book_court(1, %L, 60)', ((d0 + 2) + time '11:00') at time zone NY));
  insert into _probe_result values ('b3_back_to_back_is_fine', 'ok:', left(got, 3));
  b_ken2 := pg_temp.idof(got);

  -- ------------------------------------------------------------ r, the shape
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(2, %L, 45)', ((d0 + 2) + time '10:00') at time zone NY));
  insert into _probe_result values ('r1_45_minutes_refused', 'err:bad_length', got);
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(2, %L, 120)', ((d0 + 2) + time '10:00') at time zone NY));
  insert into _probe_result values ('r2_120_minutes_refused', 'err:bad_length', got);
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(2, %L, 60)', ((d0 + 2) + time '10:15') at time zone NY));
  insert into _probe_result values ('r3_quarter_past_refused', 'err:bad_start', got);
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(2, %L, 60)', ((d0 + 2) + time '06:30') at time zone NY));
  insert into _probe_result values ('r4_before_opening_refused', 'err:outside_hours', got);
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(2, %L, 60)', ((d0 + 2) + time '20:30') at time zone NY));
  insert into _probe_result values ('r5_past_closing_refused', 'err:outside_hours', got);
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(2, %L, 60)', ((d0 + 8) + time '10:00') at time zone NY));
  insert into _probe_result values ('r6_eight_days_out_refused', 'err:too_far_ahead', got);
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(2, %L, 60)', ((d0 - 1) + time '10:00') at time zone NY));
  insert into _probe_result values ('r7_the_past_refused', 'err:in_the_past', got);
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(9, %L, 60)', ((d0 + 2) + time '10:00') at time zone NY));
  insert into _probe_result values ('r8_no_such_court_refused', 'err:no_such_court', got);
  got := pg_temp.q(format('select count(*)::text from public.court_bookings where account_id = %L', DANA));
  insert into _probe_result values ('r9_refusals_wrote_nothing', '0', got);
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(2, %L, 90)', ((d0 + 2) + time '19:30') at time zone NY));
  insert into _probe_result values ('r10_90_minutes_to_closing_ok', 'ok:', left(got, 3));
  -- Day 7 opens at 7:00 AM New York, so the answer depends on the hour the
  -- probe runs; the expected value is the rule applied to that hour.
  got := pg_temp.as_user(DANA, format(
    'select public.book_court(2, %L, 60)', ((d0 + 7) + time '10:00') at time zone NY));
  insert into _probe_result values ('r11_day_seven_opens_at_7am',
    case when (now() at time zone NY)::time >= time '07:00' then 'ok:' else 'err:not_open_yet' end,
    case when got like 'ok:%' then 'ok:' else got end);

  -- --------------------------------------------------------- lim, the limits
  got := pg_temp.as_user(MARIA, format(
    'select public.book_court(2, %L, 60)', ((d0 + 2) + time '12:00') at time zone NY));
  insert into _probe_result values ('lim1_one_a_day', 'err:day_limit', got);
  got := pg_temp.as_user(MARIA, format(
    'select public.book_court(1, %L, 60)', ((d0 + 3) + time '10:00') at time zone NY));
  insert into _probe_result values ('lim2_second_day_ok', 'ok:', left(got, 3));
  b_maria3 := pg_temp.idof(got);
  got := pg_temp.as_user(MARIA, format(
    'select public.book_court(1, %L, 60)', ((d0 + 4) + time '10:00') at time zone NY));
  insert into _probe_result values ('lim3_two_upcoming', 'err:upcoming_limit', got);

  -- ------------------------------------------------------------ c, cancel
  got := pg_temp.as_user(MARIA, format('select public.cancel_court_booking(%L)', b_maria3));
  insert into _probe_result values ('c1_owner_cancels', 'ok:', got);
  got := pg_temp.q(format(
    'select status || '' '' || (canceled_at is not null)::text || '' '' || (canceled_by = %L)::text from public.court_bookings where id = %L',
    MARIA, b_maria3));
  insert into _probe_result values ('c1_owner_cancels_row', 'canceled true true', got);
  got := pg_temp.as_user(MARIA, format(
    'select public.book_court(1, %L, 60)', ((d0 + 4) + time '10:00') at time zone NY));
  insert into _probe_result values ('c2_cancel_frees_the_limit', 'ok:', left(got, 3));
  got := pg_temp.as_user(KEN, format('select public.cancel_court_booking(%L)', b_maria2));
  insert into _probe_result values ('c3_not_someone_elses', 'err:not_cancelable', got);
  got := pg_temp.q(format('select status from public.court_bookings where id = %L', b_maria2));
  insert into _probe_result values ('c3_not_someone_elses_row', 'booked', got);
  begin
    insert into public.court_bookings (court, account_id, starts_at, ends_at)
    values (4, MARIA, ((d0 - 1) + time '10:00') at time zone NY, ((d0 - 1) + time '11:00') at time zone NY)
    returning id into b_past;
  exception when others then b_past := null;
  end;
  got := pg_temp.as_user(MARIA, format('select public.cancel_court_booking(%L)', b_past));
  insert into _probe_result values ('c4_not_a_past_one', 'err:not_cancelable', got);
  got := pg_temp.as_user(KEN, format(
    'select public.book_court(1, %L, 60)', ((d0 + 3) + time '10:00') at time zone NY));
  insert into _probe_result values ('c5_canceled_slot_reopens', 'ok:', left(got, 3));
  b_ken3 := pg_temp.idof(got);

  -- ------------------------------------------------------ h, clinics hold
  -- Day 2, 2:00 to 3:30 PM, 8 spots, no courts assigned: courts 5 and 4.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('Probe Court Clinic', 'coed', 'Clinic', 'probe',
          ((d0 + 2) + time '14:00') at time zone NY, ((d0 + 2) + time '15:30') at time zone NY,
          now() - interval '2 days', now() - interval '1 day', 8, 'published')
  returning id into c_hold;
  got := pg_temp.as_user(CASEY, format(
    'select public.book_court(5, %L, 60)', ((d0 + 2) + time '14:00') at time zone NY));
  insert into _probe_result values ('h1_clinic_holds_court_5', 'err:court_taken', got);
  got := pg_temp.as_user(CASEY, format(
    'select public.book_court(4, %L, 60)', ((d0 + 2) + time '15:00') at time zone NY));
  insert into _probe_result values ('h1_clinic_holds_court_4_to_its_end', 'err:court_taken', got);
  got := pg_temp.as_user(CASEY, format(
    'select public.book_court(3, %L, 60)', ((d0 + 2) + time '14:00') at time zone NY));
  insert into _probe_result values ('h1_court_3_is_free', 'ok:', left(got, 3));
  -- Day 5, 9:00 to 10:30 AM, Ken placed on court 1 by Tara: court 1 only.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('Probe Court Clinic Assigned', 'coed', 'Clinic', 'probe',
          ((d0 + 5) + time '09:00') at time zone NY, ((d0 + 5) + time '10:30') at time zone NY,
          now() - interval '2 days', now() - interval '1 day', 8, 'published')
  returning id into c_assigned;
  insert into public.registrations (clinic_id, player_id, status, source, court_number)
  values (c_assigned, KEN_P, 'in', 'self', 1);
  got := pg_temp.as_user(LENA, format(
    'select public.book_court(1, %L, 60)', ((d0 + 5) + time '09:00') at time zone NY));
  insert into _probe_result values ('h2_assigned_court_held', 'err:court_taken', got);
  got := pg_temp.as_user(LENA, format(
    'select public.book_court(5, %L, 60)', ((d0 + 5) + time '09:00') at time zone NY));
  insert into _probe_result values ('h2_assigned_means_only_those', 'ok:', left(got, 3));
  -- Day 6: a draft at 9:00 and a canceled clinic at 11:00, 20 spots each.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('Probe Court Draft', 'coed', 'Clinic', 'probe',
          ((d0 + 6) + time '09:00') at time zone NY, ((d0 + 6) + time '10:30') at time zone NY,
          now() - interval '2 days', now() - interval '1 day', 20, 'draft')
  returning id into c_draft;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, canceled_at)
  values ('Probe Court Canceled', 'coed', 'Clinic', 'probe',
          ((d0 + 6) + time '11:00') at time zone NY, ((d0 + 6) + time '12:30') at time zone NY,
          now() - interval '2 days', now() - interval '1 day', 20, 'canceled', now())
  returning id into c_canceled;
  got := pg_temp.as_user(GINA, format(
    'select public.book_court(5, %L, 60)', ((d0 + 6) + time '09:00') at time zone NY));
  insert into _probe_result values ('h3_draft_holds_nothing', 'ok:', left(got, 3));
  got := pg_temp.as_user(LENA, format(
    'select public.book_court(5, %L, 60)', ((d0 + 6) + time '11:00') at time zone NY));
  insert into _probe_result values ('h3_canceled_holds_nothing', 'ok:', left(got, 3));

  -- ------------------------------------------------------------ k, blocks
  got := pg_temp.as_user(TARA, format(
    'select public.admin_block_courts(2, %L, %L, %L)::text',
    ((d0 + 2) + time '16:00') at time zone NY, ((d0 + 2) + time '18:00') at time zone NY, 'Rain out'));
  insert into _probe_result values ('k1_tara_blocks_a_court', 'ok:', left(got, 3));
  k_rain := pg_temp.idof('ok:' || coalesce(pg_temp.jof(got) ->> 'block_id', ''));
  got := pg_temp.as_user(GINA, format(
    'select public.book_court(2, %L, 60)', ((d0 + 2) + time '16:30') at time zone NY));
  insert into _probe_result values ('k1_block_holds', 'err:court_taken', got);
  got := pg_temp.as_user(TARA, format(
    'select public.admin_block_courts(null, %L, %L, %L)::text',
    ((d0 + 4) + time '12:00') at time zone NY, ((d0 + 4) + time '13:00') at time zone NY, 'Resurfacing'));
  k_all := pg_temp.idof('ok:' || coalesce(pg_temp.jof(got) ->> 'block_id', ''));
  got := pg_temp.as_user(THEO, format(
    'select public.book_court(4, %L, 60)', ((d0 + 4) + time '12:30') at time zone NY));
  insert into _probe_result values ('k2_every_court_block_holds', 'err:court_taken', got);
  -- Over Maria's 10:00 and Ken's 11:00 on court 1: listed, not canceled.
  got := pg_temp.as_user(TARA, format(
    'select (select string_agg(x ->> ''booking_id'', '','' order by x ->> ''starts_at'') from jsonb_array_elements(public.admin_block_courts(1, %L, %L, %L) -> ''conflicts'') x)',
    ((d0 + 2) + time '09:00') at time zone NY, ((d0 + 2) + time '12:00') at time zone NY, 'Lesson'));
  insert into _probe_result values ('k3_block_lists_the_bookings_under_it', 'ok:' || b_maria2 || ',' || b_ken2, got);
  got := pg_temp.q(format('select string_agg(status, '','' order by starts_at) from public.court_bookings where id in (%L, %L)', b_maria2, b_ken2));
  insert into _probe_result values ('k3_and_cancels_none', 'booked,booked', got);
  got := pg_temp.as_user(TARA, format('select public.admin_remove_court_block(%L)', k_rain));
  insert into _probe_result values ('k4_tara_removes_a_block', 'ok:', got);
  got := pg_temp.q(format('select (removed_at is not null)::text from public.court_blocks where id = %L', k_rain));
  insert into _probe_result values ('k4_removed_is_archived_not_deleted', 'true', got);
  got := pg_temp.as_user(GINA, format(
    'select public.book_court(2, %L, 60)', ((d0 + 2) + time '16:30') at time zone NY));
  insert into _probe_result values ('k4_removed_block_frees', 'ok:', left(got, 3));
  got := pg_temp.as_user(KEN, format(
    'select public.admin_block_courts(3, %L, %L, %L)::text',
    ((d0 + 3) + time '16:00') at time zone NY, ((d0 + 3) + time '18:00') at time zone NY, 'Mine'));
  insert into _probe_result values ('k5_member_cannot_block', 'err:not_authorized', got);
  got := pg_temp.q($q$select count(*)::text from public.court_blocks where reason = 'Mine'$q$);
  insert into _probe_result values ('k5_member_cannot_block_nothing_written', '0', got);

  -- -------------------------------------------------------- v, court_day
  got := pg_temp.as_user(KEN, format('select public.court_day(%L)::text', d0 + 2));
  insert into _probe_result values ('v1_no_names_no_reasons',
    'false', (got ~* ('(maria|garcia|probe court|rain out|lesson|dana|casey|gina|' || MARIA || ')'))::text);
  insert into _probe_result values ('v1_ken_reads_the_day', 'ok:', left(got, 3));
  v := substr(got, 4);
  got := pg_temp.q(format($q$
    select string_agg(distinct k, ',' order by k)
      from jsonb_array_elements(%L::jsonb -> 'courts') c,
           jsonb_array_elements(c -> 'taken') t, jsonb_object_keys(t) k$q$, v));
  insert into _probe_result values ('v2_a_taken_slot_says_only_when_and_whose', 'booking_id,ends_at,mine,starts_at', got);
  got := pg_temp.q(format($q$
    select string_agg(k, ',' order by k) from jsonb_object_keys(%L::jsonb) k$q$, v));
  insert into _probe_result values ('v2_the_day_says_only_this', 'closes_at,courts,day,opens_at', got);
  got := pg_temp.q(format($q$
    select string_agg(distinct k, ',' order by k)
      from jsonb_array_elements(%L::jsonb -> 'courts') c, jsonb_object_keys(c) k$q$, v));
  insert into _probe_result values ('v2_a_court_says_only_this', 'name,number,taken', got);
  -- Maria's 10:00 on court 1, as Ken sees it: taken, not his, no id.
  got := pg_temp.q(format($q$
    select (t ->> 'mine') || ' ' || coalesce(t ->> 'booking_id', 'null')
      from jsonb_array_elements(%L::jsonb -> 'courts') c, jsonb_array_elements(c -> 'taken') t
     where (c ->> 'number')::int = 1 and (t ->> 'starts_at')::timestamptz = %L$q$,
     v, ((d0 + 2) + time '10:00') at time zone NY));
  insert into _probe_result values ('v3_someone_elses_is_just_taken', 'false null', got);
  -- The clinic's hold on court 5 reads the same as a booking, to its end.
  got := pg_temp.q(format($q$
    select (t ->> 'mine') || ' ' || coalesce(t ->> 'booking_id', 'null') || ' '
           || ((t ->> 'ends_at')::timestamptz = %L)::text
      from jsonb_array_elements(%L::jsonb -> 'courts') c, jsonb_array_elements(c -> 'taken') t
     where (c ->> 'number')::int = 5 and (t ->> 'starts_at')::timestamptz = %L$q$,
     ((d0 + 2) + time '15:30') at time zone NY, v, ((d0 + 2) + time '14:00') at time zone NY));
  insert into _probe_result values ('v4_a_clinic_hold_looks_like_any_booking', 'false null true', got);
  got := pg_temp.as_user(MARIA, format('select public.court_day(%L)::text', d0 + 2));
  got := pg_temp.q(format($q$
    select (t ->> 'mine') || ' ' || (t ->> 'booking_id')
      from jsonb_array_elements(%L::jsonb -> 'courts') c, jsonb_array_elements(c -> 'taken') t
     where (c ->> 'number')::int = 1 and (t ->> 'starts_at')::timestamptz = %L$q$,
     substr(got, 4), ((d0 + 2) + time '10:00') at time zone NY));
  insert into _probe_result values ('v5_her_own_is_marked', 'true ' || b_maria2, got);
  got := pg_temp.q(format($q$
    select ((%L::jsonb ->> 'opens_at')::timestamptz = %L)::text || ' ' || ((%L::jsonb ->> 'closes_at')::timestamptz = %L)::text$q$,
    v, ((d0 + 2) + time '07:00') at time zone NY, v, ((d0 + 2) + time '21:00') at time zone NY));
  insert into _probe_result values ('v6_the_days_hours', 'true true', got);

  -- -------------------------------------------------- y, my_court_bookings
  got := pg_temp.as_user(MARIA, $q$select string_agg(id::text, ',' order by starts_at) from public.my_court_bookings()$q$);
  insert into _probe_result values ('y1_my_upcoming_only',
    'ok:' || pg_temp.q(format($q$select string_agg(id::text, ',' order by starts_at) from public.court_bookings
                                  where account_id = %L and status = 'booked' and starts_at > now()$q$, MARIA)), got);
  insert into _probe_result values ('y1_two_of_them', '2',
    pg_temp.q(format($q$select count(*)::text from public.court_bookings
                         where account_id = %L and status = 'booked' and starts_at > now()$q$, MARIA)));
  got := pg_temp.as_user(MARIA, $q$select string_agg(a.attname, ',' order by a.attnum)
     from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(attname, mode, attnum)
    where p.proname = 'my_court_bookings' and a.mode = 't'$q$);
  insert into _probe_result values ('y2_my_bookings_columns', 'ok:id,court,court_name,starts_at,ends_at,playing_with', got);

  -- ------------------------------------------------------------ a, Tara
  got := pg_temp.as_user(TARA, format('select public.admin_court_day(%L)::text', d0 + 2));
  insert into _probe_result values ('a1_tara_sees_who_and_why',
    'true true true', ((got ~ 'Maria')::text || ' ' || (got ~ 'Probe Court Clinic')::text || ' ' || (got ~ 'Lesson')::text));
  got := pg_temp.as_user(KEN, format('select public.admin_court_day(%L)::text', d0 + 2));
  insert into _probe_result values ('a2_member_cannot_read_tara_day', 'err:not_authorized', got);
  got := pg_temp.as_user(TARA, format(
    'select public.admin_book_court(%L, 1, %L, %L, null)', ROB,
    ((d0 + 2) + time '10:00') at time zone NY, ((d0 + 2) + time '11:00') at time zone NY));
  insert into _probe_result values ('a3_tara_never_double_books', 'err:court_taken', got);
  got := pg_temp.as_user(KEN, format(
    'select public.admin_book_court(%L, 3, %L, %L, null)', KEN,
    ((d0 + 5) + time '12:00') at time zone NY, ((d0 + 5) + time '15:00') at time zone NY));
  insert into _probe_result values ('a4_member_cannot_book_as_tara', 'err:not_authorized', got);
  got := pg_temp.as_user(KEN, format('select public.admin_cancel_court_booking(%L)', b_maria2));
  insert into _probe_result values ('a5_member_cannot_cancel_as_tara', 'err:not_authorized', got);
  got := pg_temp.as_user(TARA, format('select public.admin_cancel_court_booking(%L)', b_ken3));
  insert into _probe_result values ('a5_tara_cancels_anyones', 'ok:', got);
  got := pg_temp.q(format('select status || '' '' || (canceled_by = %L)::text from public.court_bookings where id = %L', TARA, b_ken3));
  insert into _probe_result values ('a5_tara_cancels_anyones_row', 'canceled true', got);
  got := pg_temp.as_user(KEN, $q$select public.admin_set_court_settings('{"court_max_per_day":"5"}')$q$);
  insert into _probe_result values ('a6_member_cannot_change_settings', 'err:not_authorized', got);
  got := pg_temp.as_user(TARA, $q$select public.admin_set_court_settings('{"court_max_per_day":"0"}')$q$);
  insert into _probe_result values ('a6_settings_are_validated', 'err:bad_setting', got);
  got := pg_temp.as_user(TARA, $q$select public.admin_set_court_settings('{"payments_enabled":"true"}')$q$);
  insert into _probe_result values ('a6_only_court_settings', 'err:unknown_setting', got);
  got := pg_temp.q($q$select value from public.app_settings where key = 'payments_enabled'$q$);
  insert into _probe_result values ('a6_payments_untouched', 'false', got);
  got := pg_temp.as_user(TARA, $q$select public.admin_set_court_settings('{"court_max_per_day":"2","court_lengths":"60,90,120"}')$q$);
  got := pg_temp.q($q$select string_agg(value, ' ' order by key) from public.app_settings where key in ('court_max_per_day', 'court_lengths')$q$);
  insert into _probe_result values ('a6_tara_changes_settings', '60,90,120 2', got);
  got := pg_temp.as_user(TARA, $q$select public.admin_set_court_hours(0, '20:00', '08:00')$q$);
  insert into _probe_result values ('a7_hours_close_after_open', 'err:bad_hours', got);
  got := pg_temp.as_user(TARA, $q$select public.admin_set_court_hours(0, '08:00', '20:00')$q$);
  got := pg_temp.q($q$select opens::text || '-' || closes::text from public.court_hours where weekday = 0$q$);
  insert into _probe_result values ('a7_tara_sets_sunday_hours', '08:00:00-20:00:00', got);
  got := pg_temp.as_user(KEN, $q$select public.admin_set_court_hours(0, '06:00', '23:00')$q$);
  insert into _probe_result values ('a7_member_cannot_set_hours', 'err:not_authorized', got);

  -- ------------------------------------------------- x, deleting an account
  update public.accounts set deleted_at = now() where id = MARIA;
  got := pg_temp.q(format($q$select coalesce(string_agg(status, ',' order by starts_at), '') from public.court_bookings
                              where account_id = %L and starts_at > now()$q$, MARIA));
  insert into _probe_result values ('x1_deleting_cancels_upcoming', 'canceled,canceled,canceled', got);
  got := pg_temp.q(format('select status from public.court_bookings where id = %L', b_past));
  insert into _probe_result values ('x2_and_leaves_the_past', 'booked', got);

  -- ------------------------------------------------------------- g, grants
  select count(*)::text into got from unnest(fns) f
   where to_regprocedure('public.' || f) is not null
     and not has_function_privilege('anon', to_regprocedure('public.' || f), 'EXECUTE');
  insert into _probe_result values ('g1_anon_calls_none_of_them', array_length(fns, 1)::text, got);
  select count(*)::text into got from unnest(fns) f
   where to_regprocedure('public.' || f) is not null
     and has_function_privilege('authenticated', to_regprocedure('public.' || f), 'EXECUTE');
  insert into _probe_result values ('g2_signed_in_clients_call_them', array_length(fns, 1)::text, got);
  got := pg_temp.q($q$select string_agg(relname || ':' || relrowsecurity::text, ',' order by relname) from pg_class
                      where oid in ('public.courts'::regclass, 'public.court_hours'::regclass,
                                    'public.court_bookings'::regclass, 'public.court_blocks'::regclass)$q$);
  insert into _probe_result values ('g3_rls_on_every_new_table',
    'court_blocks:true,court_bookings:true,court_hours:true,courts:true', got);
  got := pg_temp.q($q$select count(*)::text from unnest(array['public.courts', 'public.court_hours',
        'public.court_bookings', 'public.court_blocks']) t,
        unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p,
        unnest(array['anon','authenticated']) r
      where has_table_privilege(r, t, p)$q$);
  insert into _probe_result values ('g4_no_client_grant_on_any_new_table', '0', got);
end $$;

select check_name, expected, actual,
  case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result
order by check_name;

rollback;
