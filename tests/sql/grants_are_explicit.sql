-- grants_are_explicit.sql
--
-- Asserts the PRIVILEGE SURFACE of the whole schema, by enumerating it rather
-- than by naming the objects we happen to remember.
--
-- Origin: 2026-08-16. Upgrading the local Supabase CLI 2.90.0 -> 2.115.0 took
-- `authenticated`'s SELECT on `accounts` and `players` away, because the app
-- had never been granted it: it was inherited from Supabase's bootstrap
-- defaults and every migration since had only revoked from that pile. The whole
-- app broke for every signed-in user, and the same failure had been red in CI
-- for days while the laptop stayed green on the older pinned CLI.
--
-- WHY ENUMERATE. Every other probe here asserts named objects, which can only
-- ever catch problems in the objects someone thought to name. That is the same
-- blind spot as hard rule 9 one level up: `information_hiding.sql` tested the
-- read surface it knew about and could not see a write path through it. So this
-- probe walks `pg_class` and asks a question of EVERY relation in `public`,
-- which means a table added next month is covered before anyone remembers to
-- add it here.
--
-- Two directions, both of which have now bitten this project:
--   TOO WIDE  — anon holding write privileges it was never granted (2026-08-13,
--               anon could delete every clinic through an auto-updatable view).
--   TOO NARROW — the app losing a read it never wrote down (2026-08-16, this).
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;

-- ----------------------------------------------------- what the app must have
-- The client reads these directly. If any loses its grant the app is broken for
-- every user, silently, because loadProfile swallows the error.
insert into _probe_result
select 'app_can_read_' || t.relname,
       'true',
       has_table_privilege('authenticated', ('public.' || t.relname)::regclass, 'SELECT')::text
from (values ('accounts'), ('players'), ('app_settings'),
             ('clinics_public'), ('my_registrations'), ('my_clinic_messages'),
             ('my_news'), ('clinics_admin'), ('registrations_admin')) as t(relname);

-- A player edits their own contact details. Column-scoped: `role` and `email`
-- are deliberately absent, per hard rule 8.
insert into _probe_result
select 'app_can_edit_own_' || c,
       'true',
       has_column_privilege('authenticated', 'public.accounts'::regclass, c, 'UPDATE')::text
from unnest(array['first_name', 'last_name', 'phone']) as c;

insert into _probe_result
select 'account_' || c || '_is_NOT_self_writable',
       'false',
       has_column_privilege('authenticated', 'public.accounts'::regclass, c, 'UPDATE')::text
from unnest(array['role', 'email', 'id']) as c;

-- ------------------------------------------------- anon holds nothing at all
-- Enumerated, not listed. anon is the publishable key shipped inside the iOS
-- binary; before sign-in it should be able to touch nothing in this schema.
-- TRUNCATE/REFERENCES/TRIGGER are included deliberately: TRUNCATE is a delete
-- with a different name.
insert into _probe_result
select 'anon_has_no_' || lower(p) || '_anywhere',
       '',
       coalesce(string_agg(c.relname, ', ' order by c.relname), '')
from unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) as p
cross join pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where c.relkind in ('r','v')
  and has_table_privilege('anon', c.oid, p)
group by p;

-- string_agg over zero rows yields no row at all, so a privilege anon holds
-- nowhere produces no assertion rather than a passing one. That is the
-- zero-assertions failure mode the harness was already bitten by in 2026-08-10,
-- reappearing inside a probe. Emit the passing rows explicitly.
insert into _probe_result
select 'anon_has_no_' || lower(p) || '_anywhere', '', ''
from unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) as p
where not exists (
  select 1 from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
  where c.relkind in ('r','v') and has_table_privilege('anon', c.oid, p)
);

-- --------------------------------------------- authenticated writes nothing
-- Every legitimate write goes through a SECURITY DEFINER RPC, which runs as its
-- owner and needs no caller grant. So a table-level write grant on a base table
-- is by definition a hole: it is a path that skips the RPC's authorization,
-- its capacity check, and its price snapshot.
--
-- accounts is excluded because its UPDATE is column-scoped and asserted above.
insert into _probe_result
select 'authenticated_cannot_' || lower(p) || '_base_tables',
       '',
       coalesce(string_agg(c.relname, ', ' order by c.relname), '')
from unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) as p
cross join pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where c.relkind = 'r'
  and c.relname <> 'accounts'
  and has_table_privilege('authenticated', c.oid, p)
group by p;

insert into _probe_result
select 'authenticated_cannot_' || lower(p) || '_base_tables', '', ''
from unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) as p
where not exists (
  select 1 from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
  where c.relkind = 'r' and c.relname <> 'accounts'
    and has_table_privilege('authenticated', c.oid, p)
);

-- ------------------------------------------------------- views stay read-only
-- The 2026-08-13 hole in one assertion: a view that is auto-updatable AND
-- carries a write grant is an RLS bypass, because a view without
-- security_invoker executes as its owner.
insert into _probe_result
select 'no_writable_auto_updatable_views',
       '',
       coalesce(string_agg(v.table_name, ', ' order by v.table_name), '')
from information_schema.views v
where v.table_schema = 'public'
  and v.is_updatable = 'YES'
  and (has_table_privilege('authenticated', ('public.' || v.table_name)::regclass, 'UPDATE')
    or has_table_privilege('anon',          ('public.' || v.table_name)::regclass, 'UPDATE'));

insert into _probe_result
select 'no_writable_auto_updatable_views', '', ''
where not exists (
  select 1 from information_schema.views v
  where v.table_schema = 'public' and v.is_updatable = 'YES'
    and (has_table_privilege('authenticated', ('public.' || v.table_name)::regclass, 'UPDATE')
      or has_table_privilege('anon',          ('public.' || v.table_name)::regclass, 'UPDATE'))
);

-- --------------------------------------------- SECURITY DEFINER search_path
-- An unpinned search_path on a SECURITY DEFINER function lets a caller who can
-- create objects shadow a table name and have it run as the owner.
insert into _probe_result
select 'all_definer_functions_pin_search_path',
       '',
       coalesce(string_agg(p.proname, ', ' order by p.proname), '')
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
where p.prosecdef
  and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');

insert into _probe_result
select 'all_definer_functions_pin_search_path', '', ''
where not exists (
  select 1 from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
  where p.prosecdef
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
);

select
  check_name,
  expected,
  actual,
  case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result
order by check_name;

rollback;
