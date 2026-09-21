-- account_deletion.sql
--
-- Decision 0013 §5, Tara: "Keep their history." App Store guideline 5.1.1(v)
-- requires in-app account deletion. delete_my_account() scrubs the person
-- and keeps the record; the sign-in is removed by the delete-account edge
-- function through Supabase's admin API, which no probe can reach, so the
-- boundary tested here is the database half.
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
  FAR     constant uuid := 'd0000000-0000-0000-0000-000000000002';
  reg uuid; old_reg uuid; DONE_C uuid; pay uuid; got uuid; n int; v text;
  regs_before int; pays_before int; notes_before int;
begin
  -- Fixtures: Maria holds a live spot, has a past registration (a clinic that
  -- ended last week) with a payment, a private note from Tara, a device and
  -- notifications.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Past', 'ladies', 'Clinic', 'probe', now() - interval '7 days', now() - interval '7 days' + interval '1 hour',
          now() - interval '10 days', now() - interval '9 days', 8, 'published', 60)
  returning id into DONE_C;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (FAR, MARIA_P, 'in', 'self', 1800, true, 60) returning id into reg;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, paid)
  values (DONE_C, MARIA_P, 'in', 'self', 1800, true, 60, true) returning id into old_reg;
  insert into public.payments (account_id, registration_id, kind, amount_cents, status, requested_by)
  values (MARIA, old_reg, 'clinic_fee', 1800, 'succeeded', TARA) returning id into pay;
  insert into public.devices (account_id, apns_token, platform) values (MARIA, 'probe-token-maria', 'ios');
  update public.accounts set card_brand = 'visa', card_last4 = '4242', card_added_at = now(), stripe_customer_id = 'cus_probe_maria' where id = MARIA;
  select count(*) into regs_before from public.registrations r join public.players p on p.id = r.player_id where p.account_id = MARIA;
  select count(*) into pays_before from public.payments where account_id = MARIA;
  select count(*) into notes_before from public.player_notes where player_id = MARIA_P;

  -- 1. Tara cannot delete herself from the app.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    got := public.delete_my_account();
    insert into _probe_result values ('admin_cannot_delete_self', 'admin_cannot_delete', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('admin_cannot_delete_self', 'admin_cannot_delete', sqlerrm);
  end;

  -- 2. Ken deleting his account does not touch Maria's.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  got := public.delete_my_account();
  insert into _probe_result values ('returns_own_id', KEN::text, got::text);
  perform set_config('role', 'postgres', true);
  select first_name into v from public.accounts where id = MARIA;
  insert into _probe_result values ('other_accounts_untouched', 'Maria', v);

  -- 3. Maria deletes: the person is gone, the record stays.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  got := public.delete_my_account();
  perform set_config('role', 'postgres', true);

  select first_name || ' ' || last_name || ' ' || email || ' ' || coalesce(phone, 'nophone') || ' '
         || coalesce(card_brand, 'nocard') || ' ' || coalesce(card_last4, '----') || ' ' || (deleted_at is not null)::text
    into v from public.accounts where id = MARIA;
  insert into _probe_result values ('account_scrubbed', 'Deleted Account deleted-' || MARIA || '@deleted.invalid nophone nocard ---- true', v);
  select first_name || ' ' || last_name || ' ' || coalesce(level_note, 'nonote') || ' ' || is_active::text || ' ' || coalesce(date_of_birth::text, 'nodob')
    into v from public.players where id = MARIA_P;
  insert into _probe_result values ('player_scrubbed_and_inactive', 'Deleted Player nonote false nodob', v);

  select count(*) into n from public.registrations r join public.players p on p.id = r.player_id where p.account_id = MARIA;
  insert into _probe_result values ('registrations_kept', regs_before::text, n::text);
  select count(*) into n from public.payments where account_id = MARIA;
  insert into _probe_result values ('ledger_kept', pays_before::text, n::text);
  select count(*) into n from public.player_notes where player_id = MARIA_P;
  insert into _probe_result values ('taras_note_kept', notes_before::text, n::text);
  select status::text into v from public.registrations where id = old_reg;
  insert into _probe_result values ('past_registration_untouched', 'in', v);
  select status::text || ' ' || (canceled_at is not null)::text into v from public.registrations where id = reg;
  insert into _probe_result values ('live_spot_given_back_as_canceled', 'canceled true', v);
  select count(*) into n from public.devices where account_id = MARIA;
  insert into _probe_result values ('push_tokens_removed', '0', n::text);
  select count(*) into n from public.notifications where account_id = MARIA;
  insert into _probe_result values ('notifications_removed', '0', n::text);
  select stripe_customer_id into v from public.accounts where id = MARIA;
  insert into _probe_result values ('stripe_customer_kept_for_ledger', 'cus_probe_maria', v);

  -- 4. Money still adds up: the past registration's revenue is unchanged
  --    (the view answers only an admin, so read it as Tara).
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select collected_cents::text into v from public.revenue_by_clinic where clinic_id = DONE_C;
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  insert into _probe_result values ('revenue_unchanged_after_delete', '1800', coalesce(v, 'no row'));

  -- 5. Idempotent: a second call answers the same and changes nothing more.
  perform set_config('role', 'authenticated', true);
  got := public.delete_my_account();
  insert into _probe_result values ('second_delete_is_harmless', MARIA::text, got::text);
  perform set_config('role', 'postgres', true);

  -- 6. A deleted admin row could never be an admin (is_admin reads deleted_at).
  --    The role column is guarded by a trigger even for postgres, so the
  --    simulation stamps deleted_at on Tara's own row and reads is_admin as her.
  update public.accounts set deleted_at = now() where id = TARA;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  insert into _probe_result values ('deleted_account_is_never_admin', 'false', public.is_admin()::text);
  perform set_config('role', 'postgres', true);
  update public.accounts set deleted_at = null where id = TARA;

  -- 7. Grants: signed-in only, never anon.
  insert into _probe_result values ('anon_cannot_call', 'false',
    has_function_privilege('anon', 'public.delete_my_account()', 'EXECUTE')::text);
  insert into _probe_result values ('authenticated_can_call', 'true',
    has_function_privilege('authenticated', 'public.delete_my_account()', 'EXECUTE')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
