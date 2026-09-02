-- Notifications become readable. Until now no client could read a single one.
--
-- `notifications` has had a correct RLS policy (`notifications_own`,
-- account_id = auth.uid()) since 2026-07-28, and the backend has been faithfully
-- writing rows into it: invitation_received, player_canceled, clinic_canceled,
-- clinic_message, LATE_REQUEST and friends. But `authenticated` never held a
-- SELECT grant on the table, so every one of those rows was unreadable by the
-- person it was addressed to. A policy says which ROWS; a grant says which VERB.
-- The verb was missing.
--
-- Same class as 20260817000001: an inherited default grant that vanished in a
-- platform upgrade and had never been written down. grants_are_explicit.sql
-- listed the tables the app reads and this one was not on the list, because
-- nothing in the app read it yet. It does now: Tara's Action Needed is built on
-- it (late requests, cancellations, declines), and so is the player's bell.
--
-- UPDATE is column-scoped to read_at only, the same shape as
-- accounts(first_name,last_name,phone): a player may mark their own
-- notification read and change nothing else about it. Hard rule 11: revoke
-- before grant.

revoke all on public.notifications from public, anon, authenticated;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

comment on table public.notifications is
  'One row per in-app notification. SELECT + UPDATE(read_at) granted to '
  'authenticated EXPLICITLY (20260901000001); RLS notifications_own scopes rows '
  'to the recipient. Rows are written only by notify_account() from SECURITY '
  'DEFINER RPCs.';
