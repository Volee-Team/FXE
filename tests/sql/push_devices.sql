-- push_devices.sql
--
-- Covers 20260902000003 (register_device / unregister_device) and ATTACKS it.
-- A device token is the address a push goes to; if another account could
-- read or overwrite yours, they could read your invitations. So the checks
-- that matter are: nobody but the owner can see a token, the account is never
-- a parameter, and re-registering is idempotent.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  ROB   constant uuid := '44444444-4444-4444-4444-444444444444';
  n int;
  v text;
begin
  -- ------------------------------------------------------------- as Maria
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);

  perform public.register_device('  tok-maria-1  ');
  perform public.register_device('tok-maria-1');          -- same token again
  perform public.register_device('tok-maria-2', 'ios');   -- a second phone

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.devices where account_id = MARIA;
  insert into _probe_result values ('register_is_idempotent_and_trimmed', '2', n::text);
  select platform into v from public.devices where account_id = MARIA and apns_token = 'tok-maria-1';
  insert into _probe_result values ('platform_defaults_to_ios', 'ios', v);

  -- Maria cannot read the table directly, even her own row (RPC-only surface).
  perform set_config('role', 'authenticated', true);
  begin
    execute 'select count(*) from public.devices' into n;
    insert into _probe_result values ('owner_cannot_select_devices_table', 'denied', 'READ ' || n);
  exception when insufficient_privilege then
    insert into _probe_result values ('owner_cannot_select_devices_table', 'denied', 'denied');
  end;

  begin
    execute 'insert into public.devices (account_id, apns_token) values ($1, $2)' using ROB, 'planted';
    insert into _probe_result values ('cannot_insert_devices_directly', 'denied', 'INSERTED');
  exception when insufficient_privilege then
    insert into _probe_result values ('cannot_insert_devices_directly', 'denied', 'denied');
  end;

  begin
    perform public.register_device('   ');
    insert into _probe_result values ('blank_token_rejected', '22023', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('blank_token_rejected', '22023', sqlstate);
  end;

  -- --------------------------------------------------------- ATTACK: Rob
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  -- Rob registering Maria's token string gets HIS OWN row, not hers.
  perform public.register_device('tok-maria-1');
  -- Rob unregistering that string removes only his.
  perform public.unregister_device('tok-maria-1');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.devices where account_id = MARIA and apns_token = 'tok-maria-1';
  insert into _probe_result values ('unregister_cannot_touch_another_account', '1', n::text);
  select count(*) into n from public.devices where account_id = ROB;
  insert into _probe_result values ('rob_left_no_rows', '0', n::text);

  -- ------------------------------------------------------- owner removes
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.unregister_device('tok-maria-2');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.devices where account_id = MARIA;
  insert into _probe_result values ('owner_unregisters_one_token', '1', n::text);

  -- ------------------------------------------------------- ATTACK: anon
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'anon', true);
  begin
    perform public.register_device('anon-tok');
    insert into _probe_result values ('anon_cannot_register', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('anon_cannot_register', 'blocked', 'blocked');
  end;
  perform set_config('role', 'postgres', true);

  -- ---------------------------------------------------------- grants
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname in ('register_device', 'unregister_device')
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('anon_has_no_execute', '0', n::text);
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname in ('register_device', 'unregister_device')
    and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  insert into _probe_result values ('search_path_pinned', '2', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
