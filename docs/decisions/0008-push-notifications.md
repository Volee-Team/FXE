# 0008: Push notifications — device registration now, delivery when Apple lets us

**Date:** 2026-09-02 · **Status:** Active · **Supersedes:** nothing

## What we decided

1. **Delivery path.** A Supabase edge function, `push`, sends to Apple Push
   Notification service over HTTP/2 with token-based auth (a `.p8` key held in
   Supabase secrets, never in the repo). It is invoked by a database webhook
   on `INSERT` into `public.notifications`, so every RPC that already writes a
   notification row gets a push for free and no client is trusted to send.
2. **Device registration** is two RPCs added today (`register_device`,
   `unregister_device`, migration 20260902000003). The account is always
   `auth.uid()`; the `devices` table stays unreadable and unwritable by clients.
3. **Permission prompt** in the app, once, right after the profile is completed,
   with Tara's own line from the Developer Guide (Screen 3): *"Clinic updates
   come through the app. Keep notifications on so you don't miss them."* If a
   player declines, the app shows a quiet reminder on Home; nothing more.
   (**Built 2026-09-21.** `NotificationsOffLine` in
   `NotificationPermissionView.swift` reads `PushRegistrar.status == .denied`
   and renders the approved sentence plus a Turn on notifications button on
   Home. Decision 13's persistent in-app disclosure is met.)
4. **No admin marker** of who has notifications off. Tara's decision 13
   (2026-08-02): she does not want to monitor it, and the earlier design's
   "notifications off" indicator on the player profile is withdrawn.
5. **Audit columns** `delivered_at` and `delivery_error` on `notifications`,
   written by the edge function, so "did Maria actually get the invitation" is
   a query and not a guess. Added with the edge function, not today.

## Why

- Every notification already exists as a row, written server-side by the RPC
  that caused it. Sending from a database webhook means the copy, the audience
  and the timing stay where they are and the client cannot fabricate a push.
- Token-based APNs auth needs a signing key that only a paid Apple Developer
  account can create. FXE Tennis, LLC's enrollment is in review. Everything up
  to that key can be built and tested now; the key is a secret to add later.
- Registration before delivery, because tokens are only issued to a device
  that has asked for permission; the app side has to exist first for there to
  be anything to send to.

## Rejected

- **Firebase Cloud Messaging** as an intermediary. One more account, one more
  key, one more vendor between a tennis pro and her members, for a feature
  APNs does directly.
- **Sending from the iOS app or the web admin.** A client with a key that can
  push to any device is the one credential this system must never ship.
- **Polling** (the app fetching `notifications` on a timer). It is what the
  bell does when opened, and it is fine for that; it is not what "Tara
  invited you, answer within the hour" needs.

## How we will know it was wrong

- If delivery latency from `notify_account` to the lock screen is regularly
  over a minute, the webhook path is the wrong shape and a queue is needed.
- If Tara asks who has notifications off more than once, decision 13 has
  changed and the marker comes back as a new decision.

## Sequence

1. Today: `register_device` / `unregister_device` + probe; the app asks for
   permission and uploads its token; Sign Out unregisters it. Nothing is sent.
2. On enrollment: create the APNs key, add it to Supabase secrets, deploy the
   `push` edge function, configure the webhook, add the audit columns.
3. First real push goes to Alex's phone, not Tara's.

**Built 2026-09-23 (everything but the key).** Step 2 of the sequence above,
minus the one thing only Apple can supply:

- Migration `20260923000001_push_delivery.sql`: the audit columns
  `delivered_at` and `delivery_error` (item 5), withheld from clients by
  turning the table-level SELECT of 20260901000001 into a column list; and
  the "webhook" of item 1, written as a trigger (`push_on_notification`,
  AFTER INSERT, via pg_net) rather than a dashboard setting, so it exists in
  every environment and the probe can see it. Its URL and shared secret live
  in Supabase Vault (`push_function_url`, `push_webhook_secret`); with either
  missing it does nothing, and it never fails the insert.
- Edge function `push`: shared-secret auth, ES256 provider token signed with
  WebCrypto and cached 50 minutes, one request per device with the row's body
  verbatim and the unread count as the badge, `delivered_at` on any success,
  Apple's reason in `delivery_error` otherwise, tokens pruned on 410 or
  `BadDeviceToken` ("Old tokens are pruned by APNs feedback", above),
  idempotent on retry.
- Proven against a mock APNs that verifies the token signature
  (`tests/push/run.sh`, CI job "Push pipeline (mocked)") and by the probe
  `push_delivery`.

What still waits on the key: creating it, the five `APNS_*` /
`PUSH_WEBHOOK_SECRET` function secrets, deploying `push`, the two
`vault.create_secret` calls on hosted, and step 3, the first real push to
Alex's phone. The steps are in `supabase/functions/README.md` ("What Alex does
when the key arrives"). Not proven until then: that Apple accepts the key,
team and topic, and that production versus sandbox is right for the build
(TestFlight tokens are production, the default).

**Addendum 2026-09-27: the app's receiving half** (MVP audit item 12, branch
`push-client`, fixed on `fix-ios`).

- `PushAppDelegate` is the `UNUserNotificationCenter` delegate. While the app
  is open a push shows a banner, list and sound and reloads Home, but only
  while someone is signed in, so a shared phone never shows the previous
  account's text. `.badge` is left out: the reload sets the icon number.
- A tap is routed by `entity_type` and `entity_id` through one resolver
  (`NotificationRouter`), the same one the bell uses. A `registration` goes to
  the caller's own `my_registrations` first; only an admin falls back to
  `registrations_admin`, which opens her roster page. A player never queries the
  admin views. The tap stays pending until its screen is actually shown, and
  the row is marked read then.
- The icon number always equals the bell's unread count; it is set only from a
  successful fetch and goes to 0 after sign-out completes.
- **Enumerate, do not list:** every `notify_account` caller must name `clinic`
  or `registration`; a producer with a third kind turns
  `tests/sql/notification_targets.sql` red, which is the moment to teach the
  router to open it.
- The seed's invitation is written by `invite_from_pool` itself (Maria,
  Response Needed, "Evening Coed", 40 days out), with fixed ids so
  `tests/push/simctl-push.sh` can push it to the simulator.
- Also: Tara's late-request rows now open her Manage page for that clinic,
  not the player page, whose Register button did nothing for her.
