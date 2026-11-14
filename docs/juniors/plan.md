# Juniors and summer camp: the build plan (2026-11-14)

What we build for `docs/juniors/spec-2026-11-07.md` (Tara's document), in what
order, and what waits on her. John, 2026-11-14: *"we should get going on doing
the new stuff for tara"*.

- **Target:** before 2027-01-01. John told Tara yes on 2026-11-05: *"Just
  wondering if it's possible to have this done by January 1?"*
- **Scope:** her document puts pool, court reservations and Volee outside this
  update. They stay in `docs/roadmap.md` (v2).

This file is a plan, not a status. Rows that get built move to
`docs/architecture.md`, open questions live in `docs/questions-for-tara.md`
(145 to 155), and decisions get their own records.

## The one big choice: a junior class is a clinic

Every school-year class date and every summer camp day is a row in `clinics`
with `audience = 'juniors'`, tied to a new program and season. Reusing it gets
us, for free:

- the roster;
- You're In!, the Player Pool and Tara's Move In;
- courts and the court sheet;
- Came and No-show;
- Message Players and the From Tara board;
- the pros' week (decision 0051);
- guests (decision 0052, the base for walk-ins);
- the ledger and Charge, and the calendar feed.

Each of those is tested today. What is new sits on top: programs, seasons,
enrollments, approvals, families, treats and the camp pricing.

**The cost:** every adult rule has to step aside for a juniors clinic:

- the Thursday/Friday windows (decision 0001);
- the 3-hour close;
- back-to-back 105s;
- the level check;
- adult prices (0002 and 0053).

Her document says so: *"Do not apply the adult weekly registration windows to
junior offerings."* Each rule gets a probe proving it ignores juniors, and one
proving adults are unchanged.

**Rejected: separate `junior_classes` and `camp_days` tables.** That is cleaner
on paper, but it rebuilds rosters, courts, messages, the pros' screens and the
charging path a second time. It also gives the security model (hard rule 1)
two places to leak instead of one.

## Data model (new)

| Table | What it holds |
|---|---|
| `players` (exists) | A child is a `players` row with `kind = 'junior'` and `date_of_birth` (the check is there since 2026-07-28), owned by the parent's account. `account_type` already has `parent` and `both` |
| `player_guardians` | A second parent linked to the same child (account, child, who added it, when). One child, never two copies. **Waits on question 151** for who may cancel or change a booking |
| `junior_programs` | Red Dot, Orange Dot, Recreational Yellow, Junior Elite, Elite: Tara's name, description, age guidance, `needs_approval`, sort order. Never chosen from a birthday |
| `program_approvals` | Child, program, approved by, when. One approval covers school year and summer (spec 01). Parents request, Tara approves, and she can preapprove |
| `junior_seasons` | A school-year session or a summer. Program, kind (`session` / `camp`), dates, weekdays, times, excluded dates, member and non-member prices (session, drop-in, daily camp), cap, and member and non-member open date and time. Creating one makes its clinic rows, as drafts like Copy to next week (0027) |
| `session_enrollments` | A child in a whole session: `requested` → `offered` (with Tara's prorated amount for a late join) → `confirmed` (charged) / `declined`. Confirming puts the child in You're In! on every remaining class date |
| `registrations` (exists) | A drop-in request is a Pool row on that date's clinic, and Tara's approval is her Move In. New columns: `enrollment_id` (Session vs Drop-In on the roster) and `cant_attend_at` (the parent's Can't Attend: no refund, still counts against nothing) |
| `camp_bookings` | Summer: one row per child per day booked, with the agreed rate shown at booking, the treat allowance (0/1/2), and the cancellation deadline (start − 12 h) |
| `treat_log` | Treats given per child per day, recorded by staff, capped at the allowance by the database |
| `payments` (exists) | One ledger, as today. New kinds: `session_fee`, `camp_day`, `treats`. Sibling discount and Tara's adjustment are stored on the row, so history shows the line items |
| `charge_approvals` | A parent's tap approving an amount above what they agreed (spec 04). Without one, the database refuses the charge |

## Phases

Each phase ships on its own: migrations pushed, the laptop site deployed, and
the app in a 1.0.x build. The questions only block their own phase.

### Phase 1: families and programs (no blocking question). Start now.

1. **My Children** on Profile, in the app and on `web/play/`: add, edit and
   remove a child (first and last name, birthday). An adult account becomes
   `both` the moment it adds a child and keeps its own bookings and card
   (spec 06, scenario 1).
2. **A waiver per child**, signed by the parent. The adult waiver flow (0013)
   with the parent/guardian text. **Waits on question 145** for the text.
3. **Programs** on the laptop: Tara writes the five descriptions and age
   guidance.
4. **Elite approvals:** the parent taps Request Approval, and Tara approves or
   declines on the laptop, with an Action Needed row. She can also preapprove
   a child.
5. **Privacy:** the policy names children's names and birthdays, given by a
   parent. The App Store privacy answers get the same addition (John's to
   type).

### Phase 2: school-year sessions (needs 146; 147 for siblings)

Seasons and their clinic rows, then:

- **Register for Session:** review the dates and price, confirm, and pay up
  front. This is the first charge made at booking rather than after the
  clinic.
- **Request a Session Spot** when the session is full. No money moves until
  Tara offers and the parent accepts.
- **Late join:** Tara types the prorated amount, the parent accepts, and the
  card is charged.
- **Drop-ins:** the parent picks dates and requests, Tara approves each date,
  the child is billed after class, and a no-show is billed too.
- **Text Tara for Faster Approval.**
- **Can't Attend.**
- **Separate member and non-member opening times.**

### Phase 3: pros and walk-ins

The pros' week grouped by program, with:

- ages and the parent's phone;
- Session or Drop-In on each row;
- absences shown.

Add Walk-In builds on guests (0052): an existing child, or a name and parent
phone. That lands in Tara's Action Needed as "Payment follow-up needed". When
the parent signs up, the attendance links to the child once, never twice.

**Phases 1 to 3 are the January 1 target.** They cover the spring school-year
session.

### Phase 4: summer camp (needs 148, 149, 150)

- Full Week or Choose Days, with daily caps and Request a Spot.
- Free cancellation until 12 hours before each day.
- Treat allowance, and treats recorded by staff.
- Sibling discount on actual same-day attendance.
- Tara's day screen: default, sibling, adjustment, treats, total, then Charge
  Today's Camp.
- Never above the agreed amount without the parent's tap (`charge_approvals`).
- A retried batch never charges twice (the idempotency rule of 2026-09-27,
  one key per row).

Target: open before summer registration. Question 154 asks when that is.

### Phase 5: linked parents (needs 151)

`player_guardians`, an invite to the second parent, and the family seen as one
for siblings and for bookings.

## How we know it works

Her "Minimum scenarios to verify before release" (spec 06) become tests, one
per scenario:

- **SQL probes** for every money and capacity rule (written red first, as
  always);
- **a UI test** per parent flow;
- **Playwright** for the laptop.

The sql-auditor reviews every migration before it is pushed. Children's data
is the most sensitive thing this app will hold: a child is visible to their
own parents, Tara, and the pros on a day they are rostered, and to nobody else
(hard rule 1, probed).
