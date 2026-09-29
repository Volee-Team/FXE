-- player_history.sql
--
-- admin_player_history (20260928800001, decision 0027 §1): the line beside a
-- name in the Player Pool. Expected values are worked out by hand from the
-- rule, never read off the function:
--
--   played        You're In!, not a no-show, clinic ended and not canceled
--                 (the board report's "attended", 20260926000010)
--   no_shows      the same rows with no_show set
--   late_cancels  canceled with late_cancel, in a clinic not canceled; counted
--                 as soon as it happens
--   last played   the start of the latest played clinic
--
-- Three fresh players under one throwaway account, so no seed row and no
-- browser-test leftover can move a number:
--
--   HIST  A Aug 2   in                    played
--         C Sep 6   in, no-show           no-show
--         E Aug 30  canceled early        nothing
--         B Sep 13  in                    played (the latest played: last played)
--         F Sep 15  in, clinic CANCELED   nothing (later than B: would move last played)
--         D Sep 20  canceled late         late cancel
--         H Sep 21  Player Pool, ended    nothing (later than B: would move last played)
--         G 2099    in, not ended         nothing
--         G2 2099   canceled late         late cancel (counts before the clinic ends)
--      -> 2 played, 1 no-show, 2 late cancels, last played 2026-09-13 13:00 UTC
--
--   EDGE  I ends exactly now, in          played (ended means ends_at <= now())
--         F clinic CANCELED, canceled late  nothing
--         G 2099, in, no-show             nothing (the clinic has not ended)
--         H Response Needed, ended        nothing
--      -> 1 played, 0, 0, last played I's start
--
--   NEW   nothing at all                  -> 0, 0, 0, no last played ("New")
--
-- Then the boundary (hard rule 1: never a count to a player): Maria is
-- refused and receives nothing, anon and PUBLIC hold no EXECUTE.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA   constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA  constant uuid := '22222222-2222-2222-2222-222222222222';
  ACC    constant uuid := 'c0000000-0000-0000-0000-0000000000f1';
  HIST   constant uuid := 'c0000000-0000-0000-0000-0000000000f2';
  EDGE   constant uuid := 'c0000000-0000-0000-0000-0000000000f3';
  NEWP   constant uuid := 'c0000000-0000-0000-0000-0000000000f4';
  A uuid; B uuid; C uuid; D uuid; E uuid; F uuid; G uuid; G2 uuid; H uuid; I uuid;
  i_starts timestamptz;
  v text; n int; st text;
begin
  -- ------------------------------------------------------------ fixture
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values (ACC, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'history@probe.test', 'x', now(), now(), now());
  insert into public.accounts (id, first_name, last_name, email, role) values (ACC, 'History', 'Probe', 'history@probe.test', 'member');
  insert into public.players (id, account_id, kind, first_name, last_name, adult_rating, is_member) values
    (HIST, ACC, 'adult', 'Hist', 'Subject', 3.5, true),
    (EDGE, ACC, 'adult', 'Edge', 'Cases',   3.0, false),
    (NEWP, ACC, 'adult', 'New',  'Comer',   4.0, true);

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('History A', 'coed', 'Clinic', 'probe', '2026-08-02 22:00:00+00', '2026-08-02 23:00:00+00',
          '2026-07-30 12:00:00+00', '2026-07-31 12:00:00+00', 8, 'published', 60) returning id into A;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('History B', 'coed', 'Clinic', 'probe', '2026-09-13 13:00:00+00', '2026-09-13 14:00:00+00',
          '2026-09-10 12:00:00+00', '2026-09-11 12:00:00+00', 8, 'published', 60) returning id into B;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('History C', 'coed', 'Clinic', 'probe', '2026-09-06 13:00:00+00', '2026-09-06 14:00:00+00',
          '2026-09-03 12:00:00+00', '2026-09-04 12:00:00+00', 8, 'published', 60) returning id into C;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('History D', 'coed', 'Clinic', 'probe', '2026-09-20 13:00:00+00', '2026-09-20 14:00:00+00',
          '2026-09-17 12:00:00+00', '2026-09-18 12:00:00+00', 8, 'published', 60) returning id into D;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('History E', 'coed', 'Clinic', 'probe', '2026-08-30 13:00:00+00', '2026-08-30 14:00:00+00',
          '2026-08-27 12:00:00+00', '2026-08-28 12:00:00+00', 8, 'published', 60) returning id into E;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, canceled_at, duration_minutes)
  values ('History F', 'coed', 'Clinic', 'probe', '2026-09-15 22:00:00+00', '2026-09-15 23:00:00+00',
          '2026-09-10 12:00:00+00', '2026-09-11 12:00:00+00', 8, 'canceled', '2026-09-15 20:00:00+00', 60) returning id into F;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('History G', 'coed', 'Clinic', 'probe', '2099-06-02 13:00:00+00', '2099-06-02 14:00:00+00',
          '2099-05-28 12:00:00+00', '2099-05-29 12:00:00+00', 8, 'published', 60) returning id into G;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('History G2', 'coed', 'Clinic', 'probe', '2099-06-03 13:00:00+00', '2099-06-03 14:00:00+00',
          '2099-05-28 12:00:00+00', '2099-05-29 12:00:00+00', 8, 'published', 60) returning id into G2;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('History H', 'coed', 'Clinic', 'probe', '2026-09-21 13:00:00+00', '2026-09-21 14:00:00+00',
          '2026-09-17 12:00:00+00', '2026-09-18 12:00:00+00', 8, 'published', 60) returning id into H;
  -- Ends at the transaction's now(), which every now() below also reads.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('History I', 'coed', 'Clinic', 'probe', now() - interval '1 hour', now(),
          now() - interval '9 days', now() - interval '8 days', 8, 'published', 60) returning id, starts_at into I, i_starts;

  insert into public.registrations (clinic_id, player_id, status, no_show, late_cancel, canceled_at) values
    (A,  HIST, 'in',              false, false, null),
    (B,  HIST, 'in',              false, false, null),
    (C,  HIST, 'in',              true,  false, null),
    (D,  HIST, 'canceled',        false, true,  '2026-09-20 11:30:00+00'),
    (E,  HIST, 'canceled',        false, false, '2026-08-25 12:00:00+00'),
    (F,  HIST, 'in',              false, false, null),
    (G,  HIST, 'in',              false, false, null),
    (G2, HIST, 'canceled',        false, true,  now()),
    (H,  HIST, 'pool',            false, false, null),
    (I,  EDGE, 'in',              false, false, null),
    (F,  EDGE, 'canceled',        false, true,  '2026-09-15 20:30:00+00'),
    (G,  EDGE, 'in',              true,  false, null),
    (H,  EDGE, 'response_needed', false, false, null);

  -- ------------------------------------------------------------ as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  -- Every player, one call: the three probe players are among them, once each.
  select count(*) into n from public.admin_player_history() h where h.player_id in (HIST, EDGE, NEWP);
  insert into _probe_result values ('all_players_call_has_each_probe_player_once', '3', n::text);
  select count(*) into n from public.admin_player_history();
  insert into _probe_result values ('all_players_call_is_one_row_per_player',
    (select count(*) from public.players)::text, n::text);

  select h.played || '|' || h.no_shows || '|' || h.late_cancels into v
    from public.admin_player_history() h where h.player_id = HIST;
  insert into _probe_result values ('hist_played_noshows_latecancels', '2|1|2', v);
  select h.last_played_at::text into v from public.admin_player_history() h where h.player_id = HIST;
  insert into _probe_result values ('hist_last_played_is_B_not_a_later_canceled_or_pool_clinic',
    '2026-09-13 13:00:00+00', v);

  select h.played || '|' || h.no_shows || '|' || h.late_cancels into v
    from public.admin_player_history() h where h.player_id = EDGE;
  insert into _probe_result values ('edge_played_noshows_latecancels', '1|0|0', v);
  select (h.last_played_at = i_starts)::text into v
    from public.admin_player_history() h where h.player_id = EDGE;
  insert into _probe_result values ('edge_last_played_is_the_clinic_ending_now', 'true', v);

  select h.played || '|' || h.no_shows || '|' || h.late_cancels || '|' || coalesce(h.last_played_at::text, 'none') into v
    from public.admin_player_history() h where h.player_id = NEWP;
  insert into _probe_result values ('new_player_is_all_zeros', '[0|0|0|none]', '[' || v || ']');

  -- One player: that player's row, the same numbers, and nobody else.
  select count(*) || ':' || min(h.played) || '|' || min(h.no_shows) || '|' || min(h.late_cancels) into v
    from public.admin_player_history(HIST) h;
  insert into _probe_result values ('one_player_call_is_that_row', '1:2|1|2', v);
  select count(*) into n from public.admin_player_history(HIST) h where h.player_id <> HIST;
  insert into _probe_result values ('one_player_call_names_nobody_else', '0', n::text);
  select count(*) into n from public.admin_player_history('00000000-0000-0000-0000-00000000dead');
  insert into _probe_result values ('unknown_player_is_no_row', '0', n::text);

  -- ------------------------------------------------ ATTACK: as Maria
  -- A member asks for the whole club, and for her own row. Both refused, and
  -- the assertion is what she received, not only that something raised.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  n := null; st := null;
  begin
    select count(*) into n from public.admin_player_history();
  exception when others then st := sqlstate || ' ' || sqlerrm;
  end;
  insert into _probe_result values ('member_gets_not_authorized_for_the_club', '[42501 not_authorized]', '[' || coalesce(st, 'READ ' || n) || ']');
  n := null; st := null;
  begin
    select count(*) into n from public.admin_player_history('a0000000-0000-0000-0000-000000000001');
  exception when others then st := sqlstate || ' ' || sqlerrm;
  end;
  insert into _probe_result values ('member_gets_not_authorized_for_herself', '[42501 not_authorized]', '[' || coalesce(st, 'READ ' || n) || ']');
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------ grant surface
  -- Asserted with has_function_privilege, never by calling as anon (CLAUDE.md,
  -- "Known local-environment defect").
  insert into _probe_result values ('anon_cannot_execute', 'false',
    has_function_privilege('anon', 'public.admin_player_history(uuid)', 'EXECUTE')::text);
  insert into _probe_result values ('public_holds_no_execute', '0',
    (select count(*) from pg_proc p, aclexplode(p.proacl) a
      where p.oid = 'public.admin_player_history(uuid)'::regprocedure
        and a.grantee = 0 and a.privilege_type = 'EXECUTE')::text);
  insert into _probe_result values ('acl_is_explicit_not_default', 'true',
    ((select proacl from pg_proc where oid = 'public.admin_player_history(uuid)'::regprocedure) is not null)::text);
  insert into _probe_result values ('authenticated_can_execute', 'true',
    has_function_privilege('authenticated', 'public.admin_player_history(uuid)', 'EXECUTE')::text);
  insert into _probe_result values ('definer_pins_search_path', 'true',
    (select prosecdef and exists (select 1 from unnest(proconfig) cfg where cfg like 'search_path=%')
       from pg_proc where oid = 'public.admin_player_history(uuid)'::regprocedure)::text);
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
