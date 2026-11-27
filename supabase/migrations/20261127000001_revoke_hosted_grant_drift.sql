-- Revoke grants hosted had that no migration ever wrote, and stop new objects
-- being born with them.
--
-- Found 2026-11-14 by a docs audit reading hosted's ACLs (read-only,
-- scripts/hosted-read.sh), not by any probe, then enumerated in full by
-- scripts/grants-snapshot.sql on hosted against a fresh local build. Hosted
-- had, for client roles, and a fresh build has none of it:
--   news_reads: authenticated SELECT, INSERT, UPDATE, DELETE, MAINTAIN
--   accounts, players: authenticated MAINTAIN (on top of the SELECT we wrote)
--   EXECUTE for authenticated on four trigger functions (Postgres refuses a
--     direct call to a trigger function) and on card_required() and
--     courtesy_cancel_days() (they read one setting each)
--   default privileges for objects postgres creates in public: EXECUTE on
--     new functions for anon and authenticated, SELECT/USAGE/UPDATE on new
--     sequences
-- tests/sql/grants_are_explicit.sql only ever runs on fresh databases
-- (locally and in CI), so it could not see any of this. Same shape as
-- 2026-08-19 (hard rule 11): a grant you did not write is still a grant.
--
-- Why these three tables: they are the only ones from before 2026-08-13 whose
-- client grants were revoked by naming privileges one by one
-- (20260802000003, 20260817000001), never `revoke all`, so MAINTAIN (and on
-- news_reads the inherited writes) survived. (sql-auditor, 2026-11-14.)
--
-- Harm was low: PostgREST cannot run VACUUM, REINDEX or LOCK TABLE for a
-- client; news_reads is limited to the caller's own rows and is empty; every
-- migration since 2026-09-02 revokes EXECUTE from public and anon itself, and
-- the snapshot shows no function anon can execute on hosted today. Nothing
-- reads or writes news_reads from a client (git grep of FXETennis, web and
-- supabase/functions); my_news and mark_news_read reach it with owner rights.
-- The fix is still to enumerate what a role can do, not assume what it cannot.
--
-- Idempotent: revoking a privilege not held is a no-op, so on a fresh
-- database only the sequence default changes. Every relation in public is
-- owned by postgres on hosted (checked), so these revokes cannot fail there.

revoke all on public.news_reads from authenticated, anon, public;
revoke maintain on all tables in schema public from authenticated, anon, public;

revoke execute on function
  public.apply_default_clinic_close(),
  public.apply_default_clinic_pricing(),
  public.bootstrap_first_admin(),
  public.card_required(),
  public.courtesy_cancel_days(),
  public.guard_account_privilege_columns(),
  public.guard_player_owner_column()
  from authenticated, anon;

-- New objects postgres creates in public grant client roles nothing; every
-- migration grants what it means to, explicitly (hard rule 11). PUBLIC's
-- built-in EXECUTE on new functions is left alone here: every migration
-- already revokes it by hand, and removing it would change how every open
-- branch's new functions behave.
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated;
