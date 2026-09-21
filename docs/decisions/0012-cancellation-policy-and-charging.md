# 0012: Tara's cancellation policy, and cards charged after the clinic

**Date:** 2026-09-16 · **Status:** Active; §2 and §6 (the courtesy) and the 4-hour figure superseded by 0013 on 2026-09-21 · **Supersedes:** 0010 (the emergency-note rule) and the "charge when You're In!" default in 0009

## What Tara said

Relayed by Alex on 2026-09-16. Her policy text, verbatim, is the player-facing
rule and belongs in the app word for word:

> **FXE Tennis Cancellation Policy**
>
> We understand that plans change! Please cancel as early as possible so we
> have time to adjust courts, players, and coaching staff.
>
> • Cancel more than 4 hours before clinic: No charge.
> • Cancel within 4 hours of clinic: Full clinic fee will be charged.
> • No-shows: Full clinic fee will be charged.
>
> Each player receives one courtesy late cancellation every 90 days, no
> questions asked.
>
> For a true illness or emergency after your courtesy cancellation has been
> used, please contact Tara at fersctennispro@gmail.com
>
> Thank you for helping us keep clinics organized and running smoothly!

Her answers to the 2026-09-12 short list, verbatim:

1. Emergency note inside 4 hours: *"No more 'emergency' see above text."*
2. Who decides on a late charge: *"See above. One late cancellation every 90 days that the app takes care of."*
3. Late charge amount: *"Full price as you listed - yes, def full."*
4. No-shows: *"I charge them full for the no show. I charge them on the app / clinic list like the others."*
5. Regular fee: *"I want to charge everyone's card everytime they come to clinic."*
6. Card on file to register: *"Gosh I say yes. I can't have 20 people ask to still Venmo. Doing this to make my life simpler."*
7. Refunds when she cancels: *"There won't be a refund ever bc no one will be charged until after the clinic is over."*
8. Stripe account details: given to Alex directly. **They are not in this repo, the prompt log, or anywhere else, and must never be.** They go into Stripe's own form, typed by Alex or Tara.
9. The two sentences: *"You draft, I edit. But also.. here are my thoughts:"* then her own text, which is what ships (see `docs/copy.md`).
10. After a clinic: *"Correct."* (it drops off the players' list; Past is on her side).
11. Courts stay on reservemycourt.com: *"Correct."*
12. Waiver: the FXE tennis camp waiver page on fersc.com (a parent/guardian camp form; an adult version is still an open question).
13. Privacy policy can live on fersc.com.
14. Logo and colours: *"I'll have to ask someone about this. I'm personally not too concerned about it.. but should I be?"*

Two new asks in the same message: *"Reminder app needs to ask every player for
their rating.. and phone number"*, and a note field at level entry that only
Tara sees, her example: *"just coming back from a back injury so I'm a low,
3.5"*.

## What this decides

1. **Inside 4 hours a cancellation goes through.** No emergency claim, no
   required note. The note box stays, optional, under her sentence ("If there
   are circumstances you'd like us to consider, please leave a note below").
2. **One courtesy late cancellation per player per 90 days, applied by the
   app.** The first late cancel in any 90-day window is free and marked
   `courtesy_used`; the next inside that window carries the full fee.
   Illness after the courtesy is used is handled by email to Tara, outside
   the app; she can waive by simply not charging that row.
3. **Every card is charged after the clinic, never before.** Attendees pay
   the regular fee, no-shows and non-courtesy late cancels pay the full fee,
   all at the price snapshotted on the registration. Nothing is charged before
   a clinic ends, so there is nothing to refund when she cancels one.
4. **Charging is one tap per clinic** (`admin_charge_clinic`), available once
   the clinic has ended, on the web and on the phone. She marks no-shows on
   the roster first. (Inference: she said she charges "on the app / clinic
   list like the others"; an automatic charge at end time would need her to
   have marked no-shows already, so the tap is hers. Question 43.)
5. **A card on file is required to register** once payments are switched on
   (`card_required`). Browsing works without one.
6. **The courtesy covers late cancellations only**; a no-show is always the
   full fee (her policy lists them separately). Question 44 confirms.
7. **Rating and phone are required at sign-up**, and the profile gains an
   optional note only Tara reads (`players.level_note`), labelled in her
   words.

## Consequences in the code

Migration 20260916000001: settings `charge_fee_at = after_clinic`,
`card_required = true`, `courtesy_cancel_days = 90`; columns
`registrations.courtesy_used`, `registrations.no_show`, `players.level_note`;
`courtesy_available()`, `my_courtesy_available()`, `admin_set_no_show()`,
`admin_charge_clinic()`; `cancel_registration` no longer refuses a late cancel
without a note; `register_for_clinic` raises `card_required`;
`create_my_account` and `update_my_profile` take the note. Probe
`cancellation_policy.sql`; `late_cancellation.sql` updated. Her policy text
and her two sentences ship verbatim (`docs/copy.md`), marked for her edit.

## Rejected

- Charging automatically at the clinic's end time: needs no-shows marked
  before the clock fires, and hard rule 2's spirit (nothing happens to a
  player without Tara) argues for the tap. Reconsider if she asks for it.
- Keeping the emergency note as a requirement: she withdrew it.
- Refunds on her cancel: moot by construction; nothing is charged early.

## How we would know we were wrong

Tara charging late cancels by hand outside the app, or players emailing her
about courtesy counts the app got wrong. Both visible in her inbox and the
ledger.
