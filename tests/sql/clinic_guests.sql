-- clinic_guests.sql
--
-- Tara's guests (20261107000003, question 144): a first and last name on one
-- clinic for someone not in the app. From the rule, by hand:
--
--   only Tara           adds, lists, courts and removes them; a player, a pro
--                       and a signed-out caller cannot, and nobody reads the
--                       table directly
--   a name             both parts, trimmed; never on a canceled clinic
--   never anyone else's nothing is notified, charged, or put in a registration
--   room               a guest takes a spot wherever the server asks "is there
--                      room": a member in the window goes to the Waitlist, a
--                      late request is refused, and its approval too
--   removed            stays as a row (hard rule 4), off her list, and the spot
--                      is free again

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  c_one uuid; c_late uuid; c_cancel uuid;
  g public.clinic_guests; g2 public.clinic_guests;
  r public.registrations; err text; n int; got text; notes_before int; regs_before int;
begin
  -- One spot, member window open now (public opens tomorrow).
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe One Spot', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '1 hour', now() + interval '1 day', 1, 'published', 60) returning id into c_one;
  -- Registration closed, one spot: only a late request is left.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe Late One Spot', 'coed', 'Clinic', 'probe', now() + interval '2 hours', now() + interval '3 hours',
          now() - interval '2 days', now() - interval '1 day', now() - interval '1 minute', 1, 'published', 60)
  returning id into c_late;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, canceled_at)
  values ('Probe Canceled', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'canceled', 60, now()) returning id into c_cancel;
  select count(*) into notes_before from public.notifications;
  select count(*) into regs_before from public.registrations;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);

  -- ---------------------------------------------------------- adding
  g := public.admin_add_guest(c_one, '  Jane ', ' Guest  ');
  insert into _probe_result values ('tara_adds_a_guest_trimmed', 'Jane|Guest|none',
    g.first_name || '|' || g.last_name || '|' || coalesce(g.court_number::text, 'none'));
  begin perform public.admin_add_guest(c_one, 'Jane', '   '); err := 'added';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('both_names_are_needed', 'name_required', err);
  begin perform public.admin_add_guest(c_one, E'\t', 'Guest'); err := 'added';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_tab_is_not_a_name', 'name_required', err);
  begin perform public.admin_add_guest(c_one, 'jane', 'GUEST'); err := 'added';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('adding_the_same_guest_twice_is_refused', 'guest_already_added', err);
  select count(*) into n from public.admin_clinic_guests(array[c_one]);
  insert into _probe_result values ('and_keeps_one', '1', n::text);
  begin perform public.admin_add_guest(c_cancel, 'Jo', 'Guest'); err := 'added';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('never_on_a_canceled_clinic', 'clinic_canceled', err);

  select string_agg(first_name || ' ' || last_name, ', ') into got from public.admin_clinic_guests(array[c_one]);
  insert into _probe_result values ('she_lists_her_guests', 'Jane Guest', got);

  perform public.admin_set_guest_court(g.id, 3::smallint);
  select court_number::text into got from public.admin_clinic_guests(array[c_one]);
  insert into _probe_result values ('a_guest_gets_a_court', '3', got);
  begin perform public.admin_set_guest_court(g.id, 6::smallint); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('not_court_six', 'invalid_court', err);

  -- ---------------------------------------------------------- nobody else's
  perform set_config('role', 'postgres', true);
  select count(*) - notes_before into n from public.notifications;
  insert into _probe_result values ('a_guest_tells_nobody', '0', n::text);
  select count(*) - regs_before into n from public.registrations;
  insert into _probe_result values ('a_guest_is_not_a_registration', '0', n::text);
  perform set_config('role', 'authenticated', true);

  -- ---------------------------------------------------------- room
  -- The guest holds the one spot: Ken, a member inside his window, waits.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  r := public.register_for_clinic(c_one, KEN_P);
  insert into _probe_result values ('a_guest_takes_the_spot', 'pool', r.status::text);

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  g2 := public.admin_add_guest(c_late, 'Late', 'Guest');
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin perform public.request_late_spot(c_late, MARIA_P, 'Room for one more?'); err := 'asked';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_late_request_sees_the_guest', 'clinic_full', err);

  -- Removed: off her list, the row kept, the spot free again.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_remove_guest(g2.id);
  select count(*) into n from public.admin_clinic_guests(array[c_late]);
  insert into _probe_result values ('a_removed_guest_leaves_her_list', '0', n::text);
  perform set_config('role', 'postgres', true);
  select (removed_at is not null)::text into got from public.clinic_guests where id = g2.id;
  insert into _probe_result values ('and_the_row_is_kept', 'true', got);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin perform public.request_late_spot(c_late, MARIA_P, 'Room for one more?'); err := 'asked';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('then_the_late_request_goes_through', 'asked', err);
  -- A second guest arrives before Tara approves: the approval sees it.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_add_guest(c_late, 'Second', 'Guest');
  begin
    perform public.resolve_late_request(
      (select id from public.late_requests where clinic_id = c_late and player_id = MARIA_P and status = 'pending'), true);
    err := 'approved';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('the_approval_sees_the_guest', 'clinic_full', err);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id = c_late and player_id = MARIA_P and status = 'in';
  insert into _probe_result values ('and_maria_is_not_in', '0', n::text);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  begin perform public.admin_remove_guest(g2.id); err := 'removed';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('removed_twice_is_refused', 'guest_not_found', err);

  -- ---------------------------------------------------------- only Tara
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin perform public.admin_add_guest(c_one, 'Sneaky', 'Friend'); err := 'added';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_add_a_guest', 'not_authorized', err);
  begin perform count(*) from public.admin_clinic_guests(array[c_one]); err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_player_cannot_list_guests', 'not_authorized', err);
  begin perform count(*) from public.clinic_guests; err := 'read';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('nobody_reads_the_table', 'permission denied', err);
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin perform public.admin_set_guest_court(g.id, 1::smallint); err := 'set';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_pro_cannot_set_a_guests_court', 'not_authorized', err);
  begin perform public.admin_remove_guest(g.id); err := 'removed';
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('a_pro_cannot_remove_a_guest', 'not_authorized', err);

  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('the_count_helper_is_internal', 'false',
    has_function_privilege('authenticated', 'public.clinic_taken(uuid)', 'EXECUTE')::text);
  insert into _probe_result values ('anon_cannot_add', 'false',
    has_function_privilege('anon', 'public.admin_add_guest(uuid, text, text)', 'EXECUTE')::text);
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
