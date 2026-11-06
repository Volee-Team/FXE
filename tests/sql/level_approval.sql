-- level_approval.sql — pins 20261105000002 (decision 0048).
--
-- Tara: a 2.5 asks before a 3.0+ clinic, a 3.5 before a 4.0 clinic, she
-- approves once, and it lasts until she removes it. Their rating never moves.
--
--   the clinic's level      the NTRP number in its name, or none
--   below it, no approval   register and late request refused (level_approval_required)
--   at or above it          registers as before (Rob, 3.0, in a 3.0+ clinic)
--   no rating               not gated (default until Tara says otherwise)
--   asking                  one row 'requested', one note to Tara in a fixed
--                           sentence; a second tap sends nothing; still refused
--   asking when not needed  approval_not_needed; for someone else's player,
--                           not_authorized; writing the table directly, refused
--   Tara approves           'approved', one note to the player, a second tap
--                           sends nothing; registers from then on, any clinic
--                           at that level or below, not above
--   Tara removes            the row goes; new sign-ups refused again; the
--                           spot already taken stays
--   Tara places by hand     never gated (decision 4)
--   who reads what          the player their own rows, Tara everyone's
--   the rating              the player cannot change it once set (that would
--                           walk round the gate); Tara can
--
-- Priya is 3.0 in the seed; this probe makes her 2.5 inside the transaction.
-- Expected values are written from the rule, by hand.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  PRIYA   constant uuid := '55555555-5555-5555-5555-555555555555';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  THEO_P  constant uuid := 'a0000000-0000-0000-0000-000000000008';
  THEO    constant uuid := '99999999-9999-9999-9999-999999999999';
  c30 uuid; c30b uuid; c35 uuid; c_plain uuid; c_late uuid; c_placed uuid; c_beg uuid; c_25 uuid;
  v public.level_approvals; err text; n int; got text;
begin
  update public.players set adult_rating = 2.5 where id = PRIYA_P;
  update public.players set adult_rating = null where id = THEO_P;

  -- ------------------------------------------------ 1. the level in the name
  select string_agg(coalesce(public.clinic_level_from_name(x)::text, '-'), ' ' order by o) into got
    from unnest(array['Ladies 3.0+', 'Men''s 3.0+', '4.0 Clinic', '105', 'All-Level Ladies',
                      'Fri 9.30 Drill', 'Ladies 3.5-4.0', 'Coed 2.5 & Up']) with ordinality as t(x, o);
  insert into _probe_result values ('level_read_from_the_name', '3.0 3.0 4.0 - - - 3.5 2.5', got);

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Ladies 3.0+', 'coed', 'Clinic', 'probe', now() + interval '5 days', now() + interval '5 days 90 minutes',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 90) returning id into c30;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Second 3.0+', 'coed', 'Clinic', 'probe', now() + interval '6 days', now() + interval '6 days 90 minutes',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 90) returning id into c30b;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe 3.5+', 'coed', 'Clinic', 'probe', now() + interval '7 days', now() + interval '7 days 90 minutes',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 90) returning id into c35;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe All-Level', 'coed', 'Clinic', 'probe', now() + interval '5 days', now() + interval '5 days 90 minutes',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 90) returning id into c_plain;
  -- Registration closed: only a late request is left.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe Late 3.0+', 'coed', 'Clinic', 'probe', now() + interval '2 hours', now() + interval '3 hours',
          now() - interval '2 days', now() - interval '1 day', now() - interval '1 minute', 8, 'published', 60)
  returning id into c_late;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Placed 4.0', 'coed', 'Clinic', 'probe', now() + interval '8 days', now() + interval '8 days 90 minutes',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 90) returning id into c_placed;

  select min_rating::text into got from public.clinics where id = c30;
  insert into _probe_result values ('clinic_carries_its_level', '3.0', coalesce(got, 'null'));
  update public.clinics set name = 'Probe Renamed 4.0' where id = c_plain;
  select coalesce(min_rating::text, 'null') into got from public.clinics where id = c_plain;
  update public.clinics set name = 'Probe All-Level' where id = c_plain;
  insert into _probe_result values ('a_rename_moves_the_level', '4.0', got);

  -- ---------------------------------------- 2. below the level, no approval
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  select coalesce(min_rating::text, 'null') into got from public.clinics_public where id = c30;
  insert into _probe_result values ('player_sees_the_level', '3.0', got);
  begin
    perform public.register_for_clinic(c30, PRIYA_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('below_the_level_is_refused', 'level_approval_required', err);
  begin
    perform public.request_late_spot(c_late, PRIYA_P, 'please'); err := 'requested';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('late_request_below_the_level_is_refused', 'level_approval_required', err);
  -- No level in the name: nothing changes for her.
  perform public.register_for_clinic(c_plain, PRIYA_P, null);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('refusals_left_no_row', '0',
    (select count(*)::text from public.registrations where clinic_id = c30 and player_id = PRIYA_P));
  insert into _probe_result values ('no_level_registers_as_before', '1',
    (select count(*)::text from public.registrations where clinic_id = c_plain and player_id = PRIYA_P));

  -- At the level: Rob is 3.0. No rating: Theo.
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(c30, ROB_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('at_the_level_registers', 'registered', err);
  begin
    perform public.request_level_approval(ROB_P, 3.0); err := 'requested';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('asking_when_not_needed_is_refused', 'approval_not_needed', err);
  begin
    perform public.request_level_approval(PRIYA_P, 3.0); err := 'requested';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('asking_for_someone_else_is_refused', 'not_authorized', err);
  perform set_config('request.jwt.claims', json_build_object('sub', THEO)::text, true);
  begin
    perform public.register_for_clinic(c30, THEO_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('no_rating_is_not_gated', 'registered', err);
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------------ 3. asking
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  v := public.request_level_approval(PRIYA_P, 3.0);
  insert into _probe_result values ('request_is_recorded', 'requested 3.0', v.status || ' ' || v.level);
  v := public.request_level_approval(PRIYA_P, 3.0);
  insert into _probe_result values ('second_tap_changes_nothing', 'requested', v.status);
  begin
    perform public.register_for_clinic(c30, PRIYA_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('asking_does_not_register', 'level_approval_required', err);
  begin
    insert into public.level_approvals (player_id, level, status) values (PRIYA_P, 4.0, 'approved'); err := 'inserted';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('player_cannot_write_the_table', 'permission denied', err);
  begin
    perform public.admin_set_level_approval(PRIYA_P, 3.0, true); err := 'approved';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('player_cannot_approve_herself', 'not_authorized', err);
  begin
    perform * from public.admin_level_approvals(); err := 'listed';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('player_cannot_list_everyone', 'not_authorized', err);
  select count(*) into n from public.level_approvals;
  insert into _probe_result values ('player_reads_her_own_row', '1', n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  select count(*) into n from public.level_approvals;
  insert into _probe_result values ('another_player_reads_nothing', '0', n::text);
  perform set_config('role', 'postgres', true);

  select count(*)::text || ' ' || coalesce(max(body), '') into got from public.notifications
   where account_id = TARA and type = 'level_request' and entity_type = 'player' and entity_id = PRIYA_P;
  insert into _probe_result values ('tara_told_once_in_a_fixed_sentence',
    '1 Priya ' || (select last_name from public.players where id = PRIYA_P) || ' (2.5) asked to attend 3.0+ clinics.', got);

  -- -------------------------------------------------------- 4. Tara approves
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select string_agg(first_name || ' ' || status || ' ' || label, ', ') into got from public.admin_level_approvals();
  insert into _probe_result values ('tara_sees_the_request', 'Priya requested Ladies 3.0+', got);
  v := public.admin_set_level_approval(PRIYA_P, 3.0, true);
  insert into _probe_result values ('tara_approves', 'approved', v.status);
  v := public.admin_set_level_approval(PRIYA_P, 3.0, true);
  perform set_config('role', 'postgres', true);
  select count(*)::text || ' ' || coalesce(max(body), '') into got from public.notifications
   where account_id = PRIYA and type = 'level_approved' and entity_type = 'player' and entity_id = PRIYA_P;
  insert into _probe_result values ('player_told_once',
    '1 You''re approved to attend Ladies 3.0+ clinics.', got);
  insert into _probe_result values ('rating_never_moves', '2.5',
    (select adult_rating::text from public.players where id = PRIYA_P));

  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(c30, PRIYA_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('approved_registers', 'registered', err);
  begin
    perform public.register_for_clinic(c30b, PRIYA_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('approval_lasts_for_the_next_clinic', 'registered', err);
  begin
    perform public.register_for_clinic(c35, PRIYA_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('approval_does_not_reach_higher', 'level_approval_required', err);
  begin
    perform public.request_level_approval(PRIYA_P, 3.0); err := 'requested';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('asking_again_once_approved_is_not_needed', 'approval_not_needed', err);
  perform set_config('role', 'postgres', true);

  -- A 4.0 approval covers 3.5 (Tara approves straight from the profile,
  -- with no request first).
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  v := public.admin_set_level_approval(PRIYA_P, 4.0, true);
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  begin
    perform public.register_for_clinic(c35, PRIYA_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_higher_approval_covers_lower', 'registered', err);

  -- ------------------------------------------------------- 5. Tara removes
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_set_level_approval(PRIYA_P, 3.0, false);
  perform public.admin_set_level_approval(PRIYA_P, 4.0, false);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('removed_rows_are_gone', '0',
    (select count(*)::text from public.level_approvals where player_id = PRIYA_P));
  delete from public.registrations where clinic_id = c30b and player_id = PRIYA_P;
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(c30b, PRIYA_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('removed_is_refused_again', 'level_approval_required', err);
  perform set_config('role', 'postgres', true);
  -- Priya is a non-member past the member window, so her spot is on the Waitlist.
  insert into _probe_result values ('spot_taken_while_approved_stays', 'pool',
    (select status::text from public.registrations where clinic_id = c30 and player_id = PRIYA_P));

  -- --------------------------------------------- 6. Tara places by hand
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.place_player(c_placed, PRIYA_P, 'in'); err := 'placed';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('tara_places_anyone', 'placed', err);

  -- ------------------------------ 7. the rating is Tara's once it is set
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.players set adult_rating = 3.0 where id = PRIYA_P; err := 'changed';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('player_cannot_raise_her_own_rating', 'rating_set_by_tara', err);
  -- The 1.0.x app sends the rating unchanged with every Edit details save.
  begin
    update public.players set first_name = 'Priya', adult_rating = 2.5 where id = PRIYA_P; err := 'saved';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('an_unchanged_rating_still_saves', 'saved', err);
  begin
    perform public.admin_set_player_rating(PRIYA_P, 3.0); err := 'changed';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('player_cannot_use_taras_rating_rpc', 'not_authorized', err);
  perform set_config('request.jwt.claims', json_build_object('sub', THEO)::text, true);
  begin
    update public.players set adult_rating = 3.0 where id = THEO_P; err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_missing_rating_can_be_given_once', 'set', err);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  begin
    perform public.admin_set_player_rating(PRIYA_P, 3.0); err := 'changed';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('tara_changes_a_rating', 'changed 3.0',
    err || ' ' || (select adult_rating::text from public.players where id = PRIYA_P));
  -- ------------------------------ 8. no second player row on the account
  -- (the sql-auditor, 2026-11-05: a 2.5 added a 3.0 row and registered it.)
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    insert into public.players (account_id, kind, first_name, last_name, adult_rating, is_active)
    values (PRIYA, 'adult', 'Priya', 'Again', 3.0, true); err := 'inserted';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('no_second_player_row', 'permission denied', err);
  insert into _probe_result values ('no_registration_through_a_second_row', '0',
    (select count(*)::text from public.registrations r join public.players p on p.id = r.player_id
      where p.account_id = PRIYA and p.id <> PRIYA_P));

  -- ------------------------------ beginner clinics (decision 0049, Tara 2026-11-05)
  -- "Beginner clinics can be open to anyone up to a 3.0 ... even though it says
  -- beginner to 2.5". The number in a beginner clinic's name is not a minimum.
  -- A 2.0 still needs her OK for "Ladies 2.5+" (her "yes" to question 140).
  select string_agg(coalesce(public.clinic_level_from_name(x)::text, '-'), ' ' order by o) into got
    from unnest(array['Ladies Beginner - 2.5', 'Ladies Beginner - 2.5 level', 'BEGINNER 2.5',
                      'Ladies 2.5+', 'Ladies 3.0+ Clinic']) with ordinality as t(x, o);
  insert into _probe_result values ('beginner_name_carries_no_minimum', '- - - 2.5 3.0', got);

  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  delete from public.level_approvals where player_id = PRIYA_P;
  update public.players set adult_rating = 2.0 where id = PRIYA_P;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Beginner - 2.5', 'coed', 'Clinic', 'probe', now() + interval '9 days', now() + interval '9 days 60 minutes',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_beg;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Ladies 2.5+', 'coed', 'Clinic', 'probe', now() + interval '10 days', now() + interval '10 days 60 minutes',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into c_25;
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(c_beg, PRIYA_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_2_0_registers_for_a_beginner_clinic', 'registered', err);
  begin
    perform public.register_for_clinic(c_25, PRIYA_P, null); err := 'registered';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_2_0_still_asks_for_2_5_plus', 'level_approval_required', err);
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
