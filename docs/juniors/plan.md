# Juniors and summer camp: the build plan (2026-11-14)

What we build for `docs/juniors/spec-2026-11-07.md` (Tara's document), in what
order, and what waits on her. John, 2026-11-14: *"we should get going on doing
the new stuff for tara"*.

- **Target:** parents buy the **winter session** from **2026-12-15**, and
  the first class is 2027-01-04 (Tara, 2026-11-17, decision 0060). It was
  2027-01-01 for spring. John told Tara yes on 2026-11-05: *"Just wondering if
  it's possible to have this done by January 1?"*
- **Scope:** her document puts pool, court reservations and Volee outside this
  update. They stay in `docs/roadmap.md` (v2).

This file is a plan, not a status. Rows that get built move to
`docs/architecture.md`, open questions live in `docs/questions-for-tara.md`
(145 to 155 answered 2026-11-17; 166 to 168 open), and decisions get their own records.

## Releases

John, 2026-11-15: *"get started on juniors and plan for that to be as 1.0.5"*.

| Release | What | When |
|---|---|---|
| 1.0.4 | Pro rounds (0056) and the pros' roster at large text sizes. No juniors | submitted after its UI runs, mid-November |
| server, ahead of 1.0.5 | Phase 0 (`20261115000001`): live as soon as it is green, since it changes nothing anyone sees today | November |
| **1.0.5** | **Juniors**: phases 1 to 3 in the app, the members' site and Tara's laptop. Parents add children, sign a waiver per child, buy winter weekdays or ask for drop-ins; Tara runs programs, approvals, sessions and walk-ins; pros see the juniors' week | submitted as soon as it is ready, aiming for about 2026-12-08 so Apple's review finishes before sign-ups open on 2026-12-15. If it is late, parents use the members' site, which needs no review |
| 1.0.6 or later | Summer camp (phase 4) and linked parents (phase 5) | on phones by mid-February: summer registration opens 2027-03-01 (question 154) |

The server parts of each phase can go live before 1.0.5 is on phones, as
long as the 1.0.3 and 1.0.4 apps see nothing new (phase 0's rule). The laptop
and members' site deploy when ready.

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

### Phase 0: one account, several players, safely (before any child row exists)

Today every account has exactly one `players` row. An audit of 2026-11-14
read the latest definition of all 223 SQL objects, the app, both websites and
the edge functions, asking what goes wrong once an account owns a child row
too. It found 16 problems: 4 that break, 10 that are silently wrong, and 2
labels. The ones that decide the design:

- **The app picks "me" as the first row**:
  - `Session.swift` `activePlayer = players.first`, fed by `myPlayers()` with
    no order and no kind filter.
  - Row order is not stable: an update moves a row, so a parent could become
    their child.
  - Edit Profile would then write the parent's name and rating onto the
    child.
  - `web/play/play.js` falls back to a child when there is no adult row.
- **Registrations are looked up by clinic alone**:
  - `ClinicDetailView`, `ClinicsView`, `HomeView` and `play.js`.
  - A child's spot reads as the parent's, and Cancel or Respond can act on
    the wrong one.
  - Siblings in one clinic collapse into one entry.
- **`delete_my_account`** blanks `date_of_birth` on every row of the account,
  which the `junior_has_dob` check refuses. A parent could not delete their
  account.
- **No kind rule on registration**:
  - `register_for_clinic`, the audience guards and `level_ok` never look at
    `kind`.
  - `level_ok` passes an unrated row.
  - A child row is therefore the "second players row, unrated" that the
    2026-11-05 level audit closed by revoking INSERT. A child could be
    registered into an adult 3.5.
  - `clinics_public`'s gender check runs over any player on the account. A
    mother with a son would see Men's clinics, and a child with no gender
    opens both.
- **Account-level outputs need a name**:
  - `my_past_clinics`, the calendar feed, and every notification's text
    (two children in one clinic get the same push twice).
  - Tara's Players tab gives a child row the parent's Pro switch and Reset
    link.
- **The waiver is per account** (`waiver_accepted(account)`), not per child.

**The rule that follows: an app already on someone's phone sees exactly what
it sees today.** 1.0.3 will be on phones for weeks, and it would hit every
item above the moment a parent on a newer app adds a child. So:

- Client SELECT and UPDATE on `players`, and `my_registrations`,
  `my_past_clinics` and `clinics_public`, keep returning adult rows only, and
  no juniors clinics.
- Children and their bookings are read through new functions (`my_children`,
  `my_family_registrations`) that only the new app and the members' site
  call.
- Every registration path checks kind against audience: a junior only in
  `juniors` clinics, an adult never in them.
- `level_ok` and the gender rule look at the player being registered, never
  at the account.
- `delete_my_account` anonymises a child like the adult: name and birthday
  blanked, row inactive. The birthday check now applies to active rows only.
- Notifications and the calendar name the child.
- Tara's Players tab shows a child under the parent, without the adult
  controls.

Each item gets a probe, red first: a parent on the old query shapes sees no
child, a child is refused an adult clinic, an adult is refused a juniors
clinic, and so on. The phase ships before Phase 1's Add a Child appears
anywhere.

### Phase 1: families and programs (no blocking question)

**Server built 2026-11-17** (decision 0061, `20261118000001`, not pushed to
hosted): children, a waiver per child (waiting on her text), the five
programs and Elite approvals. **The members' site and the laptop built
2026-11-18** (branch `juniors-p1-web`): My Children, Add a Child, a child's
page with the waiver per child and the programs with Request Approval on
`web/play/`; the Juniors tab, Program requests in Action Needed and children
under their parent on Players on the laptop. Their words wait for John
(`docs/juniors/copy-for-john-phase1-web.md`). The app follows.

1. **My Children** on Profile, in the app and on `web/play/`: add, edit and
   remove a child (first and last name, birthday). An adult account becomes
   `both` the moment it adds a child and keeps its own bookings and card
   (spec 06, scenario 1).
2. **A waiver per child**, signed by the parent. The adult waiver flow (0013)
   with the parent/guardian text. Question 145: the tennis camp parent/guardian form, word for word (answered 2026-11-17).
3. **Programs** on the laptop: Tara writes the five descriptions and age
   guidance.
4. **Elite approvals:** the parent taps Request Approval, and Tara approves or
   declines on the laptop, with an Action Needed row. She can also preapprove
   a child.
5. **Privacy:** the policy names children's names and birthdays, given by a
   parent. The App Store privacy answers get the same addition (John's to
   type). **For John's sign-off (2026-11-18, decision 0061):** a signed
   junior waiver keeps the child's name and birthday, beside the parent's
   typed name and email, after the account is deleted. It is the legal
   record, as the adult waiver keeps the adult's. The policy wording that
   says so is John's to write and approve; nothing in it has been changed.

### Phase 2: school-year sessions (146 and 147 answered 2026-11-17)

Seasons and their clinic rows. **Each weekday of a session is its own
purchase** (question 146). Each weekday has its own dates, price and cap
(question 167); a parent buys one or several, and both days cost the sum.
There is no school-year sibling discount (147). Then:

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

**Phases 1 and 2 are the December 15 target**, so parents can add children,
sign and buy winter weekdays. **Phase 3 is the January 4 target**, the first
class.

### Phase 4: summer camp (148 to 150 answered 2026-11-17; 168 open)

- Full Week or Choose Days, with daily caps and Request a Spot.
- Free cancellation until 12 hours before each day.
- Treat allowance, and treats recorded by staff.
- Sibling discount on actual same-day attendance.
- Tara's day screen: default, sibling, adjustment, treats, total, then Charge
  Today's Camp.
- Never above the agreed amount without the parent's tap (`charge_approvals`).
- A retried batch never charges twice (the idempotency rule of 2026-09-27,
  one key per row).

Target: summer registration opens 2027-03-01 (question 154). A treat is $3, one price for every program (155). Nothing is canceled for rain (148). The $5 sibling discount is for regular campers only (150).

### Phase 5: linked parents (151 answered: either parent books, the booker pays)

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
