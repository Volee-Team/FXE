-- app_link_visits.sql
--
-- 20260929000005 (decision 0031): the app link's open count. The rule:
-- one row per New York day and source, 'qr' only when the code says so and
-- 'link' for anything else; only the edge function (service_role) writes;
-- only Tara reads; nothing about the visitor exists to leak.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  v text; n int;
begin
  delete from public.app_link_visits;   -- rolled back; the count below is the fixture's
  perform public.record_app_link_visit('qr');
  perform public.record_app_link_visit('qr');
  perform public.record_app_link_visit('link');
  perform public.record_app_link_visit('anything else');   -- counts as a plain link
  perform public.record_app_link_visit(null);

  select string_agg(via || ':' || visits, ',' order by via) into v from public.app_link_visits
   where day = (now() at time zone 'America/New_York')::date;
  insert into _probe_result values ('today_counts_qr_and_link', 'link:3,qr:2', coalesce(v, 'none'));
  select count(*) into n from information_schema.columns
   where table_schema = 'public' and table_name = 'app_link_visits';
  insert into _probe_result values ('only_day_via_visits_are_stored', '3', n::text);

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select sum(visits)::text into v from public.admin_app_link_visits();
  insert into _probe_result values ('tara_reads_the_totals', '5', v);

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.admin_app_link_visits();
    insert into _probe_result values ('member_cannot_read_visits', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_read_visits', 'not_authorized', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  insert into _probe_result values ('authenticated_cannot_record', 'false',
    has_function_privilege('authenticated', 'public.record_app_link_visit(text)', 'EXECUTE')::text);
  insert into _probe_result values ('anon_cannot_record_directly', 'false',
    has_function_privilege('anon', 'public.record_app_link_visit(text)', 'EXECUTE')::text);
  insert into _probe_result values ('service_role_records', 'true',
    has_function_privilege('service_role', 'public.record_app_link_visit(text)', 'EXECUTE')::text);
  insert into _probe_result values ('no_client_reads_the_table', 'false|false',
    has_table_privilege('authenticated', 'public.app_link_visits', 'SELECT')::text || '|' ||
    has_table_privilege('anon', 'public.app_link_visits', 'SELECT')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;
rollback;
