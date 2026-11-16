# Court reservations: the build plan (2026-11-16)

John, 2026-11-16: *"lets get court reservatiosn up asap."* Tara has asked
twice: the dream list of 2026-09-12 (relayed by Alex) and the group text of
2026-11-05, *"maybe we should also have the court reservation system within
the app as well. Don't wanna rush anything."* In September she answered
question 42, "Courts stay on reservemycourt.com for now", with "Correct." This
plan replaces that answer once she agrees to a switch date (question 164).

This file is a plan, not a status. Rows that get built move to
`docs/architecture.md`. Open questions are 156 to 165 in
`docs/questions-for-tara.md` (section AH), each with the default we build
until she answers.

## What the club uses today

They use reservemycourt.com (RMC2020), about $500 a year. Its public pages
(read 2026-11-16) describe rules the club sets:

- the shortest and longest booking;
- how far ahead people can book;
- how many reservations each kind of user can hold;
- how many they can hold at once;
- a cancellation cutoff;
- an optional fee through Stripe;
- an optional waitlist;
- weekly repeats;
- "Block" reservations the admin makes for rain-outs and clinics.

Its app books one court at a time and cannot see clinics.

**What we do better:** clinics already live in our database, so a clinic
holds its courts automatically. Tara no longer has to block them twice in two
systems.

## Releases: the website first, the app after

| Step | What | Needs App Store? |
|---|---|---|
| **1. Server** | Courts, hours, bookings and blocks; the booking and cancel functions; probes written red first | No. Goes live as soon as it is green. Old apps see nothing new (new tables only) |
| **2. Members' site** (`web/play/`) | Book a Court: pick a day, see free and taken times on each court, book, see My Courts, cancel | No. Deploys any time |
| **3. Tara's laptop** | The day grid of all five courts; block a court or a time; book or cancel for anyone; set the hours and rules | No |
| **4. The app** | Book a Court on Home, My Courts on Profile, a reminder notification | Yes: **1.0.5**, alongside juniors |

Steps 1 to 3 can be live within about a week of Tara's answers to 156 to 159.
The app follows in 1.0.5, due about 2026-12-20.

**Juniors timing:** juniors phase 2 waits on her answer to 146 anyway, so
courts fill that gap. The January 1 juniors target stays first if the two
collide.

## Rules we build until she answers (each a setting she can change)

| Rule | Default | Question |
|---|---|---|
| Who can book | Members only (`is_member`, which Tara sets). Non-members see nothing, in line with hard rule 10 | 156 |
| Courts | 1 to 5, the same numbers as `court_number` | 157 |
| Hours | 7:00 AM to 9:00 PM every day | 157 |
| Length | 60 or 90 minutes, starting on the hour or half hour | 158 |
| How far ahead | 7 days, opening at 7:00 AM | 158 |
| Limits | Each account holds at most 1 booking per day and 2 upcoming | 159 |
| Price | Free; no card involved | 160 |
| Who is playing | The booker only; an optional "Playing with" note | 161 |
| Cancel | Any time before the start, from the app or the site | 162 |
| What others see | Taken or free, never who booked it | 163 |
| Clinics | A published clinic holds courts from its start to its end. How many and which courts: question 165. Until then, the courts she assigns, else ceil(capacity / 4) courts counted from court 5 down | 165 |
| Switch date | Not live for members until she picks a date | 164 |

## Data model

- **`courts`**: number (1 to 5), name, active.
- **`court_hours`**: one row per weekday, opens and closes on the New York
  wall clock, the same rule as clinics.
- **`court_bookings`**:
  - court, account, `starts_at`, `ends_at`;
  - status (`booked`, `canceled`), `canceled_at`, `canceled_by`;
  - `playing_with` note, `made_by_admin`.
  - **No double booking:** an exclusion constraint on (court, time range)
    where the status is `booked`. Two people tapping the same slot at the
    same moment get one booking and one clear "Just taken" (the
    capacity-race lesson, probed with a race test).
- **`court_blocks`**: court (or every court), time range, reason, made by
  Tara. A booking can never overlap a block or a clinic's hold. A block
  that Tara adds over existing bookings lists them for her to cancel; it
  never cancels anyone silently.
- **`court_settings`** in `app_settings`: the rules in the table above.

**Functions:**

- `court_day(date)`: every court's free and taken times for a member, with no
  names.
- `book_court`, `cancel_court_booking` and `my_court_bookings`.
- `admin_court_day`, `admin_block_courts`, `admin_book_court` and
  `admin_cancel_court_booking`. These show names and are Tara's only.

## How we know it works

- **SQL probes, red first:**
  - no double booking;
  - the per-account limits;
  - the hours and the window;
  - clinics and blocks hold their courts;
  - non-members are refused;
  - no booker's name reaches a member.
- **A 50-way race** on one slot through the API: exactly 1 booking.
- **Playwright** for the members' site and the laptop.
- **A UI test** for the app flow in 1.0.5.
