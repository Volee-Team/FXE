-- cancel_with_message.sql
--
-- Tara's next-update list (2026-11-23):
--   "when canceling, allow me to send a message when I cancel"
--   "when somebody requests to be added to a clinic, the day of and they
--    don't accept the invite, that person should still get notification if
--    the clinic is canceled"
--
-- cancel_clinic(p_clinic, p_message default null):
--   * her message follows the usual notice, and is kept on the clinic's
--     message board (FROM TARA), as a message she sent to everyone;
--   * a player whose late request is still waiting is told too, and that
--     request is closed (declined), so it leaves every Action Needed list;
--   * with no message (or only spaces) the notice reads exactly as before and
--     nothing is posted on the board.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA   constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA  constant uuid := '22222222-2222-2222-2222-222222222222';
  ROB    constant uuid := '44444444-4444-4444-4444-444444444444';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  withmsg public.clinics; plain public.clinics; n int; t text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  withmsg := public.admin_upsert_clinic(null, 'Probe Rained Out', 'coed',
               now() + interval '2 hours', 60, 8, null, null, null, null, null);
  perform public.publish_clinic(withmsg.id);
  plain := public.admin_upsert_clinic(null, 'Probe Canceled Plain', 'coed',
             now() + interval '2 hours', 60, 8, null, null, null, null, null);
  perform public.publish_clinic(plain.id);

  -- Maria is in both; Rob only asked to get in after close.
  perform set_config('role', 'postgres', true);
  insert into public.registrations (clinic_id, player_id, status)
  values (withmsg.id, MARIA_P, 'in'), (plain.id, MARIA_P, 'in');
  insert into public.late_requests (clinic_id, player_id, message)
  values (withmsg.id, ROB_P, 'Can I still come?'), (plain.id, ROB_P, null);

  perform set_config('role', 'authenticated', true);
  perform public.cancel_clinic(withmsg.id, '  Courts are flooded. See you Thursday!  ');
  perform public.cancel_clinic(plain.id, '   ');
  perform set_config('role', 'postgres', true);

  select body into t from public.notifications
   where account_id = MARIA and type = 'clinic_canceled' and entity_id = withmsg.id;
  insert into _probe_result values ('her_message_follows_the_notice',
    'Probe Rained Out has been canceled. Courts are flooded. See you Thursday!', coalesce(t, 'NONE'));

  select count(*) into n from public.notifications
   where account_id = ROB and type = 'clinic_canceled' and entity_id = withmsg.id;
  insert into _probe_result values ('a_waiting_late_request_is_told', '1', n::text);

  select count(*) into n from public.late_requests
   where clinic_id = withmsg.id and status = 'declined' and resolved_at is not null;
  insert into _probe_result values ('the_waiting_request_is_closed', '1', n::text);

  select string_agg(audience::text || ':' || body, '|') into t from public.clinic_messages where clinic_id = withmsg.id;
  insert into _probe_result values ('her_message_is_on_the_board',
    'everyone:Courts are flooded. See you Thursday!', coalesce(t, 'NONE'));

  select body into t from public.notifications
   where account_id = MARIA and type = 'clinic_canceled' and entity_id = plain.id;
  insert into _probe_result values ('blank_message_reads_as_before',
    'Probe Canceled Plain has been canceled.', coalesce(t, 'NONE'));

  select count(*) into n from public.clinic_messages where clinic_id = plain.id;
  insert into _probe_result values ('blank_message_posts_nothing', '0', n::text);

  select count(*) into n from public.notifications
   where account_id = ROB and type = 'clinic_canceled' and entity_id = plain.id;
  insert into _probe_result values ('plain_cancel_tells_the_late_request_too', '1', n::text);

  -- The one-argument call the 1.0.4 app and the website make still works.
  perform set_config('role', 'authenticated', true);
  plain := public.admin_upsert_clinic(null, 'Probe Old Call', 'coed',
             now() + interval '2 hours', 60, 8, null, null, null, null, null);
  perform public.cancel_clinic(plain.id);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics where id = plain.id and status = 'canceled';
  insert into _probe_result values ('one_argument_call_still_cancels', '1', n::text);

  -- Only Tara cancels.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.cancel_clinic(withmsg.id, 'hi');
    t := 'ALLOWED';
  exception when others then
    t := 'REFUSED';
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('a_player_cannot_cancel', 'REFUSED', t);
end $$;

select check_name,
       case when expected = actual then 'PASS' else 'FAIL' end as result,
       expected, actual
  from _probe_result;

rollback;
