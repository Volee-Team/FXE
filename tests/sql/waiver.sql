-- waiver.sql
--
-- Decision 0013 §4: Tara's Adult Tennis Participation Waiver (version
-- 2026-09) is signed in the app before a player's first spot. Her document's
-- last page is the spec: required checkbox, typed full legal name, email
-- captured from the account, time recorded by the app, version stored.
-- Expected values are transcribed from that page, not from the functions.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  FAR     constant uuid := 'd0000000-0000-0000-0000-000000000002';
  NEW_ACC constant uuid := 'ee000000-0000-0000-0000-000000000001';
  new_p uuid; r public.registrations; a public.waiver_acceptances; n int; v text; t text;
begin
  -- An account that has not signed. Real sign-up goes through GoTrue and
  -- create_my_account; here the rows are made directly, as the seed does.
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values (NEW_ACC, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'newbie@probe.test', 'x', now(), now(), now());
  insert into public.accounts (id, first_name, last_name, email, role) values (NEW_ACC, 'New', 'Player', 'newbie@probe.test', 'member');
  insert into public.players (account_id, kind, first_name, last_name, adult_rating, is_member)
  values (NEW_ACC, 'adult', 'New', 'Player', 3.0, true) returning id into new_p;

  -- 1. The current version is her September 2026 document, and the text is hers.
  insert into _probe_result values ('current_version_is_2026_09', '2026-09', public.waiver_version());
  select title into t from public.current_waiver();
  insert into _probe_result values ('title_is_her_documents', 'Adult Tennis Participation Waiver and Release', t);
  select (body like '%governed by North Carolina law%')::text into v from public.current_waiver();
  insert into _probe_result values ('body_carries_her_nc_law_clause', 'true', v);
  select (body like '%Foxcroft East Racquet and Swim Club%')::text into v from public.current_waiver();
  insert into _probe_result values ('body_names_the_club', 'true', v);

  -- 2. Unsigned: registering is refused with waiver_required (the clinic is open).
  perform set_config('request.jwt.claims', json_build_object('sub', NEW_ACC)::text, true);
  perform set_config('role', 'authenticated', true);
  insert into _probe_result values ('unsigned_status_false', 'false', public.my_waiver_accepted()::text);
  begin
    r := public.register_for_clinic(FAR, new_p);
    insert into _probe_result values ('unsigned_cannot_register', 'waiver_required', 'CALL SUCCEEDED ' || r.status::text);
  exception when others then
    insert into _probe_result values ('unsigned_cannot_register', 'waiver_required', sqlerrm);
  end;

  -- 3. A signature needs a full legal name (her spec: "enters full legal name").
  begin
    a := public.accept_waiver('2026-09', 'X');
    insert into _probe_result values ('one_letter_name_refused', 'legal_name_required', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('one_letter_name_refused', 'legal_name_required', sqlerrm);
  end;
  begin
    a := public.accept_waiver('2026-09', 'Newbie');
    insert into _probe_result values ('single_word_name_refused', 'legal_name_required', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('single_word_name_refused', 'legal_name_required', sqlerrm);
  end;
  -- and the version must be the current one, so a stale sheet cannot sign an old text.
  begin
    a := public.accept_waiver('2025-01', 'New Player');
    insert into _probe_result values ('stale_version_refused', 'waiver_version_stale', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('stale_version_refused', 'waiver_version_stale', sqlerrm);
  end;

  -- 4. Signing records name (trimmed), the ACCOUNT email (not a client value),
  --    the time, the version and the app build.
  a := public.accept_waiver('2026-09', '  New Player  ', '0.1.0 (1)');
  insert into _probe_result values ('signature_row', 'New Player newbie@probe.test 2026-09 0.1.0 (1) true',
    a.legal_name || ' ' || a.email || ' ' || a.version || ' ' || a.app_version || ' ' || (a.accepted_at between now() - interval '1 minute' and now())::text);
  insert into _probe_result values ('signed_status_true', 'true', public.my_waiver_accepted()::text);

  -- 5. Signing twice keeps the first record (a signature is not overwritten).
  a := public.accept_waiver('2026-09', 'Someone Else', 'later');
  insert into _probe_result values ('second_signature_keeps_first', 'New Player 0.1.0 (1)', a.legal_name || ' ' || a.app_version);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.waiver_acceptances where account_id = NEW_ACC;
  insert into _probe_result values ('exactly_one_acceptance_row', '1', n::text);
  perform set_config('role', 'authenticated', true);

  -- 6. Signed: the same registration now goes through.
  r := public.register_for_clinic(FAR, new_p);
  insert into _probe_result values ('signed_can_register', 'true', (r.status in ('in','pool'))::text);
  perform set_config('role', 'postgres', true);

  -- 7. Tara placing an unsigned player by hand is not blocked (paperwork
  --    never blocks Tara), and she can see who has not signed.
  delete from public.waiver_acceptances where account_id = NEW_ACC;
  delete from public.registrations where player_id = new_p;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.register_for_clinic(FAR, new_p);
  insert into _probe_result values ('admin_can_place_unsigned', 'true', (r.status in ('in','pool'))::text);
  select waiver_accepted::text into v from public.search_players('New') where id = new_p;
  insert into _probe_result values ('directory_shows_unsigned', 'false', v);
  select waiver_accepted::text into v from public.search_players('Maria') where id = MARIA_P;
  insert into _probe_result values ('directory_shows_signed', 'true', v);
  perform set_config('role', 'postgres', true);

  -- 8. No client can read or write the tables directly: only the functions.
  insert into _probe_result values ('authenticated_cannot_select_acceptances', 'false',
    has_table_privilege('authenticated', 'public.waiver_acceptances', 'SELECT')::text);
  insert into _probe_result values ('authenticated_cannot_insert_acceptances', 'false',
    has_table_privilege('authenticated', 'public.waiver_acceptances', 'INSERT')::text);
  insert into _probe_result values ('authenticated_cannot_write_waivers', 'false',
    (has_table_privilege('authenticated', 'public.waivers', 'INSERT') or has_table_privilege('authenticated', 'public.waivers', 'UPDATE'))::text);
  insert into _probe_result values ('anon_cannot_read_waivers', 'false',
    has_table_privilege('anon', 'public.waivers', 'SELECT')::text);
  insert into _probe_result values ('anon_cannot_call_accept', 'false',
    has_function_privilege('anon', 'public.accept_waiver(text,text,text)', 'EXECUTE')::text);
  insert into _probe_result values ('signed_out_cannot_sign', 'false',
    has_function_privilege('anon', 'public.accept_waiver(text,text,text)', 'EXECUTE')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
