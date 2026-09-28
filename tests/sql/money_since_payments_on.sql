-- money_since_payments_on.sql
--
-- What the Money numbers and Charge clinic may treat as owed (20260927300001,
-- MVP fix round 2026-09-27). Written FROM THE RULE; every expected value is
-- worked out by hand from the fixture and written as a literal.
--
-- THE RULE
--   * app_settings.payments_enabled_at is the moment card payments were
--     switched on. Whoever sets payments_enabled to 'true' sets it in the same
--     change. Empty (or missing) means payments have never been on.
--   * A registration owes something only if its clinic ended AT OR AFTER that
--     moment. Before it, the club ran on Zelle and the Paid checkbox; nothing
--     from then is "not charged yet" or "declined". Empty: nothing owes.
--   * Charge clinic refuses a clinic that ended before that moment, and any
--     clinic while it is empty (clinic_before_payments), charging nothing.
--   * A registration Tara marked Paid (registrations.paid) and holding no live
--     fee is settled: not "not charged yet", not "declined", and Charge clinic
--     skips it (counted under not_owed).
--   * A decline on a deleted account stays in the declined list, flagged
--     account_deleted, so Action Needed can leave it out while the Money list
--     keeps it (M5).
--   * payments has a plain index on refunds_payment_id for refund rows (M2):
--     every "is this fee refunded" test looks refunds up by the fee's id.
--   * A LOST DISPUTE NEVER RE-OPENS A CHARGE (20260928200001). The fee stays
--     'charged' and keeps the player's one-fee slot, so the clinic owes
--     nothing and Charge clinic answers "already charged" for that player
--     instead of charging the card the bank just took the money back from.
--
-- FIXTURE (New York). payments_enabled on, payments_enabled_at = T0 = 2026-09-01 00:00.
--   A  ended 2026-08-20 19:00 (before T0): Maria in (card, unpaid), Ken no-show (card).
--   B  ended 2026-09-10 19:00 (after T0):
--        Maria in, card, unpaid, no charge                 -> not charged, chargeable 1800
--        Priya in, no card, unpaid                         -> not charged, not chargeable 2300
--        Rob   in, card, PAID by Tara, a failed 2300 charge -> settled
--        Dana  in, no card (deleted account), unpaid, failed 1800 charge -> declined, account_deleted
--   C  ended exactly T0: Ken in, card, unpaid -> not charged (at-or-after); Rob in, card, PAID, no charge -> settled.
--   D  ended 2026-09-12 19:00 (after T0): Ken in, card, unpaid, his 1800 clinic fee
--        succeeded and then LOST a dispute for all 1800.
--
-- EXPECTED
--   A: no admin_money_clinics row; Charge clinic refused clinic_before_payments; 0 payments on A.
--   B: not_charged 2 / 4100 cents, chargeable 1, declined 1.
--      declined list for B: "Dana|1800|true" (name as stored, amount, account_deleted).
--      Charge clinic: {"already": 0, "charged": 1, "no_card": 2, "not_owed": 1}
--        (Maria charged; Priya and Dana no card; Rob paid by hand).
--   C: not_charged 1 / 1800, chargeable 1. Charge clinic:
--      {"already": 0, "charged": 1, "no_card": 0, "not_owed": 1}.
--   With payments_enabled_at emptied: summary declined 0 and not charged 0, and
--      Charge clinic on B refused clinic_before_payments.
--   D: Ken's row is 'charged'; no admin_money_clinics row (owes nothing, net 0);
--      Charge clinic: {"already": 1, "charged": 0, "no_card": 0, "not_owed": 0};
--      still exactly one payment on his registration.
--   Index: one non-unique index on payments(refunds_payment_id) where kind = 'refund'.
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
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  DANA    constant uuid := '66666666-6666-6666-6666-666666666666';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  ny      constant text := 'America/New_York';
  ca uuid; cb uuid; cc uuid; cdl uuid; b_rob uuid; b_dana uuid; d_ken uuid;
  v text; n int; j jsonb;
begin
  -- ------------------------------------------------------------ fixture
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  insert into public.app_settings (key, value)
  values ('payments_enabled_at', (timestamp '2026-09-01 00:00' at time zone ny)::text)
  on conflict (key) do update set value = excluded.value;

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe before payments', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-20 18:00' at time zone ny, timestamp '2026-08-20 19:00' at time zone ny,
          timestamp '2026-08-13 08:00' at time zone ny, timestamp '2026-08-14 08:00' at time zone ny, 8, 'published', 60)
  returning id into ca;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe after payments', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-10 18:00' at time zone ny, timestamp '2026-09-10 19:00' at time zone ny,
          timestamp '2026-09-03 08:00' at time zone ny, timestamp '2026-09-04 08:00' at time zone ny, 8, 'published', 60)
  returning id into cb;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe at the switch', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-31 23:00' at time zone ny, timestamp '2026-09-01 00:00' at time zone ny,
          timestamp '2026-08-27 08:00' at time zone ny, timestamp '2026-08-28 08:00' at time zone ny, 8, 'published', 60)
  returning id into cc;

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe disputed and lost', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-12 18:00' at time zone ny, timestamp '2026-09-12 19:00' at time zone ny,
          timestamp '2026-09-03 08:00' at time zone ny, timestamp '2026-09-04 08:00' at time zone ny, 8, 'published', 60)
  returning id into cdl;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cdl, KEN_P, 'in', 'self', 1800, true, 60) returning id into d_ken;
  -- As stripe-webhook leaves it: the fee went through, then the bank took it back.
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, stripe_payment_intent_id,
      stripe_dispute_id, dispute_status, dispute_reason, dispute_amount_cents, dispute_withdrawn_cents, dispute_event_at)
  values (d_ken, KEN, 'clinic_fee', 1800, 'succeeded', 'pi_probe_lost', 'dp_probe_lost', 'lost', 'fraudulent', 1800, 1800, now());

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ca, MARIA_P, 'in', 'self', 1800, true, 60);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, no_show)
  values (ca, KEN_P, 'in', 'self', 1800, true, 60, true);

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cb, MARIA_P, 'in', 'self', 1800, true, 60);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cb, PRIYA_P, 'in', 'self', 2300, false, 60);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, paid)
  values (cb, ROB_P, 'in', 'self', 2300, false, 60, true) returning id into b_rob;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cb, DANA_P, 'in', 'self', 1800, true, 60) returning id into b_dana;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_code, failure_reason)
  values (b_rob, ROB, 'clinic_fee', 2300, 'failed', 'card_declined', 'Your card was declined.');
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_code, failure_reason)
  values (b_dana, DANA, 'clinic_fee', 1800, 'failed', 'expired_card', 'Your card has expired.');

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cc, KEN_P, 'in', 'self', 1800, true, 60);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, paid)
  values (cc, ROB_P, 'in', 'self', 2300, false, 60, true);

  update public.accounts set stripe_customer_id = 'cus_probe_maria', card_brand = 'visa', card_last4 = '4242' where id = MARIA;
  update public.accounts set stripe_customer_id = 'cus_probe_ken',   card_brand = 'visa', card_last4 = '4242' where id = KEN;
  update public.accounts set stripe_customer_id = 'cus_probe_rob',   card_brand = 'visa', card_last4 = '4242' where id = ROB;
  -- Dana deleted her account: delete_my_account scrubs the card.
  update public.accounts set deleted_at = now(), stripe_customer_id = null, card_brand = null, card_last4 = null where id = DANA;

  -- --------------------------------------------------------- as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  select count(*) into n from public.admin_money_clinics() where clinic_id = ca;
  insert into _probe_result values ('clinic_before_payments_owes_nothing', '0', n::text);

  -- A lost dispute (20260928200001): charged, owes nothing, never charged again.
  select count(*) into n from public.admin_money_clinics() where clinic_id = cdl;
  insert into _probe_result values ('lost_dispute_clinic_owes_nothing', '0', n::text);
  begin
    j := public.admin_charge_clinic(cdl);
    insert into _probe_result values ('charge_clinic_never_recharges_a_lost_dispute', '{"already": 1, "charged": 0, "no_card": 0, "not_owed": 0}', j::text);
  exception when others then
    insert into _probe_result values ('charge_clinic_never_recharges_a_lost_dispute', '{"already": 1, "charged": 0, "no_card": 0, "not_owed": 0}', sqlerrm);
  end;
  select coalesce(max(not_charged_count || '|' || not_charged_cents || '|' || chargeable_count || '|' || declined_count), 'NO ROW')
    into v from public.admin_money_clinics() where clinic_id = cb;
  insert into _probe_result values ('clinic_after_payments_owes_paid_is_settled', '2|4100|1|1', v);
  select coalesce(max(not_charged_count || '|' || not_charged_cents || '|' || chargeable_count || '|' || declined_count), 'NO ROW')
    into v from public.admin_money_clinics() where clinic_id = cc;
  insert into _probe_result values ('clinic_ending_at_the_switch_owes', '1|1800|1|0', v);

  begin
    select string_agg(d.first_name || '|' || d.amount_cents || '|' || d.account_deleted, ',') into v
      from public.admin_money_declined() d where d.clinic_id = cb;
    insert into _probe_result values ('deleted_account_decline_listed_and_flagged', 'Dana|1800|true', coalesce(v, 'NO ROW'));
  exception when others then
    insert into _probe_result values ('deleted_account_decline_listed_and_flagged', 'Dana|1800|true', sqlerrm);
  end;

  begin
    j := public.admin_charge_clinic(ca);
    insert into _probe_result values ('charge_clinic_before_payments_refused', 'clinic_before_payments', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('charge_clinic_before_payments_refused', 'clinic_before_payments', sqlerrm);
  end;

  begin
    j := public.admin_charge_clinic(cb);
    insert into _probe_result values ('charge_clinic_skips_paid_by_hand', '{"already": 0, "charged": 1, "no_card": 2, "not_owed": 1}', j::text);
  exception when others then
    insert into _probe_result values ('charge_clinic_skips_paid_by_hand', '{"already": 0, "charged": 1, "no_card": 2, "not_owed": 1}', sqlerrm);
  end;
  begin
    j := public.admin_charge_clinic(cc);
    insert into _probe_result values ('charge_clinic_at_the_switch', '{"already": 0, "charged": 1, "no_card": 0, "not_owed": 1}', j::text);
  exception when others then
    insert into _probe_result values ('charge_clinic_at_the_switch', '{"already": 0, "charged": 1, "no_card": 0, "not_owed": 1}', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  select count(*) into n from public.payments x join public.registrations r on r.id = x.registration_id where r.clinic_id = ca;
  insert into _probe_result values ('nothing_charged_before_payments', '0', n::text);
  select count(*) into n from public.payments where registration_id = b_rob and status <> 'failed';
  insert into _probe_result values ('paid_by_hand_not_charged', '0', n::text);
  select coalesce(max(m.state), 'NO ROW') into v from public.money_rows() m where m.registration_id = d_ken;
  insert into _probe_result values ('lost_dispute_leaves_the_fee_charged', 'charged', v);
  select count(*) into n from public.payments where registration_id = d_ken;
  insert into _probe_result values ('still_one_payment_after_a_lost_dispute', '1', n::text);

  -- Payments never switched on: nothing owes, nothing is declined, nothing can be charged.
  update public.app_settings set value = '' where key = 'payments_enabled_at';
  perform set_config('role', 'authenticated', true);
  select declined_count || '|' || not_charged_count into v from public.admin_money_summary();
  insert into _probe_result values ('never_switched_on_nothing_owed', '0|0', v);
  begin
    j := public.admin_charge_clinic(cb);
    insert into _probe_result values ('never_switched_on_charge_refused', 'clinic_before_payments', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('never_switched_on_charge_refused', 'clinic_before_payments', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------------- M2
  select count(*) into n from pg_indexes
   where schemaname = 'public' and tablename = 'payments'
     and indexdef not like 'CREATE UNIQUE%'
     and indexdef like '%(refunds_payment_id)%'
     and indexdef like '%kind = ''refund''::payment_kind%';
  insert into _probe_result values ('refund_lookup_index_exists', '1', n::text);

  -- ------------------------------------------------------------ grants
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('payments_enabled_at', 'payment_is_real');
  insert into _probe_result values ('both_helpers_exist', '2', n::text);
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('payments_enabled_at', 'payment_is_real')
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE') or has_function_privilege('anon', p.oid, 'EXECUTE'));
  insert into _probe_result values ('helpers_not_client_callable', '0', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
