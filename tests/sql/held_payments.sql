-- held_payments.sql
--
-- A charge stripe-charge could not safely retry is HELD: status processing,
-- failure_reason idempotency_error (the same key sent with different
-- parameters) or retry_window_passed (Stripe no longer remembers the key).
-- It may or may not have gone through, and only a person looking in Stripe
-- can tell. Until 20260927300003 the only way out was hand SQL.
--
-- THE RULE (20260927300003, MVP fix round 2026-09-27)
--   * admin_resolve_held_payment(payment, outcome), outcome 'succeeded' or
--     'canceled', admin only (a member gets not_authorized and changes nothing).
--   * Only a held row moves: status processing AND failure_reason one of the
--     two above. Anything else is refused payment_not_held and left as it was
--     (a processing row with no reason belongs to a call still in flight or to
--     the webhook).
--   * 'succeeded' goes through the same paid-marking the webhook's update
--     does: a held clinic fee that went through marks the registration paid.
--   * 'canceled' frees the one-charge slot: Tara can charge that player again.
--   * Any other outcome: invalid_outcome, nothing changes.
--   * payments.first_attempted_at (S1) exists, is written by the edge
--     function as service_role, and no client role can read or write it.
--
-- FIXTURE: an ended clinic; Maria (H1, fee 1800, held retry_window_passed),
-- Ken (H2, fee 1800, held idempotency_error), Rob (P3, fee 2300, processing,
-- no reason). Payments on; Ken has a card.
--
-- EXPECTED (by hand)
--   Maria resolving H1: not_authorized; H1 still "processing".
--   Tara: H1 succeeded -> "succeeded", Maria's registration paid "true".
--         H2 canceled  -> "canceled"; charging Ken again -> "pending 1800".
--         P3 succeeded -> payment_not_held; P3 still "processing", Rob unpaid "false".
--         H1 canceled (already resolved) -> payment_not_held; H1 still "succeeded".
--         outcome 'refunded' -> invalid_outcome.
--   Grants: anon cannot execute, authenticated can; first_attempted_at:
--     authenticated SELECT false, UPDATE false; service_role UPDATE true.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  c uuid; rm uuid; rk uuid; rr uuid; h1 uuid; h2 uuid; p3 uuid;
  v text; fn regprocedure := to_regprocedure('public.admin_resolve_held_payment(uuid, text)');
begin
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe held', 'coed', 'Clinic', 'probe', now() - interval '3 days', now() - interval '3 days' + interval '1 hour',
          now() - interval '9 days', now() - interval '8 days', 8, 'published', 60)
  returning id into c;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c, MARIA_P, 'in', 'self', 1800, true, 60) returning id into rm;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c, KEN_P, 'in', 'self', 1800, true, 60) returning id into rk;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c, ROB_P, 'in', 'self', 2300, false, 60) returning id into rr;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_reason)
  values (rm, MARIA, 'clinic_fee', 1800, 'processing', 'retry_window_passed') returning id into h1;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_reason)
  values (rk, KEN, 'clinic_fee', 1800, 'processing', 'idempotency_error') returning id into h2;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (rr, ROB, 'clinic_fee', 2300, 'processing') returning id into p3;
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  update public.accounts set stripe_customer_id = 'cus_probe_ken', card_brand = 'visa', card_last4 = '4242' where id = KEN;

  -- ------------------------------------------------------------ as Maria
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    execute 'select public.admin_resolve_held_payment($1, $2)' using h1, 'succeeded';
    insert into _probe_result values ('member_cannot_resolve', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_resolve', 'not_authorized', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  select status::text into v from public.payments where id = h1;
  insert into _probe_result values ('member_attempt_changes_nothing', 'processing', v);

  -- ------------------------------------------------------------- as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    execute 'select (public.admin_resolve_held_payment($1, $2)).status::text' into v using h1, 'succeeded';
    insert into _probe_result values ('held_went_through', 'succeeded', v);
  exception when others then
    insert into _probe_result values ('held_went_through', 'succeeded', sqlerrm);
  end;
  begin
    execute 'select (public.admin_resolve_held_payment($1, $2)).status::text' into v using h2, 'canceled';
    insert into _probe_result values ('held_did_not_go_through', 'canceled', v);
  exception when others then
    insert into _probe_result values ('held_did_not_go_through', 'canceled', sqlerrm);
  end;
  begin
    select status::text || ' ' || amount_cents into v from public.admin_charge_registration(rk, 'clinic_fee');
    insert into _probe_result values ('canceled_hold_frees_the_charge', 'pending 1800', v);
  exception when others then
    insert into _probe_result values ('canceled_hold_frees_the_charge', 'pending 1800', sqlerrm);
  end;
  begin
    execute 'select public.admin_resolve_held_payment($1, $2)' using p3, 'succeeded';
    insert into _probe_result values ('in_flight_row_refused', 'payment_not_held', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('in_flight_row_refused', 'payment_not_held', sqlerrm);
  end;
  begin
    execute 'select public.admin_resolve_held_payment($1, $2)' using h1, 'canceled';
    insert into _probe_result values ('resolved_row_refused', 'payment_not_held', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('resolved_row_refused', 'payment_not_held', sqlerrm);
  end;
  begin
    execute 'select public.admin_resolve_held_payment($1, $2)' using h2, 'refunded';
    insert into _probe_result values ('unknown_outcome_refused', 'invalid_outcome', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('unknown_outcome_refused', 'invalid_outcome', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  select paid::text into v from public.registrations where id = rm;
  insert into _probe_result values ('went_through_marks_paid', 'true', v);
  select status::text || ' ' || (select paid::text from public.registrations where id = rr) into v from public.payments where id = p3;
  insert into _probe_result values ('in_flight_row_unchanged', 'processing false', v);
  select status::text into v from public.payments where id = h1;
  insert into _probe_result values ('resolved_row_unchanged', 'succeeded', v);

  -- -------------------------------------------------------------- grants
  insert into _probe_result values ('anon_cannot_resolve', 'false',
    coalesce(has_function_privilege('anon', fn, 'EXECUTE')::text, 'MISSING'));
  insert into _probe_result values ('authenticated_can_resolve', 'true',
    coalesce(has_function_privilege('authenticated', fn, 'EXECUTE')::text, 'MISSING'));
  select coalesce(max(has_column_privilege('authenticated', 'public.payments'::regclass, a.attnum, 'SELECT')::text), 'MISSING')
    into v from pg_attribute a where a.attrelid = 'public.payments'::regclass and a.attname = 'first_attempted_at';
  insert into _probe_result values ('first_attempted_at_not_readable_by_clients', 'false', v);
  select coalesce(max(has_column_privilege('authenticated', 'public.payments'::regclass, a.attnum, 'UPDATE')::text), 'MISSING')
    into v from pg_attribute a where a.attrelid = 'public.payments'::regclass and a.attname = 'first_attempted_at';
  insert into _probe_result values ('first_attempted_at_not_writable_by_clients', 'false', v);
  select coalesce(max(has_column_privilege('service_role', 'public.payments'::regclass, a.attnum, 'UPDATE')::text), 'MISSING')
    into v from pg_attribute a where a.attrelid = 'public.payments'::regclass and a.attname = 'first_attempted_at';
  insert into _probe_result values ('first_attempted_at_written_by_service_role', 'true', v);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
