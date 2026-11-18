-- juniors_review.sql
--
-- 20261118000002 (decision 0061, "Review"): what the sql-auditor found in
-- 20261118000001, each rule written from the finding, each refusal checked
-- by the state it leaves (hard rule 9), not only by its error.
--
--   h1  A child holds no spot, Waitlist row, late request or accepted
--       invitation without a signature on the current junior waiver
--       (junior_waiver_required), or while there is no junior text at all
--       (junior_waiver_not_available). Tara placing a child is exempt, as
--       she is for the adult waiver. A child does not need the PARENT's
--       adult waiver: theirs is the junior one.
--   m2  An archived child (removed by the parent) holds nothing either
--       (player_not_found), and a child with a pending late request is not
--       removed (child_has_upcoming).
--   m3  Once Tara has approved or declined a program for a child, or a
--       waiver has been signed for them, the parent cannot change the
--       child's name or birthday (child_locked): the approval and the
--       signature are about that child. The signature keeps the child's
--       name and birthday as signed, so it survives the account being
--       blanked.
--   l5  my_news and my_clinic_messages (read by the apps already on phones)
--       count only active rows and the adult's clinics.
--   l6  set_my_gender and request_level_approval are for the adult row
--       (wrong_player_kind on a child).
--   l7  The adult waiver functions read adult text only.
--   l8  A child signature row is always the child's own parent's, on an
--       active child, and is never edited, whatever path writes it.
--   l9  At most 10 children per account (too_many_children).
--
-- Fixtures: Maria and Ken (seed members). Every expected value is the
-- literal answer of the rule.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  kid uuid; kid2 uuid; arch uuid; kenkid uuid; lock1 uuid; lock2 uuid; free1 uuid;
  c_jr uuid; c_late uuid; c_inv uuid; c_inv2 uuid; c_adult uuid;
  r_inv uuid; r_inv2 uuid; elite uuid;
  n int; v text; err text; i int;
begin
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values
    ('Review Juniors Open',   'juniors', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
     now() - interval '2 days', now() - interval '1 day', null, 8, 'published', 60),
    ('Review Juniors Late',   'juniors', 'Clinic', 'probe', now() + interval '2 hours', now() + interval '3 hours',
     now() - interval '2 days', now() - interval '1 day', now() - interval '1 minute', 8, 'published', 60),
    ('Review Juniors Invite', 'juniors', 'Clinic', 'probe', now() + interval '4 days', now() + interval '4 days 1 hour',
     now() - interval '2 days', now() - interval '1 day', null, 8, 'published', 60),
    ('Review Juniors Invite 2', 'juniors', 'Clinic', 'probe', now() + interval '5 days', now() + interval '5 days 1 hour',
     now() - interval '2 days', now() - interval '1 day', null, 8, 'published', 60),
    ('Review Adult',          'coed',    'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
     now() - interval '2 days', now() - interval '1 day', null, 8, 'published', 60);
  select id into c_jr    from public.clinics where name = 'Review Juniors Open';
  select id into c_late  from public.clinics where name = 'Review Juniors Late';
  select id into c_inv   from public.clinics where name = 'Review Juniors Invite';
  select id into c_inv2  from public.clinics where name = 'Review Juniors Invite 2';
  select id into c_adult from public.clinics where name = 'Review Adult';
  select id into elite from public.junior_programs where name = 'Elite';

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select id into kid  from public.add_my_child('Rae', 'Review', date '2016-04-01');
  select id into kid2 from public.add_my_child('Ivo', 'Review', date '2014-04-01');

  -- Tara's invitations to the children (rows written with no one signed in).
  perform set_config('request.jwt.claims', '', true);
  insert into public.registrations (clinic_id, player_id, status, source) values (c_inv, kid, 'response_needed', 'admin')
  returning id into r_inv;

  -- ---------------------------------------------------------------- h1, no text yet
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.register_for_clinic(c_jr, kid, null);
    err := 'registered';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('h1a_no_junior_text_no_spot', 'junior_waiver_not_available', err);
  select count(*) into n from public.registrations where player_id = kid and clinic_id = c_jr;
  insert into _probe_result values ('h1b_and_no_row', '0', n::text);

  -- Her text is published; Rae has not signed it.
  perform set_config('request.jwt.claims', '', true);
  insert into public.waivers (version, kind, title, organizer, body)
  values ('juniors-review', 'junior', 'Probe Parent/Guardian Waiver', 'Probe', 'probe text');
  insert into public.app_settings (key, value) values ('junior_waiver_version', 'juniors-review')
  on conflict (key) do update set value = excluded.value;

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.register_for_clinic(c_jr, kid, null);
    err := 'registered';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('h1c_unsigned_child_no_spot', 'junior_waiver_required', err);
  select count(*) into n from public.registrations where player_id = kid and clinic_id = c_jr;
  insert into _probe_result values ('h1d_and_no_row', '0', n::text);
  -- An adult clinic is the wrong place before it is a waiver question.
  begin
    perform public.register_for_clinic(c_adult, kid, null);
    err := 'registered';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('h1o_a_child_hears_wrong_clinic_before_waiver', 'wrong_player_kind', err);
  begin
    perform public.request_late_spot(c_adult, kid, null);
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('h1p_and_so_does_a_late_request', 'wrong_player_kind', err);
  begin
    perform public.request_late_spot(c_late, kid, 'please');
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('h1e_unsigned_child_no_late_request', 'junior_waiver_required', err);
  select count(*) into n from public.late_requests where player_id = kid;
  insert into _probe_result values ('h1f_and_no_late_request_row', '0', n::text);
  begin
    perform public.respond_to_invitation(r_inv, true);
    err := 'accepted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('h1g_unsigned_child_cannot_accept', 'junior_waiver_required', err);
  select status::text into v from public.registrations where id = r_inv;
  insert into _probe_result values ('h1h_and_the_invitation_is_still_waiting', 'response_needed', v);
  begin
    select status::text into v from public.respond_to_invitation(r_inv, false);
  exception when others then v := sqlerrm;
  end;
  -- A decline four days out goes back to the Waitlist (20261109000001).
  insert into _probe_result values ('h1i_declining_needs_no_signature', 'pool', v);

  -- Signed: everything works, and the parent's own adult waiver is not asked.
  perform public.accept_child_waiver(kid, 'juniors-review', 'Maria Lopez');
  perform set_config('request.jwt.claims', '', true);
  delete from public.waiver_acceptances where account_id = MARIA;
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    select status::text into v from public.register_for_clinic(c_jr, kid, null);
  exception when others then v := sqlerrm;
  end;
  insert into _probe_result values ('h1j_signed_child_registers_without_the_parents_adult_waiver', 'pool', v);
  begin
    perform public.register_for_clinic(c_adult, MARIA_P, null);
    err := 'registered';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('h1k_the_adult_still_needs_her_own', 'waiver_required', err);
  select count(*) into n from public.registrations where player_id = MARIA_P and clinic_id = c_adult;
  insert into _probe_result values ('h1l_and_holds_nothing', '0', n::text);
  begin
    select 'status:' || status into v from public.request_late_spot(c_late, kid, 'please');
  exception when others then v := sqlerrm;
  end;
  insert into _probe_result values ('h1m_signed_child_asks_late', 'status:pending', v);

  -- Tara places an unsigned child herself: her call, as with adults.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  begin
    select status::text into v from public.register_for_clinic(c_jr, kid2, null);
  exception when others then v := sqlerrm;
  end;
  insert into _probe_result values ('h1n_tara_may_place_an_unsigned_child', 'pool', v);

  -- ---------------------------------------------------------------- m2, archived
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  -- Rae holds c_jr and c_inv (Waitlist) and a pending late request; cancel
  -- both spots, keep the request, so only the request can stop the removal.
  begin
    perform public.cancel_registration((select id from public.registrations where player_id = kid and clinic_id = c_jr), null);
    perform public.cancel_registration((select id from public.registrations where player_id = kid and clinic_id = c_inv), null);
  exception when others then v := sqlerrm;
  end;
  begin
    perform public.remove_my_child(kid);
    err := 'removed';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('m2a_a_pending_late_request_keeps_the_child', 'child_has_upcoming', err);
  select is_active::text into v from public.players where id = kid;
  insert into _probe_result values ('m2b_and_the_child_stays_active', 'true', v);

  select id into arch from public.add_my_child('Arch', 'Review', date '2015-01-01');
  perform public.accept_child_waiver(arch, 'juniors-review', 'Maria Lopez');
  perform set_config('request.jwt.claims', '', true);
  insert into public.registrations (clinic_id, player_id, status, source) values (c_inv2, arch, 'response_needed', 'admin')
  returning id into r_inv2;
  -- Archived after Tara's invitation (as the database might have it; the
  -- parent's remove refuses with a live invitation).
  update public.players set is_active = false where id = arch;
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.register_for_clinic(c_jr, arch, null);
    err := 'registered';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('m2c_an_archived_child_registers_for_nothing', 'player_not_found', err);
  select count(*) into n from public.registrations where player_id = arch and clinic_id = c_jr;
  insert into _probe_result values ('m2d_and_no_row', '0', n::text);
  begin
    perform public.request_late_spot(c_late, arch, null);
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('m2e_an_archived_child_asks_for_nothing', 'player_not_found', err);
  select count(*) into n from public.late_requests where player_id = arch;
  insert into _probe_result values ('m2f_and_no_late_request_row', '0', n::text);
  begin
    perform public.respond_to_invitation(r_inv2, true);
    err := 'accepted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('m2g_an_archived_child_accepts_nothing', 'player_not_found', err);
  select status::text into v from public.registrations where id = r_inv2;
  insert into _probe_result values ('m2h_and_the_row_is_unchanged', 'response_needed', v);

  -- ---------------------------------------------------------------- m3, locked once decided or signed
  select id into lock1 from public.add_my_child('Lock', 'Approved', date '2012-01-01');
  select id into lock2 from public.add_my_child('Lock', 'Signed', date '2012-02-01');
  select id into free1 from public.add_my_child('Free', 'Asked', date '2012-03-01');
  perform public.request_program_approval(free1, elite);
  perform public.accept_child_waiver(lock2, 'juniors-review', 'Maria Lopez');
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_preapprove_program(lock1, elite);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.update_my_child(lock1, 'Other', 'Child', date '2019-06-01');
    err := 'updated';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('m3a_an_approved_child_is_locked', 'child_locked', err);
  select first_name || ' ' || last_name || ' ' || date_of_birth into v from public.players where id = lock1;
  insert into _probe_result values ('m3b_and_unchanged', 'Lock Approved 2012-01-01', v);
  begin
    perform public.update_my_child(lock2, 'Lock', 'Signed', date '2019-06-01');
    err := 'updated';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('m3c_a_signed_child_is_locked', 'child_locked', err);
  select date_of_birth::text into v from public.players where id = lock2;
  insert into _probe_result values ('m3d_and_the_birthday_unchanged', '2012-02-01', v);
  begin
    select first_name into v from public.update_my_child(free1, 'Freda', 'Asked', date '2012-03-01');
  exception when others then v := sqlerrm;
  end;
  insert into _probe_result values ('m3e_a_pending_request_alone_does_not_lock', 'Freda', v);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_decide_program_approval(free1, elite, false);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.update_my_child(free1, 'Fred', 'Asked', date '2012-03-01');
    err := 'updated';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('m3f_a_declined_child_is_locked', 'child_locked', err);

  begin
    select child_first_name || ' ' || child_last_name || ' ' || child_date_of_birth into v
      from public.junior_waiver_acceptances where player_id = lock2;
  exception when others then v := sqlerrm;
  end;
  insert into _probe_result values ('m3g_the_signature_records_the_child_as_signed', 'Lock Signed 2012-02-01', v);
  perform set_config('request.jwt.claims', '', true);
  update public.players set first_name = 'Deleted', last_name = 'Player', date_of_birth = null, is_active = false
   where id = lock2;   -- what delete_my_account does to a child
  begin
    select child_first_name || ' ' || child_last_name || ' ' || child_date_of_birth into v
      from public.junior_waiver_acceptances where player_id = lock2;
  exception when others then v := sqlerrm;
  end;
  insert into _probe_result values ('m3h_and_survives_the_account_being_blanked', 'Lock Signed 2012-02-01', v);

  -- ---------------------------------------------------------------- l5, the old apps' reads
  insert into public.news_posts (title, body, audience, status, published_at)
  values ('Review juniors news', 'probe', 'juniors', 'published', now());
  -- Ken: one child, archived.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select id into kenkid from public.add_my_child('Kenkid', 'Review', date '2016-01-01');
  perform public.remove_my_child(kenkid);
  select count(*) into n from public.my_news where title = 'Review juniors news';
  insert into _probe_result values ('l5a_an_archived_child_brings_no_juniors_news', '0', n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.my_news where title = 'Review juniors news';
  insert into _probe_result values ('l5b_an_active_child_still_does', '1', n::text);

  perform set_config('request.jwt.claims', '', true);
  insert into public.clinic_messages (clinic_id, body, audience) values (c_jr, 'Review juniors message', 'everyone');
  insert into public.registrations (clinic_id, player_id, status, source) values (c_adult, MARIA_P, 'in', 'admin');
  insert into public.clinic_messages (clinic_id, body, audience) values (c_adult, 'Review adult message', 'everyone');
  insert into public.clinic_messages (clinic_id, body, audience) values (c_jr, 'Review juniors direct', 'player')
  returning id into r_inv;
  insert into public.clinic_message_recipients (message_id, player_id) values (r_inv, kid2);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.my_clinic_messages where body like 'Review juniors%';
  insert into _probe_result values ('l5c_old_apps_read_no_message_of_a_childs_clinic', '0', n::text);
  select count(*) into n from public.my_clinic_messages where body = 'Review adult message';
  insert into _probe_result values ('l5d_and_still_the_adults_own', '1', n::text);

  -- ---------------------------------------------------------------- l6, adult-only functions
  begin
    perform public.set_my_gender(kid2, 'female');
    err := 'set';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('l6a_set_my_gender_is_for_the_adult', 'wrong_player_kind', err);
  select coalesce(gender::text, 'unset') into v from public.players where id = kid2;
  insert into _probe_result values ('l6b_and_the_childs_gender_is_unset', 'unset', v);
  begin
    perform public.request_level_approval(kid2, 4.0);
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('l6c_request_level_approval_is_for_the_adult', 'wrong_player_kind', err);
  select count(*) into n from public.level_approvals where player_id = kid2;
  insert into _probe_result values ('l6d_and_no_level_row', '0', n::text);

  -- ---------------------------------------------------------------- l7, adult text only
  perform set_config('request.jwt.claims', '', true);
  update public.app_settings set value = 'juniors-review' where key = 'waiver_version';
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  insert into _probe_result values ('l7a_waiver_version_never_names_junior_text', 'none',
    coalesce(public.waiver_version(), 'none'));
  select count(*) into n from public.current_waiver();
  insert into _probe_result values ('l7b_current_waiver_never_shows_junior_text', '0', n::text);
  perform set_config('request.jwt.claims', '', true);
  update public.app_settings set value = '2026-09' where key = 'waiver_version';

  -- ---------------------------------------------------------------- l8, the signature row
  begin
    insert into public.junior_waiver_acceptances (player_id, account_id, version, legal_name, email,
        child_first_name, child_last_name, child_date_of_birth)
    values (kid2, KEN, 'juniors-review', 'Ken Probe', 'x', 'Ivo', 'Review', date '2014-04-01');
    err := 'inserted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('l8a_only_the_childs_parent_signs_whatever_the_path', 'not_your_child', err);
  begin
    insert into public.junior_waiver_acceptances (player_id, account_id, version, legal_name, email,
        child_first_name, child_last_name, child_date_of_birth)
    values (arch, MARIA, 'juniors-review', 'Maria Lopez', 'x', 'Arch', 'Review', date '2015-01-01');
    err := 'inserted';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('l8b_nobody_signs_for_an_archived_child', 'not_your_child', err);
  select count(*) into n from public.junior_waiver_acceptances where player_id = kid2;
  insert into _probe_result values ('l8c_and_no_row_was_written', '0', n::text);
  begin
    update public.junior_waiver_acceptances set legal_name = 'Someone Else' where player_id = kid;
    err := 'updated';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('l8d_a_signature_is_never_edited', 'signature_is_final', err);
  select legal_name into v from public.junior_waiver_acceptances where player_id = kid;
  insert into _probe_result values ('l8e_and_reads_as_signed', 'Maria Lopez', v);

  -- ---------------------------------------------------------------- l9, ten children
  -- Maria has four active children here (Rae, Ivo, Lock Approved, Freda;
  -- Arch and Lock Signed are archived). Add up to ten.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.my_children();
  for i in 1 .. 10 - n loop
    perform public.add_my_child('Cap' || i, 'Review', date '2010-01-01' + i);
  end loop;
  select count(*) into n from public.my_children();
  insert into _probe_result values ('l9a_ten_children_are_allowed', '10', n::text);
  begin
    perform public.add_my_child('Eleven', 'Review', date '2010-12-01');
    err := 'added';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('l9b_an_eleventh_is_refused', 'too_many_children', err);
  select count(*) into n from public.players where account_id = MARIA and kind = 'junior' and is_active;
  insert into _probe_result values ('l9c_and_still_ten', '10', n::text);
end $$;

select check_name, expected, actual,
  case
    when actual = expected then 'PASS'
    when expected ~ '[A-Za-z]' and strpos(actual, expected) > 0 then 'PASS'
    else 'FAIL'
  end as result
from _probe_result
order by check_name;

rollback;
