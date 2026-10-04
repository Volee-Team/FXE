-- charge_each_player.sql
--
-- Tara charges each person on her own tap, and takes someone off the roster
-- so they are never charged (decision 0037, 20261002000001). Written FROM THE
-- RULE; every expected value is worked out by hand from the fixture below.
--
-- THE RULE
--   * A person on an ended clinic owes what Charge clinic would charge them:
--     came -> clinic_fee, no-show -> no_show, late cancel -> late_cancel, each
--     at the price stored on their registration. Player Pool, removed by
--     Tara, and paid by hand owe nothing.
--   * admin_fees_due(clinic) lists exactly who owes now and has no live
--     charge (a declined card owes again). Empty while payments are off.
--   * admin_charge_player(registration) charges that one person that fee.
--     Twice is one fee (already_charged). Owing nothing is not_owed. No card
--     is no_card_on_file. The clinic refusals are Charge clinic's own:
--     payments_disabled, clinic_not_over, clinic_canceled,
--     clinic_before_payments. Only an admin may call either (not_authorized).
--   * Tara removing someone after the clinic ended: they owe nothing, are not
--     marked late, and are told nothing.
--
-- FIXTURE (New York). payments on since T0 = 2026-09-01 00:00.
--   E  ended 2026-09-20 19:00:
--        Maria  in, card, 1800                  -> owes clinic_fee 1800
--        Ken    in, no-show, card, 1800         -> owes no_show 1800
--        Rob    late cancel, card, 2300         -> owes late_cancel 2300
--        Priya  in, NO card, 2300               -> owes clinic_fee 2300
--        Dana   in, card, 1800, a failed charge -> owes clinic_fee 1800 (declined)
--        Casey  in, card, 1800                  -> owes clinic_fee 1800, until Tara removes her
--        Lena   Player Pool, card               -> owes nothing
--        Theo   in, card, 2300, PAID by hand    -> owes nothing
--   G  ends tomorrow: Maria in            -> clinic_not_over
--   B  ended 2026-08-20 (before T0): Ken  -> clinic_before_payments
--   C  ended 2026-09-21, canceled: Maria  -> clinic_canceled
--
-- EXPECTED (by hand)
--   due before: Casey|clinic_fee|1800|not_charged, Dana|clinic_fee|1800|declined,
--               Ken|no_show|1800|not_charged, Maria|clinic_fee|1800|not_charged,
--               Priya|clinic_fee|2300|not_charged, Rob|late_cancel|2300|not_charged
--   Maria -> clinic_fee|1800; again -> already_charged; 1 payment, pending
--   Ken -> no_show|1800; Rob -> late_cancel|2300; Dana -> clinic_fee|1800 (2 payments)
--   Priya -> no_card_on_file; Lena, Theo -> not_owed
--   Casey removed: canceled, not late; then not_owed; 0 notifications to her
--   due after: Priya|clinic_fee|2300|not_charged, has_card false
--   G not_over and 0 due; B before_payments; C canceled
--   Maria calling either -> not_authorized
--   payments off: 0 due, Priya -> payments_disabled
--   EXECUTE: authenticated yes, anon no, public no, on both
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
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';
  LENA    constant uuid := '88888888-8888-8888-8888-888888888888';
  THEO    constant uuid := '99999999-9999-9999-9999-999999999999';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  CASEY_P constant uuid := 'a0000000-0000-0000-0000-000000000006';
  LENA_P  constant uuid := 'a0000000-0000-0000-0000-000000000007';
  THEO_P  constant uuid := 'a0000000-0000-0000-0000-000000000008';
  ny      constant text := 'America/New_York';
  ce uuid; cg uuid; cb uuid; cc uuid;
  e_maria uuid; e_ken uuid; e_rob uuid; e_priya uuid; e_dana uuid; e_casey uuid; e_lena uuid; e_theo uuid;
  g_maria uuid; b_ken uuid; c_maria uuid;
  cd uuid; c2 uuid; cs uuid; cx uuid; ct uuid; cr uuid; cl uuid;
  d_maria uuid; x2_maria uuid; s_ken uuid; x_rob uuid; t_dana uuid; r_ken uuid; r_rob uuid; r_theo uuid; l1_rob uuid; l2_rob uuid; snap uuid; f1 uuid;
  v text; n int; j jsonb;
begin
  -- ------------------------------------------------------------ fixture
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  insert into public.app_settings (key, value)
  values ('payments_enabled_at', (timestamp '2026-09-01 00:00' at time zone ny)::text)
  on conflict (key) do update set value = excluded.value;

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe each player', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-20 18:00' at time zone ny, timestamp '2026-09-20 19:00' at time zone ny,
          timestamp '2026-09-17 08:00' at time zone ny, timestamp '2026-09-18 08:00' at time zone ny, 8, 'published', 60)
  returning id into ce;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe tomorrow', 'coed', 'Clinic', 'probe',
          now() + interval '1 day', now() + interval '1 day 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into cg;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe before cards', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-20 18:00' at time zone ny, timestamp '2026-08-20 19:00' at time zone ny,
          timestamp '2026-08-13 08:00' at time zone ny, timestamp '2026-08-14 08:00' at time zone ny, 8, 'published', 60)
  returning id into cb;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, canceled_at)
  values ('Probe canceled', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-21 18:00' at time zone ny, timestamp '2026-09-21 19:00' at time zone ny,
          timestamp '2026-09-17 08:00' at time zone ny, timestamp '2026-09-18 08:00' at time zone ny, 8, 'canceled', 60, now())
  returning id into cc;

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, MARIA_P, 'in', 'self', 1800, true, 60) returning id into e_maria;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, no_show)
  values (ce, KEN_P, 'in', 'self', 1800, true, 60, true) returning id into e_ken;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
      late_cancel, canceled_at)
  values (ce, ROB_P, 'canceled', 'self', 2300, false, 60, true, timestamp '2026-09-20 17:00' at time zone ny) returning id into e_rob;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, PRIYA_P, 'in', 'self', 2300, false, 60) returning id into e_priya;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, DANA_P, 'in', 'self', 1800, true, 60) returning id into e_dana;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, CASEY_P, 'in', 'self', 1800, true, 60) returning id into e_casey;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, LENA_P, 'pool', 'self', 1800, true, 60) returning id into e_lena;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, paid)
  values (ce, THEO_P, 'in', 'self', 2300, false, 60, true) returning id into e_theo;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_code, failure_reason)
  values (e_dana, DANA, 'clinic_fee', 1800, 'failed', 'card_declined', 'Your card was declined.');

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cg, MARIA_P, 'in', 'self', 1800, true, 60) returning id into g_maria;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cb, KEN_P, 'in', 'self', 1800, true, 60) returning id into b_ken;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cc, MARIA_P, 'in', 'self', 1800, true, 60) returning id into c_maria;

  update public.accounts set stripe_customer_id = 'cus_probe_' || left(id::text, 4), card_brand = 'visa', card_last4 = '4242'
   where id in (MARIA, KEN, ROB, DANA, CASEY, LENA, THEO);
  update public.accounts set stripe_customer_id = null, card_brand = null, card_last4 = null
   where id = '55555555-5555-5555-5555-555555555555';

  -- The sql-auditor's cases (2026-10-04), each its own clinic.
  -- D: a DRAFT that ended after T0, Maria in: never published, owes nothing.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe draft', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-22 18:00' at time zone ny, timestamp '2026-09-22 19:00' at time zone ny,
          timestamp '2026-09-17 08:00' at time zone ny, timestamp '2026-09-18 08:00' at time zone ny, 8, 'draft', 60)
  returning id into cd;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cd, MARIA_P, 'in', 'admin', 1800, true, 60) returning id into d_maria;
  -- E2: a second ended, published clinic with Maria owing: never in E's list.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe other clinic', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-23 18:00' at time zone ny, timestamp '2026-09-23 19:00' at time zone ny,
          timestamp '2026-09-17 08:00' at time zone ny, timestamp '2026-09-18 08:00' at time zone ny, 8, 'published', 60)
  returning id into c2;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c2, MARIA_P, 'in', 'self', 1800, true, 60) returning id into x2_maria;
  -- S: started an hour ago, ends in an hour: not over.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe under way', 'coed', 'Clinic', 'probe', now() - interval '1 hour', now() + interval '1 hour',
          now() - interval '5 days', now() - interval '4 days', 8, 'published', 120)
  returning id into cs;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cs, KEN_P, 'in', 'self', 1800, true, 120) returning id into s_ken;
  -- X: starts before T0, ends after it: owes (ended at or after T0).
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe across the switch', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-31 23:30' at time zone ny, timestamp '2026-09-01 00:30' at time zone ny,
          timestamp '2026-08-27 08:00' at time zone ny, timestamp '2026-08-28 08:00' at time zone ny, 8, 'published', 60)
  returning id into cx;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cx, ROB_P, 'in', 'self', 2300, false, 60) returning id into x_rob;
  -- T: a sandbox fee that went through, after the live switch: still owes.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe test money', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-24 18:00' at time zone ny, timestamp '2026-09-24 19:00' at time zone ny,
          timestamp '2026-09-17 08:00' at time zone ny, timestamp '2026-09-18 08:00' at time zone ny, 8, 'published', 60)
  returning id into ct;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ct, DANA_P, 'in', 'self', 1800, true, 60) returning id into t_dana;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode)
  values (t_dana, DANA, 'clinic_fee', 1800, 'succeeded', false);
  insert into public.app_settings (key, value)
  values ('stripe_live_since', (timestamp '2026-09-15 00:00' at time zone ny)::text)
  on conflict (key) do update set value = excluded.value;
  -- R: Ken's decline Tara Resolved, Rob's fee refunded, Theo's held
  -- (processing, too old to retry), and a stale price snapshot for Lena.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe settled ways', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-25 18:00' at time zone ny, timestamp '2026-09-25 19:00' at time zone ny,
          timestamp '2026-09-17 08:00' at time zone ny, timestamp '2026-09-18 08:00' at time zone ny, 8, 'published', 60)
  returning id into cr;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cr, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_code, failure_reason, resolved_at)
  values (r_ken, KEN, 'clinic_fee', 1800, 'failed', 'card_declined', 'Your card was declined.', now());
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cr, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_rob;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode)
  values (r_rob, ROB, 'clinic_fee', 2300, 'succeeded', true) returning id into f1;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, refunds_payment_id)
  values (r_rob, ROB, 'refund', 2300, 'succeeded', true, f1);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cr, THEO_P, 'in', 'self', 2300, false, 60) returning id into r_theo;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_reason, first_attempted_at)
  values (r_theo, THEO, 'clinic_fee', 2300, 'processing', 'retry_window_passed', now() - interval '2 days');
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cr, LENA_P, 'in', 'self', 1500, true, 60) returning id into snap;
  -- L: Rob cancels late, is put back in, cancels late again: one late fee.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe twice late', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-26 18:00' at time zone ny, timestamp '2026-09-26 19:00' at time zone ny,
          timestamp '2026-09-17 08:00' at time zone ny, timestamp '2026-09-18 08:00' at time zone ny, 8, 'published', 60)
  returning id into cl;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, late_cancel, canceled_at)
  values (cl, ROB_P, 'canceled', 'self', 2300, false, 60, true, timestamp '2026-09-26 16:00' at time zone ny) returning id into l1_rob;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, late_cancel, canceled_at)
  values (cl, ROB_P, 'canceled', 'self', 2300, false, 60, true, timestamp '2026-09-26 17:00' at time zone ny) returning id into l2_rob;

  -- ------------------------------------------------------------ as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  -- Named from the fixture's own ids: Tara's role reads no base table.
  select string_agg(x.who || '|' || x.kind || '|' || x.amount_cents || '|' || x.state, ', ' order by x.who)
    into v
    from (select case d.registration_id
                   when e_maria then 'Maria' when e_ken then 'Ken' when e_rob then 'Rob'
                   when e_priya then 'Priya' when e_dana then 'Dana' when e_casey then 'Casey'
                   when e_lena then 'Lena' when e_theo then 'Theo' else 'OTHER' end as who,
                 d.kind, d.amount_cents, d.state
            from public.admin_fees_due(ce) d) x;
  insert into _probe_result values ('due_before_lists_exactly_who_owes',
    'Casey|clinic_fee|1800|not_charged, Dana|clinic_fee|1800|declined, Ken|no_show|1800|not_charged, '
    || 'Maria|clinic_fee|1800|not_charged, Priya|clinic_fee|2300|not_charged, Rob|late_cancel|2300|not_charged',
    coalesce(v, 'NONE'));

  begin
    j := public.admin_charge_player(e_maria);
    insert into _probe_result values ('came_charged_clinic_fee', 'clinic_fee|1800', (j->>'kind') || '|' || (j->>'amount_cents'));
  exception when others then
    insert into _probe_result values ('came_charged_clinic_fee', 'clinic_fee|1800', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(e_maria);
    insert into _probe_result values ('second_tap_is_already_charged', 'already_charged', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('second_tap_is_already_charged', 'already_charged', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(e_ken);
    insert into _probe_result values ('no_show_charged_no_show_fee', 'no_show|1800', (j->>'kind') || '|' || (j->>'amount_cents'));
  exception when others then
    insert into _probe_result values ('no_show_charged_no_show_fee', 'no_show|1800', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(e_rob);
    insert into _probe_result values ('late_cancel_charged_late_fee', 'late_cancel|2300', (j->>'kind') || '|' || (j->>'amount_cents'));
  exception when others then
    insert into _probe_result values ('late_cancel_charged_late_fee', 'late_cancel|2300', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(e_dana);
    insert into _probe_result values ('declined_card_can_be_charged_again', 'clinic_fee|1800', (j->>'kind') || '|' || (j->>'amount_cents'));
  exception when others then
    insert into _probe_result values ('declined_card_can_be_charged_again', 'clinic_fee|1800', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(e_priya);
    insert into _probe_result values ('no_card_refused', 'no_card_on_file', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('no_card_refused', 'no_card_on_file', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(e_lena);
    insert into _probe_result values ('player_pool_not_owed', 'not_owed', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('player_pool_not_owed', 'not_owed', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(e_theo);
    insert into _probe_result values ('paid_by_hand_not_owed', 'not_owed', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('paid_by_hand_not_owed', 'not_owed', sqlerrm);
  end;

  -- Tara takes Casey off the roster after the clinic (the puking kid).
  begin
    perform public.cancel_registration(e_casey, null);
  exception when others then
    insert into _probe_result values ('remove_after_clinic_allowed', 'ok', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(e_casey);
    insert into _probe_result values ('removed_not_owed', 'not_owed', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('removed_not_owed', 'not_owed', sqlerrm);
  end;

  -- Named from the fixture's own ids: Tara's role reads no base table.
  select string_agg(x.who || '|' || x.kind || '|' || x.amount_cents || '|' || x.state, ', ' order by x.who)
    into v
    from (select case d.registration_id
                   when e_maria then 'Maria' when e_ken then 'Ken' when e_rob then 'Rob'
                   when e_priya then 'Priya' when e_dana then 'Dana' when e_casey then 'Casey'
                   when e_lena then 'Lena' when e_theo then 'Theo' else 'OTHER' end as who,
                 d.kind, d.amount_cents, d.state
            from public.admin_fees_due(ce) d) x;
  insert into _probe_result values ('due_after_only_the_one_without_a_card', 'Priya|clinic_fee|2300|not_charged', coalesce(v, 'NONE'));
  select string_agg(d.has_card::text, ',') into v from public.admin_fees_due(ce) d;
  insert into _probe_result values ('due_says_who_has_no_card', 'false', coalesce(v, 'NONE'));

  begin
    j := public.admin_charge_player(g_maria);
    insert into _probe_result values ('not_over_refused', 'clinic_not_over', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('not_over_refused', 'clinic_not_over', sqlerrm);
  end;
  select count(*) into n from public.admin_fees_due(cg);
  insert into _probe_result values ('not_over_nothing_due', '0', n::text);
  begin
    j := public.admin_charge_player(b_ken);
    insert into _probe_result values ('before_payments_refused', 'clinic_before_payments', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('before_payments_refused', 'clinic_before_payments', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(c_maria);
    insert into _probe_result values ('canceled_clinic_refused', 'clinic_canceled', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('canceled_clinic_refused', 'clinic_canceled', sqlerrm);
  end;

  -- The auditor's cases.
  select count(*) into n from public.admin_fees_due(cd);
  insert into _probe_result values ('draft_never_owes', '0', n::text);
  begin
    j := public.admin_charge_player(d_maria);
    insert into _probe_result values ('draft_charge_refused', 'clinic_not_published', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('draft_charge_refused', 'clinic_not_published', sqlerrm);
  end;
  select count(*) into n from public.admin_fees_due(ce) d where d.registration_id = x2_maria;
  insert into _probe_result values ('fees_due_is_one_clinic_only', '0', n::text);
  select count(*) into n from public.admin_fees_due(c2);
  insert into _probe_result values ('other_clinic_lists_its_own', '1', n::text);
  begin
    j := public.admin_charge_player(s_ken);
    insert into _probe_result values ('under_way_refused', 'clinic_not_over', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('under_way_refused', 'clinic_not_over', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(x_rob);
    insert into _probe_result values ('ending_after_the_switch_owes', 'clinic_fee|2300', (j->>'kind') || '|' || (j->>'amount_cents'));
  exception when others then
    insert into _probe_result values ('ending_after_the_switch_owes', 'clinic_fee|2300', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(t_dana);
    insert into _probe_result values ('sandbox_fee_after_live_still_owes', 'clinic_fee|1800', (j->>'kind') || '|' || (j->>'amount_cents'));
  exception when others then
    insert into _probe_result values ('sandbox_fee_after_live_still_owes', 'clinic_fee|1800', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(r_ken);
    insert into _probe_result values ('resolved_decline_not_owed', 'not_owed', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('resolved_decline_not_owed', 'not_owed', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(r_rob);
    insert into _probe_result values ('refunded_not_owed', 'not_owed', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('refunded_not_owed', 'not_owed', sqlerrm);
  end;
  begin
    j := public.admin_charge_player(r_theo);
    insert into _probe_result values ('held_charge_is_already_charged', 'already_charged', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('held_charge_is_already_charged', 'already_charged', sqlerrm);
  end;
  select string_agg(d.amount_cents::text, ',') into v from public.admin_fees_due(cr) d;
  insert into _probe_result values ('settled_ways_only_the_snapshot_owes', '1500', coalesce(v, 'NONE'));
  begin
    j := public.admin_charge_player(snap);
    insert into _probe_result values ('charges_the_price_snapshot', 'clinic_fee|1500', (j->>'kind') || '|' || (j->>'amount_cents'));
  exception when others then
    insert into _probe_result values ('charges_the_price_snapshot', 'clinic_fee|1500', sqlerrm);
  end;
  select count(*) || '|' || coalesce(string_agg((d.registration_id = l2_rob)::text, ','), '') into v from public.admin_fees_due(cl) d;
  insert into _probe_result values ('two_late_cancels_one_fee_the_newest', '1|true', v);

  -- ------------------------------------------------------------ as the pro
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin
    j := public.admin_charge_player(snap);
    insert into _probe_result values ('pro_cannot_charge', 'not_authorized', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('pro_cannot_charge', 'not_authorized', sqlerrm);
  end;
  begin
    select count(*) into n from public.admin_fees_due(cr);
    insert into _probe_result values ('pro_cannot_read_fees_due', 'not_authorized', 'READ ' || n || ' ROWS');
  exception when others then
    insert into _probe_result values ('pro_cannot_read_fees_due', 'not_authorized', sqlerrm);
  end;

  -- ------------------------------------------------------------ as Maria
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    j := public.admin_charge_player(e_priya);
    insert into _probe_result values ('member_cannot_charge', 'not_authorized', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('member_cannot_charge', 'not_authorized', sqlerrm);
  end;
  begin
    select count(*) into n from public.admin_fees_due(ce);
    insert into _probe_result values ('member_cannot_read_fees_due', 'not_authorized', 'READ ' || n || ' ROWS');
  exception when others then
    insert into _probe_result values ('member_cannot_read_fees_due', 'not_authorized', sqlerrm);
  end;

  -- ------------------------------------------------------------ the ledger, as postgres
  perform set_config('role', 'postgres', true);
  select count(*) || '|' || string_agg(status::text, ',') into v from public.payments where registration_id = e_maria;
  insert into _probe_result values ('double_tap_left_one_pending_fee', '1|pending', v);
  select count(*) into n from public.payments where registration_id = e_dana;
  insert into _probe_result values ('declined_then_charged_two_rows', '2', n::text);
  select count(*) into n from public.payments where registration_id in (e_priya, e_lena, e_theo, e_casey);
  insert into _probe_result values ('nothing_queued_for_who_owes_nothing', '0', n::text);
  select status || '|' || late_cancel into v from public.registrations where id = e_casey;
  insert into _probe_result values ('remove_after_clinic_allowed', 'canceled|false', v);
  select count(*) into n from public.notifications where account_id = CASEY;
  insert into _probe_result values ('removed_player_told_nothing', '0', n::text);

  -- ------------------------------------------------------------ payments off
  update public.app_settings set value = 'false' where key = 'payments_enabled';
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.admin_fees_due(ce);
  insert into _probe_result values ('payments_off_nothing_due', '0', n::text);
  begin
    j := public.admin_charge_player(e_priya);
    insert into _probe_result values ('payments_off_refused', 'payments_disabled', 'CALL SUCCEEDED ' || j::text);
  exception when others then
    insert into _probe_result values ('payments_off_refused', 'payments_disabled', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------------ who may call
  select string_agg(r || ':' || has_function_privilege(r, f, 'execute'), ' ' order by f, r)
    into v
    from unnest(array['authenticated', 'anon']) r,
         unnest(array['public.admin_charge_player(uuid)', 'public.admin_fees_due(uuid)']) f;
  insert into _probe_result values ('execute_grants',
    'anon:false authenticated:true anon:false authenticated:true', v);
  select count(*) into n
    from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.proname in ('admin_charge_player', 'admin_fees_due') and a.grantee = 0;
  insert into _probe_result values ('public_holds_no_execute', '0', n::text);
end;
$$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
