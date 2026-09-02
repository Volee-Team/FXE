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
