-- Push delivery, the second half of decision 0008: everything but Apple's key.
--
-- WHAT. Every row inserted into `notifications` (by notify_account(), from the
-- SECURITY DEFINER RPCs that already write them) now asks the `push` edge
-- function to deliver it to the recipient's phones. The function signs an
-- APNs provider token with the .p8 key held in edge-function secrets, sends,
-- and writes the outcome back onto the row: `delivered_at`, or
-- `delivery_error` with Apple's reason. "Did Maria actually get the
-- invitation" becomes a query, not a guess (decision 0008 item 5).
--
-- WHY A TRIGGER + pg_net AND NOT A DASHBOARD WEBHOOK. A "database webhook" in
-- the Supabase dashboard is exactly this trigger, created by hand on hosted
-- and nowhere else: invisible to the repo, absent locally, absent in CI, and
-- gone on the next `db reset`. Written as a migration it exists in every
-- environment and the probe can see it. pg_net is transactional: the request
-- is queued on commit, so an RPC that rolls back never pushes a notification
-- that was never written.
--
-- WHY VAULT, NOT A URL IN THE MIGRATION OR IN app_settings. The trigger needs
-- two values: the function's URL and a shared secret the function checks.
--   * A secret in a migration is a secret in a public repo.
--   * `app_settings` is readable by every signed-in player by design, and
--     information_hiding.sql fails on any value there that is link-shaped.
--   * The URL differs per environment (hosted vs local), which a migration
--     cannot know.
-- Supabase Vault stores both encrypted, readable only by postgres (the owner
-- of this SECURITY DEFINER function). Until both exist the trigger does
-- nothing at all, so this migration is safe to push before Apple has issued
-- anything: no secrets, no push, no error.
--
-- THE INSERT MUST NEVER FAIL BECAUSE OF PUSH. The trigger runs inside the RPC
-- that wrote the notification (invite, cancel, message). If pg_net misbehaves,
-- Tara's invitation must still be written; a missed push is recoverable, a
-- missed invitation is not. Hence the exception block around http_post.
--
-- WHAT ALEX RUNS ONCE, in the hosted SQL editor, after deploying the function
-- and setting its PUSH_WEBHOOK_SECRET (same value in both places):
--
--   select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/push', 'push_function_url');
--   select vault.create_secret('<the same value as PUSH_WEBHOOK_SECRET>', 'push_webhook_secret');
--
-- THE AUDIT COLUMNS ARE NOT PLAYER-READABLE. `delivery_error` can carry an
-- APNs reason (BadDeviceToken, Unregistered), which is about the device, not
-- the message. 20260901000001 granted `authenticated` SELECT on the whole
-- table, which would have covered any column added later, these two included.
-- A table-level grant is a promise about columns that do not exist yet. It is
-- replaced here by a column list: the eight columns the app reads, and not
-- the two the edge function writes. Hard rule 11: revoke before grant.
-- (Revoking a table privilege also drops its column privileges, so the
-- UPDATE(read_at) grant is written again below.)

alter table public.notifications
  add column if not exists delivered_at   timestamptz,
  add column if not exists delivery_error text;

comment on column public.notifications.delivered_at is
  'When APNs accepted the push for at least one of the recipient''s devices. Written by the push edge function only. Not client-readable.';
comment on column public.notifications.delivery_error is
  'Why the last delivery attempt reached no device: no_device, apns_not_configured, or APNs''s reason / HTTP status. Not client-readable.';

revoke all on public.notifications from public, anon, authenticated;
grant select (id, account_id, type, entity_type, entity_id, body, created_at, read_at)
  on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

comment on table public.notifications is
  'One row per in-app notification. SELECT on eight named columns + UPDATE(read_at) '
  'granted to authenticated EXPLICITLY (20260923000001; the delivery audit columns '
  'are withheld); RLS notifications_own scopes rows to the recipient. Rows are '
  'written only by notify_account() from SECURITY DEFINER RPCs; each insert asks '
  'the push edge function to deliver it (push_on_notification).';

create extension if not exists pg_net with schema extensions;

create or replace function public.push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'push_function_url' limit 1;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;

  -- Not configured yet (every environment until Alex runs the two
  -- vault.create_secret lines above). Do nothing, loudly nowhere.
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    return new;
  end if;

  begin
    perform net.http_post(
      url                  := v_url,
      headers              := jsonb_build_object('Content-Type', 'application/json',
                                                 'X-Push-Secret', v_secret),
      body                 := jsonb_build_object('notification_id', new.id),
      timeout_milliseconds := 5000
    );
  exception when others then
    -- A push is never worth failing the RPC that wrote the notification.
    null;
  end;
  return new;
end;
$$;

comment on function public.push_on_notification() is
  'AFTER INSERT trigger on notifications: queues a pg_net POST to the push edge '
  'function with the row id. No-op unless vault secrets push_function_url and '
  'push_webhook_secret both exist. Never raises.';

-- A trigger function needs no EXECUTE grant to fire; nobody calls it directly.
revoke all on function public.push_on_notification() from public, anon, authenticated;

drop trigger if exists push_on_notification on public.notifications;
create trigger push_on_notification
  after insert on public.notifications
  for each row execute function public.push_on_notification();
