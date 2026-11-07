-- audit_fixes_1012.sql
--
-- The 2026-10-12 full error audits' database fixes (20261013000001). Written
-- from the rule; every expected value is worked out by hand.
--
-- THE RULES
--   1. A clinic's price is her table's price for its length: 60 min is $18
--      member / $23 non-member, 90 min is $22 / $28. Changing the length
--      changes the price; changing anything else does not. Someone already
--      in keeps the price they signed up at (question 113 open).
--   2. Canceling a clinic cancels its charges not yet sent to Stripe. A
--      refund still goes; a charge already with Stripe is left for Tara.
--   4. A fee refunded in full reads "refunded" on Tara's roster; a partial
--      refund leaves it charged.
--   3. Past lists only clinics she was in or canceled from: a Player Pool
--      spot never picked and an invitation never answered are not there. A
--      clinic Tara canceled says so.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  c uuid; ce uuid; cp uuid; cx uuid; reg uuid; r_ken uuid;
  p_pending uuid; p_sent uuid; p_refund uuid;
  v text; n int;
begin
  -- ----------------------------------------------- 1. a new length, a new price
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select id into c from public.admin_upsert_clinic(p_name => 'Probe length', p_audience => 'coed',
      p_starts_at => now() + interval '6 days', p_duration_minutes => 60, p_internal_capacity => 8);
  perform set_config('role', 'postgres', true);
  update public.clinics set status = 'published' where id = c;
  select member_price_cents || '/' || nonmember_price_cents into v from public.clinics where id = c;
  insert into _probe_result values ('sixty_minutes_prices', '1800/2300', v);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c, MARIA_P, 'in', 'self', 1800, true, 60) returning id into reg;

  perform set_config('role', 'authenticated', true);
  perform public.admin_upsert_clinic(p_id => c, p_duration_minutes => 90);
  perform set_config('role', 'postgres', true);
  select member_price_cents || '/' || nonmember_price_cents || '/' || duration_minutes into v from public.clinics where id = c;
  insert into _probe_result values ('ninety_minutes_reprices', '2200/2800/90', v);
  select price_cents_charged::text into v from public.registrations where id = reg;
  insert into _probe_result values ('already_in_keeps_their_price', '1800', v);

  perform set_config('role', 'authenticated', true);
  perform public.admin_upsert_clinic(p_id => c, p_name => 'Probe length renamed');
  perform public.admin_upsert_clinic(p_id => c, p_duration_minutes => 90);
  perform set_config('role', 'postgres', true);
  select member_price_cents || '/' || nonmember_price_cents into v from public.clinics where id = c;
  insert into _probe_result values ('other_edits_keep_the_price', '2200/2800', v);

  perform set_config('role', 'authenticated', true);
  perform public.admin_upsert_clinic(p_id => c, p_duration_minutes => 60);
  perform set_config('role', 'postgres', true);
  select member_price_cents || '/' || nonmember_price_cents into v from public.clinics where id = c;
  insert into _probe_result values ('back_to_sixty_reprices', '1800/2300', v);

  -- ------------------------------- 2. a canceled clinic's queued charges stop
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe rained out', 'coed', 'Clinic', 'probe', now() - interval '3 hours', now() - interval '2 hours',
          now() - interval '5 days', now() - interval '4 days', 8, 'published', 60)
  returning id into ce;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, MARIA_P, 'in', 'self', 1800, true, 60) returning id into reg;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken;
  -- Maria: a charge queued, never sent. Ken: a charge already with Stripe,
  -- and a refund of an earlier one queued.
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (reg, MARIA, 'clinic_fee', 1800, 'pending') returning id into p_pending;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, stripe_payment_intent_id, first_attempted_at)
  values (r_ken, KEN, 'clinic_fee', 1800, 'processing', 'pi_probe_sent', now()) returning id into p_sent;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, refunds_payment_id)
  values (r_ken, KEN, 'refund', 1800, 'pending', p_sent) returning id into p_refund;

  perform set_config('role', 'authenticated', true);
  perform public.cancel_clinic(ce);
  perform set_config('role', 'postgres', true);
  select status::text || '|' || coalesce(failure_reason, '') into v from public.payments where id = p_pending;
  insert into _probe_result values ('queued_charge_canceled', '[canceled|clinic_canceled]', '[' || v || ']');
  select status::text into v from public.payments where id = p_sent;
  insert into _probe_result values ('charge_with_stripe_left_alone', 'processing', v);
  select status::text into v from public.payments where id = p_refund;
  insert into _probe_result values ('queued_refund_still_goes', 'pending', v);

  -- ------------------------------- 4. a refunded fee reads refunded
  -- Ken's charge went through and was refunded in full: the roster says so.
  update public.payments set status = 'succeeded' where id = p_sent;
  update public.payments set status = 'succeeded' where id = p_refund;
  select charge_status into v from public.registrations_admin where id = r_ken;
  insert into _probe_result values ('roster_reads_refunded', 'refunded', coalesce(v, '<null>'));
  -- A partial refund leaves it charged.
  update public.payments set amount_cents = 500 where id = p_refund;
  select charge_status into v from public.registrations_admin where id = r_ken;
  insert into _probe_result values ('partial_refund_still_charged', 'succeeded', coalesce(v, '<null>'));

  -- --------------------------------------- 3. Past is what she played
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe past', 'coed', 'Clinic', 'probe', now() - interval '4 days', now() - interval '4 days' + interval '1 hour',
          now() - interval '10 days', now() - interval '9 days', 8, 'published', 60)
  returning id into cp;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, invited_at)
  values (cp, MARIA_P, 'pool', 'self', 1800, true, 60, null),
         (cp, KEN_P, 'response_needed', 'self', 1800, true, 60, now() - interval '5 days'),
         (cp, ROB_P, 'in', 'self', 2300, false, 60, null);
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, published_at)
  values ('Probe past canceled', 'coed', 'Clinic', 'probe', now() - interval '3 days', now() - interval '3 days' + interval '1 hour',
          now() - interval '9 days', now() - interval '8 days', 8, 'canceled', 60, now() - interval '9 days')
  returning id into cx;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cx, DANA_P, 'in', 'self', 1800, true, 60);

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.my_past_clinics where clinic_id = cp;
  insert into _probe_result values ('pool_never_picked_not_past', '0', n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select count(*) into n from public.my_past_clinics where clinic_id = cp;
  insert into _probe_result values ('invitation_never_answered_not_past', '0', n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', '44444444-4444-4444-4444-444444444444')::text, true);
  select count(*) || '|' || bool_and(not clinic_canceled)::text into v from public.my_past_clinics where clinic_id = cp;
  insert into _probe_result values ('played_is_past', '1|true', v);
  perform set_config('request.jwt.claims', json_build_object('sub', '66666666-6666-6666-6666-666666666666')::text, true);
  select count(*) || '|' || bool_and(clinic_canceled)::text into v from public.my_past_clinics where clinic_id = cx;
  insert into _probe_result values ('canceled_clinic_says_so', '1|true', v);
  perform set_config('role', 'postgres', true);
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
