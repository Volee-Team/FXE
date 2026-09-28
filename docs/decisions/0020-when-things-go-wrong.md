# 0020: The app and the admin site when things go wrong: no signal, stale screens, larger text, a bounded week

> **2026-09-28:** item 5's mechanism (`UIFontMetrics` at the moment a font was made) is superseded by decision 0023: text now follows Larger Text live through `.brandFont(_:)`. The rule is unchanged.

**Date:** 2026-09-27 · **Status:** Active · **Source:** the MVP audit of 2026-09-27 (build-now items 7, 8, 9, 14, 15, 16, 17), branches `ios-resilience`, `web-admin-bounds`, fixed on `fix-ios` and `fix-sql`

## What we chose

1. **No answer is not "no profile".** A profile load that failed keeps the last
   known identity; at launch with nothing known the app shows a can't-load
   screen (the connection line, Try again, Sign out), never the sign-up form.
   Only a successful empty answer means an unfinished sign-up. A load still in
   flight when someone signs out is dropped (a generation counter).
2. **Failures are classified by type and code, never by words**
   (`FXETennis/Data/RequestFailure.swift`): transport errors, HTTP 408 and 5xx,
   a gateway error with no PostgREST code, and connection-class Postgres codes
   read "Couldn't reach the server. Check your connection."; HTTP 429 reads
   "Too many attempts. Try again in a minute." on the phone and the web alike;
   GoTrue's hourly email limit is not "a minute". Only a real answer from the
   server is read as "someone beat you to the punch".
3. **Screens reload when the app comes back**, at most once every 30 seconds,
   and a clinic page redraws at its opening, close and start, so Register
   appears at 8:00 without a pull and disappears once the clinic has begun.
4. **Every onboarding step has a way out**: Sign out and Delete my account at
   the foot of the profile form, the waiver and the card step.
5. **Text follows the iPhone's Larger Text setting**: every Brand style scales
   with `UIFontMetrics` for its matching text style; the logo lockup does not.
6. **The web admin's This week is this week**: clinics ending after Sunday
   00:00 New York of the current service week, plus older clinics that are
   still owed by decision 0018's one definition; everything older is under
   Show earlier. Rosters are read only for the clinics on screen, paged past
   the API's 1000-row cap.
7. **supabase-js on the web is vendored** at an exact version (`web/vendor/`),
   checked byte for byte in CI; Dependabot proposes upgrades. Rejected: a CDN
   at a floating major version, which ran whatever was published that day on
   the page where members type a new password.

## How we would know this was wrong

A member reports the sign-up form appearing for an existing account, a
"someone beat you" message with no one else involved, or a screen that needs a
pull to show what happened while the app was closed.
