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
(`courts_not_live`) and only her side works. Nothing an app already on a
phone reads changes: new tables, new functions and new settings keys only.

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
clinic holds, from its start to its end, the courts Tara assigned on its
You're In! rows. Until she assigns any, it holds one court per 4 spots,
counted down from court 5 (question 165).

**Tara's side:**

- She sees names, reasons and clinics.
- She books for anyone outside the member rules, but never over another
  hold.
- She blocks one court or all of them. A block over bookings lists them,
  with name and phone, and cancels nobody (nothing is decided for her, hard
  rule 2).
- Blocks are removed, never deleted. Bookings are canceled, never deleted
  (hard rule 4).

**Deleting an account cancels its upcoming bookings,** by a trigger on
`accounts.deleted_at`, so every path that deletes is covered. Past bookings
stay.

## Open, for John and Tara

**What "taken" tells a member about a clinic.** A member's day shows a
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

Asked as part of 165.

**Not checked against bookings:**

- **Publishing a clinic, or assigning a court on it.** A booking can already
  sit on those courts. Tara's day shows both. Step 3 (her laptop) should warn
  when she publishes.
- **Turning a member's switch off.** Their upcoming bookings stay.

## Rejected

- **Keep reservemycourt.com and link to it.** Two logins, and clinics are
  still blocked by hand.
- **Fixed one-hour slots only.** Tara's current system lets the club set the
  shortest and longest booking; 60 or 90 is a setting, not a schema.
- **A check-then-insert without the constraint.** Two taps at the same
  moment would both pass the check (the capacity-race lesson). The race
  script shows 2 bookings on one slot without it.

## Pinned by

- `tests/sql/court_reservations.sql`: 88 checks. 86 were red before the
  migration; the 2 green ones are "still true" rows (no names, payments
  untouched). Each rule removed on its own turns its rows red.
- `tests/sql/court_booking_race.sh`: 50 members on one slot, and one member
  on five courts at once. Each phase is exactly 1 booking, and red without
  the lock or the constraint.
- `tests/sql/information_hiding.sql` row 17, and the four internal helpers in
  `grants_are_explicit.sql`.
