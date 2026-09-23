-- push_delivery.sql
--
-- Covers 20260923000001 (decision 0008, delivery). Written from the rules, not
-- from the migration:
--   1. "Did Maria get the invitation" is a column: delivered_at and
--      delivery_error exist on notifications.
--   2. Those two are the edge function's, not the player's: authenticated has
--      NO privilege of any kind on them, and still reads the eight columns the
--      app selects (the list in NotificationRepository / web Action Needed).
--   3. Every insert asks for a push: an AFTER INSERT trigger on notifications,
--      whose function no client can call.
--   4. No secrets, no push, no error: with the vault empty an insert succeeds
--      and pg_net's queue does not grow. With both secrets present the same
--      insert queues exactly one request carrying the row id and the secret
--      header. The second half is what proves the first half is not vacuous:
--      a trigger that never fires would also leave the queue alone.
--
-- Expected: every row reads PASS. Runs as postgres, inside a transaction that
-- is rolled back, so the vault secrets it creates never survive.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated;

do $$
declare
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  q0 int; q1 int; n int; v text; nid uuid;
  app_cols constant text[] := array['id','account_id','type','entity_type','entity_id','body','created_at','read_at'];
  c text; p text;
begin
  -- ------------------------------------------------------------- 1. columns
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and table_name = 'notifications'
     and column_name in ('delivered_at', 'delivery_error');
  insert into _probe_result values ('audit_columns_exist', '2', n::text);

  -- ------------------------------------------------------------- 2. grants
  foreach c in array array['delivered_at', 'delivery_error'] loop
    foreach p in array array['SELECT', 'INSERT', 'UPDATE', 'REFERENCES'] loop
      insert into _probe_result values (
        'authenticated_has_no_' || lower(p) || '_on_' || c, 'false',
        has_column_privilege('authenticated', 'public.notifications'::regclass, c, p)::text);
    end loop;
    insert into _probe_result values (
      'anon_has_no_select_on_' || c, 'false',
      has_column_privilege('anon', 'public.notifications'::regclass, c, 'SELECT')::text);
  end loop;

  -- The table-level grant is what would silently cover a new column; it must
  -- be gone, or the column list above means nothing next time.
  insert into _probe_result values ('no_table_level_select_for_authenticated', 'false',
    has_table_privilege('authenticated', 'public.notifications'::regclass, 'SELECT')::text);

  foreach c in array app_cols loop
    insert into _probe_result values ('app_still_reads_' || c, 'true',
      has_column_privilege('authenticated', 'public.notifications'::regclass, c, 'SELECT')::text);
  end loop;
  insert into _probe_result values ('read_at_still_self_writable', 'true',
    has_column_privilege('authenticated', 'public.notifications'::regclass, 'read_at', 'UPDATE')::text);

  -- Attack, not just inspect: Maria asks for her own delivery_error.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    execute 'select count(delivery_error) from public.notifications' into n;
    insert into _probe_result values ('maria_cannot_select_delivery_error', 'denied', 'READ ' || n);
  exception when insufficient_privilege then
    insert into _probe_result values ('maria_cannot_select_delivery_error', 'denied', 'denied');
  end;
  begin
    execute 'update public.notifications set delivered_at = now() where account_id = $1' using MARIA;
    insert into _probe_result values ('maria_cannot_forge_delivered_at', 'denied', 'UPDATED');
  exception when insufficient_privilege then
    insert into _probe_result values ('maria_cannot_forge_delivered_at', 'denied', 'denied');
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', null, true);

  -- ------------------------------------------------------------- 3. trigger
  select string_agg(t.tgname, ',') into v
    from pg_trigger t
   where t.tgrelid = 'public.notifications'::regclass and not t.tgisinternal
     and t.tgfoid = 'public.push_on_notification()'::regprocedure
     and (t.tgtype & 1) = 1      -- ROW
     and (t.tgtype & 2) = 0      -- AFTER (bit 1 set would be BEFORE)
     and (t.tgtype & 4) = 4;     -- INSERT
  insert into _probe_result values ('after_insert_row_trigger_exists', 'push_on_notification', coalesce(v, ''));

  insert into _probe_result values ('anon_cannot_execute_trigger_fn', 'false',
    has_function_privilege('anon', 'public.push_on_notification()', 'EXECUTE')::text);
  insert into _probe_result values ('authenticated_cannot_execute_trigger_fn', 'false',
    has_function_privilege('authenticated', 'public.push_on_notification()', 'EXECUTE')::text);
  select count(*) into n from pg_proc
   where oid = 'public.push_on_notification()'::regprocedure
     and prosecdef and exists (select 1 from unnest(coalesce(proconfig, '{}')) x where x like 'search_path=%');
  insert into _probe_result values ('trigger_fn_definer_with_pinned_search_path', '1', n::text);

  -- ------------------------------------------------------------- 4. behaviour
  select count(*) into n from pg_extension where extname = 'pg_net';
  insert into _probe_result values ('pg_net_installed', '1', n::text);

  -- 4a. Vault empty (as in every environment until Alex runs the two lines).
  delete from vault.secrets where name in ('push_function_url', 'push_webhook_secret');
  select count(*) into q0 from net.http_request_queue;
  begin
    perform public.notify_account(MARIA, 'probe_push', null, null, 'probe: no secrets');
    insert into _probe_result values ('insert_succeeds_without_secrets', 'ok', 'ok');
  exception when others then
    insert into _probe_result values ('insert_succeeds_without_secrets', 'ok', sqlerrm);
  end;
  select count(*) into q1 from net.http_request_queue;
  insert into _probe_result values ('no_secrets_queues_nothing', '0', (q1 - q0)::text);

  -- 4b. Only one of the two secrets: still nothing.
  perform vault.create_secret('http://probe.invalid/functions/v1/push', 'push_function_url');
  perform public.notify_account(MARIA, 'probe_push', null, null, 'probe: url only');
  select count(*) into q1 from net.http_request_queue;
  insert into _probe_result values ('url_without_secret_queues_nothing', '0', (q1 - q0)::text);

  -- 4c. Both secrets: exactly one queued request, for this row, with the header.
  perform vault.create_secret('probe-secret-not-real', 'push_webhook_secret');
  insert into public.notifications (account_id, type, body)
  values (MARIA, 'probe_push', 'probe: both secrets') returning id into nid;
  select count(*) into q1 from net.http_request_queue;
  insert into _probe_result values ('both_secrets_queue_one_request', '1', (q1 - q0)::text);

  select q.url || ' ' || (q.headers ->> 'X-Push-Secret') || ' ' || (convert_from(q.body, 'UTF8')::jsonb ->> 'notification_id')
    into v
    from net.http_request_queue q order by q.id desc limit 1;
  insert into _probe_result values ('queued_request_is_for_this_row',
    'http://probe.invalid/functions/v1/push probe-secret-not-real ' || nid::text, coalesce(v, ''));
end $$;

do $$ begin
  if not exists (select 1 from _probe_result) then raise exception 'push_delivery: no checks ran'; end if;
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
