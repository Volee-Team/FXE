-- past_clinics.sql
--
-- my_past_clinics (20260921000004): a player's own finished clinics, and
-- nothing else. Expected values from hard rule 1 (the nine hidden facts) and
-- from "own rows only", not from the view.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  FAR     constant uuid := 'd0000000-0000-0000-0000-000000000002';
  past uuid; n int; v text;
begin
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Played', 'ladies', 'Clinic', 'probe', now() - interval '3 days', now() - interval '3 days' + interval '1 hour',
          now() - interval '9 days', now() - interval '8 days', 8, 'published', 60)
  returning id into past;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, no_show) values
    (past, MARIA_P, 'in', 'self', 1800, true, 60, false),
    (past, KEN_P,   'in', 'self', 1800, true, 60, true),
    (FAR,  MARIA_P, 'in', 'self', 1800, true, 60, false);   -- still to come: not past

  -- 1. Maria sees her played clinic once, with her own outcome, and not the future one.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.my_past_clinics;
  insert into _probe_result values ('maria_sees_one_past_clinic', '1', n::text);
  select name || ' ' || status::text || ' ' || no_show::text || ' ' || price_cents_charged into v from public.my_past_clinics;
  insert into _probe_result values ('maria_row_is_her_own_outcome', 'Probe Played in false 1800', v);
  select count(*) into n from public.my_past_clinics where clinic_id = FAR;
  insert into _probe_result values ('future_clinic_not_past', '0', n::text);

  -- 2. Ken sees his own no-show, and never Maria's row (hidden fact 7 neighbour).
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  select count(*) || ' ' || bool_and(no_show)::text into v from public.my_past_clinics;
  insert into _probe_result values ('ken_sees_only_his_no_show', '1 true', v);
  perform set_config('role', 'postgres', true);

  -- 3. None of the nine hidden facts is a column of the view.
  select coalesce(string_agg(column_name, ', '), '') into v
    from information_schema.columns
   where table_name = 'my_past_clinics'
     and column_name in ('internal_capacity', 'court_number', 'location', 'address', 'player_id', 'canceled_by', 'cancel_note');
  insert into _probe_result values ('no_hidden_column', '', v);

  -- 4. Grants: select only, signed in only, not writable.
  insert into _probe_result values ('anon_cannot_read', 'false', has_table_privilege('anon', 'public.my_past_clinics', 'SELECT')::text);
  insert into _probe_result values ('authenticated_reads', 'true', has_table_privilege('authenticated', 'public.my_past_clinics', 'SELECT')::text);
  insert into _probe_result values ('authenticated_cannot_write', 'false',
    (has_table_privilege('authenticated', 'public.my_past_clinics', 'INSERT')
     or has_table_privilege('authenticated', 'public.my_past_clinics', 'UPDATE')
     or has_table_privilege('authenticated', 'public.my_past_clinics', 'DELETE'))::text);
end $$;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
