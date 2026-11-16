# 0058. Court reservations in the app, step 1: the server (2026-11-16)

**Status:** the plan is John's, 2026-11-16 (*"lets get court reservatiosn up
asap."*). The defaults are ours until Tara answers questions 156 to 165.
Built in `supabase/migrations/20261116000001_court_reservations.sql`. It
changes her "Correct." to question 42 (courts stay on reservemycourt.com)
once she picks a switch date (164). Plan: `docs/courts/plan.md`.

## The problem

The club books courts on reservemycourt.com, about $500 a year. Tara asked for
it in the app on 2026-09-12 (the dream list) and again on 2026-11-05. Two
systems also mean she blocks a clinic's courts twice. Our database already
knows every clinic.

## Decision

**The server first, switched off.** Courts, hours, bookings and blocks, with
the functions the members' site, Tara's laptop and the app will call.
`courts_live` is false, so until Tara picks a date a member is refused
(`courts_not_live`) on every member function, their own bookings and
cancels included, and only her side works. Nothing an app already on a
phone reads changes: new tables, new functions and new settings keys only.

**TestFlight testers first** (John, 2026-11-16: *"we are going to do the
court booking just in testflight until we are 100% sure tis good"*). Court
booking is used only by TestFlight testers until John is sure. Two halves,
both needed:

- **The app** shows Book a Court only on a TestFlight install (the
  `AppTransaction` environment is sandbox, or the receipt is the sandbox
  one) **and** when `courts_available_for_me()` is true. An App Store
  install never shows it, whatever the server says.
- **The server** keeps a testers list, `court_testers`. While `courts_live`
  is false, an account on it that is a member (or an admin) uses the member
  side as if it were live: books, reads a day, lists and cancels its own.
  Everyone else, a non-member tester included, still gets
  `courts_not_live`. Taking a tester off stamps `removed_at` (the row is
  kept) and refuses them again; deleting an account takes it off.
  `courts_available_for_me()` answers whether the member side would answer
  the caller right now (a live member, or a tester before the switch), so
  the app never shows a button the server refuses.
- **Who is a tester** is Tara's or John's choice on the laptop (Court
  rules, "Can book while courts are off (TestFlight)"), through
  `admin_set_court_tester` and `admin_court_testers`. Never named in code:
  the repo is public.

The members' website stays off for booking until `courts_live`: it is not
a TestFlight install, so the testers phase is the app only.

**The members switch is locked** (same day, same words). Tara cannot turn
`courts_live` on or off: `admin_set_court_settings` refuses the key with
`courts_live_locked`, alone or beside other rules, and changes nothing. Her
Court rules show it as words ("Off for members. Court booking is in testing
with the testers below."), not a control. **Only a later migration that John
approves turns it on**, after Tara's answers to 156 to 165 (165 above all)
and John being sure from TestFlight.

**The rules are settings, each checked when Tara changes it:**

| Rule | Default | Her question |
|---|---|---|
| Who books | members only | 156 |
| Courts and hours | 1 to 5, 7:00 AM to 9:00 PM every day | 157 |
| Length and start | 60 or 90 minutes, on :00 or :30 | 158 |
| How far ahead | 7 days, a day opening at 7:00 AM New York | 158 |
| Limits | 1 a day, 2 upcoming, per account | 159 |
| Price | free | 160 |
| Cancel | any time before the start | 162 |
| What members see | taken or free, never who | 163 |

**One booking per court and time,** enforced by an exclusion constraint while
booked. Every court write also takes one advisory lock, so the overlap with
blocks and clinics (which no constraint can see) and the per-account limits
are decided one at a time. A club's volume makes that free.

**Clinics hold their courts automatically.** A published, not canceled
clinic holds, from its start to its end, the union of:

- one court per 4 spots, counted down from court 5;
- every court on its You're In! rows;
- every court in its 105 rounds (`clinic_round_spots`).

The union because Tara and the pros assign one row at a time: when the hold
was "the assigned courts, else the counted-down ones", her first assignment
freed every other court of the clinic for booking, and a 105's rounds were
not seen at all (sql-auditor, 2026-11-16). Question 165 may change how many.

**Tara's side:**

- She sees names, reasons and clinics.
- She books for anyone outside the member rules, but never over another
  hold, and never on a court taken out of use.
- Her note on a booking (`admin_note`) is hers alone. `playing_with` is the
  member's own words and is read back to them; the two never mix.
- She blocks one court or all of them. A block over bookings lists them,
  with name and phone, and cancels nobody (nothing is decided for her, hard
  rule 2).
- Blocks are removed, never deleted. Bookings are canceled, never deleted
  (hard rule 4).
- **Her cancel tells the member** (John, 2026-11-16, yes to *"Your court
  booking on Thu at 8:00 AM was canceled by FXE."*). Notification 16 in
  `docs/notifications.md`, with the date after the weekday (on John's
  sign-off list, `docs/courts/copy-for-john.md`). Only the booker, only for
  a booking that has not started, never when she cancels her own. Entity
  `court_booking`: apps 1.0.3 and 1.0.4 show it and open nothing on a tap.
  A member's own cancel and a block send nothing. Pinned by
  `court_reservations.sql` n1 to n6.

**Deleting an account cancels its upcoming bookings,** by a trigger on
`accounts.deleted_at`, so every path that deletes is covered. Past bookings
stay.

## Open, for John and Tara

**BLOCKING `courts_live`: what "taken" tells a member about a clinic.**
`courts_live` stays false until Tara answers question 165, because what
follows is shipped as code today and the sql-auditor ranked it high. A member's day shows a
clinic's courts as taken, the same as any booking. It shows no name and no
reason. Still, someone who knows the clinic's time can read off:

- how many courts it holds (a coarse capacity, hidden fact 1);
- once Tara assigns courts, which courts the clinic is on, though not who is
  on which (hard rule 17 is about a player's own court).

Options:

- accept it, since clinic times are public to members anyway;
- show members a count of free courts per time and give a court only after
  booking;
- hide the per-court grid around clinic times.

Asked as part of 165. Related: a Ladies or Men clinic is hidden from the
other gender's clinic list (decision 0044), but its courts still read as
taken to everyone, so its time shows (no name). Settled with 165.

`court_reservations.sql` row v4 pins only that a hold, if shown, names no one
and is not the caller's. Whether it is shown at all is left unpinned until
165.

**Not checked against bookings:**

- **Publishing a clinic, or assigning a court on it.** A booking can already
  sit on those courts. Tara's day shows both. Step 3 (her laptop) should warn
  when she publishes.
- **Taking a tester off.** Their upcoming bookings stay, and they can no
  longer read or cancel them; Tara cancels them on her day if needed.
- **Turning a member's switch off.** Their upcoming bookings stay. While
  `court_members_only` is on they can no longer read or cancel them (the
  member functions refuse), so Tara cancels them on her day if needed. The
  same goes for a booking she makes for a non-member.
- **A retried booking.** If the app retries a booking that already went
  through, the retry is refused (`day_limit` or `court_taken`). The client
  should reload My Courts after any booking answer.

## Rejected

- **Keep reservemycourt.com and link to it.** Two logins, and clinics are
  still blocked by hand.
- **Fixed one-hour slots only.** Tara's current system lets the club set the
  shortest and longest booking; 60 or 90 is a setting, not a schema.
- **A check-then-insert without the constraint.** Two taps at the same
  moment would both pass the check (the capacity-race lesson). The race
  script shows 2 bookings on one slot without it.

## Pinned by

- `tests/sql/court_reservations.sql`: 144 checks. The lock's four l6 rows
  (refused on, refused beside a valid rule, refused off, nothing changed)
  were red against the unlocked function; the checks after it switch on as
  the owner, a migration's place. Before that, 141 checks. The 29 tester rows (t1 to
  t14, x3, and the three new functions and the table in g1 to g4) were red
  before the testers change (2026-11-16); the ones that pass either way
  ("a non-tester is still refused") go red under a named mutation: a
  non-member tester let through (t8), a removed tester still counted (t13),
  `admin_set_court_tester` or `admin_court_testers` without the admin check
  (t11, t10), deletion keeping the tester (x3), `courts_available_for_me`
  reading only the switch (t3, t14). Before that, 112 checks. The first 88 were written
  before the migration (86 red, the 2 green ones "still true" rows). The 24
  added after the sql-auditor (2026-11-16) were red against the first
  version, or under a named mutation:
  - h2, h4, h5: the union hold (one assignment, the 105 rounds);
  - y3: Tara's note never reaches the member;
  - l7, l8: a member's own bookings and cancel refused while not live;
  - e1, e2: the exclusion constraint alone, written as the owner past the
    lock (23P01), with a canceled row allowed to overlap. Red with the
    constraint dropped;
  - o1, o2, o3: `court_day_opens` exact on both DST Sundays (2026-11-01,
    2027-03-14) and at 6:59 against 7:00; r12, `book_court` refusing a day
    not yet open, with no dependence on the hour the probe runs;
  - a6: "060" stored as 60; a8: an inactive court refused for Tara too;
  - c4 asserts its past row was made.
  Each rule removed on its own turns its rows red.
- `tests/sql/court_booking_race.sh`: 50 members on one slot, and one member
  on five courts at once. Each phase is exactly 1 booking. Phase 2 is red
  without the advisory lock; phase 1 only without both the lock and the
  constraint (with the lock alone the bookings are taken in turn), which is
  why e1 pins the constraint by itself. Its cleanup is an EXIT trap: killed
  after setup, it leaves `courts_live` as it was and no probe accounts.
- `tests/sql/information_hiding.sql` row 17, and the five internal helpers in
  `grants_are_explicit.sql`.
