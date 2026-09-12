# 0010: Cancellation is a 4-hour honor system

**Date:** 2026-09-12 · **Status:** Partial (the cutoff and the principle are Tara's; the charge amount and who taps are still open) · **Extends:** 0009

## What Tara said

Relayed by Alex on 2026-09-12, quoted exactly as he wrote it:

> ok also tara said were gonna have honor system for canceling , unless it's
> an emergency, someone sick in your household, etc, then you get charged,
> very concise message - the threshold will be 4 hours, so before 4 hours
> anything can be cancelled but after that you have to say its an emergency
> to cancel (like basicaly

Nothing else about cancellations was said. Everything below that is not in
that quote is an inference and is marked as one.

## What this decides

1. **The cutoff is 4 hours** before the clinic starts. `app_settings.cancel_cutoff_hours` was 24 by our default; it is now 4 by her word.
2. **Before the cutoff, any cancellation is free** and needs no reason.
3. **Inside the cutoff, a player has to say it is an emergency to cancel**, with a very concise message. The app therefore requires a short note on a late cancellation by the player, and stores it. (Inference: the note is the player's own words, the same way a late request is; the app invents nothing.)
4. **Honor system.** The app does not judge the note and charges nobody on its own. A late cancellation shows up on Tara's roster with the note beside it; charging is her tap, as question 34's default already said. (Inference from "honor system" plus 0009's rule that a late charge waits for her tap.)
5. Pool and Response Needed players who drop out inside 4 hours are not "late": only a You're In! player holds a spot (question 30's default, unchanged).
6. Tara removing a player inside 4 hours is not the player's late cancel and records no note.

## What this does not decide (questions 38–42 in `questions-for-tara.md`)

- Whether an emergency cancel is always free, or hers to decide case by case.
- What the late charge is (full price, question 28) and whether no-shows are charged the same (question 29).
- Whether the regular clinic fee moves to the card at all (question 33), or the card exists only for late cancels and no-shows with Zelle staying the normal way to pay.
- The sentence the app shows inside 4 hours. Hers to write; until then only chrome shows.

## Consequences in the code

- `registrations.late_cancel` and `registrations.cancel_note` (20260912000005).
- `cancel_registration(p_registration, p_note)` raises `late_cancel_needs_note` for a You're In! player inside the cutoff with no note; the old single-argument signature is dropped so the call cannot be ambiguous.
- `registrations_admin` carries `late_cancel`, `cancel_note`, `has_card`; the web roster shows the note and, once payments are on, a Charge button.
- The player's cancel flow in the app asks for the note inside the cutoff.

## Also said the same day, kept for the record

Not decisions, but Tara's direction for the product, quoted from Alex's
message so nothing is paraphrased away (see `docs/roadmap.md`, "The dream"):

> rn they use 500/yr for reservemycourt.com to reserve courts, and for now they
> use that but we'd LOVE to someday integrate that into the app, then we could
> white label sell this to many other clubs ... - she said we can sign up and
> tara will approve me as an FXE member so I can play around with it
> ^she said the DREAM is having everything on the app: pay for treats, barcode
> to scan when you enter the pool to scan it, buy merch on the app, reserve
> pool cabana for $150 for a bday, etc etc like truly comprehensive - then this
> would TRULY be amazing to go to other clubs
