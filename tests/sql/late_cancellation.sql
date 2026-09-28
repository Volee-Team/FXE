-- late_cancellation.sql
--
-- Decision 0010 (Tara, 2026-09-12) as amended by 0012 (2026-09-16) and 0013
-- (2026-09-21): inside 3 hours the cancel goes through, it is late, the full
-- fee applies every time ("NOT DOING THIS ANYMORE" about the courtesy), and
-- the note is optional.
-- The rule lives in cancel_registration, so this probe drives it from the
-- roles the app uses and reads back what Tara's roster will see.
--
-- 2026-09-27 (20260927100002): Tara can record a late cancellation for
-- someone who texted her (admin_mark_late_cancel: You're In! to Canceled,
-- late, by her, inside the cutoff or later, not once charged, tells nobody),
-- while her plain Remove stays free and silent; and her removal no longer
-- reaches the admins as if the player had canceled. Checks 13 to 15.
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
  FAR     constant uuid := 'd0000000-0000-0000-0000-000000000002';
  soon uuid; soon2 uuid; reg_soon uuid; reg_soon2 uuid; reg_pool uuid; reg_far uuid; reg_admin uuid; pay uuid;
  reg_text uuid; reg_early uuid; reg_waiting uuid; j jsonb;
  charged_c uuid; rained_c uuid; reg_charged uuid; reg_rained uuid;
  n int; v text; r public.registrations;
begin
  -- ------------------------------------------------------------ fixtures
  -- A clinic two hours out (inside the cutoff) and the seed clinic, days out.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Soon', 'ladies', 'Clinic', 'probe', now() + interval '2 hours', now() + interval '3 hours',
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into soon;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Soon 2', 'ladies', 'Clinic', 'probe', now() + interval '2 hours 30 minutes', now() + interval '3 hours 30 minutes',
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into soon2;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (soon, MARIA_P, 'in', 'self', 1800, true, 60) returning id into reg_soon;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (soon, KEN_P, 'pool', 'self', 1800, true, 60) returning id into reg_pool;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (FAR, MARIA_P, 'in', 'self', 2200, true, 90) returning id into reg_far;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (soon, ROB_P, 'in', 'admin', 2300, false, 60) returning id into reg_admin;
  -- For Tara's late cancel (checks 13 to 15): Dana in the soon clinic (she
  -- texts Tara), Ken days out in the far one, Priya waiting in the Pool.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (soon, DANA_P, 'in', 'self', 1800, true, 60) returning id into reg_text;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (FAR, KEN_P, 'in', 'self', 2200, true, 90) returning id into reg_early;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (soon, PRIYA_P, 'pool', 'self', 2300, false, 60) returning id into reg_waiting;

  -- 1. The setting is Tara's number, and the helper reads it.
  select value into v from public.app_settings where key = 'cancel_cutoff_hours';
  insert into _probe_result values ('cutoff_setting_is_3', '3', v);
  insert into _probe_result values ('cutoff_helper_reads_setting', '3', public.cancel_cutoff_hours()::text);
  select value into v from public.app_settings where key = 'courtesy_cancel_days';
  insert into _probe_result values ('courtesy_window_is_zero', '0', v);

  -- 2. Exactly one cancel_registration exists. Two overloads would make the
  --    app's one-argument call ambiguous.
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'cancel_registration';
  insert into _probe_result values ('one_cancel_registration_signature', '1', n::text);

  -- ------------------------------------------------------------ as Maria
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);

  -- 3. Days out: no note needed, and the row is not late.
  r := public.cancel_registration(reg_far);
  insert into _probe_result values ('far_cancel_needs_no_note', 'canceled false', r.status::text || ' ' || r.late_cancel::text);

  -- 4. Inside 3 hours, You're In!, no note (decision 0013): the cancel goes
  --    through, it is late, and no courtesy exists. The fee applies.
  insert into _probe_result values ('no_courtesy_before_any_cancel', 'false', public.my_courtesy_available(MARIA_P)::text);
  r := public.cancel_registration(reg_soon);
  insert into _probe_result values ('late_cancel_without_note_goes_through', 'canceled true false',
    r.status::text || ' ' || r.late_cancel::text || ' ' || r.courtesy_used::text);
  insert into _probe_result values ('no_note_stored_when_none_sent', 'true', (r.cancel_note is null)::text);

  -- 5. A second late cancel: the fee applies again, and the optional note
  --    is kept trimmed.
  perform set_config('role', 'postgres', true);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (soon2, MARIA_P, 'in', 'self', 1800, true, 60) returning id into reg_soon2;
  perform set_config('role', 'authenticated', true);
  r := public.cancel_registration(reg_soon2, '  Kid has a fever.  ');
  insert into _probe_result values ('second_late_cancel_owes_fee_note_kept', 'canceled true false Kid has a fever.',
    r.status::text || ' ' || r.late_cancel::text || ' ' || r.courtesy_used::text || ' ' || r.cancel_note);

  -- 6. Maria sees late_cancel through her own view.
  select late_cancel::text into v from public.my_registrations where id = reg_soon;
  insert into _probe_result values ('player_view_shows_late', 'true', v);
  perform set_config('role', 'postgres', true);

  -- 7. Tara got the note in her notification, in the player's words.
  select count(*) into n from public.notifications
   where account_id = TARA and type = 'player_canceled' and entity_id = reg_soon2
     and body like '%Late, fee applies.%Note: "Kid has a fever."%';
  insert into _probe_result values ('admin_notified_with_note', '1', n::text);
  select count(*) into n from public.notifications
   where account_id = TARA and type = 'player_canceled' and entity_id = reg_soon
     and body like '%Late, fee applies.%' and body not like '%courtesy%';
  insert into _probe_result values ('admin_notified_fee_no_courtesy_wording', '1', n::text);

  -- ------------------------------------------------------------ as Ken (pool)
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  -- 8. Pool inside 3 hours holds no spot: free, no note, not late.
  r := public.cancel_registration(reg_pool);
  insert into _probe_result values ('pool_dropout_is_not_late', 'canceled false', r.status::text || ' ' || r.late_cancel::text);
  perform set_config('role', 'postgres', true);

  -- 8b. leave_pool archives too (backlog 2026-09-12, fixed 2026-09-21): the
  --     row survives as canceled with a stamp, and a second leave is refused.
  perform set_config('role', 'postgres', true);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (soon2, KEN_P, 'pool', 'self', 1800, true, 60) returning id into reg_pool;
  perform set_config('role', 'authenticated', true);
  perform public.leave_pool(reg_pool);
  perform set_config('role', 'postgres', true);
  select status::text || ' ' || (canceled_at is not null)::text || ' ' || late_cancel::text into v from public.registrations where id = reg_pool;
  insert into _probe_result values ('leave_pool_keeps_the_row_as_canceled', 'canceled true false', coalesce(v, 'ROW GONE'));
  perform set_config('role', 'authenticated', true);
  begin
    perform public.leave_pool(reg_pool);
    insert into _probe_result values ('leave_pool_twice_refused', 'not_in_pool', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('leave_pool_twice_refused', 'not_in_pool', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------------ as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  -- 9. Tara removing someone inside 3 hours is not the player's late cancel.
  r := public.cancel_registration(reg_admin);
  insert into _probe_result values ('admin_removal_is_not_late', 'canceled false', r.status::text || ' ' || r.late_cancel::text || coalesce(' ' || r.cancel_note, ''));

  -- 10. Her roster view carries the note and whether a card exists.
  select late_cancel::text || ' ' || cancel_note || ' ' || has_card::text || ' ' || courtesy_used::text into v
    from public.registrations_admin where id = reg_soon2;
  insert into _probe_result values ('roster_shows_note_and_no_card', 'true Kid has a fever. false false', v);
  select courtesy_used::text into v from public.registrations_admin where id = reg_soon;
  insert into _probe_result values ('roster_shows_no_courtesy', 'false', v);
  perform set_config('role', 'postgres', true);

  -- 11. Nothing was charged by the app on its own.
  select count(*) into n from public.payments where registration_id in (reg_soon, reg_soon2);
  insert into _probe_result values ('nothing_charged_automatically', '0', n::text);

  -- 12. Charging is her tap: with payments on and a card, the late-cancel
  --     row is created pending at the price snapshot, by her, not by the cancel.
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  -- Whoever switches payments on records when (20260927300001); the switch
  -- happened yesterday, so the clinics below all end after it.
  insert into public.app_settings (key, value) values ('payments_enabled_at', (now() - interval '1 day')::text)
    on conflict (key) do update set value = excluded.value;
  update public.accounts set stripe_customer_id = 'cus_probe_maria', card_brand = 'visa', card_last4 = '4242' where id = MARIA;
  perform set_config('role', 'authenticated', true);
  select has_card::text into v from public.registrations_admin where id = reg_soon2;
  insert into _probe_result values ('roster_shows_card_once_added', 'true', v);
  select id into pay from public.admin_charge_registration(reg_soon2, 'late_cancel');
  perform set_config('role', 'postgres', true);
  select kind::text || ' ' || amount_cents || ' ' || status::text into v from public.payments where id = pay;
  insert into _probe_result values ('late_charge_is_taras_tap', 'late_cancel 1800 pending', v);
  perform set_config('role', 'authenticated', true);
  select charge_status into v from public.registrations_admin where id = reg_soon2;
  insert into _probe_result values ('roster_shows_charge_status', 'pending', v);
  perform set_config('role', 'postgres', true);

  -- 13. Tara records a late cancellation for Dana, who texted her two hours
  --     before (inside the 3-hour cutoff): canceled, late, by Tara, no
  --     courtesy (switched off), her note kept trimmed.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.admin_mark_late_cancel(reg_text, '  Texted at 2pm, sick.  ');
  insert into _probe_result values ('tara_records_late_cancel', 'canceled true false tara Texted at 2pm, sick.',
    r.status::text || ' ' || r.late_cancel::text || ' ' || r.courtesy_used::text || ' '
    || case when r.canceled_by = TARA then 'tara' else coalesce(r.canceled_by::text, 'nobody') end
    || ' ' || coalesce(r.cancel_note, 'NO NOTE'));
  -- Her roster reads it the way it reads a player's own late cancel.
  select status::text || ' ' || late_cancel::text || ' ' || coalesce(cancel_note, 'NO NOTE') into v
    from public.registrations_admin where id = reg_text;
  insert into _probe_result values ('roster_shows_taras_late_cancel', 'canceled true Texted at 2pm, sick.', v);
  -- Twice is refused: the row is no longer You're In!.
  begin
    perform public.admin_mark_late_cancel(reg_text);
    insert into _probe_result values ('late_cancel_twice_refused', 'registration_not_in', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('late_cancel_twice_refused', 'registration_not_in', sqlerrm);
  end;
  -- Days out is not late: refused (Remove is the tool before the cutoff).
  begin
    perform public.admin_mark_late_cancel(reg_early);
    insert into _probe_result values ('late_cancel_before_cutoff_refused', 'not_late_yet', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('late_cancel_before_cutoff_refused', 'not_late_yet', sqlerrm);
  end;
  -- A Player Pool entry holds no spot, so it cannot be a late cancel.
  begin
    perform public.admin_mark_late_cancel(reg_waiting);
    insert into _probe_result values ('late_cancel_on_pool_refused', 'registration_not_in', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('late_cancel_on_pool_refused', 'registration_not_in', sqlerrm);
  end;
  -- A member cannot record one for anyone.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.admin_mark_late_cancel(reg_early);
    insert into _probe_result values ('member_cannot_mark_late_cancel', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_mark_late_cancel', 'not_authorized', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  -- The refusals changed nothing (asserted as state, not as an error).
  select (select status::text from public.registrations where id = reg_early) || ' '
      || (select status::text from public.registrations where id = reg_waiting) into v;
  insert into _probe_result values ('refused_late_cancels_change_nothing', 'in pool', v);

  -- 14. After the clinic, one tap charges Tara's late cancel as a late cancel
  --     at Dana's price, and her plain Remove of Rob (check 9) as nothing.
  --     In the soon clinic: Maria's own late cancel and Dana's are owed
  --     (both have a card now); Ken's pool drop-out, Rob's removal and
  --     Priya's Pool entry owe nothing.
  update public.accounts set stripe_customer_id = 'cus_probe_dana', card_brand = 'visa', card_last4 = '4242' where id = DANA;
  update public.clinics set starts_at = now() - interval '1 hour', ends_at = now() - interval '1 minute' where id = soon;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  j := public.admin_charge_clinic(soon);
  insert into _probe_result values ('soon_clinic_tap_summary', '{"already": 0, "charged": 2, "no_card": 0, "not_owed": 3}', j::text);
  perform set_config('role', 'postgres', true);
  select string_agg(kind::text || ' ' || amount_cents, ',') into v from public.payments where registration_id = reg_text;
  insert into _probe_result values ('taras_late_cancel_is_charged_as_late', 'late_cancel 1800', coalesce(v, 'NOT CHARGED'));
  select count(*) into n from public.payments where registration_id = reg_admin;
  insert into _probe_result values ('plain_remove_records_no_fee', '0', n::text);

  -- 15. Who was told, per registration, as account:type (hard rule 9: the
  --     rows themselves, not the absence of an error). A player's own cancel
  --     reaches every admin. Tara's Remove and her late cancel reach nobody:
  --     not Tara, as if the player had done it (the echo, 20260927100002),
  --     and not the player, whose words for it are Tara's to write.
  select coalesce(string_agg(case x.account_id when TARA then 'tara' when MARIA then 'maria' when ROB then 'rob'
                                               when DANA then 'dana' else 'other' end || ':' || x.type, ','
                             order by x.account_id, x.type), '')
    into v from public.notifications x where x.entity_id = reg_soon;
  insert into _probe_result values ('told_of_marias_own_late_cancel', 'tara:player_canceled', v);
  select coalesce(string_agg(case x.account_id when TARA then 'tara' when MARIA then 'maria' when ROB then 'rob'
                                               when DANA then 'dana' else 'other' end || ':' || x.type, ','
                             order by x.account_id, x.type), '')
    into v from public.notifications x where x.entity_id = reg_soon2;
  insert into _probe_result values ('told_of_marias_second_cancel', 'tara:player_canceled', v);
  select coalesce(string_agg(case x.account_id when TARA then 'tara' when MARIA then 'maria' when ROB then 'rob'
                                               when DANA then 'dana' else 'other' end || ':' || x.type, ','
                             order by x.account_id, x.type), '')
    into v from public.notifications x where x.entity_id = reg_admin;
  insert into _probe_result values ('told_of_taras_removal_of_rob', '', v);
  select coalesce(string_agg(case x.account_id when TARA then 'tara' when MARIA then 'maria' when ROB then 'rob'
                                               when DANA then 'dana' else 'other' end || ':' || x.type, ','
                             order by x.account_id, x.type), '')
    into v from public.notifications x where x.entity_id = reg_text;
  insert into _probe_result values ('told_of_taras_late_cancel_of_dana', '', v);

  -- 17. A charged spot and a canceled clinic (20260927300002, MVP fix round).
  --     Asserted as the resulting STATE, not the error (hard rule 9).
  --     Ken is You're In! an hour out and his clinic fee already went through;
  --     Rob is You're In! an hour out in a clinic Tara canceled (rain).
  --       * Tara's late cancel on Ken: refused, row still 'in', not late, one live fee.
  --       * Tara's late cancel on Rob: refused, row still 'in'.
  --       * Tara's Remove on Ken (cancel_registration as an admin who does not
  --         own him): refused charged_refund_first, row still 'in', one live fee.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Charged', 'coed', 'Clinic', 'probe', now() + interval '1 hour', now() + interval '2 hours',
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into charged_c;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Rained', 'coed', 'Clinic', 'probe', now() + interval '1 hour', now() + interval '2 hours',
          now() - interval '3 days', now() - interval '2 days', 8, 'canceled', 60)
  returning id into rained_c;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (charged_c, KEN_P, 'in', 'self', 1800, true, 60) returning id into reg_charged;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (rained_c, ROB_P, 'in', 'self', 2300, false, 60) returning id into reg_rained;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, stripe_payment_intent_id)
  values (reg_charged, KEN, 'clinic_fee', 1800, 'succeeded', true, 'pi_probe_late_charged');

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_mark_late_cancel(reg_charged, 'texted');
  exception when others then null;
  end;
  begin
    perform public.admin_mark_late_cancel(reg_rained, 'texted');
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select r2.status::text || ' ' || r2.late_cancel::text || ' '
         || (select count(*) from public.payments x where x.registration_id = reg_charged
              and x.kind <> 'refund' and x.status in ('pending', 'processing', 'succeeded'))
    into v from public.registrations r2 where r2.id = reg_charged;
  insert into _probe_result values ('late_cancel_on_charged_row_changes_nothing', 'in false 1', v);
  select status::text into v from public.registrations where id = reg_rained;
  insert into _probe_result values ('late_cancel_on_canceled_clinic_changes_nothing', 'in', v);

  perform set_config('role', 'authenticated', true);
  begin
    perform public.cancel_registration(reg_charged);
    insert into _probe_result values ('admin_remove_of_charged_row_refused', 'charged_refund_first', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('admin_remove_of_charged_row_refused', 'charged_refund_first', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  select r2.status::text || ' ' || r2.late_cancel::text || ' '
         || (select count(*) from public.payments x where x.registration_id = reg_charged
              and x.kind <> 'refund' and x.status in ('pending', 'processing', 'succeeded'))
    into v from public.registrations r2 where r2.id = reg_charged;
  insert into _probe_result values ('admin_remove_of_charged_row_changes_nothing', 'in false 1', v);

  -- 16. Grants: anon cannot cancel anything; PUBLIC holds nothing.
  insert into _probe_result values ('anon_cannot_execute_cancel', 'false',
    has_function_privilege('anon', 'public.cancel_registration(uuid, text)', 'EXECUTE')::text);
  insert into _probe_result values ('anon_cannot_execute_cutoff', 'false',
    has_function_privilege('anon', 'public.cancel_cutoff_hours()', 'EXECUTE')::text);
  insert into _probe_result values ('anon_cannot_mark_late_cancel', 'false',
    has_function_privilege('anon', 'public.admin_mark_late_cancel(uuid, text)', 'EXECUTE')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
