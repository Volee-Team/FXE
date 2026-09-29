-- message_templates.sql
--
-- Covers 20260928900001 (decision 0030): Tara's saved messages, and ATTACKS
-- them. Written from the rule, not from the code (CLAUDE.md, "Write the probe
-- from the rule"):
--
--   * Tara alone lists, saves and removes them. A member is refused by all
--     three and changes nothing, and so is every other role that is not admin:
--     the loop reads account_role, so the pro role (branch pro-role) is
--     attacked the day it exists. anon and PUBLIC hold no EXECUTE and no
--     client role holds any privilege on the table; anon is asserted by
--     privilege, never by calling a function (CLAUDE.md, "Known
--     local-environment defect").
--   * The same text saved twice is one live row, whatever whitespace sits at
--     its ends; nothing inside the text is changed (a different case is a
--     different message). After a Remove, the same words saved again are a new
--     live row and the removed one stays (hard rule 4).
--   * Remove stamps archived_at once: the row is kept, it leaves the list, and
--     a second Remove answers false and keeps the first stamp.
--   * A body is 1 to 1000 characters after trimming. Empty, blank, null and
--     1001 are refused and write nothing; 1000 accented characters (1968
--     bytes) are kept, so the limit counts characters, as the clients do. The
--     table's own check refuses a blank or untrimmed body from any writer.
--   * The list is live rows only, newest first.
--
-- "Kept once" when two saves land at the same moment cannot be seen from one
-- session: message_template_race.sh.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  ROB   constant uuid := '44444444-4444-4444-4444-444444444444';
  -- Unique per run, so rows left by a browser test or an earlier run cannot
  -- collide with these (every count below is by body or by id).
  tag   constant text := replace(gen_random_uuid()::text, '-', '');
  txt_a text; txt_b text; txt_c text;
  ra  public.message_templates;   -- A
  rb  public.message_templates;   -- B
  rl  public.message_templates;   -- lower(A)
  ra2 public.message_templates;   -- A again, after its Remove
  rx  public.message_templates;
  role_row record;
  v_bool  boolean;
  v_text  text;
  v_state text;
  n  int;
  n0 int;
  v_refused int;
  roles_tried   text := '';
  roles_refused text := '';
begin
  txt_a := 'Probe saved message A ' || tag;
  txt_b := 'Probe saved message B ' || tag;
  txt_c := 'Probe saved message C ' || tag;

  -- ------------------------------------------------------------- as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  -- Whitespace at the two ends is not part of her words.
  ra := public.admin_save_message_template(E'  \n' || txt_a || E' \t\r\n');
  insert into _probe_result values ('save_keeps_the_text_trimmed_at_its_ends', txt_a, ra.body);

  rx := public.admin_save_message_template(txt_a);
  insert into _probe_result values ('same_text_again_is_the_same_row', 'same',
    case when rx.id = ra.id then 'same' else 'DIFFERENT ROW' end);
  rx := public.admin_save_message_template(txt_a || E'\n\n');
  insert into _probe_result values ('same_text_other_whitespace_is_the_same_row', 'same',
    case when rx.id = ra.id then 'same' else 'DIFFERENT ROW' end);

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.message_templates where body = txt_a;
  insert into _probe_result values ('same_text_saved_three_times_is_one_row', '1', n::text);
  perform set_config('role', 'authenticated', true);

  rb := public.admin_save_message_template(txt_b);
  insert into _probe_result values ('a_different_text_is_a_second_row', 'different',
    case when rb.id <> ra.id then 'different' else 'SAME ROW' end);
  -- Nothing inside the text is changed, case included.
  rl := public.admin_save_message_template(lower(txt_a));
  insert into _probe_result values ('a_different_case_is_a_different_message', lower(txt_a) || ' / different',
    rl.body || ' / ' || case when rl.id <> ra.id then 'different' else 'SAME ROW' end);

  -- Newest first. All three were saved in this one transaction, so now()
  -- ties; give them times in insertion order, oldest first, so that heap
  -- order and an oldest-first sort both read differently from the rule.
  perform set_config('role', 'postgres', true);
  update public.message_templates set created_at = now() - interval '3 hours' where id = ra.id;
  update public.message_templates set created_at = now() - interval '2 hours' where id = rb.id;
  update public.message_templates set created_at = now() - interval '1 hour'  where id = rl.id;
  perform set_config('role', 'authenticated', true);
  select string_agg(case t.id when ra.id then 'A' when rb.id then 'B' else 'a' end, ' ' order by t.ordinality)
    into v_text
    from public.admin_message_templates() with ordinality as t
   where t.id in (ra.id, rb.id, rl.id);
  insert into _probe_result values ('the_list_is_newest_first', 'a B A', coalesce(v_text, 'EMPTY'));

  -- Remove archives: true, gone from the list, the row kept with its stamp.
  v_bool := public.admin_archive_message_template(ra.id);
  insert into _probe_result values ('remove_answers_true', 'true', coalesce(v_bool::text, 'NULL'));
  select count(*) into n from public.admin_message_templates() t where t.id = ra.id;
  insert into _probe_result values ('a_removed_message_leaves_the_list', '0', n::text);
  select count(*) into n from public.admin_message_templates() t where t.id in (rb.id, rl.id);
  insert into _probe_result values ('the_others_stay_on_the_list', '2', n::text);

  perform set_config('role', 'postgres', true);
  select case when archived_at is null then 'live' else 'kept, stamped' end
    into v_state from public.message_templates where id = ra.id;
  insert into _probe_result values ('a_removed_row_is_kept_with_a_stamp', 'kept, stamped', coalesce(v_state, 'GONE'));
  -- Backdate the stamp, so a second stamp would show.
  update public.message_templates set archived_at = timestamptz '2026-01-01 12:00+00' where id = ra.id;
  perform set_config('role', 'authenticated', true);

  v_bool := public.admin_archive_message_template(ra.id);
  insert into _probe_result values ('a_second_remove_answers_false', 'false', coalesce(v_bool::text, 'NULL'));
  perform set_config('role', 'postgres', true);
  select archived_at::text into v_text from public.message_templates where id = ra.id;
  insert into _probe_result values ('a_second_remove_keeps_the_first_stamp',
    (timestamptz '2026-01-01 12:00+00')::text, coalesce(v_text, 'GONE'));
  perform set_config('role', 'authenticated', true);

  -- The same words after a Remove: a new live row; the removed one stays.
  ra2 := public.admin_save_message_template(txt_a);
  insert into _probe_result values ('saving_removed_words_again_is_a_new_row', 'new',
    case when ra2.id <> ra.id then 'new' else 'THE REMOVED ROW' end);
  perform set_config('role', 'postgres', true);
  select count(*) filter (where archived_at is null) || ' live, '
      || count(*) filter (where archived_at is not null) || ' removed'
    into v_text from public.message_templates where body = txt_a;
  insert into _probe_result values ('the_removed_copy_stays_beside_the_new_one', '1 live, 1 removed', v_text);
  perform set_config('role', 'authenticated', true);

  begin
    perform public.admin_archive_message_template('00000000-0000-0000-0000-00000000dead');
    insert into _probe_result values ('an_unknown_id_is_not_found', 'P0002', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('an_unknown_id_is_not_found', 'P0002', sqlstate);
  end;

  -- ------------------------------------------------------------ the limit
  perform set_config('role', 'postgres', true);
  select count(*) into n0 from public.message_templates;
  perform set_config('role', 'authenticated', true);

  begin
    perform public.admin_save_message_template('');
    insert into _probe_result values ('an_empty_body_is_refused', '22023', 'KEPT');
  exception when others then
    insert into _probe_result values ('an_empty_body_is_refused', '22023', sqlstate);
  end;
  begin
    perform public.admin_save_message_template(E'  \n\t\r  ');
    insert into _probe_result values ('a_blank_body_is_refused', '22023', 'KEPT');
  exception when others then
    insert into _probe_result values ('a_blank_body_is_refused', '22023', sqlstate);
  end;
  begin
    perform public.admin_save_message_template(null);
    insert into _probe_result values ('a_null_body_is_refused', '22023', 'KEPT');
  exception when others then
    insert into _probe_result values ('a_null_body_is_refused', '22023', sqlstate);
  end;
  begin
    perform public.admin_save_message_template(left(tag || repeat('x', 1001), 1001));
    insert into _probe_result values ('a_1001_character_body_is_refused', '22001', 'KEPT');
  exception when others then
    insert into _probe_result values ('a_1001_character_body_is_refused', '22001', sqlstate);
  end;
  begin
    perform public.admin_save_message_template(left(tag || repeat(chr(233), 1001), 1001));
    insert into _probe_result values ('a_1001_accented_character_body_is_refused', '22001', 'KEPT');
  exception when others then
    insert into _probe_result values ('a_1001_accented_character_body_is_refused', '22001', sqlstate);
  end;

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.message_templates;
  insert into _probe_result values ('the_refusals_wrote_nothing', n0::text, n::text);
  perform set_config('role', 'authenticated', true);

  -- The edge itself is kept: 1000 characters, with whitespace around them
  -- that does not count, and 1000 accented characters (1968 bytes).
  begin
    rx := public.admin_save_message_template(E'\n ' || left(tag || repeat('x', 1000), 1000) || E' \n');
    insert into _probe_result values ('a_1000_character_body_is_kept', '1000', length(rx.body)::text);
  exception when others then
    insert into _probe_result values ('a_1000_character_body_is_kept', '1000', 'REFUSED ' || sqlstate);
  end;
  begin
    rx := public.admin_save_message_template(left(tag || repeat(chr(233), 1000), 1000));
    insert into _probe_result values ('a_1000_accented_character_body_is_kept', '1000 characters, 1968 bytes',
      length(rx.body) || ' characters, ' || octet_length(rx.body) || ' bytes');
  exception when others then
    insert into _probe_result values ('a_1000_accented_character_body_is_kept', '1000 characters, 1968 bytes', 'REFUSED ' || sqlstate);
  end;

  -- ------------------------------------ the table's own rules, any writer
  perform set_config('role', 'postgres', true);
  begin
    insert into public.message_templates (body) values (E'\n');
    insert into _probe_result values ('the_table_refuses_a_newline_body', '23514', 'INSERTED');
  exception when others then
    insert into _probe_result values ('the_table_refuses_a_newline_body', '23514', sqlstate);
  end;
  begin
    insert into public.message_templates (body) values (' ' || txt_c);
    insert into _probe_result values ('the_table_refuses_an_untrimmed_body', '23514', 'INSERTED');
  exception when others then
    insert into _probe_result values ('the_table_refuses_an_untrimmed_body', '23514', sqlstate);
  end;
  begin
    insert into public.message_templates (body) values (txt_b);
    insert into _probe_result values ('the_table_refuses_a_second_live_copy', '23505', 'INSERTED');
  exception when others then
    insert into _probe_result values ('the_table_refuses_a_second_live_copy', '23505', sqlstate);
  end;

  -- ------------------------------------------------------ ATTACK: Maria
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);

  begin
    perform count(*) from public.admin_message_templates();
    insert into _probe_result values ('a_member_cannot_list_them', '42501', 'READ');
  exception when others then
    insert into _probe_result values ('a_member_cannot_list_them', '42501', sqlstate);
  end;
  begin
    perform public.admin_save_message_template(txt_c);
    insert into _probe_result values ('a_member_cannot_save_one', '42501', 'SAVED');
  exception when others then
    insert into _probe_result values ('a_member_cannot_save_one', '42501', sqlstate);
  end;
  begin
    perform public.admin_archive_message_template(rb.id);
    insert into _probe_result values ('a_member_cannot_remove_one', '42501', 'REMOVED');
  exception when others then
    insert into _probe_result values ('a_member_cannot_remove_one', '42501', sqlstate);
  end;
  -- Around the functions: no privilege, so each statement is refused outright.
  begin
    perform count(*) from public.message_templates;
    insert into _probe_result values ('a_member_cannot_read_the_table', '42501', 'READ');
  exception when others then
    insert into _probe_result values ('a_member_cannot_read_the_table', '42501', sqlstate);
  end;
  begin
    insert into public.message_templates (body) values (txt_c);
    insert into _probe_result values ('a_member_cannot_insert_into_the_table', '42501', 'INSERTED');
  exception when others then
    insert into _probe_result values ('a_member_cannot_insert_into_the_table', '42501', sqlstate);
  end;
  begin
    update public.message_templates set archived_at = now() where id = rb.id;
    insert into _probe_result values ('a_member_cannot_update_the_table', '42501', 'UPDATED');
  exception when others then
    insert into _probe_result values ('a_member_cannot_update_the_table', '42501', sqlstate);
  end;

  -- ------------------------------------ ATTACK: every role that is not admin
  -- Read from the enum, never listed: a role added later is attacked the day
  -- it exists. Tara moves Rob to each (the guard trigger lets only an admin
  -- change a role); then Rob tries all three.
  for role_row in
    select e.enumlabel as label
      from pg_enum e
     where e.enumtypid = 'public.account_role'::regtype and e.enumlabel <> 'admin'
     order by e.enumsortorder
  loop
    roles_tried := roles_tried || role_row.label || ' ';
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
    begin
      update public.accounts set role = role_row.label::public.account_role where id = ROB;
    exception when others then
      roles_tried := roles_tried || '(could not set ' || role_row.label || ': ' || sqlstate || ') ';
      continue;
    end;
    perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
    perform set_config('role', 'authenticated', true);
    v_refused := 0;
    begin
      perform count(*) from public.admin_message_templates();
    exception when others then
      if sqlstate = '42501' then v_refused := v_refused + 1; end if;
    end;
    begin
      perform public.admin_save_message_template(txt_c || ' ' || role_row.label);
    exception when others then
      if sqlstate = '42501' then v_refused := v_refused + 1; end if;
    end;
    begin
      perform public.admin_archive_message_template(rb.id);
    exception when others then
      if sqlstate = '42501' then v_refused := v_refused + 1; end if;
    end;
    if v_refused = 3 then
      roles_refused := roles_refused || role_row.label || ' ';
    end if;
  end loop;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('every_non_admin_role_is_refused_all_three', roles_tried, roles_refused);
  insert into _probe_result values ('at_least_one_non_admin_role_was_attacked', 'true', (roles_tried <> '')::text);

  -- The state after every attack (hard rule 9: the outcome, not the error).
  select count(*) into n from public.message_templates where body like txt_c || '%';
  insert into _probe_result values ('the_attacks_wrote_nothing', '0', n::text);
  select case when archived_at is null then 'live' else 'REMOVED' end
    into v_state from public.message_templates where id = rb.id;
  insert into _probe_result values ('the_attacks_removed_nothing', 'live', coalesce(v_state, 'GONE'));

  -- ------------------------------------------------------------ ATTACK: anon
  -- The table only: a function call as anon is asserted by privilege below.
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'anon', true);
  begin
    perform count(*) from public.message_templates;
    insert into _probe_result values ('anon_cannot_read_the_table', '42501', 'READ');
  exception when others then
    insert into _probe_result values ('anon_cannot_read_the_table', '42501', sqlstate);
  end;
  perform set_config('role', 'postgres', true);

  -- -------------------------------------------------------- grant surface
  select relrowsecurity::text into v_text from pg_class where oid = 'public.message_templates'::regclass;
  insert into _probe_result values ('rls_is_on', 'true', v_text);

  select coalesce(string_agg(g.r || ':' || g.p, ', ' order by g.r, g.p), '') into v_text
    from (select r, p
            from unnest(array['anon', 'authenticated']) r
            cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p
           where has_table_privilege(r, 'public.message_templates', p)) g;
  insert into _probe_result values ('no_client_role_holds_a_table_privilege', '', v_text);

  select coalesce(string_agg(g.r || ':' || g.p, ', ' order by g.r, g.p), '') into v_text
    from (select r, p
            from unnest(array['anon', 'authenticated']) r
            cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'REFERENCES']) p
           where has_any_column_privilege(r, 'public.message_templates', p)) g;
  insert into _probe_result values ('no_client_role_holds_a_column_privilege', '', v_text);

  select count(*) into n
    from pg_class c, aclexplode(c.relacl) a
   where c.oid = 'public.message_templates'::regclass and a.grantee = 0;
  insert into _probe_result values ('public_holds_nothing_on_the_table', '0', n::text);

  insert into _probe_result values ('service_role_holds_dml', 'true',
    (has_table_privilege('service_role', 'public.message_templates', 'SELECT')
     and has_table_privilege('service_role', 'public.message_templates', 'INSERT')
     and has_table_privilege('service_role', 'public.message_templates', 'UPDATE')
     and has_table_privilege('service_role', 'public.message_templates', 'DELETE'))::text);

  -- By name, so an overload added later with the same name is counted too.
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('admin_message_templates', 'admin_save_message_template', 'admin_archive_message_template')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('anon_executes_none_of_them', '0', n::text);

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('admin_message_templates', 'admin_save_message_template', 'admin_archive_message_template')
     and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a
                                       where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  insert into _probe_result values ('public_executes_none_of_them', '0', n::text);

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('admin_message_templates', 'admin_save_message_template', 'admin_archive_message_template')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and p.prosecdef
     and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  insert into _probe_result values ('all_three_callable_signed_in_definer_and_pinned', '3', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
