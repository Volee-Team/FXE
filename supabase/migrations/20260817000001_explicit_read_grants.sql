-- Write down the grants the app has always depended on and never stated.
--
-- THE BUG
-- -------
-- `authenticated` had no SELECT on `public.accounts` or `public.players`, so
-- the client could not read a profile at all: `myAccount()` and `myPlayers()`
-- both return "permission denied", `SessionStore.loadProfile` swallows it, and
-- every signed-in user lands in the "Good Evening, there!" state with
-- non-member pricing and a dead Register button. The entire app, for everyone.
--
-- Nothing in `supabase/migrations/` ever granted it. It arrived free from
-- Supabase's bootstrap `alter default privileges in schema public grant all on
-- tables to anon, authenticated`, and every migration since has only ever
-- REVOKED from that inherited pile. The schema therefore described what the app
-- may not do and never once described what it must.
--
-- Found 2026-08-16, when the local CLI was upgraded 2.90.0 -> 2.115.0 and the
-- probe suite went red: `information_hiding` died with "permission denied for
-- table players" and `privilege_escalation`'s
-- `legitimate_contact_edit_still_works` with "permission denied for table
-- accounts". Same failure had been red in CI for days, because CI installs
-- `latest` while the laptop was pinned to an older CLI. The version skew was
-- hiding it, which is its own lesson about pinning CI and local to the same
-- thing.
--
-- Confirmed NOT self-inflicted: with 20260813000001, 20260815000001 and
-- 20260816000001 all moved out of the way, a fresh `db reset` on 2.115.0 still
-- produces `accounts -> REFERENCES,TRIGGER,TRUNCATE`. The newer Supabase stack
-- simply does not hand `anon`/`authenticated` a blanket table grant any more.
--
-- THE LESSON, which is hard rule 11 read in the other direction
-- ------------------------------------------------------------
-- Hard rule 11 says a grant you did not write is still a grant, and it was
-- earned by an inherited privilege being too WIDE. This is the same root cause
-- with the opposite symptom: a grant you did not write can also be taken away,
-- by a platform upgrade you did not make, at a time you did not choose. A
-- schema that only revokes is only half written.
--
-- SCOPE: exactly what the client reads today, and nothing else.
-- * Everything else the app touches goes through a view (each of which already
--   carries an explicit `grant select`) or a SECURITY DEFINER RPC (which runs
--   as its owner and needs no caller grant).
-- * `devices`, `notifications` and `news_reads` are deliberately NOT granted.
--   Push and the notification bell are unbuilt, and granting ahead of a
--   consumer is how a table starts accepting writes nobody reads.
-- * Row visibility is unchanged. RLS still decides WHICH rows: `accounts_own`
--   and `players_own` are both `id/account_id = auth.uid() OR is_admin()`.
--   A grant says which VERB is allowed, a policy says which ROWS. This restores
--   the verb only.
--
-- Hard rule 11: revoke precedes grant, so this cannot silently widen anything
-- if the platform's defaults come back.

revoke all on public.accounts from anon;
revoke all on public.players  from anon;

grant select on public.accounts to authenticated;
grant select on public.players  to authenticated;

-- Re-assert the column-level write grant from 20260802000003. It survived the
-- upgrade, but it is the single most security-sensitive grant in the schema
-- (hard rule 8: `role` must never be writable by the role it grants privilege
-- to) and it should not depend on an earlier migration's side effects.
revoke update on public.accounts from anon, authenticated;
grant  update (first_name, last_name, phone) on public.accounts to authenticated;

comment on table public.accounts is
  'One row per login. SELECT is granted to authenticated EXPLICITLY (see '
  '20260817000001): it used to be inherited from Supabase defaults and vanished '
  'in a platform upgrade. UPDATE is column-scoped on purpose; role and email are '
  'not writable by their owner.';

-- ---------------------------------------------------------------- TRUNCATE --
--
-- Found 2026-08-16 by `tests/sql/grants_are_explicit.sql` on its FIRST run,
-- which is the argument for enumerating a privilege surface instead of naming
-- the objects you remember.
--
-- `authenticated` held TRUNCATE on players, devices, news_reads and
-- notifications, inherited from the same Supabase bootstrap default as
-- everything else here and never revoked because no probe ever asked about it.
--
-- TRUNCATE IS NOT COVERED BY ROW LEVEL SECURITY. Policies filter rows for
-- SELECT/INSERT/UPDATE/DELETE; TRUNCATE removes every row in the table and RLS
-- never sees it. So `players_own` did not constrain this at all: any signed-in
-- member could have emptied the club's entire player roster with one statement,
-- and it would have cascaded into registrations.
--
-- This is the same shape as the 2026-08-13 view hole: a privilege nobody
-- granted, that RLS could not stop, reachable by an ordinary user. The
-- difference is that this time a probe found it rather than an audit.
--
-- Revoked from BOTH roles on every base table. Nothing in this app ever
-- truncates: destructive bulk operations are administrative, run as the owner,
-- and hard rule 4 says archive rather than delete anyway.

revoke truncate on all tables in schema public from anon, authenticated;

-- REFERENCES lets a caller create a foreign key against a table, which pins the
-- referenced rows and can block later cleanup. TRIGGER lets them attach a
-- trigger, which runs on someone else's write. Neither is ever needed by a
-- client and both are pure inherited residue.
revoke references, trigger on all tables in schema public from anon, authenticated;
