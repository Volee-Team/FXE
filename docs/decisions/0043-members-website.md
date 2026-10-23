# 0043. The members' website: the app's player side at `/play` (2026-10-22)

**Status:** proposed by John, 2026-10-22, on branch `player-web`; for Alex to
review before it merges. Roadmap v1.1, "A members' website with the app's
full functionality", from the call of 2026-10-19 (Tara, Kat, John, Wayne):
the club has members on Android, and the App Store build does not reach them.

## What it is

`web/play/` (`index.html`, `play.js`, `play.css`): the iOS app's player side
in a browser. Sign in, Create an account, Forgot password; the profile step;
the waiver; Home; Clinics by service week; a clinic with its one action
(Register with the note for Tara, Leave Player Pool, Accept and Decline,
Cancel Registration with the late-cancel note inside the cutoff, Message Tara
after the close); My Clinics with Past; the bell; Profile with the card on
file, Subscribe in Calendar, Edit details, Contact Tara, Privacy Policy,
Sign Out and Delete my account. Add to Calendar is an `.ics` with the name
and times only (hard rule 1, like `ClinicCalendarEvent`).

Tara's and the pros' screens are not here: Tara has the app and the web admin.

## Decisions inside it

- **Where it lives:** `https://fxe-tennis-admin.vercel.app/play/`, deployed
  with the rest of `web/` by `scripts/deploy-web.sh`. The new domain (Alex,
  2026-10-19: "a new domain to come") points here later with no code change.
- **Same reads and RPCs as the app.** `play.js` reads only `clinics_public`,
  `my_registrations`, `my_clinic_messages`, `my_past_clinics`,
  `notifications`, `app_settings` and the player's own `accounts` and
  `players` rows, and changes state only through the app's RPCs. Information
  hiding therefore holds by construction; nothing new is granted.
- **Every word is the app's.** Each string was copied from the Swift view
  named beside it in `play.js`; `check-copy.sh` found no wording that the app
  does not already show. One line was left out on purpose: the app's
  "Clinic updates come through the app. Keep notifications on..." under the
  sign-in form, because this page has no push.
- **No push in this version.** The bell (the `notifications` table) works
  for any client. Web Push on Android needs VAPID keys, a subscription table
  and a branch in the `push` function, which only sends to APNs today;
  that is its own decision when Alex wants it.
- **Cards through Stripe's Payment Element** instead of PaymentSheet, with
  the same `stripe-setup-intent` function. The card number goes to Stripe
  only; the webhook writes the summary, and the page waits for it the way
  `CardSavePoll` does (every 2 s, about 30 s). Stripe.js loads from
  `js.stripe.com`, which Stripe requires. A bank's 3-D Secure check returns to
  `#/card-saved`.
- **Two edge functions gained CORS** (`supabase/functions/_shared/cors.ts`, whose allowed origin
  already includes the admin site): `stripe-setup-intent` and
  `delete-account`. Both are in `BROWSER_EDGE` in `scripts/hosted-smoke.sh`.
  Nothing else about them changed. They must be redeployed for the page to
  add a card or delete an account on hosted.
- **Times show in America/New_York**, the club's clock, whatever the
  visitor's device says.
- `accept_waiver` and `record_card_consent` record `web` as the app version.

## Checked locally (2026-10-22), not yet on hosted

Against the local stack in a browser at phone size: sign-in, a new sign-up
through the profile and the waiver to Home, Register (the server put the
seed player in the Player Pool), Accept, Cancel Registration with its
confirmation, Profile, My Clinics with Past, the bell, and with payments
switched on locally, Register refused for the card and the card step opening;
`stripe-setup-intent` answered through CORS with `stripe_not_configured`
(no Stripe keys locally). **Not yet exercised: a real card through Stripe's
sandbox** (needs the sandbox keys, the same rehearsal as A13), and the
3-D Secure return.
