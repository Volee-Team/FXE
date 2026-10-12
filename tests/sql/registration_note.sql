-- registration_note.sql
--
-- Tara, 2026-10-11: a private note a player can leave when she registers
-- ("please put me on court with my friend Jane"), "Only Tara sees this".
-- Decision 0039, migration 20261011000001.
--
-- Expected values come from that sentence, not from the code:
--   * the writer and Tara read it; nobody else does: not another player,
--     not a pro (Tara said "only I"), not a signed-out caller;
--   * it is written at Register, and the writer can change or clear it
--     until the clinic starts, on her own live registration only;
--   * blank is no note, 300 characters is the most, trimmed;
--   * an app with no note field still registers (two arguments);
--   * deleting the account erases the writer's notes.
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
  DANA    constant uuid := '66666666-6666-6666-6666-666666666666';
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  JANE    constant text := 'please put me on court with my friend Jane';
  clinic uuid; played uuid; reg_m uuid; reg_k uuid; reg_d uuid; reg_old uuid;
  n int; v text; err text;
begin
  -- A clinic open to everyone now, two days out, and one Dana played last week.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Note', 'coed', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into clinic;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Note Played', 'coed', 'Clinic', 'probe', now() - interval '6 days', now() - interval '6 days' + interval '1 hour',
          now() - interval '12 days', now() - interval '11 days', 8, 'published', 60)
  returning id into played;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, player_note)
  values (played, DANA_P, 'in', 'self', 1800, true, 60, 'by Jen please')
  returning id into reg_old;

  perform set_config('role', 'authenticated', true);

  -- 1. Maria registers with Tara's example, padded: stored trimmed.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select id into reg_m from public.register_for_clinic(clinic, MARIA_P, '  ' || JANE || E'\n');
  select player_note into v from public.my_registrations where id = reg_m;
  -- In brackets: the harness matches a lettered expectation as a substring,
  -- so an untrimmed note would otherwise pass.
  insert into _probe_result values ('writer_reads_her_note', '[' || JANE || ']', '[' || coalesce(v, '<null>') || ']');

  -- 2. An app with no note field: two arguments still register, no note.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select id into reg_k from public.register_for_clinic(clinic, KEN_P);
  select coalesce(player_note, '<null>') into v from public.my_registrations where id = reg_k;
  insert into _probe_result values ('two_argument_register_has_no_note', '<null>', v);

  -- 3. Ken, another player, cannot read Maria's note by any door.
  select count(*) into n from public.my_registrations where id = reg_m;
  insert into _probe_result values ('other_player_my_registrations', '0', n::text);
  select count(*) into n from public.registrations_admin;
  insert into _probe_result values ('other_player_registrations_admin', '0', n::text);
  begin
    execute 'select player_note from public.registrations where id = $1' into v using reg_m;
    err := 'read: ' || coalesce(v, '<null>');
  exception when insufficient_privilege then err := 'denied';
  end;
  insert into _probe_result values ('other_player_base_table', 'denied', err);

  -- 4. Casey, a pro, does not see it: registrations_admin is Tara's alone,
  --    and Today names no note.
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  select count(*) into n from public.registrations_admin where id = reg_m;
  insert into _probe_result values ('pro_registrations_admin', '0', n::text);
  perform set_config('role', 'postgres', true);
  select coalesce(string_agg(a, ','), '') into v
    from unnest((select proargnames from pg_proc where proname = 'pro_today')) a
   where a ilike '%note%';
  insert into _probe_result values ('pro_today_has_no_note', '', v);

  -- 5. Tara reads it on her roster.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select player_note into v from public.registrations_admin where id = reg_m;
  insert into _probe_result values ('tara_reads_the_note', '[' || JANE || ']', '[' || coalesce(v, '<null>') || ']');

  -- 6. Exactly two relations in public expose the column, and they are these.
  perform set_config('role', 'postgres', true);
  select string_agg(table_name, ', ' order by table_name) into v
    from information_schema.columns
   where table_schema = 'public' and column_name = 'player_note' and table_name <> 'registrations';
  insert into _probe_result values ('only_two_views_carry_it', 'my_registrations, registrations_admin', coalesce(v, ''));

  -- 7. Grants: nothing for anon; no column privilege for authenticated.
  insert into _probe_result values ('authenticated_no_column_read', 'false',
    has_column_privilege('authenticated', 'public.registrations', 'player_note', 'SELECT')::text);
  insert into _probe_result values ('anon_no_my_registrations', 'false',
    has_table_privilege('anon', 'public.my_registrations', 'SELECT')::text);
  insert into _probe_result values ('anon_cannot_set_note', 'false',
    has_function_privilege('anon', 'public.set_my_registration_note(uuid, text)', 'EXECUTE')::text);
  insert into _probe_result values ('anon_cannot_register', 'false',
    has_function_privilege('anon', 'public.register_for_clinic(uuid, uuid, text)', 'EXECUTE')::text);
  insert into _probe_result values ('clean_note_is_internal', 'false',
    has_function_privilege('authenticated', 'public.clean_player_note(text)', 'EXECUTE')::text);
  -- Every client function returning a whole registrations row now carries
  -- the note to its caller. Today each is the owner's or Tara's alone
  -- (sql-auditor, 2026-10-11); a new one must be checked, so the set is pinned.
  select string_agg(proname, ', ' order by proname) into v from pg_proc
   where pronamespace = 'public'::regnamespace
     and prorettype = 'public.registrations'::regtype
     and has_function_privilege('authenticated', oid, 'EXECUTE');
  insert into _probe_result values ('whole_row_functions_pinned',
    '[admin_mark_late_cancel, admin_set_no_show, assign_court, cancel_invitation, cancel_registration, invite_from_pool, place_player, register_for_clinic, respond_to_invitation, set_paid]',
    '[' || coalesce(v, '') || ']');
  select count(*) into n from pg_proc where proname = 'register_for_clinic';
  insert into _probe_result values ('one_register_for_clinic', '1', n::text);

  -- 8. Too long is refused. Rob, so that a broken limit (his spot taken)
  --    cannot abort Dana's checks below.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  begin
    perform public.register_for_clinic(clinic, ROB_P, repeat('x', 301));
    err := 'accepted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('note_301_refused', 'note_too_long', err);

  -- 9. 300 exactly is fine; blank is no note.
  perform set_config('request.jwt.claims', json_build_object('sub', DANA)::text, true);
  select id into reg_d from public.register_for_clinic(clinic, DANA_P, repeat('y', 300));
  select char_length(player_note)::text into v from public.my_registrations where id = reg_d;
  insert into _probe_result values ('note_300_kept', '300', coalesce(v, '<null>'));
  -- Characters, not bytes: é is two bytes, and the box counts characters.
  begin
    perform public.set_my_registration_note(reg_d, repeat('é', 300));
    select char_length(player_note)::text into v from public.my_registrations where id = reg_d;
  exception when others then v := sqlerrm;
  end;
  insert into _probe_result values ('accented_300_kept', '300', coalesce(v, '<null>'));
  begin
    perform public.set_my_registration_note(reg_d, repeat('é', 301));
    err := 'accepted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('accented_301_refused', 'note_too_long', err);
  select coalesce(public.set_my_registration_note(reg_d, '   '), '<null>') into v;
  insert into _probe_result values ('blank_clears_returned', '<null>', v);
  select coalesce(player_note, '<null>') into v from public.my_registrations where id = reg_d;
  insert into _probe_result values ('blank_clears_stored', '<null>', v);

  -- 9b. Tara registering Rob cannot put words in his note.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select coalesce(player_note, '<null>') into v from public.register_for_clinic(clinic, ROB_P, 'Rob wants court 1');
  insert into _probe_result values ('tara_register_writes_no_note', '<null>', v);

  -- 10. Maria changes hers; Ken cannot touch it (assert the outcome).
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform public.set_my_registration_note(reg_m, 'with Tammy please');
  select player_note into v from public.my_registrations where id = reg_m;
  insert into _probe_result values ('writer_changes_note', 'with Tammy please', coalesce(v, '<null>'));
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin
    perform public.set_my_registration_note(reg_m, 'put Maria alone');
    err := 'accepted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('other_player_cannot_write', 'note_not_editable', err);
  -- Tara is no exception: the note is the player's words, not hers.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  begin
    perform public.set_my_registration_note(reg_m, 'edited by Tara');
    err := 'accepted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('tara_cannot_rewrite_it', 'note_not_editable', err);
  select player_note into v from public.registrations_admin where id = reg_m;
  insert into _probe_result values ('note_unchanged_after_attacks', 'with Tammy please', coalesce(v, '<null>'));

  -- 11. Not after the clinic has started, and not on a canceled spot.
  perform set_config('role', 'postgres', true);
  update public.clinics set starts_at = now() - interval '1 minute', ends_at = now() + interval '59 minutes' where id = clinic;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.set_my_registration_note(reg_m, 'too late');
    err := 'accepted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('not_after_start', 'note_not_editable', err);
  perform set_config('role', 'postgres', true);
  update public.clinics set starts_at = now() + interval '2 days', ends_at = now() + interval '2 days 1 hour' where id = clinic;
  update public.registrations set status = 'canceled', canceled_at = now() where id = reg_m;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.set_my_registration_note(reg_m, 'after cancel');
    err := 'accepted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('not_on_canceled_spot', 'note_not_editable', err);

  -- A canceled clinic keeps its registrations live (cancel_clinic changes the
  -- clinic only), so the clinic's own status must stop the edit. Then a draft.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  foreach v in array array['canceled', 'draft'] loop
    perform set_config('role', 'postgres', true);
    execute format('update public.clinics set status = %L where id = $1', v) using clinic;
    perform set_config('role', 'authenticated', true);
    begin
      perform public.set_my_registration_note(reg_k, 'on a ' || v || ' clinic');
      err := 'accepted';
    exception when others then err := sqlerrm;
    end;
    insert into _probe_result values ('not_on_' || v || '_clinic', 'note_not_editable', err);
  end loop;
  perform set_config('role', 'postgres', true);
  select coalesce(player_note, '<null>') into v from public.registrations where id = reg_k;
  insert into _probe_result values ('ken_note_unchanged', '<null>', v);
  update public.clinics set status = 'published' where id = clinic;
  perform set_config('role', 'authenticated', true);

  -- 12. Deleting Dana's account erases her notes, the played clinic's too.
  perform set_config('request.jwt.claims', json_build_object('sub', DANA)::text, true);
  perform public.set_my_registration_note(reg_d, 'with Maria');
  perform public.delete_my_account();
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where id in (reg_d, reg_old) and player_note is not null;
  insert into _probe_result values ('deletion_erases_notes', '0', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
