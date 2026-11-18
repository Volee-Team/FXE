-- one_account_many_players.sql
--
-- 20261115000001, juniors phase 0 (docs/juniors/plan.md, decision 0057).
-- THE RULE: an account may own junior rows beside its one adult row, and
--   - what the apps already on phones read is unchanged: a member's SELECT on
--     players, my_registrations and my_past_clinics return the adult's rows
--     only (Tara still reads everything);
--   - an account has exactly one adult;
--   - the Ladies / Men rule reads the adult's gender, never a child's;
--   - a junior plays only in a juniors clinic and an adult never in one,
--     unless Tara places them (wrong_player_kind), on registrations and late
--     requests alike;
--   - the calendar feed names a child's clinic ("Sam: ...");
--   - a parent with a child can delete their account.
--
-- Maria (seed, female adult) gets a son, Sam, for the length of the probe.
-- Expected values are written from the rule, not copied from a run; every
-- check but the "still works" ones was red on the schema before this
-- migration.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  sam uuid;
  c_jr uuid; c_adult uuid; c_men uuid; c_jr_past uuid;
  n int; v text; err text;
begin
  -- Maria answered female in the seed; make sure, since the gender checks rely on it.
  update public.players set gender = 'female' where id = MARIA_P;

  insert into public.players (account_id, kind, first_name, last_name, date_of_birth, gender)
  values (MARIA, 'junior', 'Sam', 'Probe', date '2017-05-01', 'male')
  returning id into sam;

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values
    ('Probe Red Dot',   'juniors', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour', now() - interval '2 days', now() - interval '1 day', 8, 'published', 60),
    ('Probe Adult',     'coed',    'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour', now() - interval '2 days', now() - interval '1 day', 8, 'published', 60),
    ('Probe Men Only',  'men',     'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour', now() - interval '2 days', now() - interval '1 day', 8, 'published', 60),
    ('Probe Red Past',  'juniors', 'Clinic', 'probe', now() - interval '2 days', now() - interval '2 days' + interval '1 hour', now() - interval '9 days', now() - interval '8 days', 8, 'published', 60);
  select id into c_jr      from public.clinics where name = 'Probe Red Dot';
  select id into c_adult   from public.clinics where name = 'Probe Adult';
  select id into c_men     from public.clinics where name = 'Probe Men Only';
  select id into c_jr_past from public.clinics where name = 'Probe Red Past';

  -- A clinic Sam already played (fixture, written with no one signed in).
  insert into public.registrations (clinic_id, player_id, status, source) values (c_jr_past, sam, 'in', 'admin');

  -- 1. One adult per account.
  begin
    insert into public.players (account_id, kind, first_name, last_name) values (MARIA, 'adult', 'Second', 'Adult');
    err := 'inserted';
  exception when unique_violation then err := 'unique_violation';
  end;
  insert into _probe_result values ('a1_a_second_adult_on_one_account_is_refused', 'unique_violation', err);

  -- 5. The kind rule, as Maria (her JWT, so the guard sees a signed-in member).
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    insert into public.registrations (clinic_id, player_id, status, source) values (c_adult, sam, 'in', 'self');
    err := 'inserted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('k1_a_child_is_refused_an_adult_clinic', 'wrong_player_kind', err);
  begin
    insert into public.registrations (clinic_id, player_id, status, source) values (c_jr, MARIA_P, 'in', 'self');
    err := 'inserted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('k2_an_adult_is_refused_a_juniors_clinic', 'wrong_player_kind', err);
  begin
    insert into public.late_requests (clinic_id, player_id, message) values (c_adult, sam, 'please');
    err := 'inserted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('k3_a_childs_late_request_for_an_adult_clinic_is_refused', 'wrong_player_kind', err);
  begin
    insert into public.registrations (clinic_id, player_id, status, source) values (c_jr, sam, 'in', 'self');
    err := 'inserted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('k4_a_child_in_a_juniors_clinic_still_works', 'inserted', err);
  begin
    insert into public.registrations (clinic_id, player_id, status, source) values (c_adult, MARIA_P, 'in', 'self');
    err := 'inserted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('k5_an_adult_in_an_adult_clinic_still_works', 'inserted', err);

  begin
    insert into public.late_requests (clinic_id, player_id, message) values (c_jr, MARIA_P, 'please');
    err := 'inserted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('k7_an_adults_late_request_for_a_juniors_clinic_is_refused', 'wrong_player_kind', err);
  begin
    update public.registrations set clinic_id = c_adult where clinic_id = c_jr and player_id = sam;
    err := 'moved';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('k8_moving_a_childs_spot_into_an_adult_clinic_is_refused', 'wrong_player_kind', err);
  begin
    perform public.register_for_clinic(c_adult, sam);
    err := 'registered';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('k9_register_for_clinic_refuses_a_child_in_an_adult_clinic', 'wrong_player_kind', err);

  -- Tara places anyone anywhere.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  begin
    insert into public.registrations (clinic_id, player_id, status, source) values (c_men, sam, 'in', 'admin');
    err := 'inserted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('k6_tara_may_place_a_child_in_an_adult_clinic', 'inserted', err);
  delete from public.registrations where clinic_id = c_men and player_id = sam;

  -- 2 to 4. What Maria's apps read, as Maria.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.players;
  insert into _probe_result values ('r1_a_members_players_read_is_the_adult_alone', '1', n::text);
  select string_agg(kind::text, ',') into v from public.players;
  insert into _probe_result values ('r2_and_that_row_is_the_adult', 'adult', coalesce(v, 'none'));
  select count(*) into n from public.my_registrations where player_id = sam;
  insert into _probe_result values ('r3_my_registrations_shows_no_childs_spot', '0', n::text);
  select count(*) into n from public.my_registrations where player_id = MARIA_P and clinic_id = c_adult;
  insert into _probe_result values ('r4_my_registrations_still_shows_her_own', '1', n::text);
  select count(*) into n from public.my_past_clinics where clinic_id = c_jr_past;
  insert into _probe_result values ('r5_my_past_clinics_shows_no_childs_clinic', '0', n::text);
  select count(*) into n from public.clinics_public where id = c_men;
  insert into _probe_result values ('g1_a_mother_of_a_son_does_not_see_mens_clinics', '0', n::text);
  select count(*) into n from public.clinics_public where id = c_jr;
  insert into _probe_result values ('g4_the_old_apps_list_shows_no_juniors_clinic', '0', n::text);
  select count(*) into n from public.clinics_public where id = c_adult;
  insert into _probe_result values ('g2_she_still_sees_a_coed_clinic', '1', n::text);
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  update public.players set gender = null where id = sam;
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.clinics_public where id = c_men;
  insert into _probe_result values ('g3_a_child_with_no_answer_opens_nothing', '0', n::text);

  update public.players set first_name = 'Changed';
  perform set_config('role', 'postgres', true);
  select first_name into v from public.players where id = sam;
  insert into _probe_result values ('u1_an_unfiltered_update_cannot_reach_the_child', 'Sam', v);
  update public.players set first_name = 'Maria' where id = MARIA_P;
  perform set_config('role', 'authenticated', true);

  -- Tara still reads the whole family.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select count(*) into n from public.players where account_id = MARIA;
  insert into _probe_result values ('r6_tara_reads_the_child_too', '2', n::text);
  perform set_config('role', 'postgres', true);

  -- 6. The calendar feed names the child's clinic.
  insert into public.calendar_feeds (account_id, token)
  values (MARIA, repeat('ab', 32))
  on conflict (account_id) do update set token = excluded.token;
  select string_agg(clinic_name, ' | ' order by clinic_name) into v
    from public.calendar_feed_events(repeat('ab', 32))
   where clinic_name like '%Probe%';
  insert into _probe_result values ('c1_the_feed_names_the_childs_clinic', 'Probe Adult | Sam: Probe Red Dot | Sam: Probe Red Past', coalesce(v, 'none'));

  -- 7. A parent with a child can delete their account; the child is anonymised.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.delete_my_account();
    err := 'deleted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('d1_a_parent_can_delete_their_account', 'deleted', err);
  select first_name || ' ' || is_active::text into v from public.players where id = sam;
  insert into _probe_result values ('d2_the_child_is_anonymised_and_inactive', 'Deleted false', coalesce(v, 'none'));
  perform set_config('request.jwt.claims', '', true);

  -- An active child still needs a birthday.
  begin
    insert into public.players (account_id, kind, first_name, last_name) values (TARA, 'junior', 'No', 'Birthday');
    err := 'inserted';
  exception when check_violation then err := 'check_violation';
  end;
  insert into _probe_result values ('d3_an_active_child_still_needs_a_birthday', 'check_violation', err);

  -- The guard is internal.
  insert into _probe_result values ('h1_guard_not_callable', 'false',
    case when to_regprocedure('public.guard_player_kind()') is null then 'no guard'
         else has_function_privilege('authenticated', 'public.guard_player_kind()', 'EXECUTE')::text end);
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
