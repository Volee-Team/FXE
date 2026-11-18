-- juniors_family.sql
--
-- Juniors phase 1, the server (docs/juniors/plan.md, decision 0061):
-- My Children, a waiver per child, the five programs, and Elite approvals.
-- THE RULES, each written from the plan and her document (spec 01), not
-- from the code:
--   - A parent adds, edits and removes their own children. A child is a
--     players row (kind junior, a birthday) on the parent's account; the
--     account becomes 'both' if it was an adult account. Removing archives
--     (hard rule 4) and is refused while the child holds an upcoming spot.
--     The same child twice on one account is refused.
--   - Nobody but the child's own parent account and Tara reads or changes a
--     child: another member, a pro and a signed-out caller get nothing.
--   - Phase 0 still holds: a member's own read of players returns the adult
--     only, so the apps already on phones never see a child.
--   - A waiver per child, signed by the parent, per version. Until Tara's
--     parent/guardian text is published there is no version, and the status
--     says so ('not_available') instead of 'needed' forever. A new version
--     (next year's) makes every child 'needed' again. A signature is never
--     overwritten or deleted, and the adult waiver is untouched.
--   - Five programs from her document, in her order; Junior Elite and Elite
--     need Tara's approval; parents see active programs only; only Tara
--     edits them.
--   - A parent requests approval for their own child for a program that
--     needs it; Tara approves or declines a request (once: a second decision
--     on a decided request is refused, hard rule 3), or preapproves a child
--     directly. A declined child cannot be re-requested by the parent.
--
-- Fixtures: Maria (seed member) and Ken (seed member) and Casey (seed pro).
-- Every expected value below is the literal answer the rule gives.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';
  sam uuid; lily uuid; noa uuid; kid_k uuid;
  elite uuid; jr_elite uuid; red uuid;
  c_jr uuid;
  n int; v text; err text; r record;
begin
  -- Ken is a parent-only account for c13 (a parent stays a parent).
  update public.accounts set account_type = 'parent' where id = KEN;
  update public.accounts set account_type = 'adult'  where id = MARIA;

  -- ---------------------------------------------------------------- signed out
  perform set_config('request.jwt.claims', '', true);
  begin
    perform public.add_my_child('Sam', 'Probe', date '2017-05-01');
    err := 'added';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('s1_signed_out_cannot_add_a_child', 'not_authenticated', err);
  begin
    select count(*) into n from public.my_children();
    err := n::text;
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('s2_signed_out_reads_no_children', 'not_authenticated', err);

  -- ---------------------------------------------------------------- children
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select id into sam from public.add_my_child('  Sam ', 'Probe', date '2017-05-01');
  select count(*) into n from public.players
   where id = sam and account_id = MARIA and kind = 'junior' and is_active
     and first_name = 'Sam' and date_of_birth = date '2017-05-01';
  insert into _probe_result values ('c1_a_parent_adds_a_child_on_their_account', '1', coalesce(n, 0)::text);
  select account_type::text into v from public.accounts where id = MARIA;
  insert into _probe_result values ('c2_an_adult_account_becomes_both', 'both', v);

  begin
    perform public.add_my_child('sam', 'probe', date '2017-05-01');
    err := 'added';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('c3_the_same_child_twice_is_refused', 'child_exists', err);
  begin
    perform public.add_my_child('  ', 'Probe', date '2017-05-01');
    err := 'added';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('c4_a_blank_name_is_refused', 'name_required', err);
  begin
    perform public.add_my_child('Future', 'Probe', current_date + 1);
    err := 'added';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('c5a_a_birthday_in_the_future_is_refused', 'invalid_birthday', err);
  begin
    perform public.add_my_child('Nobday', 'Probe', null);
    err := 'added';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('c5b_a_missing_birthday_is_refused', 'invalid_birthday', err);

  select id into lily from public.add_my_child('Lily', 'Probe', date '2015-02-10');
  select id into noa  from public.add_my_child('Noa',  'Probe', date '2013-08-20');

  select string_agg(first_name || ':' || age, ',' order by first_name) into v from public.my_children();
  -- Ages from the birthdays above, worked out for today's date in the probe.
  insert into _probe_result values ('c6a_my_children_lists_the_parents_children_with_ages',
    'Lily:' || extract(year from age(current_date, date '2015-02-10'))::int
    || ',Noa:' || extract(year from age(current_date, date '2013-08-20'))::int
    || ',Sam:' || extract(year from age(current_date, date '2017-05-01'))::int, v);

  perform public.update_my_child(sam, 'Samuel', 'Probe', date '2017-05-02');
  select first_name || ' ' || date_of_birth into v from public.players where id = sam;
  insert into _probe_result values ('c8a_a_parent_edits_their_child', 'Samuel 2017-05-02', v);
  begin
    perform public.update_my_child(MARIA_P, 'Not', 'Child', date '2010-01-01');
    err := 'updated';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('c9_update_my_child_never_edits_the_adult_row', 'not_your_child', err);

  -- Ken: another member.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select count(*) into n from public.my_children();
  insert into _probe_result values ('c6b_another_member_sees_none_of_them', '0', n::text);
  begin
    perform public.update_my_child(sam, 'Hacked', 'Probe', date '2017-05-02');
    err := 'updated';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('c8b_another_member_cannot_edit_the_child', 'not_your_child', err);
  select first_name into v from public.players where id = sam;
  insert into _probe_result values ('c8c_and_the_name_is_unchanged', 'Samuel', v);
  begin
    perform public.remove_my_child(sam);
    err := 'removed';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('c10a_another_member_cannot_remove_the_child', 'not_your_child', err);
  select is_active::text into v from public.players where id = sam;
  insert into _probe_result values ('c10a2_and_the_child_is_still_active', 'true', v);
  select id into kid_k from public.add_my_child('Kay', 'Probe', date '2016-01-01');
  select account_type::text into v from public.accounts where id = KEN;
  insert into _probe_result values ('c13_a_parent_account_stays_parent', 'parent', v);

  -- Casey: a pro.
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  select count(*) into n from public.my_children();
  insert into _probe_result values ('c14_a_pro_sees_none_of_them', '0', n::text);

  -- Removing: refused while Lily holds an upcoming spot, archived otherwise.
  perform set_config('request.jwt.claims', '', true);
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Juniors Family', 'juniors', 'Clinic', 'probe', now() + interval '3 days',
          now() + interval '3 days 1 hour', now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into c_jr;
  insert into public.registrations (clinic_id, player_id, status, source) values (c_jr, lily, 'in', 'admin');

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.remove_my_child(lily);
    err := 'removed';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('c11_a_child_with_an_upcoming_spot_is_not_removed', 'child_has_upcoming', err);
  perform public.remove_my_child(noa);
  select (is_active)::text || ' ' || first_name into v from public.players where id = noa;
  insert into _probe_result values ('c10b_removing_archives_the_row', 'false Noa', v);
  select count(*) into n from public.my_children() where id = noa;
  insert into _probe_result values ('c10c_a_removed_child_leaves_my_children', '0', n::text);
  begin
    perform public.update_my_child(noa, 'Noa', 'Probe', date '2013-08-20');
    err := 'updated';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('c10d_a_removed_child_cannot_be_edited', 'not_your_child', err);

  -- ---------------------------------------------------------------- waiver per child
  select count(*) into n from public.current_junior_waiver();
  insert into _probe_result values ('w1a_no_junior_waiver_until_her_text_is_published', '0', n::text);
  insert into _probe_result values ('w1b_status_says_not_available', 'not_available', public.child_waiver_status(sam));
  select string_agg(first_name || ':' || waiver_status, ',' order by first_name) into v from public.my_children();
  insert into _probe_result values ('w1c_my_children_carries_the_status', 'Lily:not_available,Samuel:not_available', v);
  begin
    perform public.accept_child_waiver(sam, 'juniors-2026', 'Maria Lopez');
    err := 'signed';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('w2_nothing_to_sign_yet', 'junior_waiver_not_available', err);

  -- Her text arrives (a later migration does exactly this).
  perform set_config('request.jwt.claims', '', true);
  insert into public.waivers (version, kind, title, organizer, body)
  values ('juniors-2026', 'junior', 'Probe Parent/Guardian Waiver', 'Probe', 'probe text');
  insert into public.app_settings (key, value) values ('junior_waiver_version', 'juniors-2026')
  on conflict (key) do update set value = excluded.value;

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  insert into _probe_result values ('w3_once_published_a_child_needs_it', 'needed', public.child_waiver_status(sam));
  select title into v from public.current_junior_waiver();
  insert into _probe_result values ('w3b_the_parent_reads_the_junior_text', 'Probe Parent/Guardian Waiver', v);
  begin
    perform public.accept_child_waiver(sam, '2026-09', 'Maria Lopez');
    err := 'signed';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('w5a_a_stale_or_adult_version_is_refused', 'waiver_version_stale', err);
  begin
    perform public.accept_child_waiver(sam, 'juniors-2026', 'Maria');
    err := 'signed';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('w5b_a_full_legal_name_is_required', 'legal_name_required', err);
  perform public.accept_child_waiver(sam, 'juniors-2026', 'Maria Lopez', '1.0.5 (1)');
  insert into _probe_result values ('w6a_signed', 'signed', public.child_waiver_status(sam));
  insert into _probe_result values ('w6b_the_sibling_still_needs_their_own', 'needed', public.child_waiver_status(lily));
  select count(*) into n from public.junior_waiver_acceptances a
    join public.accounts acc on acc.id = MARIA
   where a.player_id = sam and a.account_id = MARIA and a.version = 'juniors-2026'
     and a.legal_name = 'Maria Lopez' and a.email = acc.email;
  insert into _probe_result values ('w6c_the_record_names_signer_child_version_and_email', '1', n::text);
  perform public.accept_child_waiver(sam, 'juniors-2026', 'Someone Else');
  select string_agg(legal_name, ',') into v from public.junior_waiver_acceptances where player_id = sam;
  insert into _probe_result values ('w7_signing_twice_keeps_the_first', 'Maria Lopez', v);
  insert into _probe_result values ('w9a_the_adult_waiver_is_untouched', 'true', public.my_waiver_accepted()::text);
  begin
    perform public.accept_waiver('juniors-2026', 'Maria Lopez');
    err := 'signed';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('w9b_the_junior_text_cannot_be_signed_as_the_adult_waiver', 'waiver_version_stale', err);

  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin
    perform public.accept_child_waiver(sam, 'juniors-2026', 'Ken Probe');
    err := 'signed';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('w4_another_member_cannot_sign_for_the_child', 'not_your_child', err);
  select count(*) into n from public.junior_waiver_acceptances where account_id = KEN;
  insert into _probe_result values ('w4b_and_no_signature_of_his_exists', '0', n::text);
  begin
    v := public.child_waiver_status(sam);
    err := v;
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('w12_another_member_cannot_read_the_childs_status', 'not_your_child', err);
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin
    v := public.child_waiver_status(sam);
    err := v;
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('w13_a_pro_cannot_read_the_childs_status', 'not_your_child', err);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  insert into _probe_result values ('w14_tara_reads_any_childs_status', 'needed', public.child_waiver_status(lily));

  perform set_config('request.jwt.claims', '', true);
  begin
    insert into public.junior_waiver_acceptances (player_id, account_id, version, legal_name, email,
        child_first_name, child_last_name, child_date_of_birth)
    values (lily, MARIA, '2026-09', 'Maria Lopez', 'x', 'Lily', 'Probe', date '2015-02-10');
    err := 'inserted';
  exception when foreign_key_violation then err := 'foreign_key_violation';
  end;
  insert into _probe_result values ('w10_a_child_signature_must_be_on_a_junior_text', 'foreign_key_violation', err);
  begin
    delete from public.players where id = sam;
    err := 'deleted';
  exception when foreign_key_violation then err := 'foreign_key_violation';
  end;
  insert into _probe_result values ('w11_a_hard_delete_cannot_take_a_child_signature', 'foreign_key_violation', err);

  -- Next year's text: everyone signs again.
  insert into public.waivers (version, kind, title, organizer, body)
  values ('juniors-2027', 'junior', 'Probe Parent/Guardian Waiver 2027', 'Probe', 'probe text');
  update public.app_settings set value = 'juniors-2027' where key = 'junior_waiver_version';
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  insert into _probe_result values ('w8_a_new_version_needs_a_new_signature', 'needed', public.child_waiver_status(sam));

  -- ---------------------------------------------------------------- programs
  select string_agg(name, ', ' order by sort_order) into v from public.list_junior_programs();
  insert into _probe_result values ('p1_her_five_programs_in_her_order',
    'Red Dot, Orange Dot, Recreational Yellow, Junior Elite, Elite', v);
  select string_agg(name, ', ' order by name) into v from public.list_junior_programs() where needs_approval;
  insert into _probe_result values ('p2_the_two_elite_programs_need_approval', 'Elite, Junior Elite', v);
  select string_agg(name || '=' || age_guidance, '; ' order by sort_order) into v
    from public.list_junior_programs() where age_guidance <> '';
  insert into _probe_result values ('p3_her_age_guidance', 'Red Dot=Ages 3-6; Orange Dot=Ages 6-10; Recreational Yellow=Ages 10+', v);

  select id into elite    from public.list_junior_programs() where name = 'Elite';
  select id into jr_elite from public.list_junior_programs() where name = 'Junior Elite';
  select id into red      from public.list_junior_programs() where name = 'Red Dot';

  begin
    perform public.admin_save_junior_program(red, 'Red Dot', 'mine now', 'Ages 3-6', false, 1, true);
    err := 'saved';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('p5a_a_member_cannot_edit_a_program', 'not_authorized', err);
  select description into v from public.junior_programs where id = red;
  insert into _probe_result values ('p5a2_and_the_description_is_unchanged', '', v);
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin
    perform public.admin_save_junior_program(red, 'Red Dot', 'mine now', 'Ages 3-6', false, 1, true);
    err := 'saved';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('p5b_a_pro_cannot_edit_a_program', 'not_authorized', err);
  select description into v from public.junior_programs where id = red;
  insert into _probe_result values ('p5b2_and_the_description_is_unchanged', '', v);

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_save_junior_program(red, 'Red Dot', 'Our youngest players.', 'Ages 3-6', false, 1, true);
  select description into v from public.list_junior_programs() where id = red;
  insert into _probe_result values ('p6_tara_writes_a_description', 'Our youngest players.', v);
  begin
    perform public.admin_save_junior_program(null, '   ', '', '', false, 9, true);
    err := 'saved';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('p7a_a_program_needs_a_name', 'name_required', err);
  begin
    perform public.admin_save_junior_program(null, 'elite', '', '', true, 9, true);
    err := 'saved';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('p7b_two_programs_cannot_share_a_name', 'program_name_taken', err);
  perform public.admin_save_junior_program(null, 'Probe Archived', '', '', false, 9, false);
  select count(*) into n from public.admin_junior_programs();
  insert into _probe_result values ('p4a_tara_sees_every_program', '6', n::text);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.list_junior_programs();
  insert into _probe_result values ('p4b_parents_see_active_programs_only', '5', n::text);
  begin
    select count(*) into n from public.admin_junior_programs();
    err := n::text;
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('p4c_a_member_cannot_read_taras_list', 'not_authorized', err);

  -- ---------------------------------------------------------------- approvals
  select status into v from public.request_program_approval(sam, elite);
  insert into _probe_result values ('a1_a_parent_requests_elite', 'requested', v);
  perform public.request_program_approval(sam, elite);
  select count(*) into n from public.program_approvals where player_id = sam and program_id = elite;
  insert into _probe_result values ('a2_a_second_tap_is_one_request', '1', n::text);
  begin
    perform public.request_program_approval(sam, red);
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a3_red_dot_needs_no_approval', 'approval_not_needed', err);
  begin
    perform public.request_program_approval(MARIA_P, elite);
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a13_an_adult_row_is_not_a_child', 'not_your_child', err);
  begin
    perform public.request_program_approval(noa, elite);
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a11_a_removed_child_cannot_be_requested', 'not_your_child', err);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_save_junior_program(null, 'Probe Closed Elite', '', '', true, 10, false);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.request_program_approval(sam, (select id from public.junior_programs where name = 'Probe Closed Elite'));
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a12_an_archived_program_cannot_be_requested', 'program_not_found', err);
  select status into v from public.request_program_approval(lily, jr_elite);

  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  begin
    perform public.request_program_approval(sam, elite);
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a4_another_member_cannot_request_for_the_child', 'not_your_child', err);
  select count(*)::text || ' ' || min(status) || ' ' || (min(requested_by::text) = MARIA::text)::text into v
    from public.program_approvals where player_id = sam and program_id = elite;
  insert into _probe_result values ('a4b_and_marias_request_is_unchanged', '1 requested true', v);
  select count(*) into n from public.my_program_approvals();
  insert into _probe_result values ('a9b_another_member_sees_no_approvals', '0', n::text);
  begin
    select count(*) into n from public.admin_program_approvals();
    err := n::text;
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a5b_a_member_cannot_read_taras_list', 'not_authorized', err);
  perform set_config('request.jwt.claims', json_build_object('sub', CASEY)::text, true);
  begin
    select count(*) into n from public.admin_program_approvals();
    err := n::text;
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a5c_a_pro_cannot_read_taras_list', 'not_authorized', err);
  begin
    perform public.admin_decide_program_approval(sam, elite, true);
    err := 'decided';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a5d_a_pro_cannot_approve', 'not_authorized', err);
  select status || ' ' || coalesce(decided_by::text, 'undecided') into v
    from public.program_approvals where player_id = sam and program_id = elite;
  insert into _probe_result values ('a5e_and_the_request_is_still_open', 'requested undecided', v);

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  select string_agg(child_first_name || ' ' || child_last_name || '/' || parent_first_name || '/' || program_name || '/' || status,
                    ', ' order by child_first_name) into v
    from public.admin_program_approvals();
  insert into _probe_result values ('a5a_taras_list_names_child_parent_program',
    'Lily Probe/Maria/Junior Elite/requested, Samuel Probe/Maria/Elite/requested', v);
  select status into v from public.admin_decide_program_approval(sam, elite, true);
  insert into _probe_result values ('a6a_tara_approves', 'approved', v);
  select (decided_by = TARA and decided_at is not null)::text into v
    from public.program_approvals where player_id = sam and program_id = elite;
  insert into _probe_result values ('a6b_the_decision_records_who_and_when', 'true', v);
  begin
    perform public.admin_decide_program_approval(sam, elite, false);
    err := 'decided';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a6c_a_decided_request_is_not_decided_again', 'approval_already_decided', err);
  select status into v from public.program_approvals where player_id = sam and program_id = elite;
  insert into _probe_result values ('a6d_and_it_stays_approved', 'approved', v);
  select status into v from public.admin_decide_program_approval(lily, jr_elite, false);
  insert into _probe_result values ('a7a_tara_declines', 'declined', v);
  select status into v from public.admin_preapprove_program(lily, elite);
  insert into _probe_result values ('a8a_tara_preapproves_without_a_request', 'approved', v);
  select status into v from public.admin_preapprove_program(lily, jr_elite);
  insert into _probe_result values ('a8b_tara_can_approve_after_declining', 'approved', v);
  begin
    perform public.admin_preapprove_program(lily, red);
    err := 'approved';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a8c_red_dot_takes_no_approval', 'approval_not_needed', err);
  begin
    perform public.admin_preapprove_program(MARIA_P, elite);
    err := 'approved';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a8d_only_a_child_is_approved', 'child_not_found', err);

  -- A decline is final for the parent: Sam asks for Junior Elite, Tara says no.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform public.request_program_approval(sam, jr_elite);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform public.admin_decide_program_approval(sam, jr_elite, false);
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  begin
    perform public.request_program_approval(sam, jr_elite);
    err := 'requested';
  exception when others then err := sqlerrm;
  end;
  insert into _probe_result values ('a7b_a_declined_child_is_not_re_requested', 'approval_declined', err);
  select string_agg(child_first_name || '/' || program_name || '/' || status, ', ' order by child_first_name, program_name) into v
    from public.my_program_approvals();
  insert into _probe_result values ('a9a_the_parent_sees_each_childs_approvals',
    'Lily/Elite/approved, Lily/Junior Elite/approved, Samuel/Elite/approved, Samuel/Junior Elite/declined', v);

  -- ---------------------------------------------------------------- grants
  insert into _probe_result
  select 'g1_no_client_reads_' || t || '_directly', 'false',
         (has_table_privilege('authenticated', ('public.' || t)::regclass, 'SELECT')
          or has_table_privilege('anon', ('public.' || t)::regclass, 'SELECT'))::text
    from unnest(array['junior_programs', 'program_approvals', 'junior_waiver_acceptances']) t;
  insert into _probe_result values ('g2_the_signature_helper_is_internal', 'false',
    has_function_privilege('authenticated', 'public.junior_waiver_signed(uuid)', 'EXECUTE')::text);
end $$;

-- Phase 0 still holds: Maria's own read of players is her adult row only,
-- with three children on the account. Run as the client role.
do $$
declare n int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', '22222222-2222-2222-2222-222222222222')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.players;
  insert into _probe_result values ('c7_phase_0_still_holds_the_old_apps_read_the_adult_only', '1', n::text);
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
