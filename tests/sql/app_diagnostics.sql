-- app_diagnostics.sql
--
-- 20261001000001 (decision 0035): crash and hang reports from the phone.
-- The rule, as stated before the function was written:
--
--   * a signed-in member's report lands under HER account (auth.uid(), never
--     a parameter); signed out is refused (not_authenticated);
--   * kind is one of crash, hang, cpu, disk, launch; anything else is refused;
--   * the payload is at most 64 KB of its text form (65536 bytes): 65536
--     lands, 65537 is refused (payload_too_large), by the RPC and by the
--     table itself;
--   * at most 20 rows per account per rolling 24 hours: the 21st is refused
--     (too_many_reports) and does not land; a row older than 24 hours does
--     not count, a row 23 hours old does; another account is unaffected;
--   * no client touches the table: no SELECT/INSERT/UPDATE/DELETE/TRUNCATE
--     for anon or authenticated, and anon cannot call either function;
--   * only an admin reads, newest first, with account_id and no name or email.
--
-- Expected values are worked out by hand from the rule above, not read off
-- the function. A jsonb string of N characters prints as N + 2 bytes (its
-- quotes), which is how the 64 KB boundary is hit exactly.
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

  -- The table is closed to her, whatever the RPC wrote for her.
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

  begin
    perform public.admin_app_diagnostics();
    insert into _probe_result values ('member_cannot_read_reports', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_read_reports', 'not_authorized', sqlerrm);
  end;

  -- ------------------------------------------------ Ken, unaffected by Maria
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin
    perform public.report_app_diagnostic('hang', '0.1.0', '7', '18.6', 'iPhone15,2', '{"ken": 1}');
    insert into _probe_result values ('another_account_still_reports', 'landed', 'landed');
  exception when others then
    insert into _probe_result values ('another_account_still_reports', 'landed', sqlerrm);
  end;

  -- Exactly 64 KB: a 65534-character string prints as 65536 bytes.
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
  -- Maria 2 + 19, Ken 1 + 1 at the boundary = 23.
  select count(*) into n from public.admin_app_diagnostics(500);
  insert into _probe_result values ('admin_sees_every_row', '23', n::text);
  select count(*) into n from public.admin_app_diagnostics(2);
  insert into _probe_result values ('admin_limit_is_honoured', '2', n::text);
  -- Newest first: the 25-hour-old row is last.
  select payload::text into v from public.admin_app_diagnostics(500) offset 22;
  insert into _probe_result values ('admin_reads_newest_first', '{"old": true}', coalesce(v, 'none'));
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------ what landed, as postgres
  select count(*)::text || '|' || count(*) filter (where account_id = MARIA)::text into v
    from public.app_diagnostics where account_id = MARIA and received_at > now() - interval '24 hours';
  insert into _probe_result values ('maria_has_exactly_20_in_window', '20|20', v);
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
end $$;

-- ------------------------------------------------ privileges, by enumeration
insert into _probe_result
select 'no_client_privilege_on_table', '',
       coalesce(string_agg(r || ':' || p, ',' order by r, p), '')
from unnest(array['anon', 'authenticated']) as r
cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) as p
where has_table_privilege(r, 'public.app_diagnostics', p);

insert into _probe_result values ('rls_is_on', 'true',
  (select relrowsecurity::text from pg_class where oid = 'public.app_diagnostics'::regclass));

insert into _probe_result values ('anon_cannot_report', 'false',
  has_function_privilege('anon', 'public.report_app_diagnostic(text, text, text, text, text, jsonb)', 'EXECUTE')::text);
insert into _probe_result values ('anon_cannot_read_reports', 'false',
  has_function_privilege('anon', 'public.admin_app_diagnostics(int)', 'EXECUTE')::text);
insert into _probe_result values ('member_can_report', 'true',
  has_function_privilege('authenticated', 'public.report_app_diagnostic(text, text, text, text, text, jsonb)', 'EXECUTE')::text);

-- The account is never an argument.
insert into _probe_result values ('no_account_parameter', 'p_kind,p_app_version,p_build,p_os_version,p_device,p_payload',
  (select array_to_string(proargnames, ',') from pg_proc
    where oid = 'public.report_app_diagnostic(text, text, text, text, text, jsonb)'::regprocedure));

-- What Tara's read returns: no name, no email, nothing about the person.
insert into _probe_result values ('admin_result_has_no_name_or_email',
  'account_id,app_version,build,device,id,kind,os_version,payload,received_at',
  (select string_agg(a.name, ',' order by a.name)
     from pg_proc p, unnest(p.proargnames, p.proargmodes) as a(name, mode)
    where p.oid = 'public.admin_app_diagnostics(int)'::regprocedure and a.mode = 't'));

-- A hard delete of an account leaves its reports, unattached.
insert into _probe_result values ('account_fk_is_on_delete_set_null', 'n',
  (select confdeltype::text from pg_constraint
    where conrelid = 'public.app_diagnostics'::regclass and contype = 'f'));

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;
rollback;
