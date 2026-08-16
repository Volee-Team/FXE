-- create_my_account.sql
--
-- Covers the RPC that fixes sign-up (20260815000001), and ATTACKS it.
--
-- This function is unusually dangerous for its size: it is SECURITY DEFINER, it
-- writes to `accounts`, and `accounts.role` is the column that decides who is an
-- administrator of the whole club. Hard rule 8 says a privilege column is never
-- writable by the role it grants privilege to, and hard rule 9 says that where a
-- privilege boundary exists, write a probe that tries to cross it.
--
-- The positive cases matter just as much here. The bug being fixed was NOT a
-- crash: it was silence. Sign-up "succeeded" and left a user with no account, no
-- player, and a Register button that did nothing. So this probe asserts the rows
-- actually exist afterwards, not merely that no exception was raised.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  -- A brand new signed-up user: an auth.users row and nothing else. This is
  -- exactly the state sign-up leaves someone in today.
  NEWBIE     constant uuid := 'c0000000-0000-0000-0000-0000000000a1';
  NEWBIE_EM  constant text := 'newbie@example.test';
  -- A second new user, for the "can I create someone else's account" attack.
  VICTIM     constant uuid := 'c0000000-0000-0000-0000-0000000000a2';
  VICTIM_EM  constant text := 'victim@example.test';
  MARIA_ACC  constant uuid := '22222222-2222-2222-2222-222222222222';
  v_player   uuid;
  v_player2  uuid;
  v_role     text;
  v_email    text;
  v_member   boolean;
  n          int;
begin
  insert into auth.users (id, email, instance_id, aud, role)
  values (NEWBIE, NEWBIE_EM, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
         (VICTIM, VICTIM_EM, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

  -- ---------------------------------------------------------------- baseline
  select count(*) into n from public.accounts where id = NEWBIE;
  insert into _probe_result values ('baseline_newbie_has_no_account', '0', n::text);

  -- ------------------------------------------------- the happy path, asserted
  perform set_config('request.jwt.claims', json_build_object('sub', NEWBIE)::text, true);
  perform set_config('role', 'authenticated', true);

  v_player := public.create_my_account('Sarah', 'Smith', '704-555-0156', true, 3.5);

  perform set_config('role', 'postgres', true);

  insert into _probe_result values ('returns_a_player_id', 'not null',
    case when v_player is null then 'NULL' else 'not null' end);

  select count(*) into n from public.accounts where id = NEWBIE;
  insert into _probe_result values ('account_row_created', '1', n::text);

  select count(*) into n from public.players where account_id = NEWBIE and kind = 'adult';
  insert into _probe_result values ('adult_player_row_created', '1', n::text);

  -- The silent-failure guard: the bug was that these were absent while
  -- everything reported success.
  select is_member into v_member from public.players where id = v_player;
  insert into _probe_result values ('membership_recorded', 'true', v_member::text);

  select adult_rating::text into v_role from public.players where id = v_player;
  insert into _probe_result values ('rating_recorded', '3.5', v_role);

  -- --------------------------------------------------- ATTACK: privilege
  -- No parameter grants a role, so the only assertion that matters is the
  -- resulting value. A member who could arrive as an admin owns the club.
  select role::text into v_role from public.accounts where id = NEWBIE;
  insert into _probe_result values ('new_account_is_a_member_not_admin', 'member', v_role);

  -- ------------------------------------------- ATTACK: email is not client-set
  -- The caller never supplies an email. If one could, they could impersonate.
  select email into v_email from public.accounts where id = NEWBIE;
  insert into _probe_result values ('email_taken_from_auth_not_client', NEWBIE_EM, v_email);

  -- ------------------------------- ATTACK: create an account for someone else
  -- There is deliberately no id parameter. Signed in as NEWBIE, the best an
  -- attacker can do is call it again, which must not touch VICTIM.
  perform set_config('request.jwt.claims', json_build_object('sub', NEWBIE)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.create_my_account('Not', 'Victim', null, true, null);
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);

  select count(*) into n from public.accounts where id = VICTIM;
  insert into _probe_result values ('cannot_create_another_users_account', '0', n::text);

  -- ------------------------------------------------------- ATTACK: anonymous
  -- anon has no auth.uid(), so this must raise rather than create an orphan.
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'anon', true);
  begin
    perform public.create_my_account('Anon', 'Attacker', null, true, null);
    insert into _probe_result values ('anon_cannot_create_an_account', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('anon_cannot_create_an_account', 'blocked', 'blocked');
  end;
  perform set_config('role', 'postgres', true);

  select count(*) into n from public.accounts where first_name = 'Anon';
  insert into _probe_result values ('no_account_created_by_anon', '0', n::text);

  -- ------------------------------------------------------------ idempotency
  -- A retry after a dropped connection must not raise or duplicate.
  perform set_config('request.jwt.claims', json_build_object('sub', NEWBIE)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    v_player2 := public.create_my_account('Sarah', 'Smith', null, false, null);
    insert into _probe_result values ('second_call_does_not_raise', 'ok', 'ok');
  exception when others then
    insert into _probe_result values ('second_call_does_not_raise', 'ok', 'RAISED: ' || sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  insert into _probe_result values ('second_call_returns_same_player',
    coalesce(v_player::text, 'null'), coalesce(v_player2::text, 'null'));

  select count(*) into n from public.players where account_id = NEWBIE;
  insert into _probe_result values ('no_duplicate_player_row', '1', n::text);

  -- A retry must not be able to smuggle in changed values either: the second
  -- call passed is_member => false and it must NOT have downgraded her.
  select is_member into v_member from public.players where id = v_player;
  insert into _probe_result values ('retry_cannot_overwrite_membership', 'true', v_member::text);

  -- --------------------------------------------------------- input validation
  -- Empty names satisfy NOT NULL and are useless in Tara's roster.
  perform set_config('request.jwt.claims', json_build_object('sub', VICTIM)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.create_my_account('   ', 'Smith', null, false, null);
    insert into _probe_result values ('blank_first_name_rejected', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('blank_first_name_rejected', 'blocked', 'blocked');
  end;
  perform set_config('role', 'postgres', true);

  select count(*) into n from public.accounts where id = VICTIM;
  insert into _probe_result values ('blank_name_created_nothing', '0', n::text);

  -- ------------------------------------------------------- the actual point
  -- The whole reason this function exists: after calling it, a new user can
  -- register for a clinic. Before it, Register was a silent no-op.
  perform set_config('request.jwt.claims', json_build_object('sub', NEWBIE)::text, true);
  perform set_config('role', 'authenticated', true);
  insert into _probe_result values ('new_user_owns_their_player', 'true',
    public.owns_player(v_player)::text);
  perform set_config('role', 'postgres', true);

  -- --------------------------------------------------------- grant surface
  select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname = 'create_my_account'
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('anon_has_no_execute_grant', '0', n::text);

  select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname = 'create_my_account'
    and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  insert into _probe_result values ('authenticated_can_execute', '1', n::text);

  -- search_path pinned, like every other SECURITY DEFINER function here.
  select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname = 'create_my_account'
    and p.proconfig is not null
    and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  insert into _probe_result values ('search_path_is_pinned', '1', n::text);

  -- ------------------------------------------------------------ sanity
  -- Existing accounts must be untouched by any of the above.
  select count(*) into n from public.accounts where id = MARIA_ACC;
  insert into _probe_result values ('sanity_existing_account_untouched', '1', n::text);
end $$;

select
  check_name,
  expected,
  actual,
  case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result
order by check_name;

rollback;
