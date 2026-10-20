-- 20261014000002_app_diagnostics_retention.sql
--
-- Crash reports: tied to an account for at most a day, kept 90 days
-- (decision 0035, revised 2026-10-01 after the sql-auditor's review).
--
-- WHY A NEW FILE rather than an edit to 20261014000001: that file is
-- committed, and a committed migration is treated as applied even before it
-- reaches hosted; the CI job that refuses edits to an existing migration
-- encodes the same rule. Forward-only migrations are what a team can trust.
--
-- WHY THE LINK GOES AFTER A DAY. report_app_diagnostic files a row under
-- auth.uid() for one reason: the rate limit, 20 per account per rolling 24
-- hours. Once a row is older than that window the link answers no question
-- anyone has, and a crash report tied to a person for months is personal
-- data we had no need to keep. So:
--
--   * purge_app_diagnostics(), run by the nightly `retention` job, sets
--     account_id to null on every row older than 24 hours and deletes every
--     row older than 90 days;
--   * deleting an account (delete_my_account, or anything else that sets
--     accounts.deleted_at) nulls account_id on that account's rows at once,
--     by a trigger, the way calendar_feed_forget_deleted_account removes a
--     feed token: one trigger covers every path that deletes, where an edit
--     to delete_my_account would cover only that function and copy its whole
--     body into a second migration to drift from the first;
--   * admin_app_diagnostics no longer returns account_id at all. A crash is
--     read by build and device; nobody reading crash reports needs to know
--     whose phone it was.
--
-- The return type of admin_app_diagnostics changes, which CREATE OR REPLACE
-- cannot do, so it is dropped and recreated (its grants with it).

-- ------------------------------------------------------- the nightly purge
create or replace function public.purge_app_diagnostics()
returns table (unlinked integer, deleted integer)
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
declare u integer; d integer;
begin
  delete from public.app_diagnostics
   where received_at < now() - interval '90 days';
  get diagnostics d = row_count;
  update public.app_diagnostics set account_id = null
   where account_id is not null
     and received_at < now() - interval '24 hours';
  get diagnostics u = row_count;
  return query select u, d;
end; $$;
-- The retention job connects as postgres; no client calls this.
revoke all on function public.purge_app_diagnostics() from public, anon, authenticated;

-- ---------------------------------------- deletion unlinks at once
create or replace function public.app_diagnostics_forget_deleted_account()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  update public.app_diagnostics set account_id = null where account_id = new.id;
  return new;
end; $$;
comment on function public.app_diagnostics_forget_deleted_account() is
  'Trigger on accounts: when deleted_at is set, that account''s crash reports lose their account_id (decision 0035).';
-- Trigger functions get no EXECUTE grant: Postgres checks it at CREATE
-- TRIGGER, not when the trigger fires (20260902000001).
revoke all on function public.app_diagnostics_forget_deleted_account() from public, anon, authenticated;

drop trigger if exists app_diagnostics_forget_deleted_account on public.accounts;
create trigger app_diagnostics_forget_deleted_account
  after update of deleted_at on public.accounts
  for each row
  when (new.deleted_at is not null)
  execute function public.app_diagnostics_forget_deleted_account();

-- ---------------------------------------- the admin read, without the account
drop function if exists public.admin_app_diagnostics(int);
create function public.admin_app_diagnostics(p_limit int default 100)
returns table (
  id uuid, received_at timestamptz, kind text,
  app_version text, build text, os_version text, device text, payload jsonb
)
language plpgsql stable security definer
set search_path = public, pg_temp as $$
begin
  perform public.require_admin();
  return query
    select d.id, d.received_at, d.kind,
           d.app_version, d.build, d.os_version, d.device, d.payload
      from public.app_diagnostics d
     order by d.received_at desc, d.id
     limit least(greatest(coalesce(p_limit, 100), 1), 500);
end; $$;
revoke all on function public.admin_app_diagnostics(int) from public, anon;
grant execute on function public.admin_app_diagnostics(int) to authenticated;
