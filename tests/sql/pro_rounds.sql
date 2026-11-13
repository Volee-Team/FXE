-- pro_rounds.sql
--
-- A pro sets the 105 rounds (20261111000002, decision 0056). Written from
-- Tara's words, 2026-11-11, by hand:
--
--   "Just wanna make sure that they can position people on the courts like I
--   can do now", and on the 105 rounds: "I think can change the rounds.
--   That's totally fine. Probably need it in case I'm out of town".
--
-- THE RULE, as checked below:
--   w1  A pro sets a court of a 105's round in their week (a published clinic
--       on today's New York date or the six after), and the rounds read it
--       back, to the pro and to Tara.
--   w2  Outside the week, one answer, not_this_week, and nothing written: a
--       105 eight days out, a draft, an id that is no clinic.
--   w3  A player is refused, not_authorized, and nothing is written.
--   w4  Tara still sets rounds, and a non-105 in the week is still not_105
--       (for her, and for a pro: every refusal but the week's is hers).
--   p1  clinic_round_people: the roster a round is picked from, You're In!
--       then live guests by last name, first name; never the Waitlist or a
--       removed guest; the ids are the ones admin_set_round_court takes.
--   p2  Read by Tara, and a pro for a clinic in the week (not_this_week
--       otherwise); a player is refused. Names only: its columns are the
--       contract, nothing financial, no note, no phone or email.
--   p3  anon executes neither; a signed-in client may call both.
--
-- This attacks (hard rule 9): every refusal is followed by a read of the
-- table as the owner, because a refused write must also leave nothing.
-- Expected values are written from the rule, not copied from a run.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';   -- the seeded pro
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  c_week uuid; c_far uuid; c_draft uuid; c_plain uuid;
  c_plain_far uuid; c_plain_draft uuid; c_yesterday uuid; c_canceled uuid; c_day7 uuid;
  r_ken uuid; r_maria uuid; r_dana_pool uuid; r_ken_far uuid; r_ken_draft uuid;
  g_pat uuid; g_gone uuid;
  err text; got text;
begin
  -- ------------------------------------------------------------- fixtures
  -- The seeded pro, made a pro again inside this transaction through Tara's
  -- own switch (as pro_role.sql does), so a committed change to her role
  -- cannot turn every row below into a false red.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_set_pro(CASEY, true);
  perform set_config('role', 'postgres', true);

  -- A 105 two days out: Ken and Maria You're In!, Dana waiting, a guest, and
  -- a guest already removed.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro "105"', 'coed', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 24, 'published', 60) returning id into c_week;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_week, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_week, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_maria;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_week, DANA_P, 'pool', 'self', 1800, true, 60) returning id into r_dana_pool;
  insert into public.clinic_guests (clinic_id, first_name, last_name) values (c_week, 'Pat', 'Visitor') returning id into g_pat;
  insert into public.clinic_guests (clinic_id, first_name, last_name, removed_at)
  values (c_week, 'Gone', 'Guest', now()) returning id into g_gone;

  -- A 105 eight days out: past the week whatever the hour (today + 8).
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Far "105"', 'coed', 'Clinic', 'probe', now() + interval '8 days', now() + interval '8 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 24, 'published', 60) returning id into c_far;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_far, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken_far;

  -- A draft 105 three days out: in the week by date, not published.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Draft "105"', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 24, 'draft', 60) returning id into c_draft;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_draft, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken_draft;

  -- A clinic in the week that is not a 105.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Plain', 'coed', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_plain;
  insert into public.clinic_guests (clinic_id, first_name, last_name) values (c_plain, 'Gina', 'Plainguest');

  -- The edges the sql-auditor named (2026-11-12): a non-105 past the week
  -- and a draft one (the week answer must come before the 105 answer, or a
  -- pro learns which ids exist), yesterday, a canceled 105, and noon on
  -- day 7 (today + 7 is outside; the week is today to today + 6).
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Plain Far', 'coed', 'Clinic', 'probe', now() + interval '9 days', now() + interval '9 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_plain_far;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Plain Draft', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'draft', 60) returning id into c_plain_draft;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Yesterday "105"', 'coed', 'Clinic', 'probe', now() - interval '1 day', now() - interval '23 hours',
          now() - interval '5 days', now() - interval '4 days', 24, 'published', 60) returning id into c_yesterday;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Canceled "105"', 'coed', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 24, 'canceled', 60) returning id into c_canceled;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Day Seven "105"', 'coed', 'Clinic', 'probe',
          ((public.new_york_date(now()) + 7) + time '12:00') at time zone 'America/New_York',
          ((public.new_york_date(now()) + 7) + time '13:00') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', 24, 'published', 60) returning id into c_day7;

  perform set_config('role', 'authenticated', true);

  -- ------------------------------------------------- w1, a pro in the week
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin
    perform public.admin_set_round_court(c_week, 1, 1, array[r_ken, r_maria, null, g_pat, null, null]::uuid[]);
    err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w1_a_pro_sets_a_court_in_the_week', 'set', err);
  select string_agg(court_number || ':' || side || ':' || slot || ' ' || first_name, ', '
                    order by court_number, side, slot) into got
    from public.clinic_rounds(c_week) where round_number = 1;
  insert into _probe_result values ('w1_the_pro_reads_it_back', '1:1:1 Ken, 1:1:2 Maria, 1:2:1 Pat', got);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select string_agg(court_number || ':' || side || ':' || slot || ' ' || first_name, ', '
                    order by court_number, side, slot) into got
    from public.clinic_rounds(c_week) where round_number = 1;
  insert into _probe_result values ('w1_tara_sees_what_the_pro_set', '1:1:1 Ken, 1:1:2 Maria, 1:2:1 Pat', got);
  -- One place per round holds for a pro too: Ken picked on court 2 moves.
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  perform public.admin_set_round_court(c_week, 1, 2, array[r_ken, null, null, null, null, null]::uuid[]);
  select string_agg(court_number::text, ',' order by court_number) into got
    from public.clinic_rounds(c_week) where round_number = 1 and first_name = 'Ken';
  insert into _probe_result values ('w1_a_pro_move_is_a_move', '2', got);

  -- ------------------------------------------- w2, a pro outside the week
  begin perform public.admin_set_round_court(c_far, 1, 1, array[r_ken_far, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w2_a_pro_refused_eight_days_out', 'not_this_week', err);
  begin perform public.admin_set_round_court(c_draft, 1, 1, array[r_ken_draft, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w2_a_pro_refused_a_draft', 'not_this_week', err);
  begin perform public.admin_set_round_court(gen_random_uuid(), 1, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w2_a_pro_refused_no_clinic_alike', 'not_this_week', err);
  begin perform public.admin_set_round_court(c_plain_far, 1, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w2_a_pro_refused_a_non_105_past_the_week', 'not_this_week', err);
  begin perform public.admin_set_round_court(c_plain_draft, 1, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w2_a_pro_refused_a_draft_non_105', 'not_this_week', err);
  begin perform public.admin_set_round_court(c_yesterday, 1, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w2_a_pro_refused_yesterday', 'not_this_week', err);
  begin perform public.admin_set_round_court(c_canceled, 1, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w2_a_pro_refused_a_canceled_105', 'not_this_week', err);
  begin perform public.admin_set_round_court(c_day7, 1, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w2_a_pro_refused_day_seven', 'not_this_week', err);
  perform set_config('role', 'postgres', true);
  select count(*)::text into got from public.clinic_round_spots where clinic_id in (c_far, c_draft, c_yesterday, c_canceled, c_day7, c_plain_far, c_plain_draft);
  insert into _probe_result values ('w2_nothing_written_outside_the_week', '0', got);
  perform set_config('role', 'authenticated', true);

  -- ------------------------------------------------------- w3, a player
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin perform public.admin_set_round_court(c_week, 3, 1, array[r_maria, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w3_a_player_cannot_set_rounds', 'not_authorized', err);
  perform set_config('role', 'postgres', true);
  select count(*)::text into got from public.clinic_round_spots where clinic_id = c_week and round_number = 3;
  insert into _probe_result values ('w3_nothing_written_by_a_player', '0', got);
  perform set_config('role', 'authenticated', true);

  -- --------------------------------------------- w4, Tara, and not a 105
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  begin
    perform public.admin_set_round_court(c_week, 2, 1, array[r_maria, null, null, r_ken, null, null]::uuid[]);
    err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w4_tara_still_sets_rounds', 'set', err);
  select string_agg(side || ':' || slot || ' ' || first_name, ', ' order by side, slot) into got
    from public.clinic_rounds(c_week) where round_number = 2 and court_number = 1;
  insert into _probe_result values ('w4_and_it_reads_back', '1:1 Maria, 2:1 Ken', got);
  begin perform public.admin_set_round_court(c_plain, 1, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w4_tara_only_on_a_105', 'not_105', err);
  -- Tara is not held to the week: the far 105 is hers.
  begin perform public.admin_set_round_court(c_far, 1, 1, array[r_ken_far, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w4_tara_sets_rounds_past_the_week', 'set', err);
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin perform public.admin_set_round_court(c_plain, 1, 1, array[null, null, null, null, null, null]::uuid[]); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('w4_a_pro_only_on_a_105', 'not_105', err);

  -- ------------------------------------------- p1, p2, who can be picked
  -- As the pro: You're In! and the live guest, by last name (Alvarez,
  -- Visitor, Whitfield); not Dana (waiting), not the removed guest.
  select string_agg(last_name || ' ' || first_name || ' ' || is_guest::text, ', ' order by n) into got
    from public.clinic_round_people(c_week) with ordinality as x(person_id, first_name, last_name, is_guest, n);
  insert into _probe_result values ('p1_a_pro_reads_who_can_be_picked',
    'Alvarez Maria false, Visitor Pat true, Whitfield Ken false', got);
  select string_agg((person_id = case first_name when 'Ken' then r_ken when 'Maria' then r_maria
                                                 when 'Pat' then g_pat end)::text, ' ' order by last_name) into got
    from public.clinic_round_people(c_week);
  insert into _probe_result values ('p1_the_ids_are_what_a_court_takes', 'true true true', got);
  begin perform count(*) from public.clinic_round_people(c_far); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('p2_a_pro_reads_only_the_week', 'not_this_week', err);
  begin perform count(*) from public.clinic_round_people(c_draft); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('p2_a_pro_reads_no_draft', 'not_this_week', err);
  begin perform count(*) from public.clinic_round_people(c_yesterday); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('p2_a_pro_reads_no_past_clinic', 'not_this_week', err);
  begin perform count(*) from public.clinic_round_people(c_canceled); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('p2_a_pro_reads_no_canceled_clinic', 'not_this_week', err);
  begin perform count(*) from public.clinic_round_people(c_day7); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('p2_a_pro_reads_nothing_on_day_seven', 'not_this_week', err);
  begin perform count(*) from public.clinic_round_people(gen_random_uuid()); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('p2_a_pro_reads_no_clinic_alike', 'not_this_week', err);
  begin perform count(*) from public.clinic_round_people(c_plain_far); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('p2_a_pro_reads_no_non_105_past_the_week', 'not_this_week', err);
  -- A non-105 in the week: its guests are not the pro's (pro_week lists
  -- registrations only), so no roster off a 105.
  begin perform count(*) from public.clinic_round_people(c_plain); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('p2_a_pro_reads_no_roster_off_a_105', 'not_105', err);

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select count(*)::text into got from public.clinic_round_people(c_far);
  insert into _probe_result values ('p2_tara_reads_any_clinic', '1', got);
  select count(*)::text into got from public.clinic_round_people(c_plain);
  insert into _probe_result values ('p2_tara_reads_a_non_105_too', '1', got);

  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin perform count(*) from public.clinic_round_people(c_week); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('p2_a_player_cannot_read_who_can_be_picked', 'not_authorized', err);

  perform set_config('role', 'postgres', true);
  -- The column list is the contract (decision 0025's habit): names and
  -- whether a guest, nothing else.
  select string_agg(a, ', ' order by a) into got
    from unnest((select proargnames from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                  where ns.nspname = 'public' and p.proname = 'clinic_round_people'),
                (select proargmodes from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                  where ns.nspname = 'public' and p.proname = 'clinic_round_people')) as x(a, m)
   where m = 't';
  insert into _probe_result values ('p2_names_only', 'first_name, is_guest, last_name, person_id', got);

  -- ------------------------------------------------------------ p3, grants
  select coalesce(string_agg(p.proname, ', ' order by p.proname), '') into got
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('admin_set_round_court', 'clinic_round_people')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('p3_anon_executes_neither', '', coalesce(got, ''));
  select count(*)::text into got
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('admin_set_round_court', 'clinic_round_people')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  insert into _probe_result values ('p3_signed_in_clients_call_both', '2', got);

  -- p4: every admin_* function opens with require_admin() but the ones
  -- named here, each for a reason (decision 0056: admin_set_round_court
  -- lets a pro through for their week). A new one fails this row until it
  -- is either gated or added with its reason.
  select '[' || coalesce(string_agg(p.proname, ', ' order by p.proname), '') || ']' into got
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname like 'admin\_%'
     and p.prosrc !~ 'perform public\.require_admin\(\)';
  insert into _probe_result values ('p4_admin_functions_without_the_gate_are_named',
    '[admin_account_ids, admin_set_round_court]', got);
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
