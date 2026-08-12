-- information_hiding.sql
--
-- THE SAFETY-CRITICAL PROBE FOR THIS APP.
--
-- The Developer Guide hides nine things from players: clinic capacity, number
-- registered, spots remaining, Player Pool size, other players' names, court
-- assignments, other players' payment status, private coaching notes, and
-- clinic location. Hiding those in SwiftUI hides nothing: anyone with a network
-- proxy reads the raw response.
--
-- This probe authenticates as an ordinary player (Maria, a member with no admin
-- role) and asserts she cannot reach any of it. If a future migration adds a
-- convenience view, relaxes a grant, or "helpfully" exposes a count, this goes
-- red.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
-- The probe switches role to `authenticated` partway through, so it needs to be
-- able to record its own findings from inside that role.
grant all on _probe_result to authenticated;

do $$
declare
  MARIA     constant uuid := 'a0000000-0000-0000-0000-000000000001';
  MARIA_ACC constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN       constant uuid := 'a0000000-0000-0000-0000-000000000002';
  KEN_ACC   constant uuid := '33333333-3333-3333-3333-333333333333';
  c uuid;
  ken_reg uuid;
  n int;
begin
  -- A clinic both players are in, with a court assigned and a payment recorded.
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('Hidden Info Probe', 'coed', now() + interval '3 days', now() + interval '3 days 1 hour',
      now() - interval '1 hour', now() + interval '12 hours', 6, 'published')
  returning id into c;

  insert into public.registrations (clinic_id, player_id, status, paid, court_number)
  values (c, MARIA, 'in', false, 2),
         (c, KEN,   'in', true,  3);

  -- Resolve Ken's registration id while still privileged. If the probe looked
  -- it up after dropping to `authenticated`, the subquery itself would fail on
  -- table permissions and the RPC's own authorization guard would never run,
  -- which would test the wrong thing.
  select id into ken_reg from public.registrations
   where clinic_id = c and player_id = KEN;

  -- Become Maria: an ordinary authenticated member, not an admin.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);

  -- 1. is_admin() must be false for her, or every other check is meaningless.
  insert into _probe_result values ('maria_is_not_admin', 'false', public.is_admin()::text);

  -- 2. The clinics table itself must be unreachable. internal_capacity lives
  --    there, and so does anything location-shaped.
  begin
    execute 'select count(*) from public.clinics' into n;
    insert into _probe_result values ('cannot_read_clinics_table', 'denied', 'READ ' || n || ' ROWS');
  exception when insufficient_privilege then
    insert into _probe_result values ('cannot_read_clinics_table', 'denied', 'denied');
  end;

  -- 3. The public view must not expose capacity as a column at all.
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and table_name = 'clinics_public'
     and column_name in ('internal_capacity', 'location', 'address');
  insert into _probe_result values ('clinics_public_hides_capacity_and_location', '0', n::text);

  -- 3b. But it MUST expose both published rates and the length, so the app can
  --     show "60 min · $18". A rate sheet is not secret; a headcount is.
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and table_name = 'clinics_public'
     and column_name in ('member_price_cents', 'nonmember_price_cents', 'duration_minutes');
  insert into _probe_result values ('clinics_public_exposes_both_rates', '3', n::text);

  -- 4. The registrations table itself must be unreachable.
  begin
    execute 'select count(*) from public.registrations' into n;
    insert into _probe_result values ('cannot_read_registrations_table', 'denied', 'READ ' || n || ' ROWS');
  exception when insufficient_privilege then
    insert into _probe_result values ('cannot_read_registrations_table', 'denied', 'denied');
  end;

  -- 5. Through her own view she sees exactly one row: her own. Not Ken's.
  select count(*) into n from public.my_registrations where clinic_id = c;
  insert into _probe_result values ('sees_only_own_registration', '1', n::text);

  select count(*) into n from public.my_registrations
   where clinic_id = c and player_id = KEN;
  insert into _probe_result values ('cannot_see_other_players_registration', '0', n::text);

  -- 6. Court number must not be a column on her view. Courts are admin-only.
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and table_name = 'my_registrations'
     and column_name = 'court_number';
  insert into _probe_result values ('my_registrations_hides_court_number', '0', n::text);

  -- 7. Private coaching notes must be unreachable, including her own.
  begin
    execute 'select count(*) from public.player_notes' into n;
    insert into _probe_result values ('cannot_read_player_notes', 'denied', 'READ ' || n || ' ROWS');
  exception when insufficient_privilege then
    insert into _probe_result values ('cannot_read_player_notes', 'denied', 'denied');
  end;

  -- 8. The admin views must return nothing for a non-admin. Zero rows rather
  --    than an error keeps client code simple, but zero is the requirement.
  select count(*) into n from public.clinics_admin;
  insert into _probe_result values ('clinics_admin_empty_for_player', '0', n::text);

  select count(*) into n from public.registrations_admin;
  insert into _probe_result values ('registrations_admin_empty_for_player', '0', n::text);

  -- 9. She must not be able to see other players at all. The roster is hidden.
  select count(*) into n from public.players where id = KEN;
  insert into _probe_result values ('cannot_see_other_player_record', '0', n::text);

  -- 10. Admin-only RPCs must refuse her, not silently work.
  begin
    perform public.search_players('a');
    insert into _probe_result values ('search_players_denied', 'not_authorized', 'ALLOWED');
  exception when others then
    insert into _probe_result values ('search_players_denied', 'not_authorized', sqlerrm);
  end;

  begin
    perform public.set_paid(ken_reg, true);
    insert into _probe_result values ('set_paid_denied', 'not_authorized', 'ALLOWED');
  exception when others then
    insert into _probe_result values ('set_paid_denied', 'not_authorized', sqlerrm);
  end;

  begin
    perform public.invite_from_pool(ken_reg);
    insert into _probe_result values ('invite_from_pool_denied', 'not_authorized', 'ALLOWED');
  exception when others then
    insert into _probe_result values ('invite_from_pool_denied', 'not_authorized', sqlerrm);
  end;

  perform set_config('role', 'postgres', true);

  -- 11. Internal plumbing must not be callable by a client at all. A player who
  --     could call notify_account could fabricate a push notification from Tara.
  --
  --     This asserts the ACL rather than calling the function and catching the
  --     error. That is deliberate and it is the better test: it is deterministic,
  --     and it does not depend on how the server reports a denial. It also
  --     dodges a real defect in the LOCAL Supabase dev image, where pgaudit
  --     segfaults the backend on any EXECUTE-denied call (reproduced 2026-07-28
  --     with a two-line throwaway function; not a defect in this schema, and it
  --     does not affect the correctness of the permission itself).
  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('notify_account', 'admin_account_ids')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  insert into _probe_result values ('internal_functions_not_client_callable', '0', n::text);

  -- 12. The gated RPCs must be callable (they check is_admin() internally);
  --     if the grant were missing, admins would be broken instead of players.
  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('register_for_clinic', 'set_paid', 'invite_from_pool')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  insert into _probe_result values ('gated_rpcs_are_callable', '3', n::text);

  -- 13. CLINIC LOCATION, decision 10, and the reason matters.
  --
  --     Tara confirmed location stays hidden, and gave the reason: FXE is a
  --     member club and must not read as open to non-members. So this is not
  --     "one less column on one view", it is a rule about the whole
  --     player-facing surface, and it has to be asserted that way. Checking
  --     clinics_public alone (check 3 above) would miss a location added to
  --     my_registrations, to a new view, or to app_settings.
  --
  --     Scope: every relation `authenticated` can SELECT, minus the two
  --     is_admin()-gated admin views. Those are excluded on purpose: they are
  --     not player-facing, and pre-emptively banning an admin-only field is a
  --     rule Tara did not state. Check 14 covers them anyway today.
  select count(*) into n
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name not in ('clinics_admin', 'registrations_admin')
     and c.table_name in (
       select g.table_name from information_schema.role_table_grants g
        where g.table_schema = 'public'
          and g.grantee = 'authenticated'
          and g.privilege_type = 'SELECT'
     )
     and c.column_name ~* '(location|address|venue|map|directions|latitude|longitude|geo)';
  insert into _probe_result values ('no_location_column_player_facing', '0', n::text);

  -- 14. And nothing location-shaped on the clinics table at all, which is where
  --     it would be added first and where every clinic view draws from.
  select count(*) into n
    from information_schema.columns
   where table_schema = 'public' and table_name = 'clinics'
     and column_name ~* '(location|address|venue|map|directions|latitude|longitude|geo)';
  insert into _probe_result values ('no_location_column_on_clinics', '0', n::text);

  -- 15. app_settings is readable by every authenticated user, which makes it a
  --     tempting place to park "the club address" for a header. It is not one.
  --     No location-shaped key, and no link of any kind: a maps URL is a
  --     location wearing a different hat.
  select count(*) into n from public.app_settings
   where key ~* '(location|address|venue|map|directions)'
      or value ~* '(https?://|maps\.|directions)';
  insert into _probe_result values ('app_settings_carries_no_location', '0', n::text);
end $$;

select
  check_name,
  expected,
  actual,
  case
    when actual = expected then 'PASS'
    -- Substring matching exists for checks whose `actual` is a server error
    -- message wrapping the expected error name. It is deliberately NOT allowed
    -- for numeric expectations. The original comparison used
    -- `actual like '%' || expected || '%'`, under which an actual count of 105
    -- PASSED against an expected 0, because "105" contains "0". That silently
    -- greened a real assertion failure. LIKE also treated `_` in an expected
    -- error name as a wildcard, so strpos is used instead.
    when expected ~ '[A-Za-z]' and strpos(actual, expected) > 0 then 'PASS'
    else 'FAIL'
  end as result
from _probe_result
order by check_name;

rollback;
