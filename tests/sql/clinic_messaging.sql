-- clinic_messaging.sql
--
-- Decision 0005 (Tara, 2026-08-12) and decision 12 (2026-08-02): a clinic
-- message goes to You're In!, the Player Pool, or everyone, and is visible
-- ONLY to the group it was sent to. Hidden fact 4 in hard rule 1 is the
-- neighbour of this rule: a player must not learn who else is in a clinic
-- from which messages they can see. Until 2026-09-21 no probe sent a
-- targeted message and asked a non-recipient to read it (hard rule 9).
--
-- Expected values come from the decision text, not from the view.
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

-- What each account can see through the player view, as a sorted list of
-- message bodies in brackets, so an assertion is the whole answer, not one
-- row, and the harness's substring rule (letters in the expected value)
-- cannot pass a longer list that merely contains the expected one.
create function pg_temp.seen(acct uuid) returns text language plpgsql as $f$
declare out text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', acct)::text, true);
  perform set_config('role', 'authenticated', true);
  select '[' || coalesce(string_agg(body, ' | ' order by body), '') || ']' into out from public.my_clinic_messages;
  perform set_config('role', 'postgres', true);
  return out;
end $f$;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  DANA    constant uuid := '66666666-6666-6666-6666-666666666666';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  FAR     constant uuid := 'd0000000-0000-0000-0000-000000000002';
  OTHER   constant uuid := 'd0000000-0000-0000-0000-000000000001';
  msg_in uuid; msg_pool uuid; msg_all uuid; msg_other uuid; n int;
begin
  -- Fixtures: Maria In, Ken in the Pool, Rob canceled, Dana not registered.
  delete from public.registrations where clinic_id in (FAR, OTHER);
  delete from public.clinic_messages where clinic_id in (FAR, OTHER);   -- leftovers from a UI run must not count
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes) values
    (FAR, MARIA_P, 'in',       'self', 1800, true,  60),
    (FAR, KEN_P,   'pool',     'self', 1800, true,  60),
    (FAR, ROB_P,   'canceled', 'self', 2300, false, 60),
    (OTHER, ROB_P, 'in',       'self', 2300, false, 60);

  -- 1. Only Tara sends.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    msg_in := (public.send_clinic_message(FAR, 'in', 'Maria trying')).id;
    insert into _probe_result values ('member_cannot_send', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_send', 'blocked', 'blocked');
  end;
  perform set_config('role', 'postgres', true);

  -- Tara sends one to each audience, and one to a clinic Maria is not in.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  msg_in    := (public.send_clinic_message(FAR, 'in',       'Courts 1 and 2 tonight')).id;
  msg_pool  := (public.send_clinic_message(FAR, 'pool',     'Two spots may open')).id;
  msg_all   := (public.send_clinic_message(FAR, 'everyone', 'Rain check at 5')).id;
  msg_other := (public.send_clinic_message(OTHER, 'everyone', 'Tuesday moved indoors')).id;
  perform set_config('role', 'postgres', true);

  -- 2. Each group sees exactly its own messages plus everyone's.
  insert into _probe_result values ('youre_in_sees_in_and_everyone',
    '[Courts 1 and 2 tonight | Rain check at 5]', pg_temp.seen(MARIA));
  insert into _probe_result values ('pool_sees_pool_and_everyone',
    '[Rain check at 5 | Two spots may open]', pg_temp.seen(KEN));
  -- Rob canceled FAR: nothing from it, but his other clinic's message.
  insert into _probe_result values ('canceled_sees_nothing_from_that_clinic',
    '[Tuesday moved indoors]', pg_temp.seen(ROB));
  insert into _probe_result values ('unregistered_sees_nothing', '[]', pg_temp.seen(DANA));

  -- 3. The recipients table is the truth for targeted messages, and it holds
  --    no row for the untargeted one.
  select count(*) into n from public.clinic_message_recipients where message_id = msg_in;
  insert into _probe_result values ('in_message_has_one_recipient', '1', n::text);
  select count(*) into n from public.clinic_message_recipients where message_id = msg_pool and player_id = KEN_P;
  insert into _probe_result values ('pool_message_targets_ken', '1', n::text);
  select count(*) into n from public.clinic_message_recipients where message_id = msg_all;
  insert into _probe_result values ('everyone_message_has_no_recipient_rows', '0', n::text);

  -- 4. A recipient list is not readable by a player (it would name others).
  insert into _probe_result values ('recipients_table_hidden_from_players', 'false',
    has_table_privilege('authenticated', 'public.clinic_message_recipients', 'SELECT')::text);
  insert into _probe_result values ('messages_table_hidden_from_players', 'false',
    has_table_privilege('authenticated', 'public.clinic_messages', 'SELECT')::text);
  insert into _probe_result values ('anon_cannot_read_the_view', 'false',
    has_table_privilege('anon', 'public.my_clinic_messages', 'SELECT')::text);

  -- 5. Each recipient was told once; a non-recipient was not told.
  select count(*) into n from public.notifications where account_id = MARIA and body like '%Courts 1 and 2%';
  insert into _probe_result values ('maria_notified_of_in_message', '1', n::text);
  select count(*) into n from public.notifications where account_id = KEN and body like '%Courts 1 and 2%';
  insert into _probe_result values ('ken_not_notified_of_in_message', '0', n::text);
  select count(*) into n from public.notifications where account_id = ROB and body like '%Rain check%';
  insert into _probe_result values ('canceled_rob_not_notified_of_everyone', '0', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
