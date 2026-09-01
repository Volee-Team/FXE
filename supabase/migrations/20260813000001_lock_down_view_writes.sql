-- Lock down write access to the player-facing views.
--
-- THE HOLE. 20260728000002_helpers_views_rls.sql:90-96 revokes the base tables,
-- and that half is correct: `authenticated` genuinely has no write on clinics,
-- registrations, clinic_messages, news_posts. But Supabase bootstraps
--
--     alter default privileges in schema public
--       grant all on tables to anon, authenticated;
--
-- (confirmed in pg_default_acl: anon=arwdDxtm/postgres), so every table AND view
-- created by postgres in schema public is BORN with INSERT, UPDATE, DELETE and
-- TRUNCATE for both roles. Lines 170-175 of that migration only ever layered
-- `grant select` on top. The inherited write grant was never revoked.
--
-- Three properties then compose into a complete RLS bypass:
--   1. The views are single-table selects, so Postgres makes them auto-updatable
--      (information_schema.views.is_updatable = 'YES').
--   2. They were created without `security_invoker`, so they execute as their
--      OWNER (postgres) rather than as the caller.
--   3. relforcerowsecurity = false on every base table, so the owner is exempt
--      from RLS.
-- A write through a view therefore executes as postgres with RLS switched off.
-- The RLS policies were never consulted. They were never wrong; they were never
-- reached.
--
-- Worse, a view's WHERE clause does NOT constrain an INSERT. Without WITH CHECK
-- OPTION it filters reads only. So `where public.is_admin()` on clinics_admin
-- and `where public.owns_player(...)` on my_registrations stopped nothing.
--
-- WHAT WAS REACHABLE, all reproduced on a local throwaway DB by
-- tests/sql/view_write_paths.sql before this migration (28 checks red):
--   * anon (the publishable key that ships inside the iOS binary) could
--     `delete from clinics_public` and wipe the entire schedule, cascading
--     through registrations and clinic_messages, both ON DELETE CASCADE.
--   * anon could cancel any clinic, set any price to zero, and move a
--     registration window by 30 days, which decides who gets a seat.
--   * anon could create a clinic through clinics_admin.
--   * anon could register any player for any clinic.
--   * an ordinary member could promote herself out of the Player Pool into a
--     spot (hard rule 2), mark herself paid, hard-delete her own registration
--     (hard rule 4, archive never delete), register somebody else, and cancel a
--     clinic she merely attends.
-- The self-promotion path also skips register_for_clinic's FOR UPDATE capacity
-- serialisation and the price snapshot from decision 0002 entirely.
--
-- Supabase's own security linter had been reporting these as ERROR-level
-- findings the whole time and nobody had read them.
--
-- THE FIX IS A GRANT CHANGE, NOT security_invoker. This is the important part
-- and it is counterintuitive. Turning on security_invoker looks like the tidy
-- structural answer, and it would BREAK THE PRODUCT: `authenticated` has no
-- SELECT on the locked base tables, so the whole information-hiding model
-- depends on these views reading with owner rights. Flipping security_invoker
-- would take away both the player's clinic list and Tara's entire admin surface.
-- The four `sanity_*` rows in tests/sql/view_write_paths.sql exist to pin that
-- and will fail loudly if anyone tries it.
--
-- Order matters: revoke first, then re-grant. Same lesson as
-- 20260802000003_fix_privilege_escalation.sql line 29.

-- ------------------------------------------------------- the views ----------

revoke all on public.clinics_public      from anon, authenticated;
revoke all on public.clinics_admin       from anon, authenticated;
revoke all on public.my_registrations    from anon, authenticated;
revoke all on public.registrations_admin from anon, authenticated;
revoke all on public.my_clinic_messages  from anon, authenticated;
revoke all on public.my_news             from anon, authenticated;
revoke all on public.revenue_by_clinic   from anon, authenticated;
revoke all on public.revenue_by_segment  from anon, authenticated;

-- Re-grant exactly the reads that 20260728000002:170-175 and
-- 20260810000001:175-176 intended, and nothing else. anon gets nothing at all:
-- the app signs in before it reads anything, so no unauthenticated caller has
-- business touching schema public.
grant select on public.clinics_public      to authenticated;
grant select on public.clinics_admin       to authenticated;
grant select on public.my_registrations    to authenticated;
grant select on public.registrations_admin to authenticated;
grant select on public.my_clinic_messages  to authenticated;
grant select on public.my_news             to authenticated;
grant select on public.revenue_by_clinic   to authenticated;
grant select on public.revenue_by_segment  to authenticated;

-- --------------------------------------------- base tables anon can reach ----
-- devices, news_reads and notifications kept the same inherited write grant.
-- RLS does constrain these three (they are base tables, so the caller's own
-- rights apply and anon is not the owner), which is why they are a smaller
-- problem than the views. But an unauthenticated caller has no legitimate
-- reason to hold INSERT on any of them, and defence in depth is the whole point
-- of hard rule 8. authenticated keeps what it needs; RLS still scopes it to the
-- caller's own rows.

revoke all on public.devices       from anon;
revoke all on public.news_reads    from anon;
revoke all on public.notifications from anon;
revoke all on public.accounts      from anon;
revoke all on public.players       from anon;
revoke all on public.app_settings  from anon;

-- ------------------------------------------------ stop the recurrence --------
-- Without this, the next `create view` in schema public silently re-opens the
-- exact same hole, because it inherits the default grant again. After this,
-- every new relation starts with no anon/authenticated privileges and each
-- migration must grant what it needs explicitly.
--
-- CONSEQUENCE FOR FUTURE MIGRATIONS: if you add a table or a view and the app
-- gets a 401 or an empty result, you are missing a `grant select ... to
-- authenticated`. That is intended. Explicit beats inherited: this project has
-- now been bitten twice by privileges nobody wrote down (see hard rule 8 and
-- the 2026-08-02 privilege-escalation entry).
alter default privileges in schema public revoke all on tables from anon, authenticated;

comment on view public.clinics_public is
  'Player-facing clinic list. Carries both published rates so the client shows '
  'the one matching the viewer''s membership; a rate sheet is not secret. '
  'Deliberately omits internal_capacity and every count (hard rule 1). '
  'price_cents is deprecated; use member_price_cents / nonmember_price_cents. '
  'SELECT-only for authenticated, no grants for anon: this view is '
  'auto-updatable and runs with owner rights, so a write grant here bypasses '
  'RLS entirely. See 20260813000001 and tests/sql/view_write_paths.sql.';
