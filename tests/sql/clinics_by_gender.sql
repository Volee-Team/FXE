-- clinics_by_gender.sql
--
-- Tara, 2026-10-30 (relayed by John): "if you're a man, you should only be
-- able to see the registration for coed or men's league. You shouldn't be
-- able to see any ladies clinics." Same for women, with Ladies and Coed.
-- Decision 0044, migration 20261030000001.
--
-- Expected values come from that sentence and the decision's defaults, not
-- from the code:
--   * a man sees Men and Coed, never Ladies, and cannot register for or ask
--     late for a Ladies clinic; a woman the same way round;
--   * a player who has not answered sees and may register for everything;
--   * Tara sees everything and places anyone anywhere, and a clinic someone
--     holds a spot in stays in their list;
--   * a player answers once, for their own player only; changing it is Tara's.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  ladies uuid; men uuid; coed uuid; ladies_late uuid; ladies_placed uuid;
  n int; v text; err text; extra uuid;
begin
  -- Three open clinics, one per audience, and two more Ladies ones: one past
  -- its close (for a late request) and one Tara places Ken in.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Ladies', 'ladies', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into ladies;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Men', 'men', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into men;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Coed', 'coed', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into coed;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe Ladies Closed', 'ladies', 'Clinic', 'probe', now() + interval '2 hours', now() + interval '3 hours',
          now() - interval '2 days', now() - interval '1 day', now() - interval '1 hour', 8, 'published', 60)
  returning id into ladies_late;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Ladies Placed', 'ladies', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into ladies_placed;

  -- The seed answers for everyone; these three start unanswered here.
  update public.players set gender = null where id in (MARIA_P, KEN_P, ROB_P);

  -- Tara plays too: a player row of her own, answered male, so her view
  -- of everything rests on her being Tara and not on having no answer.
  insert into public.players (account_id, kind, first_name, last_name, gender)
  values (TARA, 'adult', 'Tara', 'Coach', 'male');

  perform set_config('role', 'authenticated', true);

  -- Answers. Maria and Ken answer for themselves; Rob never answers.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform public.set_my_gender(MARIA_P, 'female');
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform public.set_my_gender(KEN_P, 'male');

  -- 1. What each one sees.
  select string_agg(name, ',' order by name) into v from public.clinics_public
   where id in (ladies, men, coed);
  insert into _probe_result values ('man_sees_men_and_coed', 'Probe Coed,Probe Men', coalesce(v, ''));

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select string_agg(name, ',' order by name) into v from public.clinics_public
   where id in (ladies, men, coed);
  insert into _probe_result values ('woman_sees_ladies_and_coed', 'Probe Coed,Probe Ladies', coalesce(v, ''));

  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  select count(*) into n from public.clinics_public where id in (ladies, men, coed);
  insert into _probe_result values ('unanswered_sees_all_three', '3', n::text);

  -- Tara's screens read clinics_admin, which the rule does not touch, even
  -- with a player row of her own answered male.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select count(*) into n from public.clinics_admin where id in (ladies, men, coed);
  insert into _probe_result values ('tara_admin_list_has_all_three', '3', n::text);

  -- 2. Registering. Asserted on the resulting rows (hard rule 9), with the
  --    error name alongside so a different refusal is visible.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  err := 'none';
  begin
    perform public.register_for_clinic(ladies, KEN_P, null);
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('man_register_ladies_refused', 'audience_mismatch', err);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id = ladies and player_id = KEN_P;
  insert into _probe_result values ('man_has_no_ladies_row', '0', n::text);
  perform set_config('role', 'authenticated', true);

  perform public.register_for_clinic(men, KEN_P, null);
  perform public.register_for_clinic(coed, KEN_P, null);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id in (men, coed) and player_id = KEN_P;
  insert into _probe_result values ('man_registers_men_and_coed', '2', n::text);
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  err := 'none';
  begin
    perform public.register_for_clinic(men, MARIA_P, null);
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('woman_register_men_refused', 'audience_mismatch', err);
  perform public.register_for_clinic(ladies, MARIA_P, null);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id = men and player_id = MARIA_P;
  insert into _probe_result values ('woman_has_no_men_row', '0', n::text);
  select count(*) into n from public.registrations where clinic_id = ladies and player_id = MARIA_P;
  insert into _probe_result values ('woman_registers_ladies', '1', n::text);
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform public.register_for_clinic(ladies, ROB_P, null);
  perform public.register_for_clinic(men, ROB_P, null);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id in (ladies, men) and player_id = ROB_P;
  insert into _probe_result values ('unanswered_registers_both', '2', n::text);
  perform set_config('role', 'authenticated', true);

  -- 3. A late request is the other door into a clinic.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin
    perform public.request_late_spot(ladies_late, KEN_P, null);
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.late_requests where clinic_id = ladies_late and player_id = KEN_P;
  insert into _probe_result values ('man_late_request_ladies_refused', '0', n::text);
  perform set_config('role', 'authenticated', true);

  -- 4. Tara places Ken in a Ladies clinic: allowed, and it stays in his list.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.place_player(ladies_placed, KEN_P, 'in');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id = ladies_placed and player_id = KEN_P;
  insert into _probe_result values ('tara_places_man_in_ladies', '1', n::text);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select count(*) into n from public.clinics_public where id = ladies_placed;
  insert into _probe_result values ('placed_clinic_stays_visible', '1', n::text);
  select count(*) into n from public.clinics_public where id = ladies;
  insert into _probe_result values ('other_ladies_still_hidden_from_man', '0', n::text);

  -- 5. ATTACKS on the answer. Each asserted on the resulting state.
  -- 5a. Maria answers for Rob, who has not answered.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.set_my_gender(ROB_P, 'female');
  exception when others then null;
  end;
  -- 5b. Maria changes her own answer through the RPC.
  err := 'none';
  begin
    perform public.set_my_gender(MARIA_P, 'male');
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('second_answer_refused', 'gender_already_set', err);
  -- 5c. The same answer again is harmless.
  err := 'none';
  begin
    perform public.set_my_gender(MARIA_P, 'female');
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('same_answer_again_is_fine', 'none', err);
  -- 5d. Straight at the column.
  begin
    update public.players set gender = 'male' where id = MARIA_P;
  exception when others then null;
  end;
  -- 5e. Through Tara's RPC, on Rob, whose empty answer no trigger guards.
  begin
    perform public.admin_set_player_gender(ROB_P, 'female');
  exception when others then null;
  end;
  -- 5f. A new player row of her own, born with an answer.
  begin
    insert into public.players (account_id, kind, first_name, last_name, gender)
    values (MARIA, 'adult', 'Probe', 'Second', 'male') returning id into extra;
  exception when others then extra := null;
  end;
  perform set_config('role', 'postgres', true);
  select gender::text into v from public.players where id = ROB_P;
  insert into _probe_result values ('player_cannot_answer_for_another', 'NULL', coalesce(v, 'NULL'));
  select gender::text into v from public.players where id = MARIA_P;
  insert into _probe_result values ('player_cannot_change_own_answer', 'female', coalesce(v, 'NULL'));
  select count(*) into n from public.players where account_id = MARIA and gender is not null and id <> MARIA_P;
  insert into _probe_result values ('new_player_row_born_unanswered', '0', n::text);

  -- 6. Tara changes it, and clears it.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_set_player_gender(ROB_P, 'male');
  perform public.admin_set_player_gender(MARIA_P, null);
  perform set_config('role', 'postgres', true);
  select coalesce((select gender::text from public.players where id = ROB_P), 'NULL')
      || ',' || coalesce((select gender::text from public.players where id = MARIA_P), 'NULL') into v;
  insert into _probe_result values ('tara_sets_and_clears', 'male,NULL', v);
  perform set_config('role', 'authenticated', true);
  select gender::text into v from public.search_players('Delgado', false);
  insert into _probe_result values ('players_tab_reads_answer', 'male', coalesce(v, 'NULL'));
  perform set_config('role', 'postgres', true);

  -- 7. Signed out: no door at all (hard rule 11).
  insert into _probe_result values ('anon_cannot_set_gender', 'false',
    has_function_privilege('anon', 'public.set_my_gender(uuid, public.player_gender)', 'EXECUTE')::text);
  insert into _probe_result values ('anon_cannot_admin_set_gender', 'false',
    has_function_privilege('anon', 'public.admin_set_player_gender(uuid, public.player_gender)', 'EXECUTE')::text);
  insert into _probe_result values ('member_has_no_column_update', 'false',
    has_column_privilege('authenticated', 'public.players', 'gender', 'UPDATE')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
