# 0027: Tara's laptop tools: a player's history in the Pool, Copy to next week as drafts, a court sheet to print

**Date:** 2026-09-28 · **Status:** Active; three points below are for Tara or Alex · **Source:** the lead's brief for branch `tara-tools`. Tara runs the program from texts, a spreadsheet and a handwritten court sheet; the laptop is where she does weekly setup and court assignment (her decision 1, CLAUDE.md). Each tool saves her time and decides nothing: the app organizes, Tara decides.

## What we chose

1. **A player's history beside the name, so choosing from the Player Pool
   takes one look.** `admin_player_history(p_player uuid default null)`
   (20260928800001) returns, per player, how many clinics they played, their
   no-shows, their late cancellations and the start of the last clinic they
   played.
   - **Played** is the board report's *attended* (20260926000010), reused word
     for word: You're In!, not marked a no-show, in a clinic that ended
     (`ends_at <= now()`) and was not canceled. Two definitions of "came" would
     drift. **No-shows** are the same rows with her No-show mark, so the two
     partition one set. **Late cancels** are canceled inside the cutoff (by the
     player, or recorded by Tara), counted as soon as they happen, in a clinic
     that was not canceled.
   - **A canceled clinic did not happen**, so nothing in it counts:
     `cancel_clinic` leaves every registration's status as it was, and without
     this a rained-out clinic would read as played.
   - **Every player, or one.** Both, from one function, so the counting rule
     lives once: with no argument it answers for every player (the web draws
     lists: the Players tab, every Player Pool on the week, one call per render,
     read a page at a time past PostgREST's 1000-row cap like every growing
     list); with a player id it answers for that one (the phone's player page).
     The phone's Pool rows use the every-player form filtered on its result to
     the Pool's ids, one small call per load. A player with no history gets a
     row of zeros, which reads "New"; a missing row would be ambiguous with "not
     asked".
   - **Words:** "12 played · 1 no-show · 2 late cancels": after "played", only
     the parts that are not zero; "New" when there is nothing. Web: under every
     Player Pool name and on every Players-tab row, with "Last played <date>" on
     hover. Phone: the Pool rows (inside the existing `ViewThatFits`, so a row
     still drops to two lines when it does not fit) and the player's page, with
     "Last played <date>" there. The Pool's order is untouched: its numbers are
     registration order, her priority.
   - **Hidden from players** (hard rule 1: never a count to a player):
     `require_admin()` first, so a member gets `not_authorized`, never a row of
     zeros; revoked from PUBLIC and anon before the grant to `authenticated`.
2. **Copy this week to next week, as drafts.**
   `admin_copy_week(p_week_start date)` (20260928800002) copies every clinic of
   the service week starting on that Sunday, canceled ones aside, to the next
   week, and returns how many it created and how many it skipped.
   - **The week** is `service_week_start()`'s, the helper the registration
     windows use (Sunday 00:00 to Saturday 23:59:59, New York; decision 0001).
     Anything but a Sunday is refused (`not_a_sunday`).
   - **Seven days later on the same New York wall clock**: the local timestamp
     plus 7 days, converted back. 9:00 AM Saturday 2026-10-31 (EDT, 13:00 UTC)
     copies to 9:00 AM Saturday 2026-11-07 (EST, 14:00 UTC), across the
     daylight-saving change. `ends_at` moves the same way.
   - **Copied:** name, audience, category, description, length, capacity,
     template. **Recomputed for the new date:** the member and public windows
     from the rule, the close by `apply_default_clinic_close`, the prices by
     `apply_default_clinic_pricing` from the length, exactly as for any new
     clinic. **Never copied:** registrations, courts, messages, payments.
   - **Status `draft`.** Players see nothing (`clinics_public` shows published
     and canceled clinics only) until she has looked at each copy and pressed
     its Publish.
   - **Idempotent.** A clinic whose copy already exists in the target week
     (same name, same start, not canceled) is skipped, so a double click creates
     nothing twice. Two clinics with the same name at the same time (two groups
     one morning) are two copies: the n-th is skipped only when n copies exist.
     The check and the insert run under a transaction advisory lock keyed on the
     target week, so two simultaneous calls cannot both find no copy and both
     insert (`copy_week_race.sh`, red without the lock: six drafts of a
     three-clinic week).
   - **Web only**, a "Copy to next week" button on the This week tab, which
     copies the current service week (the one the tab starts at) and says
     "Copied 5 clinics to next week as drafts." or "Nothing new to copy." No
     phone UI: weekly setup is laptop work.
3. **A court sheet to print.** `web/sheet.html?clinic=<id>`, opened from a
   "Court sheet" link on each clinic card (a real link, in a new tab): the
   clinic's name, day and time, then its You're In! players by court, Court 1,
   Court 2 and so on, then "No court yet", each with their rating as the phone
   shows it ("3.5", "5.0+"), and a Print button the printout leaves out. It
   reads what the roster already reads (`clinics_admin`,
   `registrations_admin`, `players`), with the admin page's own session on the
   same origin; no new data path. Every one of those reads is admin-only in
   Postgres, so a member who opens the address reads nothing; the browser test
   asserts the database's empty answer, not the page's message.

## Rejected

- **Copying the registration windows and the close from the source.** An
  override on a source clinic was a one-off for that week (a holiday, a late
  start); carried forward it would open next week's clinic at this week's
  moment. Recomputed from the rule, as for a new clinic (probe row
  `sat_morning_windows_and_close_from_the_rule_not_the_source`, red under it).
- **Adding 168 hours.** An hour off across a daylight-saving change: the copy
  of 9:00 AM Saturday Oct 31 would be 8:00 AM Saturday Nov 7. Six probe rows go
  red under it.
- **Copying the prices.** Prices are never a parameter anywhere
  (20260826000001 note 4); a weekly copy chain would carry an old price forward
  every week after the table changed. Left null for the trigger.
- **A unique index on (name, start) instead of the lock.** It would forbid two
  clinics with the same name at the same time, a legitimate schedule, and give
  `admin_upsert_clinic` a new way to fail.
- **Skipping by name alone, or by time alone.** Name alone skips a clinic Tara
  moved to another time; time alone skips a different clinic that shares the
  slot.
- **Publishing the copies, or a "Publish all drafts" button.** Players would
  see clinics nobody has looked at. Per-clinic Publish already exists and keeps
  each one a decision.
- **Ranking or sorting the Pool by history.** Tara picks every invitation
  (hard rule 2); the app shows the record and never reorders her queue.
- **The court sheet as a print view inside `index.html`.** That page's print
  stylesheet already belongs to the board report (it hides everything but the
  report); a page of its own prints cleanly, carries the clinic's name as its
  title in the browser's print header, and opens beside the week.

## For Tara or Alex (defaults kept, not decided here)

1. **A canceled draft shows to players.** `clinics_public` lists canceled
   clinics (so a player sees her own canceled clinic as Canceled), and
   `cancel_clinic` accepts a draft, so a copy Tara cancels because next week is
   different appears in every player's Clinics list as Canceled: a clinic they
   never saw published. Pre-existing for any draft; Copy to next week makes it
   likely. Not changed here, because it changes a player-facing view (hard
   rules 1 and 10); `copy_week.sql` asserts the drafts' invisibility before any
   copy is canceled. A fix to decide: a `published_at` stamped by
   `publish_clinic`, with `clinics_public` showing a canceled clinic only if it
   was ever published. In `docs/backlog.md`.
2. **A canceled copy is not a copy.** The skip key is the brief's (same name,
   same start, not canceled), so a second Copy brings back a draft she
   canceled. The alternative (any copy, canceled or not, blocks a re-copy) is
   one condition.
3. **A late cancel in a clinic Tara later canceled does not count** against the
   player (the clinic did not happen, and Charge clinic never charges it).
   Tara may see it the other way.

## How we would know this was wrong

- Tara reads a line she disagrees with ("she came to that one"): the roster is
  the record, and a missed Came / No-show tap is the usual cause; if the rule
  is wrong, `player_history.sql` changes first.
- A copy starts an hour off, or opens at the wrong moment: `copy_week.sql`'s
  daylight-saving and window rows.
- Two drafts of one clinic after a double click: `copy_week_race.sh`.
- The printed sheet disagrees with the roster: both read
  `registrations_admin`, so the difference is the grouping, which the browser
  test pins.
