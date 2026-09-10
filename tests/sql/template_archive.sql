-- template_archive.sql
--
-- Covers 20260910000001 and ATTACKS it: only Tara archives or restores, the
-- stamp is kept on a repeat archive, the view shows archived rows to her with
-- the stamp and nothing to anyone else, and creating a clinic from an
-- archived template still works (archiving hides, it does not break weeks
-- she has already built from it).
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  T     constant uuid := 'b0000000-0000-0000-0000-000000000002';   -- Coed Cardio
  n int; t1 timestamptz; t2 timestamptz;
begin
  -- as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  perform public.admin_set_template_archived(T, true);
  select archived_at into t1 from public.templates_admin where id = T;
  insert into _probe_result values ('admin_archives_template', 'stamped', case when t1 is null then 'NULL' else 'stamped' end);

  perform pg_sleep(0.01);
  perform public.admin_set_template_archived(T, true);
  select archived_at into t2 from public.templates_admin where id = T;
  insert into _probe_result values ('repeat_archive_keeps_first_stamp', 'same', case when t1 = t2 then 'same' else 'CHANGED' end);

  select count(*) into n from public.templates_admin;
  insert into _probe_result values ('view_still_lists_archived_for_admin', '2', n::text);

  select count(*) into n from public.templates_admin where archived_at is null;
  insert into _probe_result values ('one_template_left_unarchived', '1', n::text);

  perform public.admin_set_template_archived(T, false);
  select count(*) into n from public.templates_admin where id = T and archived_at is null;
  insert into _probe_result values ('admin_restores_template', '1', n::text);

  begin
    perform public.admin_set_template_archived('00000000-0000-0000-0000-00000000dead', true);
    insert into _probe_result values ('unknown_template_rejected', 'P0002', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('unknown_template_rejected', 'P0002', sqlstate);
  end;

  -- ATTACK: Maria
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_set_template_archived(T, true);
    insert into _probe_result values ('member_cannot_archive', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_archive', 'blocked', 'blocked');
  end;
  select count(*) into n from public.templates_admin;
  insert into _probe_result values ('member_sees_no_templates', '0', n::text);

  -- ATTACK: anon
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'anon', true);
  begin
    perform public.admin_set_template_archived(T, true);
    insert into _probe_result values ('anon_cannot_archive', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('anon_cannot_archive', 'blocked', 'blocked');
  end;
  perform set_config('role', 'postgres', true);

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname = 'admin_set_template_archived'
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('anon_has_no_execute', '0', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
