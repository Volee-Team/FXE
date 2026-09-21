-- late_cancellation.sql
--
-- Decision 0010 (Tara, 2026-09-12) as amended by 0012 (2026-09-16) and 0013
-- (2026-09-21): inside 3 hours the cancel goes through, it is late, the full
-- fee applies every time ("NOT DOING THIS ANYMORE" about the courtesy), and
-- the note is optional.
-- The rule lives in cancel_registration, so this probe drives it from the
-- roles the app uses and reads back what Tara's roster will see.
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
  FAR     constant uuid := 'd0000000-0000-0000-0000-000000000002';
  soon uuid; soon2 uuid; reg_soon uuid; reg_soon2 uuid; reg_pool uuid; reg_far uuid; reg_admin uuid; pay uuid;
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
  update public.accounts set stripe_customer_id = 'cus_probe_maria' where id = MARIA;
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

  -- 13. Grants: anon cannot cancel anything; PUBLIC holds nothing.
  insert into _probe_result values ('anon_cannot_execute_cancel', 'false',
    has_function_privilege('anon', 'public.cancel_registration(uuid, text)', 'EXECUTE')::text);
  insert into _probe_result values ('anon_cannot_execute_cutoff', 'false',
    has_function_privilege('anon', 'public.cancel_cutoff_hours()', 'EXECUTE')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
