-- review_responses.sql
--
-- Covers 20260921000010 and ATTACKS it: only Tara mints a review link, the
-- token is long and URL-safe, no client role can touch either table by any
-- verb, the edge function's role can, a repeat save on one (link, page
-- version) is one row with a fresh updated_at, Tara reads every response
-- back with its label, and revoking a link keeps what it collected.
--
-- Expected values are transcribed from the rule (the migration header and
-- the task), not from the code. Verified red first by dropping the
-- updated_at trigger: repeat_save_bumps_updated_at went FAIL.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon, service_role;

do $$
declare
  TARA  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  tok text; tok2 text; lbl text; n int; t1 timestamptz; t2 timestamptz; a jsonb;
begin
  -- ATTACK: Maria (a member) cannot mint a link
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_create_review_link('Maria tries');
    insert into _probe_result values ('member_cannot_create_link', '42501', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_create_link', '42501', sqlstate);
  end;
  begin
    perform public.admin_review_responses();
    insert into _probe_result values ('member_cannot_list_responses', '42501', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_list_responses', '42501', sqlstate);
  end;

  -- ATTACK: anon cannot mint a link
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'anon', true);
  begin
    perform public.admin_create_review_link('anon tries');
    insert into _probe_result values ('anon_cannot_create_link', 'blocked', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('anon_cannot_create_link', 'blocked', 'blocked');
  end;

  -- as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  tok := public.admin_create_review_link('  Tara, September  ');
  insert into _probe_result values ('token_is_at_least_24_chars', 'true', (length(tok) >= 24)::text);
  insert into _probe_result values ('token_is_url_safe', 'true', (tok ~ '^[A-Za-z0-9_-]+$')::text);
  tok2 := public.admin_create_review_link('second');
  insert into _probe_result values ('two_links_get_different_tokens', 'true', (tok <> tok2)::text);

  begin
    perform public.admin_create_review_link('   ');
    insert into _probe_result values ('blank_label_rejected', '22023', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('blank_label_rejected', '22023', sqlstate);
  end;

  select count(*) into n from public.admin_review_responses();
  insert into _probe_result values ('no_responses_before_any_save', '0', n::text);

  -- as the edge function (service_role): the only writer of responses
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'service_role', true);

  select label into lbl from public.review_links where token = tok;
  insert into _probe_result values ('label_stored_trimmed', 'Tara, September', lbl);

  insert into public.review_responses (token, page_version, answers)
  values (tok, 'v1', '{"w0-0": {"choice": "keep"}}'::jsonb);
  select updated_at into t1 from public.review_responses where token = tok and page_version = 'v1';

  perform pg_sleep(0.01);
  insert into public.review_responses (token, page_version, answers)
  values (tok, 'v1', '{"w0-0": {"choice": "change", "alt": "her words"}}'::jsonb)
  on conflict (token, page_version) do update set answers = excluded.answers;

  select count(*) into n from public.review_responses where token = tok and page_version = 'v1';
  insert into _probe_result values ('repeat_save_is_one_row', '1', n::text);
  select answers, updated_at into a, t2 from public.review_responses where token = tok and page_version = 'v1';
  insert into _probe_result values ('repeat_save_replaces_answers', 'her words', a #>> '{w0-0,alt}');
  insert into _probe_result values ('repeat_save_bumps_updated_at', 'later', case when t2 > t1 then 'later' else 'NOT BUMPED' end);

  insert into public.review_responses (token, page_version, answers) values (tok, 'v2', '{}'::jsonb);
  select count(*) into n from public.review_responses where token = tok;
  insert into _probe_result values ('new_page_version_is_its_own_row', '2', n::text);

  begin
    insert into public.review_responses (token, page_version, answers) values ('not-a-minted-token', 'v1', '{}'::jsonb);
    insert into _probe_result values ('unminted_token_cannot_hold_answers', '23503', 'INSERT SUCCEEDED');
  exception when others then
    insert into _probe_result values ('unminted_token_cannot_hold_answers', '23503', sqlstate);
  end;

  -- as Tara again: she reads it all back, with the label
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  select count(*) into n from public.admin_review_responses() r where r.token = tok;
  insert into _probe_result values ('admin_reads_both_versions_back', '2', n::text);
  select r.label into lbl from public.admin_review_responses() r where r.token = tok and r.page_version = 'v1';
  insert into _probe_result values ('response_carries_its_label', 'Tara, September', lbl);
  select r.answers into a from public.admin_review_responses() r where r.token = tok and r.page_version = 'v1';
  insert into _probe_result values ('admin_reads_latest_answers', 'her words', a #>> '{w0-0,alt}');
  select r.page_version into lbl from public.admin_review_responses() r limit 1;
  insert into _probe_result values ('newest_response_listed_first', 'v2', lbl);

  -- Revoking a link (revoked_at, set by whoever holds service_role or by a
  -- migration) stops new saves at the edge function; it never discards
  -- answers (hard rule 4).
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'service_role', true);
  update public.review_links set revoked_at = now() where token = tok;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.admin_review_responses() r where r.token = tok;
  insert into _probe_result values ('revoked_link_keeps_its_responses', '2', n::text);

  perform set_config('role', 'postgres', true);

  -- ---------------------------------------------------- privilege surface
  -- Enumerate what each client role holds on the two tables. The rule is
  -- "nothing", so the expected string is empty.
  insert into _probe_result
  select r || '_holds_nothing_on_review_tables', '',
         coalesce(string_agg(t || ':' || lower(p), ', ' order by t, p), '')
  from unnest(array['anon', 'authenticated']) as r
  cross join unnest(array['review_links', 'review_responses']) as t
  cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) as p
  where has_table_privilege(r, ('public.' || t)::regclass, p)
  group by r;
  insert into _probe_result
  select r || '_holds_nothing_on_review_tables', '', ''
  from unnest(array['anon', 'authenticated']) as r
  where not exists (
    select 1 from unnest(array['review_links', 'review_responses']) as t
    cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) as p
    where has_table_privilege(r, ('public.' || t)::regclass, p));

  insert into _probe_result values ('service_role_can_read_write_responses', 'true',
    (has_table_privilege('service_role', 'public.review_responses'::regclass, 'SELECT')
     and has_table_privilege('service_role', 'public.review_responses'::regclass, 'INSERT')
     and has_table_privilege('service_role', 'public.review_responses'::regclass, 'UPDATE'))::text);
  insert into _probe_result values ('service_role_can_read_links', 'true',
    has_table_privilege('service_role', 'public.review_links'::regclass, 'SELECT')::text);

  select count(*) into n from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public' and c.relname in ('review_links', 'review_responses') and c.relrowsecurity;
  insert into _probe_result values ('rls_enabled_on_both_tables', '2', n::text);

  select count(*) into n from pg_policies where schemaname = 'public' and tablename in ('review_links', 'review_responses');
  insert into _probe_result values ('no_policies_admit_any_client', '0', n::text);

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname in ('admin_create_review_link', 'admin_review_responses')
    and (has_function_privilege('anon', p.oid, 'EXECUTE')
         or p.proacl is null
         or exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0 and x.privilege_type = 'EXECUTE'));
  insert into _probe_result values ('anon_and_public_cannot_execute_review_rpcs', '0', n::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
