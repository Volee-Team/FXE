-- stripe_live_cutover.sql
--
-- The sandbox-to-live switch (20260927200001, MVP audit item 3). Written FROM
-- THE RULE in that migration's header; every expected value is worked out by
-- hand from the fixture below and written as a literal.
--
-- THE RULE
--   * payments.livemode is Stripe's flag: false is test mode, null is "not
--     recorded yet" (older rows), true is live.
--   * Test-mode money is not money: the board report counts no payment whose
--     livemode is false, and a test-mode row never moves the Paid flag (a
--     test fee does not mark paid; a test refund does not unmark it).
--   * payments_ledger lists test rows until the switch and hides them after;
--     live rows are always listed.
--   * stripe_cutover_to_live(), run once by postgres or service_role: clears
--     every account's Stripe customer and card summary, cancels rows still
--     pending or processing (reason live_cutover), marks rows with no
--     recorded mode as test mode, records app_settings.stripe_live_since.
--     Refuses while any live payment exists (live_payments_exist) and refuses
--     a second run (already_live), in both cases changing nothing.
--
-- FIXTURE (New York times)
--   L  Wed 2026-08-12 18:00, 60 min, ended
--      Maria in t 1800  PL fee 1800 S live   ; RL refund of PL 500 S live
--      Rob   in f 2300  PT fee 2300 S TEST   (a sandbox charge nobody refunded)
--      Priya in f 2300  PN fee 2300 S null   (a row older than the column)
--   M  Thu 2026-08-13 18:00 (outside the report period; the Paid flag checks)
--      Maria m1: T1 test fee succeeds; Tara marks m1 paid by hand; T1R test
--                refund of T1 succeeds
--      Ken   m2: L1 live fee succeeds; L1R live refund of L1 succeeds
--      Dana  m3: N1 fee with no recorded mode succeeds
--      Priya m4: W1 fee succeeds and learns it was test mode in the same
--                update, the way the webhook writes it
--   Stripe data: Maria cus_probe_maria with Visa 4242; Ken cus_probe_ken, no card.
--
-- EXPECTED
--   Board report 2026-08-12..2026-08-12:
--     members 1 (Maria), non-members 2 (Rob, Priya), fees due 1800+2300+2300 = 6400
--     collected = PL 1800 + PN 2300 - RL 500 = 3600   (PT, test mode, not counted;
--       the old definition said 1800+2300+2300-500 = 5900)
--     10% of 3600 = 360; clinic row L collected 3600
--   Paid flags: m1 false after T1, true after Tara's mark and still true after
--     T1R; m2 true after L1, false after L1R; m3 true (null counts as before);
--     m4 false.
--   Ledger before the switch, as Tara, rows of L and M: PL RL PT PN T1 T1R L1 L1R
--     N1 W1 = 10.
--   Refused while PL, RL, L1, L1R (live) exist: Maria keeps 4242, no stripe_live_since.
--   Then the live rows are removed ("the swap happened before any live
--   charge"), and two rows still waiting are added in clinic W (Fri
--   2026-08-14): Q1 (Rob fee 2300, pending, no mode) and Q2 (Dana fee 1800,
--   processing, pi_probe_q2, test). Each has its own registration, so no
--   one-charge rule can refuse the fixture itself.
--   Cutover returns accounts 2 (Maria, Ken), canceled 2 (Q1, Q2),
--     marked test 3 (PN, N1, Q1: the rows still without a mode).
--   After: Maria's four card columns empty; Q1 canceled live_cutover false;
--     PN still succeeded, now false; stripe_live_since set to the returned time;
--     ledger rows of L, M and W as Tara 0; board report collected 0 (due still 6400);
--     a new live row is listed (1); Maria, with payments on, is refused
--     card_required; a second run is refused already_live and Maria's re-added
--     card survives it.
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
  PRIYA   constant uuid := '55555555-5555-5555-5555-555555555555';
  DANA    constant uuid := '66666666-6666-6666-6666-666666666666';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  FAR     constant uuid := 'd0000000-0000-0000-0000-000000000002';
  ny      constant text := 'America/New_York';
  cl uuid; cm uuid; cw uuid;
  r_lm uuid; r_lr uuid; r_lp uuid; m1 uuid; m2 uuid; m3 uuid; m4 uuid; w_rob uuid; w_dana uuid;
  pl uuid; pt uuid; pn uuid; t1 uuid; t1r uuid; l1 uuid; l1r uuid; n1 uuid; w1 uuid; q1 uuid; q2 uuid;
  s record; v text; n int; at_ts timestamptz; r public.registrations;
begin
  -- ------------------------------------------------------------ fixture
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe live Aug 12', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-12 18:00' at time zone ny, timestamp '2026-08-12 19:00' at time zone ny,
          timestamp '2026-08-06 08:00' at time zone ny, timestamp '2026-08-07 08:00' at time zone ny, 8, 'published', 60)
  returning id into cl;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe paid Aug 13', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-13 18:00' at time zone ny, timestamp '2026-08-13 19:00' at time zone ny,
          timestamp '2026-08-06 08:00' at time zone ny, timestamp '2026-08-07 08:00' at time zone ny, 8, 'published', 60)
  returning id into cm;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe waiting Aug 14', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-14 18:00' at time zone ny, timestamp '2026-08-14 19:00' at time zone ny,
          timestamp '2026-08-06 08:00' at time zone ny, timestamp '2026-08-07 08:00' at time zone ny, 8, 'published', 60)
  returning id into cw;

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cl, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_lm;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cl, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_lr;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cl, PRIYA_P, 'in', 'self', 2300, false, 60) returning id into r_lp;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cm, MARIA_P, 'in', 'self', 1800, true, 60) returning id into m1;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cm, KEN_P, 'in', 'self', 1800, true, 60) returning id into m2;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cm, DANA_P, 'in', 'self', 1800, true, 60) returning id into m3;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cm, PRIYA_P, 'in', 'self', 2300, false, 60) returning id into m4;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cw, ROB_P, 'in', 'self', 2300, false, 60) returning id into w_rob;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cw, DANA_P, 'in', 'self', 1800, true, 60) returning id into w_dana;

  update public.accounts set stripe_customer_id = 'cus_probe_maria', card_brand = 'visa',
                             card_last4 = '4242', card_added_at = now() where id = MARIA;
  update public.accounts set stripe_customer_id = 'cus_probe_ken' where id = KEN;

  -- Clinic L's ledger, as the edge functions would have left it.
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, stripe_payment_intent_id)
  values (r_lm, MARIA, 'clinic_fee', 1800, 'succeeded', true, 'pi_probe_pl') returning id into pl;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, refunds_payment_id, stripe_refund_id)
  values (r_lm, MARIA, 'refund', 500, 'succeeded', true, pl, 're_probe_rl');
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, stripe_payment_intent_id)
  values (r_lr, ROB, 'clinic_fee', 2300, 'succeeded', false, 'pi_probe_pt') returning id into pt;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, stripe_payment_intent_id)
  values (r_lp, PRIYA, 'clinic_fee', 2300, 'succeeded', 'pi_probe_pn') returning id into pn;

  -- ------------------------------------------- 1. the Paid flag (as postgres)
  -- Rows start processing and succeed by UPDATE, the path the webhook takes,
  -- because the trigger is BEFORE UPDATE.
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode)
  values (m1, MARIA, 'clinic_fee', 1800, 'processing', false) returning id into t1;
  update public.payments set status = 'succeeded' where id = t1;
  select paid::text into v from public.registrations where id = m1;
  insert into _probe_result values ('test_fee_does_not_mark_paid', 'false', v);

  update public.registrations set paid = true where id = m1;   -- Tara's own mark
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, refunds_payment_id)
  values (m1, MARIA, 'refund', 1800, 'processing', false, t1) returning id into t1r;
  update public.payments set status = 'succeeded' where id = t1r;
  select paid::text into v from public.registrations where id = m1;
  insert into _probe_result values ('test_refund_does_not_unmark_paid', 'true', v);

  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode)
  values (m2, KEN, 'clinic_fee', 1800, 'processing', true) returning id into l1;
  update public.payments set status = 'succeeded' where id = l1;
  select paid::text into v from public.registrations where id = m2;
  insert into _probe_result values ('live_fee_marks_paid', 'true', v);
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, refunds_payment_id)
  values (m2, KEN, 'refund', 1800, 'processing', true, l1) returning id into l1r;
  update public.payments set status = 'succeeded' where id = l1r;
  select paid::text into v from public.registrations where id = m2;
  insert into _probe_result values ('live_refund_unmarks_paid', 'false', v);

  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (m3, DANA, 'clinic_fee', 1800, 'processing') returning id into n1;
  update public.payments set status = 'succeeded' where id = n1;
  select paid::text into v from public.registrations where id = m3;
  insert into _probe_result values ('fee_with_no_recorded_mode_marks_paid_as_before', 'true', v);

  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (m4, PRIYA, 'clinic_fee', 2300, 'processing') returning id into w1;
  update public.payments set status = 'succeeded', livemode = false where id = w1;
  select paid::text into v from public.registrations where id = m4;
  insert into _probe_result values ('webhook_style_test_success_does_not_mark_paid', 'false', v);

  -- ------------------------------------------------------ 2. grants
  insert into _probe_result values ('cutover_not_executable_by_authenticated', 'false',
    has_function_privilege('authenticated', 'public.stripe_cutover_to_live()', 'EXECUTE')::text);
  insert into _probe_result values ('cutover_not_executable_by_anon', 'false',
    has_function_privilege('anon', 'public.stripe_cutover_to_live()', 'EXECUTE')::text);
  insert into _probe_result values ('cutover_executable_by_service_role', 'true',
    has_function_privilege('service_role', 'public.stripe_cutover_to_live()', 'EXECUTE')::text);
  insert into _probe_result values ('livemode_not_writable_by_authenticated', 'false',
    has_column_privilege('authenticated', 'public.payments'::regclass, 'livemode', 'UPDATE')::text);

  -- ------------------------------------ 3. as Tara, before the switch
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select member_attendances || '|' || nonmember_attendances || '|' || fees_due_cents || '|'
         || collected_cents || '|' || board_share_cents
    into v from public.admin_board_report('2026-08-12', '2026-08-12');
  insert into _probe_result values ('board_report_counts_no_test_money', '1|2|6400|3600|360', v);
  select collected_cents::text into v from public.admin_board_report_clinics('2026-08-12', '2026-08-12') where clinic_id = cl;
  insert into _probe_result values ('board_clinic_row_counts_no_test_money', '3600', coalesce(v, 'NULL'));

  select count(*) into n from public.payments_ledger where clinic_id in (cl, cm);
  insert into _probe_result values ('ledger_lists_test_rows_before_the_switch', '10', n::text);
  select livemode::text into v from public.payments_ledger where id = pt;
  insert into _probe_result values ('ledger_carries_livemode', 'false', coalesce(v, 'NULL'));
  perform set_config('role', 'postgres', true);

  -- 3b. Before the switch a sandbox charge still holds its one-charge slot
  --     (20260927300001): the sandbox run of docs/stripe-e2e-test.md must see
  --     "already charged" on a second tap, exactly as a member will.
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  perform set_config('role', 'authenticated', true);
  select charge_status into v from public.registrations_admin where id = r_lr;
  insert into _probe_result values ('before_switch_test_fee_shows_on_roster', 'succeeded', coalesce(v, 'NULL'));
  begin
    perform public.admin_charge_registration(r_lr, 'clinic_fee');
    insert into _probe_result values ('before_switch_test_fee_blocks_second_charge', 'already_charged', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('before_switch_test_fee_blocks_second_charge', 'already_charged', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  update public.app_settings set value = 'false' where key = 'payments_enabled';

  -- -------------------------------- 4. refused while live money exists
  begin
    perform * from public.stripe_cutover_to_live();
    insert into _probe_result values ('cutover_refused_after_a_live_payment', 'live_payments_exist', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('cutover_refused_after_a_live_payment', 'live_payments_exist', sqlerrm);
  end;
  select coalesce(card_last4, 'NULL') into v from public.accounts where id = MARIA;
  insert into _probe_result values ('refused_cutover_keeps_cards', '4242', v);
  select count(*) into n from public.app_settings where key = 'stripe_live_since';
  insert into _probe_result values ('refused_cutover_records_no_switch', '0', n::text);

  -- The swap happened before any live charge: remove the live rows, then add
  -- the two still waiting.
  delete from public.payments where livemode is true and kind = 'refund';
  delete from public.payments where livemode is true;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (w_rob, ROB, 'clinic_fee', 2300, 'pending') returning id into q1;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, stripe_payment_intent_id)
  values (w_dana, DANA, 'clinic_fee', 1800, 'processing', false, 'pi_probe_q2') returning id into q2;

  -- -------------------------------------------------------- 5. the switch
  select * into s from public.stripe_cutover_to_live();
  insert into _probe_result values ('cutover_counts', '2|2|3',
    s.accounts_cleared || '|' || s.payments_canceled || '|' || s.payments_marked_test);

  select coalesce(stripe_customer_id, 'NULL') || '|' || coalesce(card_brand, 'NULL') || '|'
         || coalesce(card_last4, 'NULL') || '|' || coalesce(card_added_at::text, 'NULL')
    into v from public.accounts where id = MARIA;
  insert into _probe_result values ('maria_card_cleared', 'NULL|NULL|NULL|NULL', v);
  select coalesce(stripe_customer_id, 'NULL') into v from public.accounts where id = KEN;
  insert into _probe_result values ('ken_customer_cleared', 'NULL', v);
  select count(*) into n from public.accounts
   where stripe_customer_id is not null or card_brand is not null or card_last4 is not null or card_added_at is not null;
  insert into _probe_result values ('no_account_keeps_stripe_data', '0', n::text);

  select status || '|' || coalesce(failure_reason, 'NULL') || '|' || coalesce(livemode::text, 'NULL')
    into v from public.payments where id = q1;
  insert into _probe_result values ('waiting_charge_canceled_and_marked_test', 'canceled|live_cutover|false', v);
  select status::text into v from public.payments where id = q2;
  insert into _probe_result values ('processing_charge_canceled', 'canceled', v);
  select status || '|' || coalesce(livemode::text, 'NULL') into v from public.payments where id = pn;
  insert into _probe_result values ('old_row_kept_and_marked_test', 'succeeded|false', v);
  select (value = s.live_since::text)::text into v from public.app_settings where key = 'stripe_live_since';
  insert into _probe_result values ('switch_moment_recorded', 'true', coalesce(v, 'NULL'));

  -- ------------------------------------------ 6. as Tara, after the switch
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.payments_ledger where clinic_id in (cl, cm, cw);
  insert into _probe_result values ('ledger_hides_test_rows_after_the_switch', '0', n::text);
  select fees_due_cents || '|' || collected_cents into v from public.admin_board_report('2026-08-12', '2026-08-12');
  insert into _probe_result values ('board_report_after_the_switch', '6400|0', v);
  perform set_config('role', 'postgres', true);

  -- On Maria's L registration, whose live rows were removed above: Rob's
  -- still holds PT, and a succeeded fee (test or not) keeps its one-charge slot.
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode)
  values (r_lm, MARIA, 'clinic_fee', 1800, 'succeeded', true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.payments_ledger where clinic_id in (cl, cm, cw);
  insert into _probe_result values ('ledger_lists_live_rows_after_the_switch', '1', n::text);

  -- 6b. After the switch test money is not money anywhere (20260927300001):
  --     the Money tab's Charged for clinic L is the one live 1800 fee just
  --     added (not 1800 + PT 2300 + PN 2300, both test mode now).
  select charged_cents::text into v from public.admin_money_clinics() where clinic_id = cl;
  insert into _probe_result values ('after_switch_money_charged_counts_no_test_money', '1800', coalesce(v, 'NULL'));
  select charge_status into v from public.registrations_admin where id = r_lr;
  insert into _probe_result values ('after_switch_test_fee_leaves_the_roster', 'NULL', coalesce(v, 'NULL'));
  perform set_config('role', 'postgres', true);

  -- Maria had a (sandbox) card before; with payments on, she must add a real one.
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    r := public.register_for_clinic(FAR, MARIA_P);
    insert into _probe_result values ('maria_asked_for_a_real_card', 'card_required', 'CALL SUCCEEDED ' || r.status::text);
  exception when others then
    insert into _probe_result values ('maria_asked_for_a_real_card', 'card_required', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- 6c. Rob's L registration still holds PT, a succeeded TEST fee. After the
  --     switch it is not a charge: with a real card on file Tara can charge
  --     him for real, through the RPC and past the unique index.
  update public.accounts set stripe_customer_id = 'cus_live_rob', card_brand = 'visa',
                             card_last4 = '5556', card_added_at = now() where id = ROB;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    select status::text || ' ' || amount_cents into v from public.admin_charge_registration(r_lr, 'clinic_fee');
    insert into _probe_result values ('after_switch_test_fee_does_not_block_a_real_charge', 'pending 2300', v);
  exception when others then
    insert into _probe_result values ('after_switch_test_fee_does_not_block_a_real_charge', 'pending 2300', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from pg_indexes
   where schemaname = 'public' and tablename = 'payments'
     and indexname in ('payments_one_live_charge', 'payments_one_live_app_refund')
     and indexdef like '%livemode IS NOT FALSE%';
  insert into _probe_result values ('unique_charge_indexes_ignore_test_rows', '2', n::text);

  -- ------------------------------------------------- 7. never twice
  update public.accounts set stripe_customer_id = 'cus_live_maria', card_brand = 'visa',
                             card_last4 = '1881', card_added_at = now() where id = MARIA;
  delete from public.payments where livemode is true;   -- so only the once-guard can refuse
  begin
    perform * from public.stripe_cutover_to_live();
    insert into _probe_result values ('second_cutover_refused', 'already_live', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('second_cutover_refused', 'already_live', sqlerrm);
  end;
  select coalesce(card_last4, 'NULL') into v from public.accounts where id = MARIA;
  insert into _probe_result values ('second_cutover_keeps_the_live_card', '1881', v);
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
