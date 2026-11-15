-- Every privilege a client role holds in schema public, one line each, sorted.
-- Run against hosted (scripts/hosted-read.sh) and against a database built
-- fresh from the migrations; scripts/check-hosted-grants.sh diffs the two.
-- A line on hosted and not locally is a grant no migration wrote (2026-11-14:
-- MAINTAIN and writes on news_reads, found by a docs audit, invisible to every
-- probe because probes only ever see fresh databases).
-- Covers relations, columns, functions, the schema itself, membership in the
-- built-in roles that grant everything without appearing in an ACL, default
-- privileges, and relations not owned by postgres.
select line from (
  select 'rel ' || c.relkind::text || ' ' || c.relname || ' ' || coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') || ' ' || a.privilege_type as line
  from pg_class c cross join lateral aclexplode(c.relacl) a
  where c.relnamespace = 'public'::regnamespace
    and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole))
  union all
  select 'col ' || c.relname || '.' || att.attname || ' ' || coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') || ' ' || a.privilege_type
  from pg_attribute att join pg_class c on c.oid = att.attrelid
  cross join lateral aclexplode(att.attacl) a
  where c.relnamespace = 'public'::regnamespace and not att.attisdropped
    and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole))
  union all
  select 'fn ' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ') ' || coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') || ' ' || a.privilege_type
  from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.pronamespace = 'public'::regnamespace
    and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole))
  union all
  select 'schema public ' || coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') || ' ' || a.privilege_type
  from pg_namespace n cross join lateral aclexplode(n.nspacl) a
  where n.nspname = 'public' and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole))
  union all
  select 'member ' || r || ' ' || b
  from unnest(array['anon', 'authenticated']) r, unnest(array['pg_maintain', 'pg_read_all_data', 'pg_write_all_data']) b
  where pg_has_role(r, b, 'member')
  union all
  select 'default ' || d.defaclrole::regrole || ' ' || d.defaclobjtype::text || ' ' || coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC') || ' ' || a.privilege_type
  from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
  where d.defaclrole = 'postgres'::regrole
    and (d.defaclnamespace = 0 or d.defaclnamespace = 'public'::regnamespace)
    and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole))
  union all
  select 'owner ' || relkind::text || ' ' || relname || ' ' || relowner::regrole
  from pg_class
  where relnamespace = 'public'::regnamespace and relkind in ('r','v','m','p','f','S')
    and relowner <> 'postgres'::regrole
) s order by line
