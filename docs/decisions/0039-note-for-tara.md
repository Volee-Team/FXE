# 0039: A private note for Tara at Register

**Date:** 2026-10-11 · **Status:** Active · **Source:** Tara, relayed by Alex
2026-10-11: *"When people register for the clinics, can there be a private
note they can put when they register? So for instance, if Quinn wants to
register for a clinic, but she wants to be on the same core as her friend
Tammy then she can write a note when she registers. That only I will see so
make sure it says only Tara can see this."* Then her words for the screen:
*"As the example put 'please put me on court with my friend Jane'. Only Tara
sees this"*.

## What we chose

1. **A box on the clinic page, above Register.** Label "Note for Tara
   (optional)" (the late-cancel sheet's approved label), her example inside
   it, her line "Only Tara sees this" under it. Optional; Register works
   with it empty. Return is Done (the keyboard goes, Register is in reach).
2. **Only Tara and the writer read it, enforced in the database** (hard
   rule 1). `registrations.player_note`, which no client role can select;
   read through `registrations_admin` (`where is_admin()`) and
   `my_registrations` (`owns_player`) and nothing else. Pros do not see it:
   she said "only I", and `pro_today()` names its columns. Other players,
   anon, and counts: nothing. `tests/sql/registration_note.sql` (33 checks)
   asserts each, and that exactly those two views carry the column.
3. **She can change or clear it until the clinic starts**, on her own live
   spot (You're In!, Player Pool, Response Needed): the same box, with Save
   once the text differs from what Tara has (`set_my_registration_note`, a
   conditional update; zero rows is "Couldn't save your note."). Tara cannot
   rewrite it: it is the player's words. Question 109 confirms with Tara.
4. **Tara reads it beside the name** on every roster list, phone and laptop,
   quoted under the rating line. **Not on the printed court sheet** until
   she says otherwise (question 110): paper on a bench is not "only Tara".

## Since the review (2026-10-11, before hosted)

The sql-auditor found no way for anyone but Tara and the writer to read a
note, and six gaps, all closed before the migration left this branch:
`register_for_clinic` kept a note when Tara registered someone, which put
words in a player's mouth (now only the owner's note is kept); the probe never
tried a canceled or draft clinic, never counted accented letters, and did not
pin the ten client functions that return a whole registration row (each now
carries the note to its caller, and each is the owner's or Tara's); one check
could not fail and is gone; and the hosted smoke test now sends build 9's
two-argument call. Each new check was shown red on its own break. The probe is
33 checks.

## Engineering calls (ours)

- At most 300 characters as Postgres counts them (Unicode scalars; the box
  stops there and never splits an emoji), trimmed, blank is no note.
- `register_for_clinic` takes the note as an optional third argument; the
  two-argument form was dropped so there is one function, and a call with
  two arguments still resolves to it through the default (checked through
  PostgREST: HTTP 200), so build 9 on testers' phones keeps registering.
- Deleting an account erases the writer's notes, played clinics included:
  they are her words, not history Tara needs.
- No notification when a note is written (question 111); it waits on the
  roster.

## Rejected

- **A notes field on Tara's existing player notes (`player_notes`).** Those
  are Tara's notes about a player, private from the player. This is the
  player's note to Tara about one clinic, which she must be able to see.
- **Putting the note in the late-request message table.** Different thing:
  that is asking to get in after the close.
- **Letting pros see it.** They do run courts, but she said "only I". If she
  wants it, it is one column in `pro_today()` (question 112).

## How we would know we were wrong

Tara asks why she cannot see notes on the court sheet or why a pro could not
see one; or players ask why they cannot change it after the start.
