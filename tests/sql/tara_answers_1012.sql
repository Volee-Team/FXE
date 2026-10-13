-- tara_answers_1012.sql
--
-- Tara's answers of 2026-10-12 that change the database (decision 0040,
-- 20261012000001). Written FROM HER ANSWERS; every expected value is worked
-- out by hand from the fixture below.
--
-- THE RULES
--   106 "Yes": Tara can waive a late cancel's fee. A waived late cancel owes
--       nothing (no Charge button, admin_charge_player says not_owed), and
--       un-waiving puts it back. Only a late cancel with no live charge can be
--       waived; anything else is not_waivable. Only an admin may do it.
--   107 "Yes": accepting an invitation needs a saved card, as registering
--       does, while payments are on and cards are required. Refused with
--       card_required and nothing moves; Decline still works; with either
--       switch off, Accept works without a card.
--   105 "Yes": the history line counts every cancel, late ones included:
--       cancels the player made herself (You're In! or the Pool) plus late
--       cancels whoever marked them. Tara's plain Remove and a clinic Tara
--       canceled are not the player's cancels.
--
-- FIXTURE (New York). Payments on since 2026-09-01; cards required.
--   E ended 2026-09-20: Rob late cancel 2300 (card), Ken late cancel 1800
--     (card), Maria in 1800 (card).
--   F starts in 3 days: Priya (NO card) invited, Maria (card) invited.
--   Casey's history: H1 played; H2 no-show; H3 she canceled her spot; H4 a
--     late cancel Tara marked; H5 Tara removed her; H6 she left the Pool;
--     H7 she canceled, but Tara canceled the clinic; H8 she canceled late herself
--     (counted once).
--
-- EXPECTED (by hand)
--   due on E before: Ken|late_cancel|1800, Maria|clinic_fee|1800 (she came),
--     Rob|late_cancel|2300
--   Rob waived -> {"fee_waived": true}; due: Ken, Maria; charge Rob -> not_owed
--   Rob restored -> due: Ken, Maria, Rob again; then waived again
--   Maria's 'in' row and Dana's removal (not late) -> not_waivable; Ken charged then waived -> not_waivable
--   Maria (a member) waiving -> not_authorized, Ken's row unchanged
--   Priya Accept -> card_required, still response_needed; Decline -> pool
--   Maria Accept -> in
--   cards not required: Priya Accept (again invited) -> in
--   Casey: played 1, no_shows 1, late_cancels 2, canceled 4
--   EXECUTE on admin_set_fee_waived: authenticated yes, anon no, public no
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
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  CASEY_P constant uuid := 'a0000000-0000-0000-0000-000000000006';
  LENA    constant uuid := '88888888-8888-8888-8888-888888888888';
  LENA_P  constant uuid := 'a0000000-0000-0000-0000-000000000007';
  ny      constant text := 'America/New_York';
  ce uuid; cf uuid; h uuid;
  e_rob uuid; e_ken uuid; e_maria uuid; e_dana uuid; f_priya uuid; f_maria uuid;
  e_ken2 uuid; e_lena1 uuid; e_lena2 uuid; cg uuid; g_priya uuid;
  v text; n int; j jsonb; err text;
begin
  -- ------------------------------------------------------------ fixture
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  update public.app_settings set value = 'true' where key = 'card_required';
  insert into public.app_settings (key, value)
  values ('payments_enabled_at', (timestamp '2026-09-01 00:00' at time zone ny)::text)
  on conflict (key) do update set value = excluded.value;
  update public.accounts set stripe_customer_id = 'cus_probe_' || left(id::text, 4), card_brand = 'visa', card_last4 = '4242'
   where id in (MARIA, KEN, ROB);
  -- Priya opened the card sheet (a Stripe customer) but saved no card: not a
  -- card (decision 0015 §5).
  update public.accounts set stripe_customer_id = 'cus_probe_nocard', card_brand = null, card_last4 = null where id = PRIYA;
  update public.accounts set stripe_customer_id = 'cus_probe_lena', card_brand = 'visa', card_last4 = '4242' where id = LENA;

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe waive', 'coed', 'Clinic', 'probe',
          timestamp '2026-09-20 18:00' at time zone ny, timestamp '2026-09-20 19:00' at time zone ny,
          timestamp '2026-09-10 08:00' at time zone ny, timestamp '2026-09-11 08:00' at time zone ny, 8, 'published', 60)
  returning id into ce;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
      late_cancel, canceled_at, canceled_by)
  values (ce, ROB_P, 'canceled', 'self', 2300, false, 60, true, timestamp '2026-09-20 17:00' at time zone ny, ROB)
  returning id into e_rob;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
      late_cancel, canceled_at, canceled_by)
  values (ce, KEN_P, 'canceled', 'self', 1800, true, 60, true, timestamp '2026-09-20 16:30' at time zone ny, KEN)
  returning id into e_ken;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ce, MARIA_P, 'in', 'self', 1800, true, 60)
  returning id into e_maria;
  -- Dana: Tara removed her (canceled, not late), so nothing to waive.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
      late_cancel, canceled_at, canceled_by)
  values (ce, DANA_P, 'canceled', 'self', 1800, true, 60, false, timestamp '2026-09-19 12:00' at time zone ny, TARA)
  returning id into e_dana;

  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe accept', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into cf;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, invited_at)
  values (cf, PRIYA_P, 'response_needed', 'self', 2300, false, 60, now()) returning id into f_priya;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, invited_at)
  values (cf, MARIA_P, 'response_needed', 'self', 1800, true, 60, now()) returning id into f_maria;

  -- ------------------------------------------------------- 106: waive
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select coalesce(string_agg(p.first_name || '|' || d.kind || '|' || d.amount_cents, ', ' order by p.first_name), '') into v
    from public.admin_fees_due(ce) d
    join public.registrations_admin r on r.id = d.registration_id
    join public.players p on p.id = r.player_id;
  insert into _probe_result values ('due_before_waive', '[Ken|late_cancel|1800, Maria|clinic_fee|1800, Rob|late_cancel|2300]', '[' || v || ']');

  j := public.admin_set_fee_waived(e_rob, true);
  insert into _probe_result values ('waive_answers', 'true', j->>'fee_waived');
  select coalesce(string_agg(p.first_name, ', ' order by p.first_name), '') into v
    from public.admin_fees_due(ce) d
    join public.registrations_admin r on r.id = d.registration_id
    join public.players p on p.id = r.player_id;
  insert into _probe_result values ('due_after_waive', '[Ken, Maria]', '[' || v || ']');
  begin
    perform public.admin_charge_player(e_rob);
    err := 'charged';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('waived_not_chargeable', 'not_owed', err);
  select (fee_waived_at is not null)::text into v from public.registrations_admin where id = e_rob;
  insert into _probe_result values ('roster_shows_waived', 'true', v);

  begin
    j := public.admin_set_fee_waived(e_rob, false);
    v := j->>'fee_waived';
  exception when others then v := sqlerrm;
  end;
  insert into _probe_result values ('restore_answers', 'false', v);
  select coalesce(string_agg(p.first_name, ', ' order by p.first_name), '') into v
    from public.admin_fees_due(ce) d
    join public.registrations_admin r on r.id = d.registration_id
    join public.players p on p.id = r.player_id;
  insert into _probe_result values ('due_after_restore', '[Ken, Maria, Rob]', '[' || v || ']');
  begin
    perform public.admin_set_fee_waived(e_rob, true);
  exception when others then null;   -- a broken waive is caught above, not here
  end;

  begin
    perform public.admin_set_fee_waived(e_dana, true);
    err := 'waived';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('removed_not_waivable', 'not_waivable', err);

  begin
    perform public.admin_set_fee_waived(e_maria, true);
    err := 'waived';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('came_not_waivable', 'not_waivable', err);

  begin
    perform public.admin_charge_player(e_ken);
  exception when others then null;
  end;
  begin
    perform public.admin_set_fee_waived(e_ken, true);
    err := 'waived';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('charged_not_waivable', 'not_waivable', err);
  -- Back in and late again: Ken holds a live charge in this clinic, so this
  -- newer late cancel is shown as charged and cannot read "Fee waived".
  perform set_config('role', 'postgres', true);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
      late_cancel, canceled_at, canceled_by)
  values (ce, KEN_P, 'canceled', 'admin', 1800, true, 60, true, timestamp '2026-09-20 17:30' at time zone ny, TARA)
  returning id into e_ken2;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_set_fee_waived(e_ken2, true);
    err := 'waived';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('charged_player_not_waivable', 'not_waivable', err);

  -- Lena canceled late twice (in, out, back, out): only the newest owes, so
  -- only the newest can be waived, and waiving it leaves Lena owing nothing.
  perform set_config('role', 'postgres', true);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
      late_cancel, canceled_at, canceled_by)
  values (ce, LENA_P, 'canceled', 'self', 1800, true, 60, true, timestamp '2026-09-20 15:00' at time zone ny, LENA)
  returning id into e_lena1;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
      late_cancel, canceled_at, canceled_by)
  values (ce, LENA_P, 'canceled', 'self', 1800, true, 60, true, timestamp '2026-09-20 16:00' at time zone ny, LENA)
  returning id into e_lena2;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_set_fee_waived(e_lena1, true);
    err := 'waived';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('older_late_cancel_not_waivable', 'not_waivable', err);
  -- A member attacking a row Tara could waive: refused, and nothing moved.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.admin_set_fee_waived(e_lena2, true);
    err := 'waived';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('member_cannot_waive', 'not_authorized', err);
  perform set_config('role', 'postgres', true);
  select coalesce(fee_waived_at::text, '<null>') into v from public.registrations where id = e_lena2;
  insert into _probe_result values ('lena_unchanged_by_member', '<null>', v);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_set_fee_waived(e_lena2, true);
  select count(*) into n from public.admin_fees_due(ce) d
   join public.registrations_admin r on r.id = d.registration_id where r.player_id = LENA_P;
  insert into _probe_result values ('newest_waived_lena_owes_nothing', '0', n::text);

  -- The old whole-clinic tap (no screen calls it) skips a waived fee too.
  perform public.admin_charge_clinic(ce);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.payments where registration_id in (e_rob, e_lena1, e_lena2);
  insert into _probe_result values ('clinic_tap_skips_waived', '0', n::text);
  perform set_config('role', 'authenticated', true);

  perform set_config('role', 'postgres', true);

  insert into _probe_result values ('waive_authenticated', 'true',
    has_function_privilege('authenticated', 'public.admin_set_fee_waived(uuid, boolean)', 'EXECUTE')::text);
  insert into _probe_result values ('waive_anon', 'false',
    has_function_privilege('anon', 'public.admin_set_fee_waived(uuid, boolean)', 'EXECUTE')::text);
  insert into _probe_result values ('waive_public', 'false',
    exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
             where p.oid = 'public.admin_set_fee_waived(uuid, boolean)'::regprocedure
               and a.grantee = 0 and a.privilege_type = 'EXECUTE')::text);

  -- ----------------------------------------------- 107: Accept needs a card
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  begin
    perform public.respond_to_invitation(f_priya, true);
    err := 'accepted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('no_card_accept_refused', 'card_required', err);
  select status::text into v from public.my_registrations where id = f_priya;
  insert into _probe_result values ('no_card_nothing_moved', 'response_needed', v);
  begin
    perform public.respond_to_invitation(f_priya, false);
  exception when others then null;
  end;
  select status::text into v from public.my_registrations where id = f_priya;
  insert into _probe_result values ('no_card_decline_works', 'pool', v);

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform public.respond_to_invitation(f_maria, true);
  select status::text into v from public.my_registrations where id = f_maria;
  insert into _probe_result values ('card_accept_works', 'in', v);

  perform set_config('role', 'postgres', true);
  update public.app_settings set value = 'false' where key = 'card_required';
  update public.registrations set status = 'response_needed', invited_at = now() where id = f_priya;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  begin
    perform public.respond_to_invitation(f_priya, true);
  exception when others then null;
  end;
  select status::text into v from public.my_registrations where id = f_priya;
  insert into _probe_result values ('cards_not_required_accept_works', 'in', v);

  -- Payments off, cards still required: no card needed to Accept.
  perform set_config('role', 'postgres', true);
  update public.app_settings set value = 'true' where key = 'card_required';
  update public.app_settings set value = 'false' where key = 'payments_enabled';
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe accept off', 'coed', 'Clinic', 'probe', now() + interval '4 days', now() + interval '4 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into cg;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, invited_at)
  values (cg, PRIYA_P, 'response_needed', 'self', 2300, false, 60, now()) returning id into g_priya;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.respond_to_invitation(g_priya, true);
  exception when others then null;
  end;
  select status::text into v from public.my_registrations where id = g_priya;
  insert into _probe_result values ('payments_off_accept_works', 'in', v);

  -- ------------------------------------------- 105: every cancel counted
  perform set_config('role', 'postgres', true);
  -- H1 played, H2 no-show, H3 she canceled, H4 late (Tara marked),
  -- H5 Tara removed, H6 she left the Pool, H7 clinic canceled by Tara.
  for n in 1..8 loop
    insert into public.clinics (name, audience, category, description, starts_at, ends_at,
        member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
    values ('Probe history ' || n, 'coed', 'Clinic', 'probe',
            now() - make_interval(days => 10 + n), now() - make_interval(days => 10 + n) + interval '1 hour',
            now() - make_interval(days => 20 + n), now() - make_interval(days => 19 + n), 8,
            case when n = 7 then 'canceled'::clinic_status else 'published'::clinic_status end, 60)
    returning id into h;
    insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
        no_show, late_cancel, canceled_at, canceled_by)
    values (h, CASEY_P,
            case when n in (1, 2) then 'in'::registration_status else 'canceled'::registration_status end,
            'self', 1800, true, 60,
            n = 2, n in (4, 8),
            case when n >= 3 then now() - make_interval(days => 11 + n) end,
            case when n in (3, 6, 7, 8) then CASEY when n in (4, 5) then TARA end);
  end loop;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select played || ' played, ' || canceled || ' canceled (' || late_cancels || ' late), ' || no_shows || ' no-show'
    into v from public.admin_player_history(CASEY_P);
  insert into _probe_result values ('casey_history', '[1 played, 4 canceled (2 late), 1 no-show]', '[' || v || ']');
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
