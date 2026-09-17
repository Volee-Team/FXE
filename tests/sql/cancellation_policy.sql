-- cancellation_policy.sql
--
-- Decision 0012 (Tara, 2026-09-16): a card on file to register, no-shows
-- marked by Tara, one courtesy late cancellation per 90 days applied by the
-- app, and every charge waiting for the clinic to end and for her one tap.
-- Expected values come from her policy text, not from the functions.
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
  FAR     constant uuid := 'd0000000-0000-0000-0000-000000000002';
  done_c uuid; reg_m uuid; reg_k uuid; reg_r uuid; reg_d uuid; n int; v text; j jsonb; r public.registrations;
begin
  -- ---------------------------------------------------------- settings
  select value into v from public.app_settings where key = 'card_required';
  insert into _probe_result values ('card_required_setting_true', 'true', v);
  select value into v from public.app_settings where key = 'courtesy_cancel_days';
  insert into _probe_result values ('courtesy_window_is_90_days', '90', v);
  select value into v from public.app_settings where key = 'charge_fee_at';
  insert into _probe_result values ('fee_charged_after_clinic', 'after_clinic', v);

  -- ------------------------------------------- card required to register
  -- Payments off: registering needs no card (nothing changes until she flips it).
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.register_for_clinic(FAR, MARIA_P);
  insert into _probe_result values ('no_card_needed_while_payments_off', 'true', (r.status in ('in','pool'))::text);
  perform public.cancel_registration(r.id);
  perform set_config('role', 'postgres', true);
  delete from public.registrations where player_id = MARIA_P and clinic_id = FAR;

  -- Payments on, no card: refused with card_required. With a card: in.
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(FAR, MARIA_P);
    insert into _probe_result values ('no_card_refused_when_payments_on', 'card_required', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('no_card_refused_when_payments_on', 'card_required', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  update public.accounts set stripe_customer_id = 'cus_probe_maria' where id = MARIA;
  perform set_config('role', 'authenticated', true);
  r := public.register_for_clinic(FAR, MARIA_P);
  insert into _probe_result values ('card_on_file_registers', 'true', (r.status in ('in','pool'))::text);
  perform set_config('role', 'postgres', true);
  delete from public.registrations where player_id = MARIA_P and clinic_id = FAR;

  -- Tara placing someone by hand is never blocked by the card rule.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.place_player(FAR, ROB_P, 'in');
  insert into _probe_result values ('admin_placement_needs_no_card', 'in', r.status::text);
  perform set_config('role', 'postgres', true);
  delete from public.registrations where player_id = ROB_P and clinic_id = FAR;

  -- --------------------------------------- a clinic that has already ended
  -- Maria came (card), Ken came (no card), Rob no-show (card), Dana late
  -- cancel without courtesy (card).
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Done', 'coed', 'Clinic', 'probe', now() - interval '3 hours', now() - interval '2 hours',
          now() - interval '5 days', now() - interval '4 days', 8, 'published', 60)
  returning id into done_c;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (done_c, MARIA_P, 'in', 'self', 1800, true, 60) returning id into reg_m;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (done_c, KEN_P, 'in', 'self', 1800, true, 60) returning id into reg_k;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (done_c, ROB_P, 'in', 'self', 2300, false, 60) returning id into reg_r;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
                                    late_cancel, courtesy_used, canceled_at)
  values (done_c, DANA_P, 'canceled', 'self', 1800, true, 60, true, false, now() - interval '4 hours') returning id into reg_d;
  update public.accounts set stripe_customer_id = 'cus_probe_rob' where id = '44444444-4444-4444-4444-444444444444';
  update public.accounts set stripe_customer_id = 'cus_probe_dana' where id = '66666666-6666-6666-6666-666666666666';

  -- Only Tara marks a no-show, and only on a You're In! row.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_set_no_show(reg_r, true);
    insert into _probe_result values ('player_cannot_mark_no_show', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('player_cannot_mark_no_show', 'not_authorized', sqlerrm);
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  r := public.admin_set_no_show(reg_r, true);
  insert into _probe_result values ('admin_marks_no_show', 'true', r.no_show::text);
  begin
    perform public.admin_set_no_show(reg_d, true);
    insert into _probe_result values ('no_show_only_on_in_rows', 'registration_not_in', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('no_show_only_on_in_rows', 'registration_not_in', sqlerrm);
  end;

  -- Charging: refused while the clinic is still on; then one tap makes the
  -- right rows and skips the right rows.
  perform set_config('role', 'postgres', true);
  update public.clinics set ends_at = now() + interval '1 hour' where id = done_c;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_charge_clinic(done_c);
    insert into _probe_result values ('charge_refused_before_clinic_ends', 'clinic_not_over', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('charge_refused_before_clinic_ends', 'clinic_not_over', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  update public.clinics set ends_at = now() - interval '2 hours' where id = done_c;
  perform set_config('role', 'authenticated', true);
  j := public.admin_charge_clinic(done_c);
  insert into _probe_result values ('one_tap_summary', '{"already": 0, "charged": 3, "no_card": 1, "not_owed": 0}', j::text);
  perform set_config('role', 'postgres', true);
  select kind::text || ' ' || amount_cents || ' ' || status::text into v from public.payments where registration_id = reg_m;
  insert into _probe_result values ('attendee_owes_clinic_fee', 'clinic_fee 1800 pending', v);
  select kind::text || ' ' || amount_cents into v from public.payments where registration_id = reg_r;
  insert into _probe_result values ('no_show_owes_full_fee', 'no_show 2300', v);
  select kind::text || ' ' || amount_cents into v from public.payments where registration_id = reg_d;
  insert into _probe_result values ('late_cancel_without_courtesy_owes_full_fee', 'late_cancel 1800', v);
  select count(*) into n from public.payments where registration_id = reg_k;
  insert into _probe_result values ('no_card_is_skipped_and_counted', '0', n::text);

  -- A second tap changes nothing: the three live rows are reported as already.
  perform set_config('role', 'authenticated', true);
  j := public.admin_charge_clinic(done_c);
  insert into _probe_result values ('second_tap_is_idempotent', '{"already": 3, "charged": 0, "no_card": 1, "not_owed": 0}', j::text);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.payments where registration_id in (reg_m, reg_r, reg_d);
  insert into _probe_result values ('still_one_row_each', '3', n::text);

  -- A courtesy late cancel owes nothing: flip Dana's row and check the tap skips it.
  update public.payments set status = 'canceled' where registration_id = reg_d;
  update public.registrations set courtesy_used = true where id = reg_d;
  perform set_config('role', 'authenticated', true);
  j := public.admin_charge_clinic(done_c);
  insert into _probe_result values ('courtesy_cancel_not_charged', '1', (j->>'not_owed'));
  perform set_config('role', 'postgres', true);

  -- The player cannot run the tap.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_charge_clinic(done_c);
    insert into _probe_result values ('player_cannot_charge_clinic', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('player_cannot_charge_clinic', 'not_authorized', sqlerrm);
  end;

  -- ------------------------------------------- the courtesy window rolls
  perform set_config('role', 'postgres', true);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
                                    late_cancel, courtesy_used, canceled_at)
  values (done_c, KEN_P, 'canceled', 'self', 1800, true, 60, true, true, now() - interval '89 days')
  on conflict do nothing;
  insert into _probe_result values ('courtesy_used_89_days_ago_blocks', 'false', public.courtesy_available(KEN_P)::text);
  update public.registrations set canceled_at = now() - interval '91 days' where player_id = KEN_P and courtesy_used;
  insert into _probe_result values ('courtesy_used_91_days_ago_is_back', 'true', public.courtesy_available(KEN_P)::text);

  -- ------------------------------------------- the note only Tara sees
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  update public.players set level_note = 'coming back from a back injury' where id = MARIA_P;
  select level_note into v from public.players where id = MARIA_P;
  insert into _probe_result values ('player_writes_own_level_note', 'coming back from a back injury', v);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select count(*) into n from public.players where id = MARIA_P and level_note is not null;
  insert into _probe_result values ('another_player_cannot_read_the_note', '0', n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select level_note into v from public.players where id = MARIA_P;
  insert into _probe_result values ('tara_reads_the_note', 'coming back from a back injury', v);
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------------- grants
  insert into _probe_result values ('anon_cannot_charge_clinic', 'false',
    has_function_privilege('anon', 'public.admin_charge_clinic(uuid)', 'EXECUTE')::text);
  insert into _probe_result values ('anon_cannot_mark_no_show', 'false',
    has_function_privilege('anon', 'public.admin_set_no_show(uuid, boolean)', 'EXECUTE')::text);
  insert into _probe_result values ('courtesy_helper_is_internal', 'false',
    has_function_privilege('authenticated', 'public.courtesy_available(uuid)', 'EXECUTE')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
