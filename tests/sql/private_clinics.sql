-- private_clinics.sql
--
-- Tara, 2026-11-23: "private events/clinics and allow me to privately invite
-- people to that clinic for payment. Maybe I still can do this actually but
-- not 'publish' it?" She could not: an unpublished clinic refuses an
-- invitation (clinic_not_published), and a published one is listed to every
-- member. Decision 0062: a Private switch on the clinic.
--
-- The rule, written from her ask and not from the code:
--   * a private clinic is listed (clinics_public) only to an account with a
--     player on it: You're In!, Waitlist or Response Needed;
--   * nobody else can register for it, join its Waitlist or ask for a late
--     spot, and the refusal is the one an unpublished clinic gets
--     (clinic_not_found), so it does not say the clinic exists;
--   * Tara's own tools work on it: invite, add (place_player), guests,
--     messages; the invited player sees it and can Accept;
--   * switching it on or off tells nobody;
--   * only Tara can switch it; anon cannot even call it;
--   * off again, it is listed to everyone and open to register as before.
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
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  priv uuid; closed uuid; gone uuid; v_reg public.registrations; n int; t text;
begin
  -- Two coed clinics with registration open: one in two days, one starting
  -- in two hours whose registration has closed (the late-request path).
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Private Event', 'coed', 'Clinic', 'probe', now() + interval '2 days', now() + interval '2 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into priv;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('Probe Private Closed', 'coed', 'Clinic', 'probe', now() + interval '2 hours', now() + interval '3 hours',
          now() - interval '2 days', now() - interval '1 day', now() - interval '1 hour', 8, 'published', 60)
  returning id into closed;

  -- A new clinic is not private.
  select count(*) into n from public.clinics where id = priv and not is_private;
  insert into _probe_result values ('a_new_clinic_is_not_private', '1', n::text);

  -- Tara makes both private.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.admin_set_clinic_private(priv, true);
  perform public.admin_set_clinic_private(closed, true);
  select string_agg(is_private::text, ',') into t from public.clinics_admin where id = priv;
  insert into _probe_result values ('clinics_admin_shows_private', 'true', coalesce(t, 'NONE'));
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics where id in (priv, closed) and is_private;
  insert into _probe_result values ('the_switch_sets_the_column', '2', n::text);

  -- Switching it tells nobody.
  select count(*) into n from public.notifications where entity_id in (priv, closed);
  insert into _probe_result values ('switching_on_tells_nobody', '0', n::text);

  -- Ken, on neither: not listed, cannot register, cannot ask late.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.clinics_public where id in (priv, closed);
  insert into _probe_result values ('not_listed_to_who_is_not_on_it', '0', n::text);
  begin
    perform public.register_for_clinic(priv, KEN_P, null);
    t := 'ALLOWED';
  exception when others then t := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('register_refused_and_no_row', 'clinic_not_found|0',
    t || '|' || (select count(*) from public.registrations where clinic_id = priv and player_id = KEN_P)::text);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.request_late_spot(closed, KEN_P, 'Can I come?');
    t := 'ALLOWED';
  exception when others then t := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  -- The last 0 is Tara's bell: a refused ask tells nobody.
  insert into _probe_result values ('late_request_refused_and_no_row', 'clinic_not_found|0|0',
    t || '|' || (select count(*) from public.late_requests where clinic_id = closed)::text
      || '|' || (select count(*) from public.notifications where account_id = TARA and entity_id = closed)::text);

  -- The same refusal an unpublished clinic gets: the words do not say it exists.
  update public.clinics set status = 'draft' where id = closed;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(closed, KEN_P, null);
    t := 'ALLOWED';
  exception when others then t := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('same_words_as_an_unpublished_clinic', 'clinic_not_found', t);
  update public.clinics set status = 'published' where id = closed;

  -- Tara invites Maria and adds Rob: both work on a private clinic.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  v_reg := public.admin_invite_player(priv, MARIA_P);
  perform public.place_player(priv, ROB_P, 'in');
  perform public.admin_add_guest(priv, 'Probe', 'Guest');
  perform set_config('role', 'postgres', true);
  select string_agg(p.first_name || ':' || r.status::text, ',' order by p.first_name) into t
    from public.registrations r join public.players p on p.id = r.player_id where r.clinic_id = priv;
  insert into _probe_result values ('invite_and_add_work', 'Maria:response_needed,Rob:in', coalesce(t, 'NONE'));
  select count(*) into n from public.clinic_guests where clinic_id = priv;
  insert into _probe_result values ('a_guest_can_be_added', '1', n::text);
  select count(*) into n from public.notifications where account_id = MARIA and type = 'invitation_received' and entity_id = v_reg.id;
  insert into _probe_result values ('the_invitation_is_sent', '1', n::text);

  -- Maria, invited, now sees it and can Accept.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.clinics_public where id = priv;
  insert into _probe_result values ('invited_player_sees_it', '1', n::text);
  perform public.respond_to_invitation(v_reg.id, true);
  perform set_config('role', 'postgres', true);
  select status::text into t from public.registrations where id = v_reg.id;
  insert into _probe_result values ('invited_player_can_accept', 'in', coalesce(t, 'NONE'));

  -- Already on it, her own Register is a second sign-up, refused as always,
  -- and adds nothing: a player's call never inserts on a private clinic.
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(priv, MARIA_P, null);
    t := 'ALLOWED';
  exception when others then t := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('on_it_register_again_adds_nothing', 'already_registered|1',
    t || '|' || (select count(*) from public.registrations where clinic_id = priv and player_id = MARIA_P)::text);

  -- A pro sees it in the week, as staff (decision 0062): Tara's pros work it.
  perform set_config('request.jwt.claims', json_build_object('sub', '77777777-7777-7777-7777-777777777777')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(distinct clinic_id) into n from public.pro_week() where clinic_id = priv;
  insert into _probe_result values ('a_pro_sees_it_in_the_week', '1', n::text);

  -- Rob, added by Tara, sees it; Ken still does not.
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.clinics_public where id = priv;
  insert into _probe_result values ('added_player_sees_it', '1', n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select count(*) into n from public.clinics_public where id = priv;
  insert into _probe_result values ('still_not_listed_to_ken', '0', n::text);

  -- Her message to everyone reaches who is on it, and only them.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.send_clinic_message(priv, 'everyone', 'Bring water.');
  perform set_config('role', 'postgres', true);
  select string_agg(a.first_name, ',' order by a.first_name) into t
    from public.notifications nt join public.accounts a on a.id = nt.account_id
   where nt.entity_id = priv and nt.type = 'clinic_message';
  insert into _probe_result values ('message_reaches_who_is_on_it', 'Maria,Rob', coalesce(t, 'NONE'));

  -- Rob cancels his spot: canceling works, and the clinic leaves his list.
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.cancel_registration(
    (select id from public.my_registrations where clinic_id = priv and status = 'in'), null);
  select count(*) into n from public.clinics_public where id = priv;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('a_canceled_player_no_longer_sees_it', 'canceled|0',
    (select status::text from public.registrations where clinic_id = priv and player_id = ROB_P) || '|' || n::text);
  -- ...and cannot sign up again by himself.
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(priv, ROB_P, null);
    t := 'ALLOWED';
  exception when others then t := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('a_canceled_player_cannot_register_again', 'clinic_not_found|0',
    t || '|' || (select count(*) from public.registrations where clinic_id = priv and player_id = ROB_P and status <> 'canceled')::text);

  -- Only Tara switches it: Ken's call is refused and nothing moves.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_set_clinic_private(priv, false);
    t := 'ALLOWED';
  exception when others then t := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('a_player_cannot_switch_it', 'not_authorized|true',
    t || '|' || (select is_private::text from public.clinics where id = priv));
  insert into _probe_result values ('anon_cannot_call_it', 'false',
    has_function_privilege('anon', 'public.admin_set_clinic_private(uuid,boolean)', 'execute')::text);
  insert into _probe_result values ('public_cannot_call_it', 'false',
    exists (select 1 from pg_proc p, aclexplode(p.proacl) a
             where p.oid = 'public.admin_set_clinic_private(uuid,boolean)'::regprocedure
               and a.grantee = 0 and a.privilege_type = 'EXECUTE')::text);
  insert into _probe_result values ('authenticated_can_call_it', 'true',
    has_function_privilege('authenticated', 'public.admin_set_clinic_private(uuid,boolean)', 'execute')::text);
  -- A clinic that is not there is said as such.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_set_clinic_private(gen_random_uuid(), true);
    t := 'ALLOWED';
  exception when others then t := sqlerrm;
  end;
  insert into _probe_result values ('an_unknown_clinic_is_not_found', 'clinic_not_found', t);

  -- Copy to next week keeps it private: a copy of her private event must not
  -- be listed to everyone the day she publishes the week.
  perform public.admin_copy_week((select public.service_week_start(starts_at) from public.clinics_admin where id = priv));
  perform set_config('role', 'postgres', true);
  select string_agg(is_private::text, ',') into t from public.clinics
   where name = 'Probe Private Event' and id <> priv;
  insert into _probe_result values ('a_copy_of_a_private_clinic_is_private', 'true', coalesce(t, 'NONE'));

  -- Off again: listed to everyone, Ken registers as before, and nobody is told.
  delete from public.notifications where entity_id = priv;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.admin_set_clinic_private(priv, false);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notifications where entity_id = priv;
  insert into _probe_result values ('switching_off_tells_nobody', '0', n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.clinics_public where id = priv;
  insert into _probe_result values ('off_again_listed_to_everyone', '1', n::text);
  -- Ken is a member and the public open has passed: the Waitlist (decision 0050).
  begin
    select status::text into t from public.register_for_clinic(priv, KEN_P, null);
  exception when others then t := sqlerrm;
  end;
  insert into _probe_result values ('off_again_anyone_can_register', 'pool', coalesce(t, 'NONE'));

  -- Tara herself is exempt: her own register_for_clinic on a private clinic
  -- puts the player on it (sql-auditor, 2026-11-27: unpinned until now).
  perform set_config('role', 'postgres', true);
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, is_private)
  values ('Probe Private Tara Registers', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60, true)
  returning id into gone;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.register_for_clinic(gone, KEN_P, null);
    t := 'ok';
  exception when others then t := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('tara_can_register_someone_on_a_private_clinic', 'ok|1',
    t || '|' || (select count(*) from public.registrations where clinic_id = gone and player_id = KEN_P and status <> 'canceled')::text);

  -- A private clinic Tara cancels: Maria, who held a spot, still sees
  -- Canceled; a player who was never on it does not.
  perform set_config('role', 'postgres', true);
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, is_private)
  values ('Probe Private Rained Out', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60, true)
  returning id into gone;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (gone, MARIA_P, 'in', 'admin', 1800, true, 60);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.cancel_clinic(gone);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.clinics_public where id = gone and status = 'canceled';
  insert into _probe_result values ('canceled_private_still_shown_to_who_was_on_it', '1', n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select count(*) into n from public.clinics_public where id = gone;
  insert into _probe_result values ('canceled_private_gone_for_others', '0', n::text);
  perform set_config('role', 'postgres', true);
end $$;

select check_name,
       case when expected = actual then 'PASS' else 'FAIL' end as result,
       expected, actual
  from _probe_result;

rollback;
