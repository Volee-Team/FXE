# 0056. Pros set the 105 rounds in their week (2026-11-11)

**Status:** accepted by John, 2026-11-11 (he relayed Tara's answer and
approved it for 1.0.4); built in
`supabase/migrations/20261111000002_pro_rounds.sql` and the pro's Manage tab.
Changes the rounds clause of decision 0054 (item 8), where pros read the
rounds and only Tara wrote them.

## Her words

Relayed by John on 2026-11-11:

> Currently, my pros can't put people on a court... Just wanna make sure that
> they can position people on the courts like I can do now

And on the 105 rounds:

> I think can change the rounds. That's totally fine. Probably need it in
> case I'm out of town

## What was already there

A pro gives a You're In! player a court on any clinic in their week
(`pro_assign_court`, decision 0051), so a regular court was covered. The 105
rounds were not: 0054 read "Just me and pros for rounds" alongside her
11-06 line that pros only "assign courts and see who is in the clinic", so
pros read the rounds (`clinic_rounds`) and only Tara wrote them
(`admin_set_round_court`). 0054 left that open for her; this is her answer.

## Decision

A pro sets a 105's rounds exactly where they already read them: a clinic in
their week, meaning published and starting on today's New York date or one
of the six after it (the window of `pro_week` and `clinic_rounds`).

- `admin_set_round_court` lets Tara or such a pro through. Everything else
  is as it was for Tara: rounds 1 to 3, courts 1 to 5, six spots, one place
  per person per round, You're In! and live guests only, 105s only, not a
  canceled clinic, under the clinic's FOR UPDATE lock. Outside the week a pro
  gets one answer, `not_this_week`, for a clinic eight days out, a draft, a
  canceled clinic or an id that is no clinic, so the refusal says nothing
  about a clinic they cannot see. Players are refused (`not_authorized`), as
  before. Tara is not held to the week.
- `clinic_round_people` is new: who a round is picked from, You're In!
  registrations and guests not removed, with the id `admin_set_round_court`
  takes and the first and last name, by last name. Tara's screens build this
  list from her own roster; a pro has no roster read that includes guests,
  so the server gives it. Same access as `clinic_rounds`. Names only: no
  price, paid flag, note, phone, email or count.
- The pro's Manage tab: Rounds on a 105 in the week opens the same sheet as
  Tara's, with Round 1 to 3 and the six pickers per court, and Save. The
  sheet reads `clinic_round_people` itself; if that read fails it shows the
  rounds read-only with "Couldn't load the roster." A save refused because
  the clinic has left the week reads "That clinic isn't in your week
  anymore."
- The function keeps its `admin_` name: the 1.0.3 app and the laptop call it
  by name, and a rename would break both for no change in behaviour.

## Rejected

- **A separate `pro_set_round_court`.** A second copy of the same
  validation, which would drift from Tara's. One function with the caller
  checked once at the top keeps one set of rules.
- **Letting a pro set rounds on any clinic.** Pros already see and act on
  the week only (0051); Tara's reason ("in case I'm out of town") is the
  clinics coming up, not the schedule a month out.
- **Sending the pro's sheet everyone in `pro_week`.** `pro_week` lists
  registrations only, never guests, and a round is picked from both.

## How we would know we were wrong

Tara finds rounds changed on a 105 she had laid out and did not want
touched, or asks to see who last changed them. Neither is recorded today
(`clinic_round_spots.set_at` says when, not who).

## Pinned by

`tests/sql/pro_rounds.sql`; `tests/sql/tara_items_0054.sql`'s pro row now
reads `a_pro_sets_rounds_in_the_week`; `pro_role.sql` names both functions
among a pro's declared reach; `ClinicExtrasTests` (the people row and the
`not_this_week` words).
