-- calendar_feed.sql
--
-- Covers 20260929000003 (decision 0029): a player's clinics as a subscribed
-- calendar. Written from the rule, not from the code:
--
--   * the token is the credential, so no client role touches the table, the
--     account is never a parameter, and one account cannot read, reset or
--     reach another's token;
--   * the same token comes back until a reset, and a reset kills the old one;
--   * a deleted account gets nothing, and delete_my_account() takes the token
--     away;
--   * the feed is this account's You're In! and Response Needed registrations
--     in published clinics that ended at most 30 days ago, and nothing else:
--     not the Player Pool, not a spot given up, not a canceled or draft
--     clinic, not someone else's clinic; name, start, end and status only, so
--     no location (decision 10) and no court (decision 17) can reach it.
--
-- The expected feeds below were worked out by hand from the seed (Maria holds
-- one registration, e0000000-...-0001, Response Needed in Evening Coed) plus
-- the fixture clinics this file adds, listed in start order.
--
-- Function ACLs are asserted with has_function_privilege, never by calling as
-- a role without EXECUTE (the local image segfaults on that; CLAUDE.md).
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon, service_role;

-- A feed as one line, "name|status, ..." in start order (with the
-- registration id when asked), read as whoever calls it. It never raises: a
-- feed that fails reads "ERROR <message>", so a broken rule turns the rows
-- that name it red instead of aborting the whole block. Temporary: gone at
-- the rollback.
create function pg_temp.feed_of(p_token text, p_with_id boolean default false, p_future_only boolean default false)
returns text language plpgsql as $f$
declare v text;
begin
  select string_agg(e.clinic_name || '|' || e.status || case when p_with_id then '|' || e.registration_id else '' end,
                    ', ' order by e.starts_at) into v
    from public.calendar_feed_events(p_token) e
   where not p_future_only or e.starts_at > now();
  return coalesce(v, '');
exception when others then
  return 'ERROR ' || sqlerrm;
end $f$;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  DANA    constant uuid := '66666666-6666-6666-6666-666666666666';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  INVITE  constant uuid := 'e0000000-0000-0000-0000-000000000001';  -- seed: Maria, Response Needed, Evening Coed
  -- Fixture clinics, one per case of the rule.
  C_IN     constant uuid := 'cf000000-0000-0000-0000-000000000001';
  C_POOL   constant uuid := 'cf000000-0000-0000-0000-000000000002';
  C_GAVEUP constant uuid := 'cf000000-0000-0000-0000-000000000003';
  C_CANCEL constant uuid := 'cf000000-0000-0000-0000-000000000004';
  C_DRAFT  constant uuid := 'cf000000-0000-0000-0000-000000000005';
  C_RECENT constant uuid := 'cf000000-0000-0000-0000-000000000006';
  C_EDGE   constant uuid := 'cf000000-0000-0000-0000-000000000007';
  C_OLD    constant uuid := 'cf000000-0000-0000-0000-000000000008';
  C_ROB    constant uuid := 'cf000000-0000-0000-0000-000000000009';
  C_TARA   constant uuid := 'cf000000-0000-0000-0000-00000000000a';
  R_IN     constant uuid := 'cf100000-0000-0000-0000-000000000001';
  R_TARA   constant uuid := 'cf100000-0000-0000-0000-00000000000a';
  GHOST    constant uuid := 'cf200000-0000-0000-0000-000000000001';
  t1 text; t2 text; t3 text; t4 text; rob_t text; ken_t text; dana_t text;
  n int; v text;
begin
  -- ------------------------------------------------------------- fixture
  -- As postgres. Clinic times are relative to now(), which is one instant for
  -- the whole transaction, so the 30-day edge below is exact.
  insert into public.clinics (id, name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes) values
    (C_IN,     'Feed In',       'coed', 'Clinic', 'probe', now() + interval '2 days',  now() + interval '2 days 1 hour',  now() - interval '9 days', now() - interval '8 days', 8, 'published', 60),
    (C_POOL,   'Feed Pool',     'coed', 'Clinic', 'probe', now() + interval '4 days',  now() + interval '4 days 1 hour',  now() - interval '9 days', now() - interval '8 days', 8, 'published', 60),
    (C_GAVEUP, 'Feed Gave Up',  'coed', 'Clinic', 'probe', now() + interval '5 days',  now() + interval '5 days 1 hour',  now() - interval '9 days', now() - interval '8 days', 8, 'published', 60),
    (C_CANCEL, 'Feed Canceled', 'coed', 'Clinic', 'probe', now() + interval '6 days',  now() + interval '6 days 1 hour',  now() - interval '9 days', now() - interval '8 days', 8, 'canceled',  60),
    (C_DRAFT,  'Feed Draft',    'coed', 'Clinic', 'probe', now() + interval '7 days',  now() + interval '7 days 1 hour',  now() - interval '9 days', now() - interval '8 days', 8, 'draft',     60),
    -- Ended 29 days ago: history, kept.
    (C_RECENT, 'Feed Recent',   'coed', 'Clinic', 'probe', now() - interval '29 days 1 hour', now() - interval '29 days', now() - interval '40 days', now() - interval '39 days', 8, 'published', 60),
    -- Ended exactly 30 days ago: "no more than 30 days", so kept.
    (C_EDGE,   'Feed Edge',     'coed', 'Clinic', 'probe', now() - interval '30 days 1 hour', now() - interval '30 days', now() - interval '40 days', now() - interval '39 days', 8, 'published', 60),
    -- Ended 30 days and one second ago: gone.
    (C_OLD,    'Feed Old',      'coed', 'Clinic', 'probe', now() - interval '30 days 1 hour 1 second', now() - interval '30 days 1 second', now() - interval '40 days', now() - interval '39 days', 8, 'published', 60),
    (C_ROB,    'Feed Rob',      'coed', 'Clinic', 'probe', now() + interval '3 days',  now() + interval '3 days 1 hour',  now() - interval '9 days', now() - interval '8 days', 8, 'published', 60),
    (C_TARA,   'Feed Tara Cancels', 'coed', 'Clinic', 'probe', now() + interval '8 days', now() + interval '8 days 1 hour', now() - interval '9 days', now() - interval '8 days', 8, 'published', 60);

  insert into public.registrations (id, clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes) values
    (R_IN,   C_IN,     MARIA_P, 'in',       'self', 1800, true,  60),
    (default, C_POOL,  MARIA_P, 'pool',     'self', 1800, true,  60),
    (default, C_GAVEUP, MARIA_P, 'canceled', 'self', 1800, true,  60),
    (default, C_CANCEL, MARIA_P, 'in',       'self', 1800, true,  60),
    (default, C_DRAFT, MARIA_P, 'in',       'self', 1800, true,  60),
    (default, C_RECENT, MARIA_P, 'in',       'self', 1800, true,  60),
    (default, C_EDGE,  MARIA_P, 'in',       'self', 1800, true,  60),
    (default, C_OLD,   MARIA_P, 'in',       'self', 1800, true,  60),
    (default, C_ROB,   ROB_P,   'in',       'self', 2300, false, 60),
    (R_TARA, C_TARA,   MARIA_P, 'in',       'self', 1800, true,  60);
  -- Tara has assigned Maria a court. It must not reach the feed (decision 17).
  update public.registrations set court_number = 4 where id = R_IN;

  -- ------------------------------------------------------- Maria's token
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  t1 := public.my_calendar_feed_token();
  t2 := public.my_calendar_feed_token();
  insert into _probe_result values ('token_is_64_lowercase_hex', 'true', (t1 ~ '^[0-9a-f]{64}$')::text);
  insert into _probe_result values ('same_token_twice', 'true', (t1 = t2)::text);

  -- Maria cannot touch the table directly, not even her own row.
  begin
    execute 'select count(*) from public.calendar_feeds' into n;
    insert into _probe_result values ('owner_cannot_select_calendar_feeds', 'denied', 'READ ' || n);
  exception when insufficient_privilege then
    insert into _probe_result values ('owner_cannot_select_calendar_feeds', 'denied', 'denied');
  end;
  begin
    execute 'insert into public.calendar_feeds (account_id, token) values ($1, $2)' using ROB, repeat('a', 64);
    insert into _probe_result values ('cannot_insert_calendar_feeds', 'denied', 'INSERTED');
  exception when insufficient_privilege then
    insert into _probe_result values ('cannot_insert_calendar_feeds', 'denied', 'denied');
  end;
  begin
    execute 'update public.calendar_feeds set token = $1' using repeat('b', 64);
    insert into _probe_result values ('cannot_update_calendar_feeds', 'denied', 'UPDATED');
  exception when insufficient_privilege then
    insert into _probe_result values ('cannot_update_calendar_feeds', 'denied', 'denied');
  end;
  begin
    execute 'delete from public.calendar_feeds';
    insert into _probe_result values ('cannot_delete_calendar_feeds', 'denied', 'DELETED');
  exception when insufficient_privilege then
    insert into _probe_result values ('cannot_delete_calendar_feeds', 'denied', 'denied');
  end;

  -- ---------------------------------------------------------- ATTACK: Rob
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  begin
    execute 'select token from public.calendar_feeds where account_id = $1' into v using MARIA;
    insert into _probe_result values ('rob_cannot_read_marias_token', 'denied', 'READ ' || coalesce(v, 'nothing'));
  exception when insufficient_privilege then
    insert into _probe_result values ('rob_cannot_read_marias_token', 'denied', 'denied');
  end;
  rob_t := public.my_calendar_feed_token();
  insert into _probe_result values ('rob_gets_his_own_token', 'true', (rob_t <> t1)::text);
  -- Rob resets HIS link; the account is auth.uid(), so Maria's cannot move.
  rob_t := public.reset_my_calendar_feed();
  perform set_config('role', 'postgres', true);
  select token into v from public.calendar_feeds where account_id = MARIA;
  insert into _probe_result values ('robs_reset_leaves_maria_alone', 'true', (v = t1)::text);

  -- ----------------------------------------------------- the feed's rule
  -- Maria's feed, by hand: the 30-day edge, the recent one, Feed In, and the
  -- seed's invitation. Not: Pool, Gave Up, Canceled, Draft, Old, Rob's.
  perform set_config('role', 'service_role', true);
  insert into _probe_result values ('marias_feed_is_exactly_hers',
    'Feed Edge|in, Feed Recent|in, Feed In|in, Feed Tara Cancels|in, Evening Coed|response_needed', pg_temp.feed_of(t1));
  begin
    select e.registration_id::text into v from public.calendar_feed_events(t1) e where e.clinic_name = 'Evening Coed';
  exception when others then v := 'ERROR ' || sqlerrm;
  end;
  insert into _probe_result values ('the_event_is_the_registration', INVITE::text, coalesce(v, ''));
  begin
    select (e.starts_at = c.starts_at and e.ends_at = c.ends_at)::text into v
      from public.calendar_feed_events(t1) e join public.clinics c on c.id = C_IN
     where e.registration_id = R_IN;
  exception when others then v := 'ERROR ' || sqlerrm;
  end;
  insert into _probe_result values ('times_are_the_clinics', 'true', coalesce(v, ''));
  insert into _probe_result values ('robs_feed_is_exactly_his', 'Feed Rob|in', pg_temp.feed_of(rob_t));

  -- Only the columns the feed needs: none of the nine hidden facts can be
  -- added to the feed without this row going red.
  insert into _probe_result values ('feed_returns_only_name_times_status',
    'TABLE(registration_id uuid, status registration_status, clinic_name text, starts_at timestamp with time zone, ends_at timestamp with time zone)',
    pg_get_function_result('public.calendar_feed_events(text)'::regprocedure));

  -- Unknown, empty and null tokens are one answer.
  begin
    perform public.calendar_feed_events(repeat('0', 64));
    insert into _probe_result values ('unknown_token_is_not_found', 'feed_not_found P0002', 'ANSWERED');
  exception when others then
    insert into _probe_result values ('unknown_token_is_not_found', 'feed_not_found P0002', sqlerrm || ' ' || sqlstate);
  end;
  begin
    perform public.calendar_feed_events('');
    insert into _probe_result values ('empty_token_is_not_found', 'feed_not_found', 'ANSWERED');
  exception when others then
    insert into _probe_result values ('empty_token_is_not_found', 'feed_not_found', sqlerrm);
  end;
  begin
    perform public.calendar_feed_events(null);
    insert into _probe_result values ('null_token_is_not_found', 'feed_not_found', 'ANSWERED');
  exception when others then
    insert into _probe_result values ('null_token_is_not_found', 'feed_not_found', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- -------------------------------------- changes reach the feed by the rule
  -- Through the real RPCs: Maria gives up Feed In, Tara cancels Feed Tara
  -- Cancels, Maria accepts the invitation (the same event, now You're In!).
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.cancel_registration(R_IN, null);
  perform public.respond_to_invitation(INVITE, true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.cancel_clinic(C_TARA);
  perform set_config('role', 'service_role', true);
  insert into _probe_result values ('given_up_and_canceled_leave_accepted_stays',
    'Evening Coed|in|' || INVITE, pg_temp.feed_of(t1, true, true));
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------------- reset
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  t3 := public.reset_my_calendar_feed();
  t4 := public.my_calendar_feed_token();
  insert into _probe_result values ('reset_gives_a_new_token', 'true', (t3 <> t1 and t3 ~ '^[0-9a-f]{64}$')::text);
  insert into _probe_result values ('the_new_token_is_the_one_returned', 'true', (t4 = t3)::text);
  perform set_config('role', 'service_role', true);
  begin
    perform public.calendar_feed_events(t1);
    insert into _probe_result values ('old_token_stops_working', 'feed_not_found', 'ANSWERED');
  exception when others then
    insert into _probe_result values ('old_token_stops_working', 'feed_not_found', sqlerrm);
  end;
  insert into _probe_result values ('new_token_serves_the_feed',
    'Feed Edge|in, Feed Recent|in, Evening Coed|in', pg_temp.feed_of(t3));
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.calendar_feeds where account_id = MARIA;
  insert into _probe_result values ('one_row_per_account', '1', n::text);

  -- ---------------------------------------------------- signed out
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.my_calendar_feed_token();
    insert into _probe_result values ('signed_out_gets_no_token', 'not_authenticated', 'ANSWERED');
  exception when others then
    insert into _probe_result values ('signed_out_gets_no_token', 'not_authenticated', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- ---------------------------------------------------- a deleted account
  -- Ken has a token, then deletes his account the supported way.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  ken_t := public.my_calendar_feed_token();
  perform public.delete_my_account();
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.calendar_feeds where account_id = KEN;
  insert into _probe_result values ('delete_my_account_takes_the_token', '0', n::text);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.my_calendar_feed_token();
    insert into _probe_result values ('deleted_account_gets_no_token', 'account_not_found', 'ANSWERED');
  exception when others then
    insert into _probe_result values ('deleted_account_gets_no_token', 'account_not_found', sqlerrm);
  end;
  begin
    perform public.reset_my_calendar_feed();
    insert into _probe_result values ('deleted_account_cannot_reset', 'account_not_found', 'ANSWERED');
  exception when others then
    insert into _probe_result values ('deleted_account_cannot_reset', 'account_not_found', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.calendar_feeds where account_id = KEN;
  insert into _probe_result values ('deleted_account_left_no_row', '0', n::text);
  perform set_config('role', 'service_role', true);
  begin
    perform public.calendar_feed_events(ken_t);
    insert into _probe_result values ('deleted_accounts_feed_is_gone', 'feed_not_found', 'ANSWERED');
  exception when others then
    insert into _probe_result values ('deleted_accounts_feed_is_gone', 'feed_not_found', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- Defence in depth: a row that somehow survived the deletion (here, planted
  -- after Dana's deleted_at by hand) still serves nothing.
  update public.accounts set deleted_at = now() where id = DANA;
  dana_t := repeat('d', 64);
  insert into public.calendar_feeds (account_id, token) values (DANA, dana_t);
  perform set_config('role', 'service_role', true);
  begin
    perform public.calendar_feed_events(dana_t);
    insert into _probe_result values ('a_deleted_accounts_row_serves_nothing', 'feed_not_found', 'ANSWERED');
  exception when others then
    insert into _probe_result values ('a_deleted_accounts_row_serves_nothing', 'feed_not_found', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- A hard delete (the dashboard's Delete user) takes the token with it and is
  -- not blocked by it.
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values (GHOST, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'feed-ghost@fxe.test', '', now(), now(), now());
  insert into public.accounts (id, first_name, last_name, email) values (GHOST, 'Feed', 'Ghost', 'feed-ghost@fxe.test');
  insert into public.calendar_feeds (account_id, token) values (GHOST, repeat('e', 64));
  begin
    delete from auth.users where id = GHOST;
    select count(*) into n from public.calendar_feeds where account_id = GHOST;
    insert into _probe_result values ('hard_delete_takes_the_token', '0', n::text);
  exception when others then
    insert into _probe_result values ('hard_delete_takes_the_token', '0', 'BLOCKED ' || sqlstate);
  end;

  -- The table holds only the shape the function makes.
  begin
    insert into public.calendar_feeds (account_id, token) values (TARA, 'not-a-token');
    insert into _probe_result values ('token_shape_enforced', '23514', 'INSERTED');
  exception when others then
    insert into _probe_result values ('token_shape_enforced', '23514', sqlstate);
  end;

  -- ------------------------------------------------------------ grants
  -- Enumerated: every privilege a client role holds on the table.
  select coalesce(string_agg(r || ':' || p, ', ' order by r, p), '') into v
    from unnest(array['anon', 'authenticated']) r
    cross join unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
   where has_table_privilege(r, 'public.calendar_feeds'::regclass, p);
  insert into _probe_result values ('no_client_privilege_on_calendar_feeds', '', v);
  select coalesce(string_agg(c, ', '), '') into v
    from unnest(array['account_id', 'token', 'created_at']) c
   where has_column_privilege('authenticated', 'public.calendar_feeds'::regclass, c, 'SELECT')
      or has_column_privilege('anon', 'public.calendar_feeds'::regclass, c, 'SELECT');
  insert into _probe_result values ('no_client_column_privilege', '', v);
  select relrowsecurity::text into v from pg_class where oid = 'public.calendar_feeds'::regclass;
  insert into _probe_result values ('rls_enabled', 'true', v);
  insert into _probe_result values ('service_role_holds_dml', 'true',
    (has_table_privilege('service_role', 'public.calendar_feeds'::regclass, 'SELECT')
     and has_table_privilege('service_role', 'public.calendar_feeds'::regclass, 'INSERT')
     and has_table_privilege('service_role', 'public.calendar_feeds'::regclass, 'UPDATE')
     and has_table_privilege('service_role', 'public.calendar_feeds'::regclass, 'DELETE'))::text);

  -- Who may call what, as name:role pairs, over the four new functions.
  select string_agg(p.proname || ':' || r, ', ' order by p.proname, r) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
    cross join unnest(array['anon', 'authenticated', 'service_role']) r
   where p.proname in ('my_calendar_feed_token', 'reset_my_calendar_feed', 'calendar_feed_events', 'calendar_feed_forget_deleted_account')
     and has_function_privilege(r, p.oid, 'EXECUTE')
     and not (r = 'service_role' and p.proname <> 'calendar_feed_events');
  insert into _probe_result values ('who_executes_what',
    'calendar_feed_events:service_role, my_calendar_feed_token:authenticated, reset_my_calendar_feed:authenticated', coalesce(v, ''));
  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname in ('my_calendar_feed_token', 'reset_my_calendar_feed', 'calendar_feed_events', 'calendar_feed_forget_deleted_account')
     and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0));
  insert into _probe_result values ('public_executes_none_of_them', '0', n::text);
  select string_agg(p.proname || ':' || p.pronargs, ', ' order by p.proname) into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname in ('my_calendar_feed_token', 'reset_my_calendar_feed');
  insert into _probe_result values ('the_account_is_never_a_parameter', 'my_calendar_feed_token:0, reset_my_calendar_feed:0', coalesce(v, ''));
  select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname in ('my_calendar_feed_token', 'reset_my_calendar_feed', 'calendar_feed_events', 'calendar_feed_forget_deleted_account')
     and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  insert into _probe_result values ('search_path_pinned', '4', n::text);
end $$;

-- Exact comparison only, deliberately. The first draft copied the other
-- probes' substring rule (an expected value with letters passes when it is
-- inside the actual one), and red-first caught it: with the 30-day window
-- removed, Maria's feed gained "Feed Old|in, " at the front and still read
-- PASS, and a Player Pool row did the same to the list after the changes.
-- Every error here is raised with an exact message, so nothing needs fuzz.
select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
