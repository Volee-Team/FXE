-- late_cancellation.sql
--
-- Decision 0010 (Tara, 2026-09-12): "before 4 hours anything can be
-- cancelled but after that you have to say it's an emergency to cancel."
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
  soon uuid; reg_soon uuid; reg_pool uuid; reg_far uuid; reg_admin uuid; pay uuid;
  n int; v text; r public.registrations;
begin
  -- ------------------------------------------------------------ fixtures
  -- A clinic two hours out (inside the cutoff) and the seed clinic, days out.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Soon', 'ladies', 'Clinic', 'probe', now() + interval '2 hours', now() + interval '3 hours',
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into soon;
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
  insert into _probe_result values ('cutoff_setting_is_4', '4', v);
  insert into _probe_result values ('cutoff_helper_reads_setting', '4', public.cancel_cutoff_hours()::text);

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

  -- 4. Inside 4 hours, You're In!, no note: refused.
  begin
    perform public.cancel_registration(reg_soon);
    insert into _probe_result values ('late_cancel_without_note_refused', 'late_cancel_needs_note', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('late_cancel_without_note_refused', 'late_cancel_needs_note', sqlerrm);
  end;
  begin
    perform public.cancel_registration(reg_soon, '   ');
    insert into _probe_result values ('blank_note_is_no_note', 'late_cancel_needs_note', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('blank_note_is_no_note', 'late_cancel_needs_note', sqlerrm);
  end;

  -- 5. With a note: canceled, flagged late, note kept trimmed.
  r := public.cancel_registration(reg_soon, '  Kid has a fever.  ');
  insert into _probe_result values ('late_cancel_with_note_goes_through', 'canceled true Kid has a fever.',
    r.status::text || ' ' || r.late_cancel::text || ' ' || r.cancel_note);

  -- 6. Maria sees late_cancel through her own view.
  select late_cancel::text into v from public.my_registrations where id = reg_soon;
  insert into _probe_result values ('player_view_shows_late', 'true', v);
  perform set_config('role', 'postgres', true);

  -- 7. Tara got the note in her notification, in the player's words.
  select count(*) into n from public.notifications
   where account_id = TARA and type = 'player_canceled' and entity_id = reg_soon
     and body like '%Note: "Kid has a fever."%';
  insert into _probe_result values ('admin_notified_with_note', '1', n::text);

  -- ------------------------------------------------------------ as Ken (pool)
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  -- 8. Pool inside 4 hours holds no spot: free, no note, not late.
  r := public.cancel_registration(reg_pool);
  insert into _probe_result values ('pool_dropout_is_not_late', 'canceled false', r.status::text || ' ' || r.late_cancel::text);
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------------ as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  -- 9. Tara removing someone inside 4 hours is not the player's late cancel.
  r := public.cancel_registration(reg_admin);
  insert into _probe_result values ('admin_removal_is_not_late', 'canceled false', r.status::text || ' ' || r.late_cancel::text || coalesce(' ' || r.cancel_note, ''));

  -- 10. Her roster view carries the note and whether a card exists.
  select late_cancel::text || ' ' || cancel_note || ' ' || has_card::text into v
    from public.registrations_admin where id = reg_soon;
  insert into _probe_result values ('roster_shows_note_and_no_card', 'true Kid has a fever. false', v);
  perform set_config('role', 'postgres', true);

  -- 11. Nothing was charged by the app on its own.
  select count(*) into n from public.payments where registration_id = reg_soon;
  insert into _probe_result values ('nothing_charged_automatically', '0', n::text);

  -- 12. Charging is her tap: with payments on and a card, the late-cancel
  --     row is created pending at the price snapshot, by her, not by the cancel.
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  update public.accounts set stripe_customer_id = 'cus_probe_maria' where id = MARIA;
  perform set_config('role', 'authenticated', true);
  select has_card::text into v from public.registrations_admin where id = reg_soon;
  insert into _probe_result values ('roster_shows_card_once_added', 'true', v);
  select id into pay from public.admin_charge_registration(reg_soon, 'late_cancel');
  perform set_config('role', 'postgres', true);
  select kind::text || ' ' || amount_cents || ' ' || status::text into v from public.payments where id = pay;
  insert into _probe_result values ('late_charge_is_taras_tap', 'late_cancel 1800 pending', v);
  perform set_config('role', 'authenticated', true);
  select charge_status into v from public.registrations_admin where id = reg_soon;
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
