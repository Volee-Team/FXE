-- player_directory.sql
--
-- Covers 20260902000002: private notes and membership correction, and ATTACKS
-- them. Notes are one of the nine hidden facts (information_hiding.sql check
-- 7), so the interesting assertions are the ones where a player tries to read
-- their own note through the new function, and the one where a member tries
-- to promote themselves to member pricing.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA   constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA  constant uuid := '22222222-2222-2222-2222-222222222222';
  ROB    constant uuid := '44444444-4444-4444-4444-444444444444';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  v_text  text;
  v_bool  boolean;
  n       int;
begin
  -- ------------------------------------------------------------ as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  -- Seed gives Maria a note already.
  v_text := public.admin_player_note(MARIA_P);
  insert into _probe_result values ('admin_reads_existing_note', 'true', (v_text <> '')::text);

  v_text := public.admin_player_note(ROB_P);
  insert into _probe_result values ('admin_reads_missing_note_as_empty', '', v_text);

  perform public.admin_set_player_note(ROB_P, '  Left-handed. Prefers court 2.  ');
  v_text := public.admin_player_note(ROB_P);
  insert into _probe_result values ('admin_note_saved_and_trimmed', 'Left-handed. Prefers court 2.', v_text);

  -- Saving blank removes the row, so search_players.has_notes stays honest.
  perform public.admin_set_player_note(ROB_P, '   ');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.player_notes where player_id = ROB_P;
  insert into _probe_result values ('blank_note_deletes_row', '0', n::text);
  perform set_config('role', 'authenticated', true);

  select has_notes into v_bool from public.search_players('Rob', false);
  insert into _probe_result values ('has_notes_false_after_blank', 'false', v_bool::text);

  -- Membership correction: Rob signed up as a non-member.
  perform public.admin_set_membership(ROB_P, true);
  perform set_config('role', 'postgres', true);
  select is_member into v_bool from public.players where id = ROB_P;
  insert into _probe_result values ('admin_corrects_membership', 'true', v_bool::text);
  perform set_config('role', 'authenticated', true);

  begin
    perform public.admin_set_player_note('00000000-0000-0000-0000-00000000dead', 'x');
    insert into _probe_result values ('unknown_player_rejected', 'P0002', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('unknown_player_rejected', 'P0002', sqlstate);
  end;

  -- ------------------------------------------------------ ATTACK: as Maria
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);

  -- Her OWN note is hidden from her (hidden fact 7).
  begin
    v_text := public.admin_player_note(MARIA_P);
    insert into _probe_result values ('member_cannot_read_own_note', 'blocked', 'READ: ' || v_text);
  exception when others then
    insert into _probe_result values ('member_cannot_read_own_note', 'blocked', 'blocked');
  end;

  begin
    perform public.admin_set_player_note(MARIA_P, 'I am great');
    insert into _probe_result values ('member_cannot_write_own_note', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_write_own_note', 'blocked', 'blocked');
  end;

  -- Rob is a non-member as far as Maria is concerned; she cannot promote him,
  -- and (the one that matters for money) cannot promote herself.
  begin
    perform public.admin_set_membership(MARIA_P, true);
    insert into _probe_result values ('member_cannot_set_own_membership', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_set_own_membership', 'blocked', 'blocked');
  end;

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.player_notes where body = 'I am great';
  insert into _probe_result values ('no_note_written_by_member', '0', n::text);

  -- -------------------------------------------------------- ATTACK: anon
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'anon', true);
  begin
    v_text := public.admin_player_note(MARIA_P);
    insert into _probe_result values ('anon_cannot_read_notes', 'blocked', 'READ');
  exception when others then
    insert into _probe_result values ('anon_cannot_read_notes', 'blocked', 'blocked');
  end;
  perform set_config('role', 'postgres', true);

  -- ---------------------------------------------------------- grant surface
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
    and p.proname in ('admin_player_note', 'admin_set_player_note', 'admin_set_membership')
    and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('anon_has_no_execute_on_directory_rpcs', '0', n::text);

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
    and p.proname in ('admin_player_note', 'admin_set_player_note', 'admin_set_membership')
    and p.proconfig is not null
    and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  insert into _probe_result values ('directory_rpcs_pin_search_path', '3', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
