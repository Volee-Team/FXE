-- payments_foundation.sql
--
-- Covers 20260912000001 (decision 0009) and ATTACKS it. Money is the one
-- place a bug is not a bug but a loss, so the checks that matter are: nobody
-- charges anyone while payments are off; a player cannot write the ledger or
-- forge a card; a double tap is one fee; and the ledger, not a checkbox, is
-- what marks a registration paid.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  CLINIC  constant uuid := 'd0000000-0000-0000-0000-000000000002';
  reg_m uuid; reg_r uuid; pay uuid; ref uuid; n int; v text; paid boolean;
begin
  -- Fixtures (as postgres): two registrations with price snapshots.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (CLINIC, MARIA_P, 'in', 'admin', 2200, true, 90) returning id into reg_m;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (CLINIC, ROB_P, 'in', 'admin', 2800, false, 90) returning id into reg_r;

  -- ------------------------------------------------ payments are OFF
  select value into v from public.app_settings where key = 'payments_enabled';
  insert into _probe_result values ('payments_disabled_by_default', 'false', v);

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_charge_registration(reg_m, 'clinic_fee');
    insert into _probe_result values ('nothing_charges_while_disabled', 'payments_disabled', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('nothing_charges_while_disabled', 'payments_disabled', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------ switch on, no card
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_charge_registration(reg_m, 'clinic_fee');
    insert into _probe_result values ('no_card_on_file_rejected', 'no_card_on_file', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('no_card_on_file_rejected', 'no_card_on_file', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- The webhook (service role) is what records a card. Simulate it.
  update public.accounts set stripe_customer_id = 'cus_test_maria', card_brand = 'visa', card_last4 = '4242', card_added_at = now() where id = MARIA;

  -- ------------------------------------------------ Tara charges
  perform set_config('role', 'authenticated', true);
  select id into pay from public.admin_charge_registration(reg_m, 'clinic_fee');
  perform set_config('role', 'postgres', true);
  select amount_cents::text || ' ' || status::text || ' ' || kind::text into v from public.payments where id = pay;
  insert into _probe_result values ('charge_row_uses_price_snapshot', '2200 pending clinic_fee', v);

  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_charge_registration(reg_m, 'clinic_fee');
    insert into _probe_result values ('double_tap_is_one_fee', 'already_charged', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('double_tap_is_one_fee', 'already_charged', sqlerrm);
  end;
  -- A late-cancel fee with an explicit amount is a separate kind, allowed.
  perform public.admin_charge_registration(reg_m, 'late_cancel', 1000);
  begin
    perform public.admin_charge_registration(reg_m, 'refund');
    insert into _probe_result values ('refund_kind_not_via_charge', '22023', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('refund_kind_not_via_charge', '22023', sqlstate);
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.payments where registration_id = reg_m;
  insert into _probe_result values ('two_rows_for_maria', '2', n::text);

  -- Pending is not paid. The ledger drives the checkbox only on success.
  select r.paid into paid from public.registrations r where r.id = reg_m;
  insert into _probe_result values ('pending_charge_does_not_mark_paid', 'false', paid::text);
  update public.payments set status = 'succeeded', stripe_payment_intent_id = 'pi_test_1' where id = pay;
  select r.paid into paid from public.registrations r where r.id = reg_m;
  insert into _probe_result values ('succeeded_fee_marks_paid', 'true', paid::text);

  -- ------------------------------------------------ refund
  perform set_config('role', 'authenticated', true);
  select id into ref from public.admin_refund_payment(pay);
  begin
    perform public.admin_refund_payment(pay);
    insert into _probe_result values ('second_refund_rejected', 'already_refunded', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('second_refund_rejected', 'already_refunded', sqlerrm);
  end;
  begin
    perform public.admin_refund_payment(ref);
    insert into _probe_result values ('cannot_refund_a_refund', 'not_refundable', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('cannot_refund_a_refund', 'not_refundable', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  update public.payments set status = 'succeeded', stripe_refund_id = 're_test_1' where id = ref;
  select r.paid into paid from public.registrations r where r.id = reg_m;
  insert into _probe_result values ('succeeded_refund_unmarks_paid', 'false', paid::text);

  -- ------------------------------------------------ ATTACK: Maria
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.payments;
  insert into _probe_result values ('player_sees_only_own_ledger', '3', n::text);   -- fee, late, refund; none of Rob's
  begin
    execute 'update public.payments set status = $1::public.payment_status where id = $2' using 'canceled', pay;
    insert into _probe_result values ('player_cannot_write_ledger', 'denied', 'UPDATED');
  exception when insufficient_privilege then
    insert into _probe_result values ('player_cannot_write_ledger', 'denied', 'denied');
  end;
  begin
    execute 'insert into public.payments (registration_id, account_id, kind, amount_cents) values ($1, $2, $3::public.payment_kind, 1)' using reg_m, MARIA, 'refund';
    insert into _probe_result values ('player_cannot_insert_ledger', 'denied', 'INSERTED');
  exception when others then
    insert into _probe_result values ('player_cannot_insert_ledger', 'denied', 'denied');
  end;
  begin
    execute 'update public.accounts set stripe_customer_id = $1 where id = $2' using 'cus_forged', MARIA;
    insert into _probe_result values ('player_cannot_forge_card', 'denied', 'UPDATED');
  exception when insufficient_privilege then
    insert into _probe_result values ('player_cannot_forge_card', 'denied', 'denied');
  end;
  begin
    perform public.admin_charge_registration(reg_r, 'clinic_fee');
    insert into _probe_result values ('player_cannot_charge_anyone', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('player_cannot_charge_anyone', 'blocked', 'blocked');
  end;

  -- ------------------------------------------------ ATTACK: Rob sees nothing of Maria's
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  select count(*) into n from public.payments;
  insert into _probe_result values ('other_player_sees_zero_rows', '0', n::text);

  -- ------------------------------------------------ anon
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'anon', true);
  begin
    execute 'select count(*) from public.payments' into n;
    insert into _probe_result values ('anon_cannot_read_ledger', 'denied', 'READ');
  exception when insufficient_privilege then
    insert into _probe_result values ('anon_cannot_read_ledger', 'denied', 'denied');
  end;
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------ grants / hygiene
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
    and p.proname in ('admin_charge_registration', 'admin_refund_payment', 'payments_enabled')
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('anon_has_no_execute', '0', n::text);
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
    and p.proname in ('admin_charge_registration', 'admin_refund_payment', 'payments_enabled', 'payments_sync_registration_paid')
    and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  insert into _probe_result values ('search_path_pinned', '4', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
