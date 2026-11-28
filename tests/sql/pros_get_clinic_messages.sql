-- pros_get_clinic_messages.sql
--
-- 20261127000004. Tara, via John, 2026-11-27: "every pro sees every clinic
-- message". Every pro is told of every message Tara sends to a clinic, once,
-- but not an Unpaid one or one on a draft. Not of a cancel (John,
-- 2026-11-27: "drop"). One player's message stays private. A deleted pro is
-- not told.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  PRO     constant uuid := '77777777-7777-7777-7777-777777777777';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  c public.clinics; n int; t text;
begin
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.accounts where id = PRO and role::text = 'pro';
  insert into _probe_result values ('seed_has_the_pro', '1', n::text);

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  c := public.admin_upsert_clinic(null, 'Probe Pro Messages', 'coed',
         now() + interval '2 days', 60, 8, null, null, null, null, null);
  perform public.publish_clinic(c.id);
  perform set_config('role', 'postgres', true);
  insert into public.registrations (clinic_id, player_id, status) values (c.id, MARIA_P, 'in');

  -- Everyone, then You're In! only: the pro is told of each. Unpaid is not
  -- for a pro (decision 0025: a pro never sees money).
  perform set_config('role', 'authenticated', true);
  perform public.send_clinic_message(c.id, 'everyone', 'Probe pro everyone');
  perform public.send_clinic_message(c.id, 'in', 'Probe pro in');
  perform public.send_clinic_message(c.id, 'unpaid', 'Probe pro unpaid');
  perform set_config('role', 'postgres', true);
  select string_agg(body, '|' order by body) into t from public.notifications
   where account_id = PRO and entity_id = c.id and type = 'clinic_message';
  insert into _probe_result values ('the_pro_gets_every_audience_but_unpaid',
    'Probe pro everyone|Probe pro in', coalesce(t, 'NONE'));
  select count(*) into n from public.notifications
   where account_id = MARIA and entity_id = c.id and type = 'clinic_message' and body = 'Probe pro everyone';
  insert into _probe_result values ('players_still_told_once', '1', n::text);

  -- One player's message stays between Tara and that player.
  perform set_config('role', 'authenticated', true);
  perform public.admin_message_player(MARIA_P, 'Probe pro private', c.id);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where account_id = PRO and body = 'Probe pro private';
  insert into _probe_result values ('one_players_message_is_not_for_the_pro', '0', n::text);

  -- A pro who is also on the clinic as a player is told once, not twice.
  insert into public.players (id, account_id, kind, first_name, last_name, adult_rating, is_member, gender)
  select 'a0000000-0000-0000-0000-0000000000e7', PRO, 'adult', 'Probe', 'Pro Player', 4.0, true, 'male'
   where not exists (select 1 from public.players where account_id = PRO and kind = 'adult');
  insert into public.registrations (clinic_id, player_id, status)
  select c.id, id, 'in' from public.players where account_id = PRO and kind = 'adult' limit 1;
  perform set_config('role', 'authenticated', true);
  perform public.send_clinic_message(c.id, 'everyone', 'Probe pro twice');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where account_id = PRO and body = 'Probe pro twice';
  insert into _probe_result values ('a_pro_on_the_clinic_is_told_once', '1', n::text);

  -- The cancel notice is not for a pro who is not on the clinic (John,
  -- 2026-11-27: "drop").
  perform set_config('role', 'authenticated', true);
  c := public.admin_upsert_clinic(null, 'Probe Pro Messages', 'coed',
         now() + interval '3 days', 60, 8, null, null, null, null, null);
  perform public.publish_clinic(c.id);
  perform public.cancel_clinic(c.id, 'Courts are wet');
  perform set_config('role', 'postgres', true);
  select string_agg(body, '|') into t from public.notifications
   where account_id = PRO and entity_id = c.id and type = 'clinic_canceled';
  insert into _probe_result values ('the_pro_gets_no_cancel_notice', 'NONE', coalesce(t, 'NONE'));

  -- A message on a clinic never published reaches no pro.
  perform set_config('role', 'authenticated', true);
  c := public.admin_upsert_clinic(null, 'Probe Pro Draft', 'coed',
         now() + interval '2 days', 60, 8, null, null, null, null, null);
  perform public.send_clinic_message(c.id, 'everyone', 'Probe pro draft');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where account_id = PRO and body = 'Probe pro draft';
  insert into _probe_result values ('a_draft_tells_no_pro', '0', n::text);
  -- And canceling a draft tells no pro either.
  perform set_config('role', 'authenticated', true);
  perform public.cancel_clinic(c.id, 'Probe pro draft cancel');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where account_id = PRO and entity_id = c.id;
  insert into _probe_result values ('canceling_a_draft_tells_no_pro', '0', n::text);

  -- A parent with two children on a clinic is told once per message.
  perform set_config('role', 'authenticated', true);
  c := public.admin_upsert_clinic(null, 'Probe Pro Juniors', 'juniors',
         now() + interval '2 days', 60, 8, null, null, null, null, null);
  perform public.publish_clinic(c.id);
  perform set_config('role', 'postgres', true);
  insert into public.players (id, account_id, kind, first_name, last_name, date_of_birth)
  values ('a0000000-0000-0000-0000-0000000000d1', MARIA, 'junior', 'Probe', 'Kid A', '2015-03-01'),
         ('a0000000-0000-0000-0000-0000000000d2', MARIA, 'junior', 'Probe', 'Kid B', '2017-03-01');
  insert into public.registrations (clinic_id, player_id, status)
  values (c.id, 'a0000000-0000-0000-0000-0000000000d1', 'in'), (c.id, 'a0000000-0000-0000-0000-0000000000d2', 'in');
  perform set_config('role', 'authenticated', true);
  perform public.send_clinic_message(c.id, 'in', 'Probe pro two kids');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where account_id = MARIA and body = 'Probe pro two kids';
  insert into _probe_result values ('a_parent_of_two_is_told_once', '1', n::text);
  select count(*) into n from public.clinic_message_recipients r join public.clinic_messages m on m.id = r.message_id
   where m.body = 'Probe pro two kids';
  insert into _probe_result values ('each_child_is_still_a_recipient', '2', n::text);

  -- A pro on a canceled clinic as a player gets one cancel notice.
  perform set_config('role', 'authenticated', true);
  c := public.admin_upsert_clinic(null, 'Probe Pro Plays', 'coed',
         now() + interval '2 days', 60, 8, null, null, null, null, null);
  perform public.publish_clinic(c.id);
  perform set_config('role', 'postgres', true);
  insert into public.registrations (clinic_id, player_id, status)
  select c.id, id, 'in' from public.players where account_id = PRO and kind = 'adult' limit 1;
  perform set_config('role', 'authenticated', true);
  perform public.cancel_clinic(c.id);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where account_id = PRO and entity_id = c.id and type = 'clinic_canceled';
  insert into _probe_result values ('a_pro_playing_gets_one_cancel_notice', '1', n::text);

  -- A deleted pro is told nothing.
  perform set_config('role', 'authenticated', true);
  c := public.admin_upsert_clinic(null, 'Probe Pro Deleted', 'coed',
         now() + interval '2 days', 60, 8, null, null, null, null, null);
  perform public.publish_clinic(c.id);
  perform set_config('role', 'postgres', true);
  update public.accounts set deleted_at = now() where id = PRO;
  perform set_config('role', 'authenticated', true);
  perform public.send_clinic_message(c.id, 'everyone', 'Probe pro deleted');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where account_id = PRO and body = 'Probe pro deleted';
  insert into _probe_result values ('a_deleted_pro_is_not_told', '0', n::text);
  perform set_config('role', 'authenticated', true);
  perform public.cancel_clinic(c.id, 'Probe pro deleted cancel');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where account_id = PRO and entity_id = c.id and type = 'clinic_canceled';
  insert into _probe_result values ('a_deleted_pro_gets_no_cancel_notice', '0', n::text);
  update public.accounts set deleted_at = null where id = PRO;
end $$;

select check_name,
       case when expected = actual then 'PASS' else 'FAIL' end as result,
       expected, actual
  from _probe_result;

rollback;
