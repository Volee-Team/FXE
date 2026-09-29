-- canceled_drafts.sql
--
-- The rule (found by the laptop-tools builder, 2026-09-28): a clinic a player
-- never saw published must never appear to them, canceled or not. Copy to
-- next week makes drafts, and canceling an unwanted copy is how Tara drops it;
-- before 20260929000001 `clinics_public` listed every canceled clinic, so a
-- draft nobody had seen turned up in the list wearing a Canceled chip. A
-- clinic that WAS published and is then canceled must still show Canceled:
-- a player holding a spot needs to see that.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  draft public.clinics; shown public.clinics; n int; stamped timestamptz;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  -- A draft she cancels without ever publishing it.
  draft := public.admin_upsert_clinic(null, 'Probe Draft Never Shown', 'coed',
             now() + interval '5 days', 60, 8, null, null, null, null, null);
  perform public.cancel_clinic(draft.id);

  -- A clinic she publishes, then cancels.
  shown := public.admin_upsert_clinic(null, 'Probe Shown Then Canceled', 'coed',
             now() + interval '5 days', 60, 8, null, null, null, null, null);
  perform public.publish_clinic(shown.id);

  perform set_config('role', 'postgres', true);
  select published_at into stamped from public.clinics where id = shown.id;
  insert into _probe_result values ('publishing_stamps_published_at', 'stamped', case when stamped is null then 'NULL' else 'stamped' end);
  select count(*) into n from public.clinics where id = draft.id and published_at is null;
  insert into _probe_result values ('a_draft_has_no_published_at', '1', n::text);

  perform set_config('role', 'authenticated', true);
  perform public.cancel_clinic(shown.id);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics where id = shown.id and published_at = stamped;
  insert into _probe_result values ('cancel_keeps_published_at', '1', n::text);

  -- Seed clinics are inserted as published: the insert stamps them too.
  select count(*) into n from public.clinics where status = 'published' and published_at is null;
  insert into _probe_result values ('no_published_clinic_without_stamp', '0', n::text);

  -- As Maria.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.clinics_public where id = draft.id;
  insert into _probe_result values ('canceled_draft_invisible_to_player', '0', n::text);
  select count(*) into n from public.clinics_public where id = shown.id and status = 'canceled';
  insert into _probe_result values ('canceled_published_clinic_still_shown', '1', n::text);

  -- A plain draft stays invisible, as before.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  draft := public.admin_upsert_clinic(null, 'Probe Plain Draft', 'coed',
             now() + interval '5 days', 60, 8, null, null, null, null, null);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.clinics_public where id = draft.id;
  insert into _probe_result values ('plain_draft_invisible_to_player', '0', n::text);

  -- ATTACK: a member cannot stamp published_at themselves.
  begin
    update public.clinics set published_at = now() where id = draft.id;
    get diagnostics n = row_count;
    insert into _probe_result values ('member_cannot_write_published_at', '0', n::text);
  exception when others then
    insert into _probe_result values ('member_cannot_write_published_at', '0', '0');
  end;
  perform set_config('role', 'postgres', true);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
