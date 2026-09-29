# 0029: A player's clinics as a subscribed calendar

**Date:** 2026-09-28 · **Status:** Active · **Source:** the roadmap's wow list
(2026-09-28), "Your clinics in your calendar, automatically"; builds on Add to
Calendar (decision 0023), which is one-shot and goes stale when Tara moves or
cancels a clinic.

## What we chose

1. **Profile gets "Subscribe in Calendar"**, under My Clinics, for any account
   with a player row. A tap asks the server for this account's token
   (`my_calendar_feed_token()`), builds
   `webcal://<project>/functions/v1/calendar-feed?t=<token>`
   (`FXETennis/Models/CalendarFeed.swift`) and hands it to iOS, which opens
   Calendar's own Add Subscription Calendar sheet. The phone then re-reads the
   feed on its own. Google and Outlook take the same address with `https://`
   pasted in. **Profile, not My Clinics**: the subscription is per account and
   set once, and Profile is where account-level things live; My Clinics is a
   list she opens often, and its empty state already has a button. An account
   with no player row (Tara's) does not see the button: its calendar would
   always be empty.
2. **What is in it** (`calendar_feed_events`, in SQL so the probe pins it):
   this account's registrations that are **You're In!** (`STATUS:CONFIRMED`) or
   **Response Needed** (`STATUS:TENTATIVE`, summary suffixed
   "(Response Needed)"), in **published** clinics that ended **no more than 30
   days ago**. A canceled clinic, a draft, a spot given up and the Player Pool
   are not in it, so an event disappears at the next refresh when any of those
   happens. Each event is the clinic's name, start and end in UTC, a DTSTAMP,
   and a UID of `<registration id>@fxetennis`: when an invitation is accepted
   it is the same event, updated in place.
3. **Nothing about where, and no court.** No LOCATION, URL or DESCRIPTION
   property exists in the builder (`supabase/functions/calendar-feed/ics.ts`),
   and the SQL function returns five columns only. Location is hidden
   (decision 10) and the court is hidden (decision 17); a calendar syncs to
   other devices and is shared with other people, so the clinic description
   (which could mention where) stays in the app, as it does for Add to
   Calendar.
4. **The token is the credential.** Calendar apps send nothing but the URL,
   so the function runs with `verify_jwt = false` and checks the token. It is
   32 random bytes as hex, one per account in `calendar_feeds`, which no
   client role can touch. Unknown, malformed, rotated-away and deleted
   accounts all get the same bare 404 (empty body), so a guess learns nothing.
   `reset_my_calendar_feed()` replaces it and kills the old link at once; it
   has no button yet.
5. **Deletion.** A trigger on `accounts.deleted_at` removes the token, so the
   link dies whichever path deletes the account; a hard delete cascades it.
   A token is a credential, not history (the same reasoning as a push token
   in 20260921000003), so hard rule 4 does not apply. The trigger was chosen
   over a line in `delete_my_account()` so that function is not redefined
   (a parallel branch redefining it would silently drop one change) and so a
   future path that sets `deleted_at` is covered too.
6. **Refresh hints** `X-PUBLISHED-TTL` and `REFRESH-INTERVAL` of one hour.
   Apple and Outlook honour them; Google refreshes on its own schedule.

## Rejected

- **Storing a hash of the token instead of the token.** A hash protects a
  credential that unlocks more than the database already holds. This one
  unlocks a read of five columns that sit in the same database, so anyone who
  can read `calendar_feeds` can already read the schedule itself. And a hash
  cannot be handed back, so tapping Subscribe on a second phone would have to
  rotate the token and kill the first phone's subscription. `review_links`
  stores its token the same way.
- **Including the Player Pool** (as tentative). A Pool entry is not a spot:
  Tara picks by hand (hard rule 2), and a calendar entry for a clinic she may
  never pick you for reads as a promise.
- **A per-clinic link or the feed rule in TypeScript.** The rule lives in SQL
  so `tests/sql/calendar_feed.sql` can pin it with hand-worked rows; the
  function only formats.
- **A VTIMEZONE and local times.** UTC needs no timezone block and every
  client agrees on it; the phone shows the time in its own zone.
- **A "Copy link" for Google and Outlook, and a Reset button.** Each is a new
  string for Alex (hard rule 13) and neither was asked for; the RPC for reset
  exists so the button is UI work only.

## How we would know this was wrong

- A member reports a clinic in their calendar after Tara canceled it or after
  they gave up the spot, more than a refresh (about an hour on an iPhone, up to
  a day in Google) later.
- Anything about where the club is, or a court number, appears in anyone's
  calendar. `information_hiding.sql` (`calendar_feed_carries_nothing_hidden`)
  and the harness's property allowlist exist to make that fail first.
- A member on hosted sees iOS's "Insecure Connection" prompt. On the local
  stack (plain http) iOS tried HTTPS first and asked before falling back;
  hosted is HTTPS, so it should connect securely without asking. Checked on a
  real phone after the first deploy.
- Members want the Pool in it after all, or Tara wants a calendar of every
  clinic she coaches (a different feed: hers, not a member's).

## Proof

`tests/sql/calendar_feed.sql` (40 checks, red under 16 mutants, one rule each),
`tests/sql/calendar_feed_race.sh` (two first calls at once get one token; red
without the re-read and with a plain INSERT), a row in `information_hiding.sql`
and `grants_are_explicit.sql`, `tests/calendar/run.sh` against the served
function (48 checks, red under five function mutants) with
`tests/calendar/ics.test.ts` (RFC 5545 escaping, folding and UTC, red under
five mutants), `FXETennisTests/CalendarFeedTests.swift`, and a walk on the
simulator to Calendar's own Add Subscription Calendar sheet showing
"FXE Tennis" and "Evening Coed (Response Needed)".
