-- declined_card.sql
--
-- Tara's round-four answers (decision 0024, 2026-09-28), the rule this probe
-- is written from, before any code:
--   78  "Cannot sign up without proper, transactional card. App needs to tell
--        them why their card isn’t working, yes."
--   83  "Can we have a button that says “resolved” and it clears - for me only
--        to see ofc"
--
-- As built (20260928700001, decision 0026), written out as the expected
-- values below:
--   * Once a charge on a player's card is declined, that player cannot
--     register and cannot accept an invitation (card_declined, nothing
--     moves) until a card is saved again or a later charge goes through.
--     Declining an invitation still works. Tara is exempt. Only while cards
--     are required (payments on and card_required), like card_required.
--   * Declined means: a charge (never a refund) going from pending or
--     processing to failed with Stripe's code, on real money. A retry (back
--     to pending), a hold (processing with a reason), our own refusal
--     (failed, no code), Tara's "Did not go through" (canceled, even if a
--     failure arrives for it later), a failed refund, and test money after
--     the switch to live block nobody.
--   * "Until a LATER charge goes through" is about when charges were
--     ATTEMPTED, not when Stripe's answers were recorded: a success clears
--     only a decline attempted no later than it, a decline does not block
--     once a later-attempted charge has gone through, and a decline for a
--     charge attempted before the card on file was saved blocks nobody.
--     (The four orders are written out below; sql-auditor, 2026-09-28.)
--   * A new card saved (by the pipeline) clears it; a card removed does not,
--     so an Accept stays refused, and Register asks for a card first.
--   * The player reads their own decline, never another's, and never the
--     words "lost", "stolen" or "fraud": those are kept as a plain decline.
--     The player cannot clear it, and neither can a definer path acting for
--     them, directly or by writing a card date.
--   * Resolved is Tara's alone, only on a failed unresolved charge; it takes
--     the decline out of her lists and figures (the Declined count too),
--     keeps the charge and its date in the ledger, is never charged again by
--     Charge clinic, and does NOT unblock the player.
--
-- Every attack asserts the resulting STATE, not the error (hard rule 9): a
-- blocked UPDATE can fail silently, and a refusal that still moved a row is a
-- failure here.
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
  past_c uuid; open_1 uuid; open_2 uuid; open_3 uuid; open_4 uuid; open_5 uuid; invite_c uuid;
  r_maria uuid; r_ken uuid; r_ken2 uuid; r_rob uuid; r_dana uuid; r_priya uuid; r_invite uuid; r_invite2 uuid;
  p1 uuid; p3 uuid; p_ok uuid; p_held uuid; p_retry uuid; p_own uuid; p_fee_rob uuid; p_refund uuid;
  p_test uuid; p_sandbox uuid; p_priya uuid; p_pending uuid;
  v text; err text; v_hint text; n int; t timestamptz; t2 timestamptz; p_dana2 uuid;
  r_priya_inv uuid; v_reg uuid; pa uuid; pb uuid; p_h uuid; p_d uuid; p_c uuid; p_late uuid;
  t_early timestamptz := now() - interval '4 hours'; t_late timestamptz := now() - interval '3 hours';
begin
  -- ------------------------------------------------------------ the scene
  -- Cards required and payments on, since ten days ago.
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  update public.app_settings set value = 'true' where key = 'card_required';
  update public.app_settings set value = (now() - interval '10 days')::text where key = 'payments_enabled_at';
  delete from public.app_settings where key = 'stripe_live_since';

  -- One clinic that ended yesterday (the one charged), five open to all, one
  -- holding an invitation.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Declined Past', 'coed', 'Clinic', 'probe', now() - interval '25 hours', now() - interval '24 hours',
          now() - interval '9 days', now() - interval '8 days', 8, 'published', 60)
  returning id into past_c;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Declined Open 1', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into open_1;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Declined Open 2', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into open_2;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Declined Open 3', 'coed', 'Clinic', 'probe', now() + interval '4 days', now() + interval '4 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into open_3;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Declined Open 4', 'coed', 'Clinic', 'probe', now() + interval '4 days', now() + interval '4 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into open_4;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Declined Open 5', 'coed', 'Clinic', 'probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into open_5;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Declined Invite', 'coed', 'Clinic', 'probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60) returning id into invite_c;

  -- Every player in the scene has a card on file, saved two days ago, the way
  -- the webhook leaves it.
  update public.accounts set stripe_customer_id = 'cus_probe_' || left(id::text, 8), card_brand = 'visa',
         card_last4 = '4242', card_added_at = now() - interval '2 days'
   where id in (MARIA, KEN, ROB, DANA, PRIYA);

  -- Each played yesterday's clinic; each fee is charged below.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (past_c, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_maria;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (past_c, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (past_c, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_rob;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (past_c, DANA_P, 'in', 'self', 1800, true, 60) returning id into r_dana;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (past_c, PRIYA_P, 'in', 'self', 2300, false, 60) returning id into r_priya;
  -- And Maria holds an invitation (Response Needed) to a clinic next week.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, invited_at)
  values (invite_c, MARIA_P, 'response_needed', 'self', 1800, true, 60, now() - interval '1 hour') returning id into r_invite;

  -- ======================================================= A. THE DECLINE
  -- Maria's fee: stripe-charge claimed it, Stripe declined it, and the
  -- webhook records that (service_role: no signed-in person).
  perform set_config('request.jwt.claims', '', true);
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_maria, MARIA, 'clinic_fee', 1800, 'processing', now() - interval '20 hours') returning id into p1;
  update public.payments set status = 'failed', failure_code = 'insufficient_funds',
         failure_reason = 'Your card has insufficient funds.'
   where id = p1;
  select coalesce(card_decline_code, 'NULL') || '|' || (card_declined_at is not null) into v
    from public.accounts where id = MARIA;
  insert into _probe_result values ('a_decline_marks_the_account', 'insufficient_funds|true', v);

  -- She tries to register.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'registered'; v_hint := '';
  begin
    perform public.register_for_clinic(open_1, MARIA_P);
  exception when others then
    err := sqlerrm;
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('declined_player_cannot_register', 'card_declined', err);
  insert into _probe_result values ('the_refusal_says_why', 'insufficient_funds', v_hint);
  select count(*) into n from public.registrations where clinic_id = open_1 and player_id = MARIA_P;
  insert into _probe_result values ('the_refusal_moves_nothing', '0', n::text);

  -- She tries to accept her invitation.
  perform set_config('role', 'authenticated', true);
  err := 'accepted';
  begin
    perform public.respond_to_invitation(r_invite, true);
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('declined_player_cannot_accept', 'card_declined', err);
  select status::text || '|' || coalesce(responded_at::text, 'NULL') into v
    from public.registrations where id = r_invite;
  insert into _probe_result values ('the_accept_refusal_moves_nothing', 'response_needed|NULL', v);

  -- She reads her own decline, the way Profile does.
  perform set_config('role', 'authenticated', true);
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = MARIA;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('the_player_reads_her_own_decline', 'insufficient_funds', v);

  -- Ken's card is declined too (written as the pipeline would, with no
  -- signed-in person); Maria cannot see his (hard rule 1: other players'
  -- payment status).
  perform set_config('request.jwt.claims', '', true);
  update public.accounts set card_declined_at = now(), card_decline_code = 'expired_card' where id = KEN;
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.accounts where id = KEN;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('the_player_cannot_read_anothers_decline', '0', n::text);
  perform set_config('request.jwt.claims', '', true);
  update public.accounts set card_declined_at = null, card_decline_code = null where id = KEN;
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);

  -- -------------------------------------------- she cannot clear it herself
  -- 1. Straight at the columns (hard rule 8, the column grants).
  perform set_config('role', 'authenticated', true);
  begin
    update public.accounts set card_declined_at = null, card_decline_code = null where id = MARIA;
  exception when others then null; end;
  -- 2. By pretending a new card was saved (only the webhook writes a card).
  begin
    update public.accounts set card_last4 = '1111', card_added_at = now() where id = MARIA;
  exception when others then null; end;
  perform set_config('role', 'postgres', true);
  select coalesce(card_decline_code, 'NULL') || '|' || coalesce(card_last4, 'NULL') into v
    from public.accounts where id = MARIA;
  insert into _probe_result values ('the_player_cannot_clear_her_decline', 'insufficient_funds|4242', v);
  -- 3. Through a definer path acting for her: an RPC runs as its owner
  --    with her claims set, which is what the trigger backstop is for.
  err := 'cleared';
  begin
    update public.accounts set card_declined_at = null, card_decline_code = null where id = MARIA;
  exception when others then err := sqlerrm; end;
  insert into _probe_result values ('no_definer_path_clears_it_for_her', 'card_decline_not_writable', err);
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = MARIA;
  insert into _probe_result values ('still_declined_after_every_attack', 'insufficient_funds', v);

  -- ------------------------------------------------------------ Tara exempt
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'registered';
  begin
    perform public.register_for_clinic(open_2, MARIA_P);
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('tara_can_still_put_her_in', 'registered', err);

  -- ------------------------------ declining an invitation still works
  -- A second invitation, so the first stays for the accept after the new card.
  perform set_config('request.jwt.claims', '', true);
  update public.registrations set status = 'response_needed', invited_at = now()
   where clinic_id = open_2 and player_id = MARIA_P
  returning id into r_invite2;
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'declined';
  begin
    perform public.respond_to_invitation(r_invite2, false);
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  select status::text into v from public.registrations where clinic_id = open_2 and player_id = MARIA_P;
  insert into _probe_result values ('declining_an_invitation_still_works', 'declined|pool', err || '|' || v);

  -- ============================================ what is NOT a card decline
  perform set_config('request.jwt.claims', '', true);
  -- Ken: a charge held past the retry window (stripe-charge leaves it
  -- processing with a reason), then Tara records "Did not go through".
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_ken, KEN, 'clinic_fee', 1800, 'processing', now() - interval '25 hours') returning id into p_held;
  update public.payments set failure_reason = 'retry_window_passed' where id = p_held;
  select (card_declined_at is null)::text into v from public.accounts where id = KEN;
  insert into _probe_result values ('a_held_charge_blocks_nobody', 'true', v);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.admin_resolve_held_payment(p_held, 'canceled');
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  select (card_declined_at is null)::text into v from public.accounts where id = KEN;
  insert into _probe_result values ('did_not_go_through_blocks_nobody', 'true', v);
  -- A dropped connection: back to pending, retried under the same key.
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_ken, KEN, 'clinic_fee', 1800, 'processing', now() - interval '1 hour') returning id into p_retry;
  update public.payments set status = 'pending' where id = p_retry;
  -- An idempotency error: held, with that reason.
  update public.payments set status = 'processing', failure_reason = 'idempotency_error' where id = p_retry;
  select (card_declined_at is null)::text into v from public.accounts where id = KEN;
  insert into _probe_result values ('a_retry_or_an_idempotency_hold_blocks_nobody', 'true', v);
  update public.payments set status = 'canceled' where id = p_retry;
  -- Our own refusal before any Stripe call: failed, with no code.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (open_5, KEN_P, 'in', 'admin', 1800, true, 60) returning id into r_ken2;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_ken2, KEN, 'no_show', 1800, 'processing', now()) returning id into p_own;
  update public.payments set status = 'failed', failure_reason = 'no_card_on_file' where id = p_own;
  select (card_declined_at is null)::text into v from public.accounts where id = KEN;
  insert into _probe_result values ('our_own_refusal_blocks_nobody', 'true', v);
  -- And Ken registers.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'registered';
  begin
    perform public.register_for_clinic(open_1, KEN_P);
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('ken_registers_after_all_of_that', 'registered', err);

  -- Rob: his fee went through; a refund of it failed with a Stripe code.
  perform set_config('request.jwt.claims', '', true);
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode)
  values (r_rob, ROB, 'clinic_fee', 2300, 'succeeded', true) returning id into p_fee_rob;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, refunds_payment_id)
  values (r_rob, ROB, 'refund', 2300, 'processing', p_fee_rob) returning id into p_refund;
  update public.payments set status = 'failed', failure_code = 'charge_already_refunded',
         failure_reason = 'Charge has already been refunded.'
   where id = p_refund;
  select (card_declined_at is null)::text into v from public.accounts where id = ROB;
  insert into _probe_result values ('a_failed_refund_blocks_nobody', 'true', v);

  -- Dana: before the switch to live, the sandbox IS the payment system, so a
  -- test-mode decline counts; after it, test mode is not money.
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, first_attempted_at)
  values (r_dana, DANA, 'clinic_fee', 1800, 'processing', false, now()) returning id into p_sandbox;
  update public.payments set status = 'failed', failure_code = 'generic_decline',
         failure_reason = 'Your card was declined.'
   where id = p_sandbox;
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = DANA;
  insert into _probe_result values ('a_sandbox_decline_counts_before_the_switch', 'generic_decline', v);
  update public.accounts set card_last4 = '4242', card_added_at = now() - interval '1 day' where id = DANA;
  insert into public.app_settings (key, value) values ('stripe_live_since', now()::text);
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, first_attempted_at)
  values (r_dana, DANA, 'no_show', 1800, 'processing', false, now()) returning id into p_test;
  update public.payments set status = 'failed', failure_code = 'insufficient_funds',
         failure_reason = 'Your card has insufficient funds.'
   where id = p_test;
  select (card_declined_at is null)::text into v from public.accounts where id = DANA;
  insert into _probe_result values ('test_money_after_the_switch_blocks_nobody', 'true', v);
  delete from public.app_settings where key = 'stripe_live_since';

  -- ===================================================== B. RESOLVED
  -- The date the decline happened, older than this transaction, so that a
  -- write stamping now() would show. (The ledger trigger stamps updated_at;
  -- it is off for this one fixture statement, as in 20260927300003.)
  alter table public.payments disable trigger payments_sync_registration_paid;
  update public.payments set updated_at = now() - interval '3 hours' where id = p1;
  alter table public.payments enable trigger payments_sync_registration_paid;
  select updated_at into t from public.payments where id = p1;

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select string_agg(payment_id::text || '|' || coalesce(failure_code, 'NULL'), ',') into v
    from public.admin_money_declined() where registration_id = r_maria;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('her_list_names_the_charge_to_resolve', p1::text || '|insufficient_funds', coalesce(v, 'NO ROW'));

  perform set_config('role', 'authenticated', true);
  select declined_count::text into v from public.admin_money_summary();
  perform set_config('role', 'postgres', true);
  -- Maria's, and Dana's sandbox decline on the same clinic.
  insert into _probe_result values ('the_declined_figure_counts_hers', '2', v);

  -- A member cannot press it.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'resolved';
  begin
    perform public.admin_resolve_decline(p1);
  exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  select coalesce(resolved_at::text, 'NULL') into v from public.payments where id = p1;
  insert into _probe_result values ('a_member_cannot_resolve', 'not_authorized|NULL', err || '|' || v);
  insert into _probe_result values ('anon_cannot_call_resolve', 'false',
    has_function_privilege('anon', 'public.admin_resolve_decline(uuid)', 'EXECUTE')::text);

  -- Only a failed, unresolved charge: not one that went through, not a
  -- refund, not one still pending.
  perform set_config('request.jwt.claims', '', true);
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_priya, PRIYA, 'late_cancel', 2300, 'pending') returning id into p_pending;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  v := '';
  begin perform public.admin_resolve_decline(p_fee_rob); v := v || 'resolved'; exception when others then v := v || sqlerrm; end;
  begin perform public.admin_resolve_decline(p_refund);  v := v || '|resolved'; exception when others then v := v || '|' || sqlerrm; end;
  begin perform public.admin_resolve_decline(p_pending); v := v || '|resolved'; exception when others then v := v || '|' || sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('resolve_only_an_open_decline',
    'decline_not_open|decline_not_open|decline_not_open', v);
  select count(*) into n from public.payments where id in (p_fee_rob, p_refund, p_pending) and resolved_at is not null;
  insert into _probe_result values ('the_refused_resolves_stamped_nothing', '0', n::text);

  -- Tara presses Resolved.
  perform set_config('role', 'authenticated', true);
  perform public.admin_resolve_decline(p1);
  perform set_config('role', 'postgres', true);
  select (resolved_at is not null) || '|' || (resolved_by = TARA) into v from public.payments where id = p1;
  insert into _probe_result values ('resolved_is_stamped_with_who', 'true|true', v);
  select resolved_at into t2 from public.payments where id = p1;

  -- It clears: gone from her declined list, from the Declined figures, and
  -- from what the This week tab keeps; money_rows calls it resolved.
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.admin_money_declined() where registration_id = r_maria;
  insert into _probe_result values ('resolved_leaves_her_declined_list', '0', n::text);
  select declined_count::text into v from public.admin_money_clinics() where clinic_id = past_c;
  perform set_config('role', 'postgres', true);
  -- Dana's sandbox decline is the other one on that clinic.
  insert into _probe_result values ('resolved_leaves_the_declined_count', '1', coalesce(v, 'NO ROW'));
  select state into v from public.money_rows() where registration_id = r_maria;
  insert into _probe_result values ('money_rows_calls_it_resolved', 'resolved', coalesce(v, 'NO ROW'));
  perform set_config('role', 'authenticated', true);
  select declined_count::text into v from public.admin_money_summary();
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('resolved_leaves_the_declined_figure', '1', v);

  -- Charge clinic never charges a resolved decline again: Resolved is "I will
  -- not chase it" (sql-auditor finding 3). The clinic's other fees are not
  -- this probe's business and are removed after.
  perform set_config('role', 'authenticated', true);
  perform public.admin_charge_clinic(past_c);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.payments where registration_id = r_maria and status in ('pending', 'processing');
  insert into _probe_result values ('charge_clinic_leaves_a_resolved_decline_alone', '0', n::text);
  delete from public.payments where status = 'pending'
     and registration_id in (select id from public.registrations where clinic_id = past_c) and id <> p_pending;

  -- The history keeps it: still a failed charge with its reason and its date.
  select status::text || '|' || failure_code || '|' || (updated_at = t) into v from public.payments where id = p1;
  insert into _probe_result values ('the_ledger_keeps_the_decline_and_its_date', 'failed|insufficient_funds|true', v);
  perform set_config('role', 'authenticated', true);
  select status::text || '|' || coalesce(failure_code, 'NULL') || '|' || (resolved_at is not null) into v
    from public.payments_ledger where id = p1;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('the_card_list_still_shows_it_resolved', 'failed|insufficient_funds|true', coalesce(v, 'NO ROW'));

  -- A second press changes nothing, and keeps the first stamp (backdated, so
  -- a second stamp inside this transaction would show).
  update public.payments set resolved_at = now() - interval '1 hour' where id = p1;
  select resolved_at into t2 from public.payments where id = p1;
  perform set_config('role', 'authenticated', true);
  err := 'resolved again';
  begin perform public.admin_resolve_decline(p1); exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  select (resolved_at = t2)::text into v from public.payments where id = p1;
  insert into _probe_result values ('a_second_press_changes_nothing', 'decline_not_open|true', err || '|' || v);

  -- A webhook delivering the same outcome again moves nothing either.
  perform set_config('request.jwt.claims', '', true);
  update public.payments set status = 'failed', failure_code = 'insufficient_funds',
         failure_reason = 'Your card has insufficient funds.'
   where id = p1;
  select (updated_at = t)::text into v from public.payments where id = p1;
  insert into _probe_result values ('a_replayed_outcome_keeps_the_date', 'true', v);

  -- Resolved does NOT unblock her: the card is still the one declined.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'registered';
  begin perform public.register_for_clinic(open_3, MARIA_P); exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('resolved_does_not_unblock_her', 'card_declined', err);

  -- A new decline on the same registration needs her again.
  perform set_config('request.jwt.claims', '', true);
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_maria, MARIA, 'clinic_fee', 1800, 'processing', now()) returning id into p3;
  update public.payments set status = 'failed', failure_code = 'expired_card',
         failure_reason = 'Your card has expired.'
   where id = p3;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select string_agg(payment_id::text || '|' || coalesce(failure_code, 'NULL'), ',') into v
    from public.admin_money_declined() where registration_id = r_maria;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('a_new_decline_after_resolved_is_back', p3::text || '|expired_card', coalesce(v, 'NO ROW'));
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = MARIA;
  insert into _probe_result values ('the_account_carries_the_newest_reason', 'expired_card', v);

  -- ======================================== unblocking: a new card saved
  perform set_config('request.jwt.claims', '', true);
  update public.accounts set card_brand = 'mastercard', card_last4 = '4444', card_added_at = now() - interval '3 hours'
   where id = MARIA;
  select coalesce(card_decline_code, 'NULL') || '|' || coalesce(card_declined_at::text, 'NULL') into v
    from public.accounts where id = MARIA;
  insert into _probe_result values ('a_new_card_clears_the_decline', 'NULL|NULL', v);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'registered';
  begin perform public.register_for_clinic(open_3, MARIA_P); exception when others then err := sqlerrm; end;
  v := 'accepted';
  begin perform public.respond_to_invitation(r_invite, true); exception when others then v := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('with_a_new_card_she_registers_and_accepts', 'registered|accepted', err || '|' || v);
  -- A replay of the old failure, after the new card, does not re-block her.
  perform set_config('request.jwt.claims', '', true);
  update public.payments set status = 'failed', failure_code = 'expired_card',
         failure_reason = 'Your card has expired.'
   where id = p3;
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = MARIA;
  insert into _probe_result values ('a_replayed_failure_does_not_reblock', 'NULL', v);

  -- ================================== unblocking: a later charge succeeds
  -- A no-show fee attempted two hours ago declines; a late-cancel fee
  -- attempted an hour ago, after it, goes through.
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_maria, MARIA, 'no_show', 1800, 'processing', now() - interval '2 hours') returning id into p_ok;
  update public.payments set status = 'failed', failure_code = 'do_not_honor',
         failure_reason = 'Your card was declined.'
   where id = p_ok;
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = MARIA;
  insert into _probe_result values ('declined_again', 'do_not_honor', v);
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_maria, MARIA, 'late_cancel', 1800, 'processing', now() - interval '1 hour') returning id into p_late;
  update public.payments set status = 'succeeded', livemode = true where id = p_late;
  select coalesce(card_decline_code, 'NULL') || '|' || coalesce(card_declined_at::text, 'NULL') into v
    from public.accounts where id = MARIA;
  insert into _probe_result values ('a_later_success_clears_the_decline', 'NULL|NULL', v);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'registered';
  begin perform public.register_for_clinic(open_4, MARIA_P); exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('after_a_success_she_registers', 'registered', err);

  -- ===================== the card removed: the decline stays, Register asks for a card
  perform set_config('request.jwt.claims', '', true);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, invited_at)
  values (invite_c, PRIYA_P, 'response_needed', 'self', 2300, false, 60, now() - interval '1 hour') returning id into r_priya_inv;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_priya, PRIYA, 'clinic_fee', 2300, 'processing', now()) returning id into p_priya;
  update public.payments set status = 'failed', failure_code = 'lost_card',
         failure_reason = 'Your card was declined.'
   where id = p_priya;
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = PRIYA;
  insert into _probe_result values ('lost_card_is_kept_as_a_plain_decline', 'generic_decline', v);
  -- The customer is gone at Stripe: stripe-charge clears the summary.
  update public.accounts set stripe_customer_id = null, card_brand = null, card_last4 = null, card_added_at = null
   where id = PRIYA;
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = PRIYA;
  insert into _probe_result values ('a_removed_card_keeps_its_decline', 'generic_decline', v);
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'registered';
  begin perform public.register_for_clinic(open_4, PRIYA_P); exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('and_she_is_asked_for_a_card_first', 'card_required', err);
  perform set_config('role', 'authenticated', true);
  err := 'accepted'; v_hint := '';
  begin
    perform public.respond_to_invitation(r_priya_inv, true);
  exception when others then
    err := sqlerrm;
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('and_an_accept_stays_refused_in_plain_words', 'card_declined|generic_decline', err || '|' || v_hint);

  -- ================================ only while cards are required
  -- Dana's late-cancel fee is declined (real money this time); with
  -- card_required off, like a missing card, a declined one blocks nobody.
  perform set_config('request.jwt.claims', '', true);
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, first_attempted_at)
  values (r_dana, DANA, 'late_cancel', 1800, 'processing', true, now()) returning id into p_dana2;
  update public.payments set status = 'failed', failure_code = 'card_declined',
         failure_reason = 'Your card was declined.'
   where id = p_dana2;
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = DANA;
  insert into _probe_result values ('dana_declined_for_real', 'card_declined', v);
  update public.app_settings set value = 'false' where key = 'card_required';
  perform set_config('request.jwt.claims', json_build_object('sub', DANA)::text, true);
  perform set_config('role', 'authenticated', true);
  err := 'registered';
  begin perform public.register_for_clinic(open_4, DANA_P); exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('no_block_while_cards_are_not_required', 'registered', err);
  update public.app_settings set value = 'true' where key = 'card_required';
  perform set_config('role', 'authenticated', true);
  err := 'registered';
  begin perform public.register_for_clinic(open_5, DANA_P); exception when others then err := sqlerrm; end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('and_the_block_is_back_with_them', 'card_declined', err);

  -- ============== the order charges were ATTEMPTED, not the order answers came
  -- A goes through and B is declined, on Priya's card (saved ten days ago),
  -- in each of the four orders. The rule: a decline stands unless a charge
  -- attempted after it went through.
  perform set_config('request.jwt.claims', '', true);
  for i in 1..4 loop
    update public.accounts set stripe_customer_id = 'cus_probe_priya', card_brand = 'visa', card_last4 = '4242',
           card_added_at = now() - interval '10 days' where id = PRIYA;
    update public.accounts set card_declined_at = null, card_decline_code = null where id = PRIYA;
    insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
    values ((array[open_1, open_2, open_3, open_5])[i], PRIYA_P, 'in', 'admin', 2300, false, 60) returning id into v_reg;
    insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
    values (v_reg, PRIYA, 'clinic_fee', 2300, 'processing', case when i <= 2 then t_early else t_late end) returning id into pa;
    insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
    values (v_reg, PRIYA, 'no_show', 2300, 'processing', case when i <= 2 then t_late else t_early end) returning id into pb;
    if i in (1, 4) then
      update public.payments set status = 'succeeded', livemode = true where id = pa;
      update public.payments set status = 'failed', failure_code = 'insufficient_funds', failure_reason = 'x' where id = pb;
    else
      update public.payments set status = 'failed', failure_code = 'insufficient_funds', failure_reason = 'x' where id = pb;
      update public.payments set status = 'succeeded', livemode = true where id = pa;
    end if;
    select coalesce(card_decline_code, 'clear') into v from public.accounts where id = PRIYA;
    insert into _probe_result values (
      (array['order_1_attempted_A_then_B_recorded_A_then_B', 'order_2_attempted_A_then_B_recorded_B_then_A',
             'order_3_attempted_B_then_A_recorded_B_then_A', 'order_4_attempted_B_then_A_recorded_A_then_B'])[i],
      case when i <= 2 then 'insufficient_funds' else 'clear' end, v);
    delete from public.payments where id in (pa, pb);
  end loop;

  -- A decline attempted after the card on file was saved blocks; one
  -- attempted before it (for the previous card) does not.
  update public.accounts set card_added_at = now() - interval '2 hours', card_declined_at = null, card_decline_code = null
   where id = PRIYA;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_priya, PRIYA, 'no_show', 2300, 'processing', now() - interval '3 hours') returning id into pb;
  update public.payments set status = 'failed', failure_code = 'expired_card', failure_reason = 'x' where id = pb;
  select coalesce(card_decline_code, 'clear') into v from public.accounts where id = PRIYA;
  insert into _probe_result values ('a_decline_for_the_card_before_blocks_nobody', 'clear', v);
  delete from public.payments where id = pb;

  -- Tara's "Went through" on a charge held for three days does not clear a
  -- decline attempted yesterday.
  update public.accounts set card_added_at = now() - interval '10 days' where id = PRIYA;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_priya, PRIYA, 'clinic_fee', 2300, 'processing', now() - interval '3 days') returning id into p_h;
  update public.payments set failure_reason = 'retry_window_passed' where id = p_h;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_priya, PRIYA, 'no_show', 2300, 'processing', now() - interval '1 day') returning id into p_d;
  update public.payments set status = 'failed', failure_code = 'insufficient_funds', failure_reason = 'x' where id = p_d;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.admin_resolve_held_payment(p_h, 'succeeded');
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  select coalesce(card_decline_code, 'clear') into v from public.accounts where id = PRIYA;
  insert into _probe_result values ('went_through_on_an_older_charge_keeps_a_newer_decline', 'insufficient_funds', v);
  delete from public.payments where id in (p_h, p_d);

  -- A charge Tara marked "Did not go through", for which a failure arrives
  -- later through the webhook, blocks nobody.
  update public.accounts set card_added_at = now() - interval '9 days', card_declined_at = null, card_decline_code = null
   where id = PRIYA;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  values (r_priya, PRIYA, 'clinic_fee', 2300, 'processing', now() - interval '26 hours') returning id into p_c;
  update public.payments set failure_reason = 'retry_window_passed' where id = p_c;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.admin_resolve_held_payment(p_c, 'canceled');
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
  update public.payments set status = 'failed', failure_code = 'card_declined', failure_reason = 'x' where id = p_c;
  select coalesce(card_decline_code, 'clear') into v from public.accounts where id = PRIYA;
  insert into _probe_result values ('a_canceled_charge_failing_later_blocks_nobody', 'clear', v);

  -- No definer path clears a decline by writing a card date for the person
  -- it acts for (sql-auditor finding 5): only the pipeline saves a card.
  update public.accounts set card_declined_at = now(), card_decline_code = 'expired_card' where id = KEN;
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin
    update public.accounts set card_added_at = now() where id = KEN;
  exception when others then null; end;
  perform set_config('request.jwt.claims', '', true);
  select coalesce(card_decline_code, 'NULL') into v from public.accounts where id = KEN;
  insert into _probe_result values ('no_definer_path_clears_it_by_writing_a_card_date', 'expired_card', v);

  -- ================================= the swap to live takes every decline
  -- Each was recorded against a sandbox card, gone at the swap: Maria's with
  -- a card on file, Priya's with none. (stripe_live_cutover.sql covers the
  -- rest of the swap on its own fixture.) The swap refuses while live money
  -- exists, so this fixture's live rows go first, as that probe does.
  perform set_config('request.jwt.claims', '', true);
  update public.accounts set card_declined_at = now(), card_decline_code = 'insufficient_funds' where id in (MARIA, PRIYA);
  update public.accounts set stripe_customer_id = null, card_brand = null, card_last4 = null, card_added_at = null
   where id = PRIYA;
  delete from public.payments where kind = 'refund'
     and refunds_payment_id in (select id from public.payments where livemode is true);
  delete from public.payments where livemode is true;
  perform * from public.stripe_cutover_to_live();
  select count(*) into n from public.accounts where card_declined_at is not null or card_decline_code is not null;
  insert into _probe_result values ('the_swap_to_live_takes_every_decline', '0', n::text);

  -- ================================================= the privilege surface
  insert into _probe_result
  select 'decline_column_' || c || '_not_client_writable', 'false',
         has_column_privilege('authenticated', 'public.accounts'::regclass, c, 'UPDATE')::text
    from unnest(array['card_declined_at', 'card_decline_code']) as c;
  insert into _probe_result
  select 'resolved_column_' || c || '_not_client_readable_or_writable', 'false|false',
         has_column_privilege('authenticated', 'public.payments'::regclass, c, 'SELECT')::text || '|'
      || has_column_privilege('authenticated', 'public.payments'::regclass, c, 'UPDATE')::text
    from unnest(array['resolved_at', 'resolved_by']) as c;
  insert into _probe_result values ('trigger_functions_callable_by_nobody', 'false|false|false|false',
    has_function_privilege('authenticated', 'public.payments_card_decline()', 'EXECUTE')::text || '|'
 || has_function_privilege('anon', 'public.payments_card_decline()', 'EXECUTE')::text || '|'
 || has_function_privilege('authenticated', 'public.accounts_card_decline()', 'EXECUTE')::text || '|'
 || has_function_privilege('anon', 'public.accounts_card_decline()', 'EXECUTE')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
  from _probe_result
 order by check_name;

rollback;
