-- late_requests.sql
--
-- Covers the "can I still get in?" path (20260827000002), and ATTACKS it.
--
-- Tara, 2026-08-27: "if they try to register within 3 hours, they have the
-- option to send me a direct message to get into the clinic, assuming there is
-- space and it isn't full."
--
-- Every clause in that sentence is a condition, and each one is a way in if it
-- is not checked: inside the window, before the clinic starts, and not full.
-- This probe asserts all three, then tries to cross them.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA_ACC  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA     constant uuid := 'a0000000-0000-0000-0000-000000000001';
  MARIA_ACC constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN       constant uuid := 'a0000000-0000-0000-0000-000000000002';
  KEN_ACC   constant uuid := '33333333-3333-3333-3333-333333333333';
  v_open    uuid;   -- registration still open
  v_closed  uuid;   -- inside the 3h window
  v_started uuid;   -- already under way
  v_full    uuid;   -- closed AND full
  v_req     public.late_requests;
  n         int;
  v_txt     text;
begin
  perform set_config('role', 'postgres', true);

  -- Fixtures. Windows are set explicitly rather than via the helpers so the
  -- probe controls exactly which condition each clinic violates.
  insert into public.clinics (name, audience, starts_at, ends_at, duration_minutes,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status)
  values ('Probe OPEN', 'ladies', now() + interval '10 days', now() + interval '10 days 1 hour', 60,
          now() - interval '2 days', now() - interval '1 day', now() + interval '9 days', 8, 'published')
  returning id into v_open;

  insert into public.clinics (name, audience, starts_at, ends_at, duration_minutes,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status)
  values ('Probe CLOSED', 'ladies', now() + interval '2 hours', now() + interval '3 hours', 60,
          now() - interval '2 days', now() - interval '1 day', now() - interval '1 hour', 8, 'published')
  returning id into v_closed;

  insert into public.clinics (name, audience, starts_at, ends_at, duration_minutes,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status)
  values ('Probe STARTED', 'ladies', now() - interval '30 minutes', now() + interval '30 minutes', 60,
          now() - interval '2 days', now() - interval '1 day', now() - interval '4 hours', 8, 'published')
  returning id into v_started;

  insert into public.clinics (name, audience, starts_at, ends_at, duration_minutes,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status)
  values ('Probe FULL', 'ladies', now() + interval '2 hours', now() + interval '3 hours', 60,
          now() - interval '2 days', now() - interval '1 day', now() - interval '1 hour', 1, 'published')
  returning id into v_full;

  insert into public.registrations (clinic_id, player_id, status, paid)
  values (v_full, KEN, 'in', false);

  -- ============================================================ happy path ==
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);

  v_req := public.request_late_spot(v_closed, MARIA, 'Stuck in traffic but I can make it!');
  insert into _probe_result values ('can_ask_inside_the_window', 'pending', v_req.status);
  insert into _probe_result values ('message_is_kept', 'Stuck in traffic but I can make it!', v_req.message);

  -- Asking is NOT registering. Hard rule 2: only Tara puts someone in.
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id = v_closed and player_id = MARIA;
  insert into _probe_result values ('asking_does_not_register_you', '0', n::text);

  -- Tara is told. This IS the "direct message" from her side.
  select count(*) into n from public.notifications
   where type = 'LATE_REQUEST' and account_id = TARA_ACC and entity_id = v_closed;
  insert into _probe_result values ('tara_is_notified', '1', n::text);
  perform set_config('role', 'authenticated', true);

  -- Two taps on a bad connection must not put two rows in her queue.
  begin
    perform public.request_late_spot(v_closed, MARIA, 'again');
    insert into _probe_result values ('cannot_ask_twice', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('cannot_ask_twice', 'blocked', 'blocked');
  end;

  -- ====================================================== the three clauses ==
  -- "within 3 hours": before the window there is a normal Register button, and
  -- offering both would be two doors to one room.
  begin
    perform public.request_late_spot(v_open, MARIA, null);
    insert into _probe_result values ('cannot_ask_while_still_open', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('cannot_ask_while_still_open', 'blocked', 'blocked');
  end;

  begin
    perform public.request_late_spot(v_started, MARIA, null);
    insert into _probe_result values ('cannot_ask_after_it_starts', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('cannot_ask_after_it_starts', 'blocked', 'blocked');
  end;

  -- "assuming there is space and it isn't full"
  begin
    perform public.request_late_spot(v_full, MARIA, null);
    insert into _probe_result values ('cannot_ask_when_full', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('cannot_ask_when_full', 'blocked', 'blocked');
  end;

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.late_requests where clinic_id in (v_open, v_started, v_full);
  insert into _probe_result values ('no_rows_from_blocked_asks', '0', n::text);
  perform set_config('role', 'authenticated', true);

  -- ================================================== ATTACK: someone else ==
  -- Ken asking on Maria's behalf would let anyone put another member in front
  -- of Tara under their name.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN_ACC)::text, true);
  begin
    perform public.request_late_spot(v_closed, MARIA, 'not me');
    insert into _probe_result values ('cannot_ask_for_another_player', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('cannot_ask_for_another_player', 'blocked', 'blocked');
  end;

  -- A player must not be able to approve their own request.
  begin
    perform public.resolve_late_request(v_req.id, true);
    insert into _probe_result values ('player_cannot_approve', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('player_cannot_approve', 'blocked', 'blocked');
  end;
  perform set_config('role', 'postgres', true);
  select status into v_txt from public.late_requests where id = v_req.id;
  insert into _probe_result values ('still_pending_after_attack', 'pending', v_txt);
  select count(*) into n from public.registrations where clinic_id = v_closed and status = 'in';
  insert into _probe_result values ('attack_placed_nobody', '0', n::text);

  -- ============================================================ anon ========
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
  begin
    perform public.request_late_spot(v_closed, KEN, 'anon');
    insert into _probe_result values ('anon_cannot_ask', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('anon_cannot_ask', 'blocked', 'blocked');
  end;

  -- ======================================================= Tara resolves ====
  perform set_config('request.jwt.claims', json_build_object('sub', TARA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);

  v_req := public.resolve_late_request(v_req.id, true);
  insert into _probe_result values ('tara_can_approve', 'approved', v_req.status);

  perform set_config('role', 'postgres', true);
  select status::text into v_txt from public.registrations
   where clinic_id = v_closed and player_id = MARIA;
  insert into _probe_result values ('approval_places_the_player', 'in', coalesce(v_txt, 'NOT PLACED'));

  select count(*) into n from public.notifications
   where type = 'LATE_REQUEST_APPROVED' and account_id = MARIA_ACC;
  insert into _probe_result values ('player_is_told_the_answer', '1', n::text);
  perform set_config('role', 'authenticated', true);

  -- Hard rule 3: resolving twice must not place them twice.
  begin
    perform public.resolve_late_request(v_req.id, true);
    insert into _probe_result values ('cannot_resolve_twice', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('cannot_resolve_twice', 'blocked', 'blocked');
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id = v_closed and player_id = MARIA;
  insert into _probe_result values ('still_one_registration', '1', n::text);

  -- Hard rule 4: a declined request keeps its row and its timestamp.
  insert into public.late_requests (clinic_id, player_id, message)
  values (v_closed, KEN, 'me too') returning * into v_req;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);
  v_req := public.resolve_late_request(v_req.id, false);
  insert into _probe_result values ('tara_can_decline', 'declined', v_req.status);
  insert into _probe_result values ('declined_row_is_kept', 'true', (v_req.resolved_at is not null)::text);

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where clinic_id = v_closed and player_id = KEN;
  insert into _probe_result values ('decline_places_nobody', '0', n::text);

  -- ---------------------------------------------------------------- grants
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('request_late_spot','resolve_late_request')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('anon_has_no_execute', '0', n::text);

  select count(*) into n from information_schema.role_table_grants
   where table_schema='public' and table_name='late_requests'
     and grantee in ('anon','authenticated')
     and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE');
  insert into _probe_result values ('no_direct_writes_to_the_table', '0', n::text);
end $$;

select
  check_name, expected, actual,
  case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result
order by check_name;

rollback;
