-- payment_disputes.sql
--
-- Chargebacks on card payments (20260928200001). Written FROM THE RULE in that
-- migration's header, not from its SQL; every expected value is worked out by
-- hand from the fixture below and written as a literal.
--
-- THE RULE
--   Columns. payments carries stripe_dispute_id, dispute_status,
--     dispute_reason, dispute_amount_cents, dispute_withdrawn_cents,
--     disputed_at, dispute_due_by and dispute_event_at. No client role can
--     read or write any of them: a member cannot read the dispute on a
--     payment, not even their own. service_role (the webhook) can write them.
--     The table refuses a dispute status without its id, amounts and event time.
--   Recording, stripe_record_dispute(PaymentIntent, dispute id, status,
--     reason, disputed amount, withdrawn amount, opened, respond-by, event
--     time, [payment id from the PaymentIntent's metadata]), service_role only:
--     * finds the fee by its PaymentIntent, never a refund row; else the row
--       the metadata names, only while that row has no PaymentIntent (it then
--       gets this one); nothing found answers 'no_payment' and changes nothing;
--     * writes every field and answers 'recorded'; a replay writes the same;
--     * an event older than the one recorded answers 'stale', changes nothing;
--     * a decided dispute (won, lost, warning_closed) is never reopened by a
--       created/updated event for the SAME dispute, older, same second or
--       newer ('stale'); a newer decision replaces it;
--     * a different dispute replaces an earlier one when newer, EXCEPT a lost
--       one: that answers 'second_dispute' and the lost one stays;
--     * never the fee's status or amount, the registration's Paid flag, or
--       another row;
--     * missing essentials: dispute_incomplete.
--   Listing, admin_money_disputes(): admin only; the OPEN disputes (every
--     status but won, lost, warning_closed) with the cardholder's name, the
--     clinic, the DISPUTED amount, Stripe's reason, status and respond-by,
--     soonest respond-by first, none last. Test-mode disputes are listed until
--     the club switches to live (app_settings.stripe_live_since), not after.
--   Tara reads a payment's dispute_status through payments_ledger.
--
-- FIXTURE
--   Clinic "Probe dispute events" (ended):
--     Maria fee PM 1800 succeeded, pi_probe_dm, her registration PAID (as the
--       ledger trigger leaves a succeeded fee; a dispute must not unmark it);
--     Ken fee PK 1800 succeeded, pi_probe_dk (never disputed);
--     Rob fee 2300 succeeded pi_probe_dr, and a refund row RR carrying the
--       PaymentIntent pi_probe_refund (artificial: no code path makes one,
--       which is why the guard needs a test);
--     Dana fee PH 1800 succeeded with NO PaymentIntent: a held charge Tara
--       resolved as "Went through".
--   Events on PM, in delivery order (event times UTC, 2026-09-20), each
--   withdrawing 1800 (Stripe holds the money from the moment of the chargeback):
--      1 dp_1 needs_response fraudulent at 10:00       -> recorded
--      2 the same again                                -> recorded, same row
--      3 dp_1 needs_response at 09:00 (older)          -> stale
--      4 dp_1 under_review at 11:00                    -> recorded
--      5 dp_1 lost at 12:00                            -> recorded
--      6 dp_1 under_review at 11:30 (late retry)       -> stale, still lost
--      7 dp_1 under_review at 12:00 (same second)      -> stale, still lost
--      8 dp_1 under_review at 13:00 (newer, reopen)    -> stale, still lost
--      9 dp_1 won at 14:00, nothing withdrawn          -> recorded, won
--     10 dp_2 needs_response at 15:00 (another dispute) -> recorded
--     11 dp_2 lost at 16:00                            -> recorded
--     12 dp_3 needs_response at 17:00                  -> second_dispute, dp_2 lost stays
--   On PH: by PaymentIntent pi_probe_held alone -> no_payment; with PH's id
--   from the metadata -> recorded, and PH now carries pi_probe_held. The
--   metadata naming PK (which has its own PaymentIntent) or the refund row RR
--   -> no_payment.
--   Clinic "Probe disputes listed" (ended), one fee each (all succeeded):
--     L1 Ken   1800, dp_l1 needs_response        product_not_received, respond by 2026-10-05
--     L2 Rob   2300, dp_l2 warning_needs_response general,              respond by 2026-10-02
--     L3 Priya 2300, dp_l3 under_review, disputed 1000 (partial), fraudulent, no respond-by
--     L4 Dana  1800, dp_l4 won;  L5 Maria 1800, dp_l5 lost;  L6 Dana late fee 1800, dp_l6 warning_closed
--     L7 Maria no-show fee 1800, TEST MODE, dp_l7 needs_response, respond by 2026-10-03
--     L8 Rob late fee 2300, no dispute
--
-- EXPECTED (by hand)
--   Listed, soonest respond-by first, none last:
--     Rob Delgado|2300|general|warning_needs_response|2026-10-02
--     Maria Alvarez|1800|duplicate|needs_response|2026-10-03        (L7, test mode, before the switch)
--     Ken Whitfield|1800|product_not_received|needs_response|2026-10-05
--     Priya Raman|1000|fraudulent|under_review|none                  (the disputed amount, not the fee)
--   After the switch to live: the same without L7.
--   The events clinic lists only PH's dp_h (PM's dp_2 is lost):
--     Dana Okonkwo|1800|general|needs_response.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon, service_role;

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
  COLS    constant text[] := array['stripe_dispute_id', 'dispute_status', 'dispute_reason', 'dispute_amount_cents',
                                   'dispute_withdrawn_cents', 'disputed_at', 'dispute_due_by', 'dispute_event_at'];
  rec     regprocedure := to_regprocedure('public.stripe_record_dispute(text, text, text, text, integer, integer, timestamptz, timestamptz, timestamptz, uuid)');
  lst     regprocedure := to_regprocedure('public.admin_money_disputes()');
  ce uuid; cl uuid; rm uuid; rk uuid; rr uuid; rd uuid;
  pm uuid; pk uuid; prr uuid; ph uuid; refund_row uuid;
  r1 uuid; r2 uuid; r3 uuid; r4 uuid; r5 uuid;
  v text; w text; ken_before text; n int;
  outcomes text := '';
  d0  constant timestamptz := timestamptz '2026-09-19 18:30:00+00';
  due constant timestamptz := timestamptz '2026-10-01 23:59:59+00';
  ev  constant timestamptz := timestamptz '2026-09-20 00:00:00+00';
begin
  -- ---------------------------------------------------------- columns
  -- By attnum, not by name: a name that is not a column raises, and a missing
  -- column must read as a failure, not abort the probe.
  select coalesce(string_agg(c, ', ' order by c), '') into v
    from unnest(COLS) c
    left join pg_attribute a on a.attrelid = 'public.payments'::regclass and a.attname = c and not a.attisdropped
   where a.attnum is null
      or has_column_privilege('authenticated', 'public.payments'::regclass, a.attnum, 'SELECT')
      or has_column_privilege('authenticated', 'public.payments'::regclass, a.attnum, 'UPDATE')
      or has_column_privilege('authenticated', 'public.payments'::regclass, a.attnum, 'INSERT')
      or has_column_privilege('anon', 'public.payments'::regclass, a.attnum, 'SELECT');
  insert into _probe_result values ('dispute_columns_exist_and_no_client_can_touch_them', '', v);

  select coalesce(string_agg(c, ', ' order by c), '') into v
    from unnest(COLS) c
    left join pg_attribute a on a.attrelid = 'public.payments'::regclass and a.attname = c and not a.attisdropped
   where a.attnum is null
      or not has_column_privilege('service_role', 'public.payments'::regclass, a.attnum, 'UPDATE');
  insert into _probe_result values ('service_role_writes_every_dispute_column', '', v);

  -- The old column list is untouched: the owner still reads their own status.
  insert into _probe_result values ('member_still_reads_payment_status', 'true',
    has_column_privilege('authenticated', 'public.payments'::regclass, 'status', 'SELECT')::text);

  -- ----------------------------------------------------- function grants
  insert into _probe_result values ('record_exists', 'true', (rec is not null)::text);
  insert into _probe_result values ('record_service_role_only',
    'anon false | authenticated false | public false | service_role true',
    case when rec is null then 'MISSING' else
      'anon ' || has_function_privilege('anon', rec, 'EXECUTE')
      || ' | authenticated ' || has_function_privilege('authenticated', rec, 'EXECUTE')
      || ' | public ' || exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
                                  where p.oid = rec and x.grantee = 0 and x.privilege_type = 'EXECUTE')
      || ' | service_role ' || has_function_privilege('service_role', rec, 'EXECUTE') end);
  insert into _probe_result values ('listing_admin_rpc_grants',
    'anon false | public false | authenticated true | definer true | search_path pinned',
    case when lst is null then 'MISSING' else
      'anon ' || has_function_privilege('anon', lst, 'EXECUTE')
      || ' | public ' || exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
                                  where p.oid = lst and x.grantee = 0 and x.privilege_type = 'EXECUTE')
      || ' | authenticated ' || has_function_privilege('authenticated', lst, 'EXECUTE')
      || ' | definer ' || (select p.prosecdef from pg_proc p where p.oid = lst)
      || case when exists (select 1 from pg_proc p, unnest(p.proconfig) cfg where p.oid = lst and cfg like 'search_path=%')
              then ' | search_path pinned' else ' | search_path OPEN' end end);

  -- ---------------------------------------------------------- fixture
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe dispute events', 'coed', 'Clinic', 'probe', now() - interval '9 days', now() - interval '9 days' + interval '1 hour',
          now() - interval '15 days', now() - interval '14 days', 8, 'published', 60)
  returning id into ce;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe disputes listed', 'coed', 'Clinic', 'probe', now() - interval '8 days', now() - interval '8 days' + interval '1 hour',
          now() - interval '14 days', now() - interval '13 days', 8, 'published', 60)
  returning id into cl;

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, paid)
  values (ce, MARIA_P, 'in', 'self', 1800, true, 60, true) returning id into rm;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, KEN_P, 'in', 'self', 1800, true, 60) returning id into rk;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, ROB_P, 'in', 'self', 2300, false, 60) returning id into rr;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, DANA_P, 'in', 'self', 1800, true, 60) returning id into rd;

  -- As the edge functions leave them (service_role; postgres stands in).
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, stripe_payment_intent_id, livemode)
  values (rm, MARIA, 'clinic_fee', 1800, 'succeeded', 'pi_probe_dm', true) returning id into pm;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, stripe_payment_intent_id, livemode)
  values (rk, KEN, 'clinic_fee', 1800, 'succeeded', 'pi_probe_dk', true) returning id into pk;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, stripe_payment_intent_id, livemode)
  values (rr, ROB, 'clinic_fee', 2300, 'succeeded', 'pi_probe_dr', true) returning id into prr;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, refunds_payment_id, stripe_payment_intent_id, livemode)
  values (rr, ROB, 'refund', 2300, 'succeeded', prr, 'pi_probe_refund', true) returning id into refund_row;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_reason, livemode)
  values (rd, DANA, 'clinic_fee', 1800, 'succeeded', 'retry_window_passed', true) returning id into ph;
  select p::text into ken_before from public.payments p where p.id = pk;

  -- ------------------------------------------------ the webhook's writes
  perform set_config('role', 'service_role', true);
  begin
    outcomes := outcomes || public.stripe_record_dispute('pi_probe_dm', 'dp_1', 'needs_response', 'fraudulent', 1800, 1800, d0, due, ev + interval '10 hours');
    select p.stripe_dispute_id || '|' || p.dispute_status || '|' || p.dispute_reason || '|' || p.dispute_amount_cents
           || '|' || p.dispute_withdrawn_cents
           || '|' || to_char(p.disputed_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI')
           || '|' || to_char(p.dispute_due_by at time zone 'UTC', 'YYYY-MM-DD HH24:MI')
           || '|' || to_char(p.dispute_event_at at time zone 'UTC', 'HH24:MI')
      into v from public.payments p where p.id = pm;
    outcomes := outcomes || ' ' || public.stripe_record_dispute('pi_probe_dm', 'dp_1', 'needs_response', 'fraudulent', 1800, 1800, d0, due, ev + interval '10 hours');
    select p.stripe_dispute_id || '|' || p.dispute_status || '|' || p.dispute_reason || '|' || p.dispute_amount_cents
           || '|' || p.dispute_withdrawn_cents
           || '|' || to_char(p.disputed_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI')
           || '|' || to_char(p.dispute_due_by at time zone 'UTC', 'YYYY-MM-DD HH24:MI')
           || '|' || to_char(p.dispute_event_at at time zone 'UTC', 'HH24:MI')
      into w from public.payments p where p.id = pm;
    outcomes := outcomes || ' ' || public.stripe_record_dispute('pi_probe_dm', 'dp_1', 'needs_response', 'general', 1800, 1800, d0, due, ev + interval '9 hours');
    outcomes := outcomes || ' ' || public.stripe_record_dispute('pi_probe_dm', 'dp_1', 'under_review', 'fraudulent', 1800, 1800, d0, due, ev + interval '11 hours');
    outcomes := outcomes || ' ' || public.stripe_record_dispute('pi_probe_dm', 'dp_1', 'lost', 'fraudulent', 1800, 1800, d0, due, ev + interval '12 hours');
    outcomes := outcomes || ' ' || public.stripe_record_dispute('pi_probe_dm', 'dp_1', 'under_review', 'fraudulent', 1800, 1800, d0, due, ev + interval '11 hours 30 minutes');
    outcomes := outcomes || ' ' || public.stripe_record_dispute('pi_probe_dm', 'dp_1', 'under_review', 'fraudulent', 1800, 1800, d0, due, ev + interval '12 hours');
    outcomes := outcomes || ' ' || public.stripe_record_dispute('pi_probe_dm', 'dp_1', 'under_review', 'fraudulent', 1800, 1800, d0, due, ev + interval '13 hours');
  exception when others then
    outcomes := outcomes || ' ERROR ' || sqlerrm;
  end;
  perform set_config('role', 'postgres', true);

  insert into _probe_result values ('first_event_records_every_field',
    'dp_1|needs_response|fraudulent|1800|1800|2026-09-19 18:30|2026-10-01 23:59|10:00', coalesce(v, 'NOT RECORDED'));
  insert into _probe_result values ('a_replay_writes_the_same_row', coalesce(v, 'NOT RECORDED'), coalesce(w, 'NOT RECORDED'));
  insert into _probe_result values ('the_webhook_answers_in_delivery_order',
    'recorded recorded stale recorded recorded stale stale stale', outcomes);
  select p.dispute_status || '|' || to_char(p.dispute_event_at at time zone 'UTC', 'HH24:MI') into v
    from public.payments p where p.id = pm;
  insert into _probe_result values ('a_late_or_newer_update_never_reopens_a_lost_dispute', 'lost|12:00', coalesce(v, 'NULL'));

  -- Events 9 to 12: a newer decision replaces a decision; another dispute
  -- replaces a won one when newer; nothing replaces a lost one.
  perform set_config('role', 'service_role', true);
  begin
    outcomes := public.stripe_record_dispute('pi_probe_dm', 'dp_1', 'won', 'fraudulent', 1800, 0, d0, due, ev + interval '14 hours');
    select p.dispute_status || ' ' || p.dispute_withdrawn_cents into v from public.payments p where p.id = pm;
    outcomes := outcomes || ' ' || v || ' ' || public.stripe_record_dispute('pi_probe_dm', 'dp_2', 'needs_response', 'general', 1800, 1800, d0, null, ev + interval '15 hours');
    select p.stripe_dispute_id || ' ' || p.dispute_status || ' ' || coalesce(to_char(p.dispute_due_by, 'YYYY'), 'no-respond-by')
      into v from public.payments p where p.id = pm;
    outcomes := outcomes || ' ' || v;
  exception when others then
    outcomes := 'ERROR ' || sqlerrm;
  end;
  begin
    w := public.stripe_record_dispute('pi_probe_dm', 'dp_2', 'lost', 'general', 1800, 1800, d0, null, ev + interval '16 hours')
      || ' ' || public.stripe_record_dispute('pi_probe_dm', 'dp_3', 'needs_response', 'duplicate', 1800, 1800, d0, due, ev + interval '17 hours');
    select w || ' ' || p.stripe_dispute_id || ' ' || p.dispute_status into w from public.payments p where p.id = pm;
  exception when others then
    w := 'ERROR ' || sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('a_newer_decision_and_a_new_dispute_are_recorded',
    'recorded won 0 recorded dp_2 needs_response no-respond-by', outcomes);
  insert into _probe_result values ('a_second_dispute_never_replaces_a_lost_one',
    'recorded second_dispute dp_2 lost', w);

  -- A held charge Tara resolved as "Went through" has no PaymentIntent; the
  -- webhook finds it through the PaymentIntent's metadata.
  perform set_config('role', 'service_role', true);
  begin
    outcomes := public.stripe_record_dispute('pi_probe_held', 'dp_h', 'needs_response', 'general', 1800, 1800, d0, due, ev + interval '10 hours')
      || ' ' || public.stripe_record_dispute('pi_probe_held', 'dp_h', 'needs_response', 'general', 1800, 1800, d0, due, ev + interval '10 hours', ph)
      || ' ' || public.stripe_record_dispute('pi_probe_other', 'dp_k', 'needs_response', 'general', 1800, 1800, d0, due, ev + interval '10 hours', pk)
      || ' ' || public.stripe_record_dispute('pi_probe_other2', 'dp_r', 'needs_response', 'general', 2300, 2300, d0, due, ev + interval '10 hours', refund_row);
  exception when others then
    outcomes := 'ERROR ' || sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('the_metadata_finds_a_fee_without_a_payment_intent_and_only_that',
    'no_payment recorded no_payment no_payment', outcomes);
  select coalesce(p.stripe_payment_intent_id, 'NULL') || ' ' || coalesce(p.stripe_dispute_id, 'NULL') || ' ' || p.status
    into v from public.payments p where p.id = ph;
  insert into _probe_result values ('the_held_fee_gets_its_payment_intent_and_the_dispute', 'pi_probe_held dp_h succeeded', v);

  -- Nothing else moved: the fee, the Paid flag, Ken's row, the refund row.
  select p.status || ' ' || p.amount_cents || ' ' || p.kind || ' paid=' || r.paid into v
    from public.payments p join public.registrations r on r.id = p.registration_id where p.id = pm;
  insert into _probe_result values ('the_fee_and_its_paid_flag_are_untouched', 'succeeded 1800 clinic_fee paid=true', v);
  select p::text into v from public.payments p where p.id = pk;
  insert into _probe_result values ('another_payment_is_untouched', ken_before, v);

  -- No such fee, a refund row by PaymentIntent, missing essentials.
  perform set_config('role', 'service_role', true);
  begin
    outcomes := public.stripe_record_dispute('pi_probe_nobody', 'dp_x', 'needs_response', 'general', 500, 500, d0, due, ev + interval '10 hours')
      || ' ' || public.stripe_record_dispute('pi_probe_refund', 'dp_y', 'needs_response', 'general', 2300, 2300, d0, due, ev + interval '10 hours');
  exception when others then
    outcomes := 'ERROR ' || sqlerrm;
  end;
  begin
    perform public.stripe_record_dispute('pi_probe_dk', 'dp_z', 'needs_response', 'general', null, 0, d0, due, ev + interval '10 hours');
    w := 'CALL SUCCEEDED';
  exception when others then
    w := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('unknown_payment_intent_and_refund_rows_are_no_payment', 'no_payment no_payment', outcomes);
  select count(*) into n from public.payments where stripe_dispute_id in ('dp_x', 'dp_y', 'dp_z', 'dp_k', 'dp_r');
  insert into _probe_result values ('nothing_recorded_for_them', '0', n::text);
  insert into _probe_result values ('missing_amount_is_refused', 'dispute_incomplete', w);

  -- The table itself refuses a half-written dispute (service_role could write one by hand).
  begin
    update public.payments set dispute_status = 'needs_response' where id = pk;
    w := 'UPDATE SUCCEEDED';
  exception when check_violation then
    w := 'refused';
  end;
  insert into _probe_result values ('table_refuses_a_status_without_id_amounts_and_event', 'refused', w);

  -- ---------------------------------------------------- listing fixture
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cl, KEN_P, 'in', 'self', 1800, true, 60) returning id into r1;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cl, ROB_P, 'in', 'self', 2300, false, 60) returning id into r2;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cl, PRIYA_P, 'in', 'self', 2300, false, 60) returning id into r3;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cl, DANA_P, 'in', 'self', 1800, true, 60) returning id into r4;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cl, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r5;

  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, stripe_payment_intent_id,
      stripe_dispute_id, dispute_status, dispute_reason, dispute_amount_cents, dispute_withdrawn_cents,
      disputed_at, dispute_due_by, dispute_event_at)
  values
    (r1, KEN,   'clinic_fee',  1800, 'succeeded', true,  'pi_probe_l1', 'dp_l1', 'needs_response',         'product_not_received', 1800, 1800, d0, timestamptz '2026-10-05 23:59:59+00', d0),
    (r2, ROB,   'clinic_fee',  2300, 'succeeded', true,  'pi_probe_l2', 'dp_l2', 'warning_needs_response', 'general',              2300,    0, d0, timestamptz '2026-10-02 23:59:59+00', d0),
    (r3, PRIYA, 'clinic_fee',  2300, 'succeeded', null,  'pi_probe_l3', 'dp_l3', 'under_review',           'fraudulent',           1000, 1000, d0, null,                                   d0),
    (r4, DANA,  'clinic_fee',  1800, 'succeeded', true,  'pi_probe_l4', 'dp_l4', 'won',                    'fraudulent',           1800,    0, d0, timestamptz '2026-10-01 23:59:59+00', d0),
    (r5, MARIA, 'clinic_fee',  1800, 'succeeded', true,  'pi_probe_l5', 'dp_l5', 'lost',                   'fraudulent',           1800, 1800, d0, timestamptz '2026-10-01 23:59:59+00', d0),
    (r4, DANA,  'late_cancel', 1800, 'succeeded', true,  'pi_probe_l6', 'dp_l6', 'warning_closed',         'general',              1800,    0, d0, timestamptz '2026-10-01 23:59:59+00', d0),
    (r5, MARIA, 'no_show',     1800, 'succeeded', false, 'pi_probe_l7', 'dp_l7', 'needs_response',         'duplicate',            1800, 1800, d0, timestamptz '2026-10-03 23:59:59+00', d0);
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, stripe_payment_intent_id)
  values (r2, ROB, 'late_cancel', 2300, 'succeeded', true, 'pi_probe_l8');

  -- ------------------------------------------------------------ as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    select string_agg(d.first_name || ' ' || d.last_name || '|' || d.amount_cents || '|' || coalesce(d.reason, 'NULL')
                      || '|' || d.status || '|' || coalesce(to_char(d.respond_by at time zone 'America/New_York', 'YYYY-MM-DD'), 'none'),
                      ' ; ')
      into v from public.admin_money_disputes() d where d.clinic_id = cl;   -- the function's own order
  exception when others then v := 'ERROR ' || sqlerrm;
  end;
  insert into _probe_result values ('open_disputes_listed_soonest_respond_by_first',
    'Rob Delgado|2300|general|warning_needs_response|2026-10-02 ; Maria Alvarez|1800|duplicate|needs_response|2026-10-03 ; '
    || 'Ken Whitfield|1800|product_not_received|needs_response|2026-10-05 ; Priya Raman|1000|fraudulent|under_review|none',
    coalesce(v, 'NO ROWS'));
  begin
    select string_agg(d.first_name || ' ' || d.last_name || '|' || d.amount_cents || '|' || d.reason || '|' || d.status, ' ; ')
      into v from public.admin_money_disputes() d where d.clinic_id = ce;
  exception when others then v := 'ERROR ' || sqlerrm;
  end;
  insert into _probe_result values ('the_events_clinic_lists_only_the_open_one', 'Dana Okonkwo|1800|general|needs_response', coalesce(v, 'NO ROWS'));
  begin
    select string_agg(d.payment_id::text || '|' || d.registration_id::text || '|' || d.clinic_name
                      || '|' || (d.clinic_starts_at is not null) || '|' || (d.disputed_at = d0), ' ; ')
      into v from public.admin_money_disputes() d where d.clinic_id = ce;
  exception when others then v := 'ERROR ' || sqlerrm;
  end;
  insert into _probe_result values ('each_row_names_its_payment_registration_and_clinic',
    ph::text || '|' || rd::text || '|Probe dispute events|true|true', coalesce(v, 'NO ROWS'));
  select coalesce(max(l.dispute_status), 'NULL') into v from public.payments_ledger l where l.id = pm;
  insert into _probe_result values ('ledger_shows_tara_the_dispute_status', 'lost', v);

  -- After the switch to live, a test-mode dispute is not money and leaves the list.
  perform set_config('role', 'postgres', true);
  insert into public.app_settings (key, value) values ('stripe_live_since', now()::text);
  perform set_config('role', 'authenticated', true);
  begin
    select string_agg(d.first_name || ' ' || d.last_name, ' ; ')
      into v from public.admin_money_disputes() d where d.clinic_id = cl;
  exception when others then v := 'ERROR ' || sqlerrm;
  end;
  insert into _probe_result values ('test_mode_disputes_leave_the_list_after_the_switch',
    'Rob Delgado ; Ken Whitfield ; Priya Raman', coalesce(v, 'NO ROWS'));
  perform set_config('role', 'postgres', true);
  delete from public.app_settings where key = 'stripe_live_since';

  -- ------------------------------------------------------ ATTACK: Maria
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_money_disputes();
    insert into _probe_result values ('member_cannot_list_disputes', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_list_disputes', 'not_authorized', sqlerrm);
  end;
  -- Not even her own: the column is not hers to read, and asking is refused.
  begin
    execute 'select count(*) from public.payments where dispute_status is not null' into n;
    insert into _probe_result values ('member_cannot_read_her_own_dispute', 'denied', 'READ ' || n || ' ROWS');
  exception when insufficient_privilege then
    insert into _probe_result values ('member_cannot_read_her_own_dispute', 'denied', 'denied');
  end;
  select count(*) into n from public.payments_ledger;
  insert into _probe_result values ('member_sees_no_ledger_rows', '0', n::text);
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', null, true);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
