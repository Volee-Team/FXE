-- admin_clinic_crud.sql
--
-- Covers the RPCs that let Tara create and edit her own schedule
-- (20260826000001), and ATTACKS them.
--
-- These are the most powerful write RPCs in the system: they mint the rows
-- every registration hangs off, and they set the registration windows that
-- decide who gets a seat. A non-admin who could reach them could invent a
-- clinic, or move a window so their own registration lands first.
--
-- The positive assertions matter as much as the attacks. The bug being replaced
-- was not a crash, it was ABSENCE: nothing could create a clinic from any
-- client, so Tara's real schedule was unreachable except by hand-written SQL as
-- service role.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA_ACC  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA_ACC constant uuid := '22222222-2222-2222-2222-222222222222';
  WHEN_     constant timestamptz := '2026-09-15 08:00:00-04';
  LATER_    constant timestamptz := '2026-09-22 08:00:00-04';
  v_clinic  public.clinics;
  v_id      uuid;
  n         int;
  v_txt     text;
  v_int     int;
  v_tmpl    uuid;
begin
  -- ================================================================ ADMIN ====
  perform set_config('request.jwt.claims', json_build_object('sub', TARA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);

  v_clinic := public.admin_upsert_clinic(
    p_name => 'Probe Ladies 3.0+', p_audience => 'ladies',
    p_starts_at => WHEN_, p_duration_minutes => 60, p_internal_capacity => 8,
    p_description => 'Probe fixture.');
  v_id := v_clinic.id;

  insert into _probe_result values ('admin_can_create_a_clinic', 'true', (v_id is not null)::text);
  insert into _probe_result values ('new_clinic_starts_as_draft', 'draft', v_clinic.status::text);
  insert into _probe_result values ('ends_at_derived_from_duration', '60',
    ((extract(epoch from (v_clinic.ends_at - v_clinic.starts_at)) / 60)::int)::text);

  -- Decision 0001: the window is per SERVICE WEEK, so it must equal the helper
  -- exactly rather than being some offset from the clinic itself.
  insert into _probe_result values ('member_window_matches_week_rule',
    public.member_opens_at(WHEN_)::text, v_clinic.member_opens_at::text);
  insert into _probe_result values ('public_window_matches_week_rule',
    public.public_opens_at(WHEN_)::text, v_clinic.public_opens_at::text);
  insert into _probe_result values ('members_open_before_public', 'true',
    (v_clinic.member_opens_at < v_clinic.public_opens_at)::text);

  -- closes_at had never been populated by anything, so finished clinics stayed
  -- bookable and real Player Pool rows appeared for events already over.
  -- Tara, 2026-08-27: registration closes 3 hours before the clinic starts.
  -- Asserted as a duration, not a literal timestamp, so the check still reads
  -- as the rule when she moves the number (she expects to, after trial).
  insert into _probe_result values ('closes_at_is_set', 'true',
    (v_clinic.closes_at is not null)::text);
  insert into _probe_result values ('closes_3h_before_start', '3.0',
    round(extract(epoch from (v_clinic.starts_at - v_clinic.closes_at)) / 3600, 1)::text);
  insert into _probe_result values ('closes_before_it_starts', 'true',
    (v_clinic.closes_at < v_clinic.starts_at)::text);

  -- Prices are derived by trigger from length, never typed into a form, so a
  -- typo cannot undercharge the club.
  insert into _probe_result values ('member_price_derived', 'true',
    (v_clinic.member_price_cents > 0)::text);
  insert into _probe_result values ('nonmember_costs_more', 'true',
    (v_clinic.nonmember_price_cents > v_clinic.member_price_cents)::text);

  -- ------------------------------------------------------------------ edit
  -- One field changes; everything else must survive untouched.
  v_clinic := public.admin_upsert_clinic(p_id => v_id, p_internal_capacity => 12);
  insert into _probe_result values ('edit_changes_capacity', '12', v_clinic.internal_capacity::text);
  insert into _probe_result values ('edit_leaves_name_alone', 'Probe Ladies 3.0+', v_clinic.name);
  insert into _probe_result values ('edit_leaves_description_alone', 'Probe fixture.', v_clinic.description);

  -- Rescheduling must move the window with the clinic. Keeping last week's open
  -- time on a moved clinic is how a window ends up in the past.
  v_clinic := public.admin_upsert_clinic(p_id => v_id, p_starts_at => LATER_);
  insert into _probe_result values ('reschedule_moves_member_window',
    public.member_opens_at(LATER_)::text, v_clinic.member_opens_at::text);
  insert into _probe_result values ('reschedule_moves_close', '3.0',
    round(extract(epoch from (v_clinic.starts_at - v_clinic.closes_at)) / 3600, 1)::text);
  insert into _probe_result values ('reschedule_keeps_duration', '60',
    ((extract(epoch from (v_clinic.ends_at - v_clinic.starts_at)) / 60)::int)::text);

  -- An explicit override is allowed: her guide anticipates a clinic that needs
  -- a different date.
  v_clinic := public.admin_upsert_clinic(
    p_id => v_id, p_member_opens_at => '2026-09-01 08:00:00-04');
  insert into _probe_result values ('explicit_window_override_wins',
    '2026-09-01 08:00:00-04'::timestamptz::text, v_clinic.member_opens_at::text);

  -- Status is owned by publish_clinic / cancel_clinic, not by this form.
  insert into _probe_result values ('edit_cannot_change_status', 'draft', v_clinic.status::text);

  -- -------------------------------------------------------------- validation
  begin
    perform public.admin_upsert_clinic(p_name => '  ', p_audience => 'ladies',
      p_starts_at => WHEN_, p_duration_minutes => 60, p_internal_capacity => 8);
    insert into _probe_result values ('blank_name_rejected', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('blank_name_rejected', 'blocked', 'blocked');
  end;

  begin
    perform public.admin_upsert_clinic(p_name => 'Zero cap', p_audience => 'ladies',
      p_starts_at => WHEN_, p_duration_minutes => 60, p_internal_capacity => 0);
    insert into _probe_result values ('zero_capacity_rejected', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('zero_capacity_rejected', 'blocked', 'blocked');
  end;

  -- ---------------------------------------------------------------- templates
  perform public.admin_upsert_template(
    p_name => 'Probe Template', p_audience => 'coed',
    p_duration_minutes => 90, p_internal_capacity => 6);
  -- Read as postgres: clinic_templates is revoked from `authenticated` on
  -- purpose, so verifying the write has to step outside the caller's role.
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinic_templates where name = 'Probe Template';
  insert into _probe_result values ('admin_can_create_a_template', '1', n::text);
  select member_price_cents into v_int from public.clinic_templates where name = 'Probe Template';
  insert into _probe_result values ('template_price_derived_from_length', 'true', (v_int > 0)::text);
  perform set_config('role', 'authenticated', true);

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics where id = v_id;
  insert into _probe_result values ('clinic_really_exists_in_the_table', '1', n::text);
  perform set_config('role', 'authenticated', true);

  -- ====================================================== ATTACK: non-admin ==
  -- Maria is an ordinary member. Every one of these must fail, and the
  -- assertion is on the resulting ROW COUNT, not on whether an exception was
  -- raised: a write blocked by authorization can also affect zero rows quietly.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_upsert_clinic(
      p_name => 'ATTACKER CLINIC', p_audience => 'coed', p_starts_at => WHEN_,
      p_duration_minutes => 60, p_internal_capacity => 99);
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into v_int from public.clinics;
  insert into _probe_result values ('member_cannot_create_a_clinic', n::text, v_int::text);
  perform set_config('role', 'authenticated', true);

  -- Moving a window is the subtle attack: it decides who gets a seat.
  begin
    perform public.admin_upsert_clinic(
      p_id => v_id, p_member_opens_at => '2020-01-01 00:00:00-05');
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select (member_opens_at < '2021-01-01'::timestamptz) into v_txt
    from public.clinics where id = v_id;
  insert into _probe_result values ('member_cannot_move_the_window', 'false', coalesce(v_txt, 'ROW GONE'));
  perform set_config('role', 'authenticated', true);

  begin
    perform public.admin_upsert_clinic(p_id => v_id, p_internal_capacity => 999);
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select internal_capacity into v_int from public.clinics where id = v_id;
  insert into _probe_result values ('member_cannot_edit_capacity', '12', v_int::text);
  perform set_config('role', 'authenticated', true);

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinic_templates;
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_upsert_template(p_name => 'ATTACKER TEMPLATE',
      p_audience => 'coed', p_duration_minutes => 60, p_internal_capacity => 4);
  exception when others then null;
  end;
  begin
    -- The id has to be found as postgres; the point of the attack is the
    -- delete, not whether a member can list templates (they cannot).
    perform set_config('role', 'postgres', true);
    select id into v_tmpl from public.clinic_templates order by name limit 1;
    perform set_config('role', 'authenticated', true);
    perform public.admin_delete_template(v_tmpl);
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into v_int from public.clinic_templates;
  insert into _probe_result values ('member_cannot_touch_templates', n::text, v_int::text);
  perform set_config('role', 'authenticated', true);

  -- =========================================================== ATTACK: anon ==
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics;
  perform set_config('role', 'anon', true);
  begin
    perform public.admin_upsert_clinic(
      p_name => 'ANON CLINIC', p_audience => 'coed', p_starts_at => WHEN_,
      p_duration_minutes => 60, p_internal_capacity => 4);
    insert into _probe_result values ('anon_cannot_create_a_clinic', 'blocked', 'ACCEPTED');
  exception when others then
    insert into _probe_result values ('anon_cannot_create_a_clinic', 'blocked', 'blocked');
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into v_int from public.clinics;
  insert into _probe_result values ('anon_created_nothing', n::text, v_int::text);

  -- ------------------------------------------------------------- grants
  select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname like 'admin_%'
    and p.proname <> 'admin_account_ids'
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('anon_has_no_execute_on_admin_rpcs', '0', n::text);

  select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname in
        ('admin_upsert_clinic','admin_upsert_template','admin_delete_template')
    and p.prosecdef
    and exists (select 1 from unnest(coalesce(p.proconfig,'{}')) c where c like 'search_path=%');
  insert into _probe_result values ('admin_rpcs_are_definer_with_pinned_path', '3', n::text);
end $$;

select
  check_name,
  expected,
  actual,
  case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result
order by check_name;

rollback;
