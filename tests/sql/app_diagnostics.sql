-- app_diagnostics.sql
--
-- 20261014000001 and 20261014000002 (decision 0035): crash and hang reports
-- from the phone. The rule, as stated before the functions were written:
--
--   * a signed-in member's report lands under HER account (auth.uid(), never
--     a parameter); signed out is refused (not_authenticated); a deleted
--     account is refused (account_not_found) and nothing lands;
--   * kind is one of crash, hang, cpu, disk, launch; anything else is refused;
--   * the payload is at most 64 KB of its text form, in BYTES (65536): 65536
--     lands, 65537 is refused (payload_too_large), by the RPC and by the
--     table itself, for multibyte text as for ASCII;
--   * at most 20 rows per account per rolling 24 hours: the 21st is refused
--     (too_many_reports) and does not land; a row older than 24 hours does
--     not count, a row 23 hours old does; another account is unaffected
--     (the race is app_diagnostics_race.sh);
--   * a report is tied to its account for at most a day: the nightly purge
--     unlinks rows older than 24 hours and deletes rows older than 90 days;
--     deleting the account unlinks its rows at once;
--   * no client touches the table: no privilege of any kind for anon or
--     authenticated, column-level included; anon calls neither function;
--   * only an admin reads (not a member, not a pro), newest first, at most
--     500 rows, and the result has no account, name or email.
--
-- Expected values are worked out by hand from the rule above, not read off
-- the function. A jsonb string of N characters prints as its bytes plus 2
-- (the quotes): 'x' is 1 byte, 'é' is 2, which is how the 64 KB boundary
-- is hit exactly.
--
-- The destructive attacks (DELETE, TRUNCATE) run last, in their own block,
-- so a hole there cannot make an earlier check pass on an emptied table.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN   constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB   constant uuid := '44444444-4444-4444-4444-444444444444';
  CASEY constant uuid := '77777777-7777-7777-7777-777777777777';
  ok int := 0; refused text := ''; v text; n int; i int;
begin
  delete from public.app_diagnostics;   -- rolled back; counts below are this probe's

  -- Two rows of Maria's from before: one 25 hours old (outside the window),
  -- one 23 hours old (inside it, so it uses one of her twenty).
  insert into public.app_diagnostics (account_id, received_at, kind, payload) values
    (MARIA, now() - interval '25 hours', 'crash', '{"old": true}'),
    (MARIA, now() - interval '23 hours', 'hang',  '{"recent": true}');

  -- ------------------------------------------------ Maria, signed in
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);

  -- 1 already in the window, so 19 more land and the next one is the 21st.
  for i in 1..19 loop
    begin
      perform public.report_app_diagnostic('crash', '0.1.0', '7', '26.0', 'iPhone17,1', jsonb_build_object('n', i));
      ok := ok + 1;
    exception when others then
      refused := refused || sqlerrm || ';';
    end;
  end loop;
  insert into _probe_result values ('nineteen_more_land_inside_the_window', '19|', ok::text || '|' || refused);

  begin
    perform public.report_app_diagnostic('crash', '0.1.0', '7', '26.0', 'iPhone17,1', '{"n": 21}');
    insert into _probe_result values ('twenty_first_in_24h_is_refused', 'too_many_reports', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('twenty_first_in_24h_is_refused', 'too_many_reports', sqlerrm);
  end;

  -- Read, write and change are closed to her, whatever the RPC wrote for her.
  begin
    perform count(*) from public.app_diagnostics;
    insert into _probe_result values ('member_cannot_select_table', 'permission denied for table app_diagnostics', 'SELECT SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_select_table', 'permission denied for table app_diagnostics', sqlerrm);
  end;
  begin
    insert into public.app_diagnostics (account_id, kind, payload) values (KEN, 'crash', '{}');
    insert into _probe_result values ('member_cannot_insert_table', 'permission denied for table app_diagnostics', 'INSERT SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_insert_table', 'permission denied for table app_diagnostics', sqlerrm);
  end;
  begin
    update public.app_diagnostics set kind = 'hang';
    insert into _probe_result values ('member_cannot_update_table', 'permission denied for table app_diagnostics', 'UPDATE SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_update_table', 'permission denied for table app_diagnostics', sqlerrm);
  end;

  begin
    perform public.admin_app_diagnostics();
    insert into _probe_result values ('member_cannot_read_reports', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_read_reports', 'not_authorized', sqlerrm);
  end;

  -- A pro (decision 0025) runs clinics, not the app: no crash reports.
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin
    perform public.admin_app_diagnostics();
    insert into _probe_result values ('pro_cannot_read_reports', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('pro_cannot_read_reports', 'not_authorized', sqlerrm);
  end;

  -- ------------------------------------------------ Ken, unaffected by Maria
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin
    perform public.report_app_diagnostic('hang', '0.1.0', '7', '18.6', 'iPhone15,2', '{"ken": 1}');
    insert into _probe_result values ('another_account_still_reports', 'landed', 'landed');
  exception when others then
    insert into _probe_result values ('another_account_still_reports', 'landed', sqlerrm);
  end;

  -- Exactly 64 KB: a 65534-character ASCII string prints as 65536 bytes.
  begin
    perform public.report_app_diagnostic('cpu', null, null, null, null, to_jsonb(repeat('x', 65534)));
    insert into _probe_result values ('payload_of_65536_bytes_lands', 'landed', 'landed');
  exception when others then
    insert into _probe_result values ('payload_of_65536_bytes_lands', 'landed', sqlerrm);
  end;
  begin
    perform public.report_app_diagnostic('cpu', null, null, null, null, to_jsonb(repeat('x', 65535)));
    insert into _probe_result values ('payload_of_65537_bytes_refused', 'payload_too_large', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('payload_of_65537_bytes_refused', 'payload_too_large', sqlerrm);
  end;
  -- The cap is bytes, not characters: 32767 'é' are 65534 bytes plus the
  -- quotes, 65536, and land; 32768 are 65538 bytes (only 32770 characters).
  begin
    perform public.report_app_diagnostic('disk', null, null, null, null, to_jsonb(repeat('é', 32767)));
    insert into _probe_result values ('multibyte_65536_bytes_lands', 'landed', 'landed');
  exception when others then
    insert into _probe_result values ('multibyte_65536_bytes_lands', 'landed', sqlerrm);
  end;
  begin
    perform public.report_app_diagnostic('disk', null, null, null, null, to_jsonb(repeat('é', 32768)));
    insert into _probe_result values ('multibyte_65538_bytes_refused', 'payload_too_large', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('multibyte_65538_bytes_refused', 'payload_too_large', sqlerrm);
  end;

  begin
    perform public.report_app_diagnostic('memory', null, null, null, null, '{}');
    insert into _probe_result values ('invalid_kind_refused', 'invalid_kind', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('invalid_kind_refused', 'invalid_kind', sqlerrm);
  end;

  -- ------------------------------------------------ signed out
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.report_app_diagnostic('crash', null, null, null, null, '{}');
    insert into _probe_result values ('signed_out_refused', 'not_authenticated', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('signed_out_refused', 'not_authenticated', sqlerrm);
  end;

  -- ------------------------------------------------ Tara reads
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  -- Maria 2 + 19, Ken 1 + 1 ASCII at the boundary + 1 multibyte = 24.
  select count(*) into n from public.admin_app_diagnostics(500);
  insert into _probe_result values ('admin_sees_every_row', '24', n::text);
  select count(*) into n from public.admin_app_diagnostics(2);
  insert into _probe_result values ('admin_limit_is_honoured', '2', n::text);
  -- Newest first: the 25-hour-old row is last.
  select payload::text into v from public.admin_app_diagnostics(500) offset 23;
  insert into _probe_result values ('admin_reads_newest_first', '{"old": true}', coalesce(v, 'none'));
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------ what landed, as postgres
  select count(*) into n from public.app_diagnostics
   where account_id = MARIA and received_at > now() - interval '24 hours';
  insert into _probe_result values ('maria_has_exactly_20_in_window', '20', n::text);
  select count(*) into n from public.app_diagnostics where payload = '{"n": 21}';
  insert into _probe_result values ('refused_21st_did_not_land', '0', n::text);
  select string_agg(distinct coalesce(account_id::text, 'null'), ',') into v
    from public.app_diagnostics where payload ? 'n';
  insert into _probe_result values ('maria_reports_carry_her_account', MARIA::text, coalesce(v, 'none'));
  select string_agg(coalesce(account_id::text, 'null') || ':' || kind || ':' || coalesce(device, 'null'), ',') into v
    from public.app_diagnostics where payload = '{"ken": 1}';
  insert into _probe_result values ('ken_report_carries_his_account', KEN::text || ':hang:iPhone15,2', coalesce(v, 'none'));
  select count(*) into n from public.app_diagnostics
   where kind = 'memory' or octet_length(payload::text) > 65536;
  insert into _probe_result values ('refused_rows_did_not_land', '0', n::text);

  -- The table refuses an oversize payload by itself, for a future writer
  -- that is not this RPC.
  begin
    insert into public.app_diagnostics (account_id, kind, payload) values (KEN, 'crash', to_jsonb(repeat('x', 65535)));
    insert into _probe_result values ('table_refuses_oversize_payload', 'check_violation', 'INSERT SUCCEEDED');
  exception when check_violation then
    insert into _probe_result values ('table_refuses_oversize_payload', 'check_violation', 'check_violation');
  when others then
    insert into _probe_result values ('table_refuses_oversize_payload', 'check_violation', sqlerrm);
  end;

  -- ------------------------------------------------ the nightly purge
  -- Four rows of Rob's on either side of the two edges: a minute inside and
  -- a minute past 24 hours, a day inside and a day past 90 days.
  insert into public.app_diagnostics (account_id, received_at, kind, payload) values
    (ROB, now() - interval '23 hours 59 minutes', 'crash', '{"purge": "23h59"}'),
    (ROB, now() - interval '24 hours 1 minute',   'crash', '{"purge": "24h01"}'),
    (ROB, now() - interval '89 days',             'crash', '{"purge": "89d"}'),
    (ROB, now() - interval '91 days',             'crash', '{"purge": "91d"}');
  -- Unlinked: Maria's 25h row, Rob's 24h01 and 89d (Maria's 23h row and
  -- Rob's 23h59 stay linked). Deleted: Rob's 91d only.
  select unlinked || '|' || deleted into v from public.purge_app_diagnostics();
  insert into _probe_result values ('purge_unlinks_3_and_deletes_1', '3|1', v);
  select string_agg(payload->>'purge' || ':' || coalesce(account_id::text, 'null'), ',' order by received_at desc) into v
    from public.app_diagnostics where payload ? 'purge';
  insert into _probe_result values ('purge_edges_24h_and_90d',
    '23h59:' || ROB::text || ',24h01:null,89d:null', coalesce(v, 'none'));
  select coalesce(account_id::text, 'null') into v from public.app_diagnostics where payload = '{"recent": true}';
  insert into _probe_result values ('purge_keeps_a_23h_link', MARIA::text, coalesce(v, 'none'));
  select coalesce(account_id::text, 'null') into v from public.app_diagnostics where payload = '{"old": true}';
  insert into _probe_result values ('purge_unlinks_a_25h_row', 'null', coalesce(v, 'none'));
  select unlinked || '|' || deleted into v from public.purge_app_diagnostics();
  insert into _probe_result values ('second_purge_does_nothing', '0|0', v);

  -- ------------------------------------------------ deleted accounts
  -- delete_my_account unlinks the account's rows at once, whatever their age.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform public.delete_my_account();
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.app_diagnostics where account_id = ROB;
  insert into _probe_result values ('delete_my_account_unlinks_reports', '0', n::text);
  select count(*) into n from public.app_diagnostics where payload ? 'purge';
  insert into _probe_result values ('delete_my_account_keeps_the_reports', '3', n::text);

  -- A deleted account cannot report, by any path that set deleted_at.
  update public.accounts set deleted_at = now() where id = KEN;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin
    perform public.report_app_diagnostic('crash', null, null, null, null, '{"deleted": true}');
    insert into _probe_result values ('deleted_account_refused', 'account_not_found', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('deleted_account_refused', 'account_not_found', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.app_diagnostics where payload = '{"deleted": true}';
  insert into _probe_result values ('deleted_account_lands_nothing', '0', n::text);
  select count(*) into n from public.app_diagnostics where account_id = KEN;
  insert into _probe_result values ('deleted_at_unlinks_reports', '0', n::text);

  -- ------------------------------------------------ the 500 cap
  insert into public.app_diagnostics (received_at, kind, payload)
  select now() - interval '2 days', 'launch', '{}' from generate_series(1, 600);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select count(*) into n from public.admin_app_diagnostics(100000);
  insert into _probe_result values ('admin_read_is_at_most_500', '500', n::text);
  perform set_config('role', 'postgres', true);
end $$;

-- ------------------------------------------------ privileges, by enumeration
-- Column-level grants count: has_table_privilege would miss
-- "grant select (payload) on app_diagnostics to authenticated".
insert into _probe_result
select 'no_client_privilege_on_table', '',
       coalesce(string_agg(r || ':' || p, ',' order by r, p), '')
from unnest(array['anon', 'authenticated']) as r
cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'REFERENCES', 'DELETE', 'TRUNCATE', 'TRIGGER']) as p
where case when p in ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES')
           then has_any_column_privilege(r, 'public.app_diagnostics', p)
           else has_table_privilege(r, 'public.app_diagnostics', p) end;

insert into _probe_result values ('rls_is_on', 'true',
  (select relrowsecurity::text from pg_class where oid = 'public.app_diagnostics'::regclass));

insert into _probe_result values ('anon_cannot_report', 'false',
  has_function_privilege('anon', 'public.report_app_diagnostic(text, text, text, text, text, jsonb)', 'EXECUTE')::text);
insert into _probe_result values ('anon_cannot_read_reports', 'false',
  has_function_privilege('anon', 'public.admin_app_diagnostics(int)', 'EXECUTE')::text);
insert into _probe_result values ('member_can_report', 'true',
  has_function_privilege('authenticated', 'public.report_app_diagnostic(text, text, text, text, text, jsonb)', 'EXECUTE')::text);
insert into _probe_result values ('no_client_runs_the_purge', 'false|false',
  has_function_privilege('authenticated', 'public.purge_app_diagnostics()', 'EXECUTE')::text || '|' ||
  has_function_privilege('anon', 'public.purge_app_diagnostics()', 'EXECUTE')::text);

-- The account is never an argument.
insert into _probe_result values ('no_account_parameter', 'p_kind,p_app_version,p_build,p_os_version,p_device,p_payload',
  (select array_to_string(proargnames, ',') from pg_proc
    where oid = 'public.report_app_diagnostic(text, text, text, text, text, jsonb)'::regprocedure));

-- What the admin read returns: no account, no name, no email.
insert into _probe_result values ('admin_result_has_no_account_name_or_email',
  'app_version,build,device,id,kind,os_version,payload,received_at',
  (select string_agg(a.name, ',' order by a.name)
     from pg_proc p, unnest(p.proargnames, p.proargmodes) as a(name, mode)
    where p.oid = 'public.admin_app_diagnostics(int)'::regprocedure and a.mode = 't'));

-- A hard delete of an account leaves its reports, unattached.
insert into _probe_result values ('account_fk_is_on_delete_set_null', 'n',
  (select confdeltype::text from pg_constraint
    where conrelid = 'public.app_diagnostics'::regclass and contype = 'f'));

-- ------------------------------------------------ destructive attacks, last
do $$
declare MARIA constant uuid := '22222222-2222-2222-2222-222222222222'; n int; before int;
begin
  select count(*) into before from public.app_diagnostics;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    delete from public.app_diagnostics;
    insert into _probe_result values ('member_cannot_delete_table', 'permission denied for table app_diagnostics', 'DELETE SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_delete_table', 'permission denied for table app_diagnostics', sqlerrm);
  end;
  begin
    truncate public.app_diagnostics;
    insert into _probe_result values ('member_cannot_truncate_table', 'permission denied for table app_diagnostics', 'TRUNCATE SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_truncate_table', 'permission denied for table app_diagnostics', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.app_diagnostics;
  insert into _probe_result values ('attacks_removed_no_row', before::text, n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;
rollback;
