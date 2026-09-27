-- card_consent.sql
--
-- Decision 0015 §5 and §7. Kat and Tara's "Final Updates", 2026-09-26:
--   "Ensure no user can register for a clinic without a card on file."
--   "Need to add a check box that says I give permission for my card to be
--    charged and if deselected it does not let them proceed. Consent needs to
--    be saved & stored for as long as the account is active and if they
--    cancel their account - stored for another 90 days."
--
-- Expected values are those sentences. The card attacks come first because
-- they are the ones a screen cannot enforce: a player with a Stripe customer
-- id but no saved card (what opening the card sheet and closing it leaves)
-- must not register, must not read as "has card" on Tara's roster, and must
-- not be chargeable. All three passed that player before 20260926000001.
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
  cl uuid; reg uuid; v text; n int; t timestamptz;
begin
  -- ------------------------------------------------------ the words
  insert into _probe_result values ('consent_words_are_theirs',
    'I give permission for my card to be charged', public.card_consent_text());

  -- -------------------------------------- card on file, payments on
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  update public.app_settings set value = 'true' where key = 'card_required';
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Card Clinic', 'ladies', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into cl;
  -- Maria opened the card sheet and closed it: a customer, no card.
  update public.accounts set stripe_customer_id = 'cus_probe_no_card', card_last4 = null, card_brand = null
   where id = MARIA;

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(cl, MARIA_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('customer_without_card_cannot_register', 'card_required', v);
  perform set_config('role', 'postgres', true);

  -- Tara places her by hand (capacity and paperwork never block Tara), so
  -- the roster and the charge can be asked about the same player.
  -- (If the attack above got through, her row already exists; reuse it so
  -- the probe reports every failure instead of aborting on the first.)
  select id into reg from public.registrations
   where clinic_id = cl and player_id = MARIA_P and status in ('in', 'pool', 'response_needed');
  if reg is null then
    insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
    values (cl, MARIA_P, 'in', 'admin', 1800, true, 60) returning id into reg;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select has_card::text into v from public.registrations_admin where id = reg;
  insert into _probe_result values ('roster_says_no_card_for_customer_only', 'false', v);
  begin
    perform public.admin_charge_registration(reg, 'clinic_fee'); v := 'charged';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('customer_without_card_cannot_be_charged', 'no_card_on_file', v);
  perform set_config('role', 'postgres', true);

  -- The webhook records a saved card: now all three agree she has one.
  update public.accounts set card_brand = 'visa', card_last4 = '4242', card_added_at = now() where id = MARIA;
  perform set_config('role', 'authenticated', true);
  select has_card::text into v from public.registrations_admin where id = reg;
  insert into _probe_result values ('roster_says_card_once_saved', 'true', v);
  begin
    perform public.admin_charge_registration(reg, 'clinic_fee'); v := 'charged';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('saved_card_can_be_charged', 'charged', v);
  perform set_config('role', 'postgres', true);
  update public.registrations set status = 'canceled', canceled_at = now() where id = reg;
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(cl, MARIA_P); v := 'registered';
  exception when others then v := sqlerrm; end;
  insert into _probe_result values ('saved_card_can_register', 'registered', v);

  -- ------------------------------------------------ consent, as Maria
  insert into _probe_result values ('no_consent_before_the_box', 'false', public.my_card_consent()::text);
  t := public.record_card_consent('Version 0.1.0 (1)');
  insert into _probe_result values ('consent_recorded_returns_time', 'true', (t is not null)::text);
  insert into _probe_result values ('consent_now_on_file', 'true', public.my_card_consent()::text);
  -- Ticking twice records once: a retry returns the first record's time.
  insert into _probe_result values ('second_tick_returns_first_record', 'true',
    (public.record_card_consent('Version 0.1.0 (2)') = t)::text);
  perform set_config('role', 'postgres', true);
  select k.consent_text || ' | ' || k.version || ' | ' || k.app_version into v
    from public.card_consents k where k.account_id = MARIA;
  insert into _probe_result values ('stored_with_words_version_and_build',
    'I give permission for my card to be charged | 2026-09-26 | Version 0.1.0 (1)', v);

  -- The words change: consent to old words is not consent to new ones.
  update public.app_settings set value = 'I give permission for my card to be charged after each clinic'
   where key = 'card_consent_text';
  perform set_config('role', 'authenticated', true);
  insert into _probe_result values ('new_words_ask_again', 'false', public.my_card_consent()::text);
  perform set_config('role', 'postgres', true);
  update public.app_settings set value = 'I give permission for my card to be charged'
   where key = 'card_consent_text';

  -- ------------------------------------------------- nobody reads it raw
  insert into _probe_result values ('player_cannot_select_consents', 'false',
    has_table_privilege('authenticated', 'public.card_consents', 'SELECT')::text);
  insert into _probe_result values ('player_cannot_insert_consents', 'false',
    has_table_privilege('authenticated', 'public.card_consents', 'INSERT')::text);
  insert into _probe_result values ('player_cannot_delete_consents', 'false',
    has_table_privilege('authenticated', 'public.card_consents', 'DELETE')::text);
  insert into _probe_result values ('anon_cannot_record_consent', 'false',
    has_function_privilege('anon', 'public.record_card_consent(text)', 'EXECUTE')::text);
  insert into _probe_result values ('player_cannot_run_the_purge', 'false',
    has_function_privilege('authenticated', 'public.purge_expired_card_consents()', 'EXECUTE')::text);
  insert into _probe_result values ('anon_cannot_run_the_purge', 'false',
    has_function_privilege('anon', 'public.purge_expired_card_consents()', 'EXECUTE')::text);

  -- -------------------------- "stored for another 90 days" after deletion
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.record_card_consent('Version 0.1.0 (1)');
  perform public.delete_my_account();
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.card_consents where account_id = KEN;
  insert into _probe_result values ('deleting_the_account_keeps_the_consent', '1', n::text);
  -- A hard delete (the dashboard's Delete user cascades auth.users ->
  -- accounts) must not take the consent early: RESTRICT refuses it.
  begin
    delete from public.accounts where id = KEN;
  exception when others then null; end;
  select count(*) into n from public.card_consents where account_id = KEN;
  insert into _probe_result values ('hard_delete_cannot_take_the_consent', '1', n::text);

  update public.accounts set deleted_at = now() - interval '89 days' where id = KEN;
  n := public.purge_expired_card_consents();
  insert into _probe_result values ('day_89_purges_nothing', '0', n::text);
  update public.accounts set deleted_at = now() - interval '91 days' where id = KEN;
  n := public.purge_expired_card_consents();
  insert into _probe_result values ('day_91_purges_kens', '1', n::text);
  select count(*) into n from public.card_consents where account_id = KEN;
  insert into _probe_result values ('kens_consent_gone_after_90_days', '0', n::text);
  select count(*) into n from public.card_consents where account_id = MARIA;
  insert into _probe_result values ('active_account_consent_kept', '1', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
