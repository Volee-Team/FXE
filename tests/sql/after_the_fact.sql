-- after_the_fact.sql
--
-- A transition must look at whether the clinic is still happening. The rule,
-- stated before the code (20260928300001 and 20260928400001, decision 0022):
--
--   * A canceled clinic has no spots. Nobody can accept an invitation to it,
--     Tara cannot invite anyone to it from the Pool, and she cannot approve a
--     late request for it. Declining either stays possible.
--   * A clinic that has ended cannot be joined. An invitation accepted after
--     the end is refused; declining it is fine.
--
-- Expected values are the rule's, written out by hand: the error each refusal
-- raises, and the state that must NOT have moved (the registration's status,
-- the late request's status, how many notifications the attempt wrote). A
-- refusal that raised the right error but still moved a row would fail here,
-- and so would a row that moved with no error at all (hard rule 9: assert the
-- outcome, not the error).
--
-- Sanity rows at the end prove the same calls still work on a clinic that is
-- happening, so the fix cannot be "refuse everything".
--
-- The concurrency half (a cancel racing an Accept) is tests/sql/accept_cancel_race.sh.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;
update public.app_settings set value = 'false' where key = 'payments_enabled';

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  PRIYA   constant uuid := '55555555-5555-5555-5555-555555555555';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  ended_c uuid; rained uuid; live_c uuid;
  reg_ended uuid; reg_rained_pool uuid; reg_live_pool uuid; reg_ended_decline uuid;
  req_rained uuid; req_rained2 uuid; req_live uuid;
  before int; err text; st text;
begin
  -- A clinic that ended yesterday, a clinic Tara will cancel, and one that is
  -- happening next week.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Ended', 'coed', 'Clinic', 'probe', now() - interval '26 hours', now() - interval '25 hours',
          now() - interval '9 days', now() - interval '8 days', 8, 'published', 60)
  returning id into ended_c;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Rained', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into rained;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Live', 'coed', 'Clinic', 'probe', now() + interval '4 days', now() + interval '4 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into live_c;

  -- Invitations and Pool rows, as the admin paths leave them.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, invited_at)
  values (ended_c, ROB_P, 'response_needed', 'self', 2300, false, 60, now() - interval '3 days') returning id into reg_ended;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, invited_at)
  values (ended_c, PRIYA_P, 'response_needed', 'self', 2300, false, 60, now() - interval '3 days') returning id into reg_ended_decline;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (rained, ROB_P, 'pool', 'self', 2300, false, 60) returning id into reg_rained_pool;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (live_c, ROB_P, 'pool', 'self', 2300, false, 60) returning id into reg_live_pool;
  insert into public.late_requests (clinic_id, player_id, message) values (rained, PRIYA_P, 'probe') returning id into req_rained;
  insert into public.late_requests (clinic_id, player_id, message) values (rained, DANA_P, 'probe') returning id into req_rained2;
  insert into public.late_requests (clinic_id, player_id, message) values (live_c, PRIYA_P, 'probe') returning id into req_live;

  -- Tara cancels the rained clinic.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.cancel_clinic(rained);
  perform set_config('role', 'postgres', true);

  -- ===== 1. Accept after the clinic ended: refused, nothing moves, nobody told.
  select count(*) into before from public.notifications;
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.respond_to_invitation(reg_ended, true); err := 'accepted';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  select status::text into st from public.registrations where id = reg_ended;
  insert into _probe_result values ('accept_after_end_is_refused', 'clinic_ended', err);
  insert into _probe_result values ('accept_after_end_moves_nothing', 'response_needed|0',
    st || '|' || ((select count(*) from public.notifications) - before)::text);

  -- ===== 2. Decline after the end: allowed (it changes nothing that matters).
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.respond_to_invitation(reg_ended_decline, false); err := 'declined';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('decline_after_end_still_works', 'declined|pool',
    err || '|' || (select status::text from public.registrations where id = reg_ended_decline));

  -- ===== 3. Invite from the Pool of a canceled clinic: refused, nothing moves.
  select count(*) into before from public.notifications;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.invite_from_pool(reg_rained_pool); err := 'invited';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('invite_on_canceled_is_refused', 'clinic_canceled', err);
  insert into _probe_result values ('invite_on_canceled_moves_nothing', 'pool|0',
    (select status::text from public.registrations where id = reg_rained_pool) || '|'
      || ((select count(*) from public.notifications) - before)::text);

  -- ===== 4. Approve a late request for a canceled clinic: refused; nothing
  --          placed, the request still pending, nobody told.
  select count(*) into before from public.notifications;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.resolve_late_request(req_rained, true); err := 'approved';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('approve_on_canceled_is_refused', 'clinic_canceled', err);
  insert into _probe_result values ('approve_on_canceled_moves_nothing', 'pending|0|0',
    (select status::text from public.late_requests where id = req_rained) || '|'
      || (select count(*) from public.registrations where clinic_id = rained and player_id = PRIYA_P)::text || '|'
      || ((select count(*) from public.notifications) - before)::text);

  -- ===== 5. Decline a late request for a canceled clinic: allowed.
  perform set_config('role', 'authenticated', true);
  begin
    perform public.resolve_late_request(req_rained2, false); err := 'declined';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('decline_request_on_canceled_still_works', 'declined|declined',
    err || '|' || (select status::text from public.late_requests where id = req_rained2));

  -- ===== Sanity: the same calls on a clinic that is happening still work.
  perform set_config('role', 'authenticated', true);
  begin
    perform public.invite_from_pool(reg_live_pool); err := 'invited';
  exception when others then err := sqlerrm; end;
  begin
    perform public.resolve_late_request(req_live, true); st := 'approved';
  exception when others then st := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('sanity_invite_on_live_works', 'invited|response_needed',
    err || '|' || (select status::text from public.registrations where id = reg_live_pool));
  insert into _probe_result values ('sanity_approve_on_live_works', 'approved|in',
    st || '|' || coalesce((select status::text from public.registrations where clinic_id = live_c and player_id = PRIYA_P), 'none'));

  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.respond_to_invitation(reg_live_pool, true); err := 'accepted';
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('sanity_accept_on_live_works', 'accepted|in',
    err || '|' || (select status::text from public.registrations where id = reg_live_pool));
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
