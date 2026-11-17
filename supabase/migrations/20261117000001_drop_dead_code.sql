-- Drop database objects nothing calls (decision 0059, 2026-11-17).
--
-- John, 2026-11-17: "clean up all of that for 1.0.5", after a read-only
-- survey of the repo for dead code. Every object below was checked three ways
-- before it went on this list:
--
--   1. Nothing at HEAD calls it: not the app, not web/, not an edge function,
--      not another SQL function, view, policy or trigger, not a cron job.
--   2. No app build still on phones calls it. The builds seen on hosted
--      (waiver_acceptances.app_version and card_consents.app_version, read
--      2026-11-17) are 0.1.0 (2, 3, 7, 8), 1.0.0 (12), 1.0.1 (14), 1.0.2 (15)
--      and 1.0.3 (18), plus 1.0.4 (19) now in review. At every release tag
--      and branch, the Swift that names these objects is a wrapper nothing
--      calls (NewsRepository, myCourtesyAvailable), or the object is not named
--      at all.
--   3. Hosted holds no rows in the two tables (news_posts 0, news_reads 0,
--      read 2026-11-17).
--
-- KEPT, and why: admin_charge_clinic. TestFlight builds 2 to 8 call it from
-- Tara's Charge clinic button, and builds 7 and 8 were seen on hosted as late
-- as 2026-11-05. Drop it once those TestFlight builds have expired.
--
-- No CASCADE anywhere. Dependents were listed with pg_depend first: my_news
-- is the only thing that reads news_posts and news_reads, and each table's
-- policies go with the table. The two revenue views have no dependents;
-- revenue_summary() reads payments directly and never used them.

-- The news feature, deferred by decision 0006 and never switched on.
drop view if exists public.my_news;
drop function if exists public.mark_news_read(uuid);
drop function if exists public.publish_news(uuid);
drop table if exists public.news_reads;
drop table if exists public.news_posts;
drop type if exists public.news_audience;
drop type if exists public.news_status;

-- Replaced by admin_upsert_clinic and admin_copy_week.
drop function if exists public.create_clinic_from_template(uuid, timestamptz, timestamptz);

-- Templates are archived instead (admin_set_template_archived).
drop function if exists public.admin_delete_template(uuid);

-- Decision 0013 left no courtesy on the cancel sheet; this was only ever
-- reached through an app wrapper nothing called.
drop function if exists public.my_courtesy_available(uuid);

-- Crash reports are read on hosted with SQL, not through a screen.
drop function if exists public.admin_app_diagnostics(integer);

-- The laptop's Money tab uses revenue_summary(); these two views had no reader.
drop view if exists public.revenue_by_clinic;
drop view if exists public.revenue_by_segment;
