-- privilege_escalation.sql
--
-- This probe ATTACKS. Every other probe asserts that the system is in the state
-- we expect; this one tries to move it into a state we do not want.
--
-- Origin: on 2026-08-02 an adversarial review found that an ordinary player
-- could run one statement, `update accounts set role='admin' where id=<self>`,
-- and become an administrator. Reproduced end to end: clinic capacity, every
-- registration in the club, other players' names, their court assignments and
-- their payment status all became readable.
--
-- The existing information_hiding.sql probe was green throughout. It asserted
-- that the player was NOT an admin, then tested what a non-admin can read. It
-- never attempted the transition. THE LESSON: a probe that only tests the state
-- you expect cannot find a transition you did not think of. Where a privilege
-- boundary exists, write a probe that tries to cross it.
--
-- Expected: every row reads PASS, meaning every attack failed.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated;

do $$
declare
  MARIA     constant uuid := 'a0000000-0000-0000-0000-000000000001';
  MARIA_ACC constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN       constant uuid := 'a0000000-0000-0000-0000-000000000002';
  KEN_ACC   constant uuid := '33333333-3333-3333-3333-333333333333';
  TARA_ACC  constant uuid := '11111111-1111-1111-1111-111111111111';
  v_role text;
  v_owner uuid;
  n int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);

  -- Baseline: she is an ordinary member.
  insert into _probe_result values ('baseline_not_admin', 'false', public.is_admin()::text);

  -- ATTACK 1: promote myself to admin. THE original hole.
  begin
    update public.accounts set role = 'admin' where id = MARIA_ACC;
    insert into _probe_result values ('cannot_self_promote', 'blocked', 'UPDATE SUCCEEDED');
  exception when others then
    insert into _probe_result values ('cannot_self_promote', 'blocked', 'blocked');
  end;

  -- Whatever happened above, the role must still be 'member'. This is the
  -- assertion that actually matters: an UPDATE that silently affects zero rows
  -- also "succeeds", so checking the outcome is stronger than checking for an
  -- exception.
  perform set_config('role', 'postgres', true);
  select role::text into v_role from public.accounts where id = MARIA_ACC;
  insert into _probe_result values ('role_still_member_after_attack', 'member', v_role);
  perform set_config('role', 'authenticated', true);

  insert into _probe_result values ('still_not_admin', 'false', public.is_admin()::text);

  -- ATTACK 2: promote someone else (a confederate account).
  begin
    update public.accounts set role = 'admin' where id = KEN_ACC;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select role::text into v_role from public.accounts where id = KEN_ACC;
  insert into _probe_result values ('cannot_promote_another_account', 'member', v_role);
  perform set_config('role', 'authenticated', true);

  -- ATTACK 3: demote the real admin, which would lock Tara out of her own club.
  begin
    update public.accounts set role = 'member' where id = TARA_ACC;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select role::text into v_role from public.accounts where id = TARA_ACC;
  insert into _probe_result values ('cannot_demote_the_admin', 'admin', v_role);
  perform set_config('role', 'authenticated', true);

  -- ATTACK 4: change my own account id to impersonate another account.
  begin
    update public.accounts set id = KEN_ACC where id = MARIA_ACC;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.accounts where id = MARIA_ACC;
  insert into _probe_result values ('account_id_immutable', '1', n::text);
  perform set_config('role', 'authenticated', true);

  -- ATTACK 5: reassign another player to my account, which would let me
  -- register them, read their status, and cancel their spot.
  begin
    update public.players set account_id = MARIA_ACC where id = KEN;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select account_id into v_owner from public.players where id = KEN;
  insert into _probe_result values ('cannot_steal_another_player', KEN_ACC::text, v_owner::text);
  perform set_config('role', 'authenticated', true);

  -- ATTACK 6: move my own player record onto someone else's account.
  begin
    update public.players set account_id = KEN_ACC where id = MARIA;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select account_id into v_owner from public.players where id = MARIA;
  insert into _probe_result values ('cannot_move_own_player_away', MARIA_ACC::text, v_owner::text);
  perform set_config('role', 'authenticated', true);

  -- ATTACK 7: insert a brand new admin account for myself.
  begin
    insert into public.accounts (id, first_name, last_name, email, role)
    values (gen_random_uuid(), 'Evil', 'Admin', 'evil@probe.test', 'admin');
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.accounts where email = 'evil@probe.test';
  insert into _probe_result values ('cannot_insert_admin_account', '0', n::text);
  perform set_config('role', 'authenticated', true);

  -- ATTACK 8: delete the admin account outright.
  begin
    delete from public.accounts where id = TARA_ACC;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.accounts where id = TARA_ACC;
  insert into _probe_result values ('cannot_delete_the_admin', '1', n::text);
  perform set_config('role', 'authenticated', true);

  -- SANITY: legitimate self-service must still work, or we have "fixed" the
  -- hole by breaking the product. A player edits their own phone number.
  begin
    update public.accounts set phone = '704-555-9999' where id = MARIA_ACC;
    insert into _probe_result values ('legitimate_contact_edit_still_works', 'ok', 'ok');
  exception when others then
    insert into _probe_result values ('legitimate_contact_edit_still_works', 'ok', 'BROKEN: ' || sqlerrm);
  end;

  perform set_config('role', 'postgres', true);
end $$;

select
  check_name,
  expected,
  actual,
  case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result
order by check_name;

rollback;
