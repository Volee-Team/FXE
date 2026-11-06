# 0048. Below a clinic's level, a player asks Tara once (2026-11-05)

**Status:** accepted by John, 2026-11-04 ("now make the changes"); built in
`supabase/migrations/20261105000002_level_approval.sql`. Item 4 of Tara's
email of 2026-10-15 (decision 0041), which was recorded and never built.
Same day, same PR: the non-member 90-minute price goes from $28 to $30 for
clinics from the week of 2026-11-08
(`supabase/migrations/20261105000001_nonmember_ninety_thirty.sql`).

## Her words

Email of 2026-10-15 (decision 0041): *"For a 2.5 player who hasn't been
approved, please show: 'You're currently rated 2.5. You can request approval
from Tara to attend Ladies 3.0+ clinics. Once approved, you can sign up without
requesting again.' Button: Request Approval for Ladies 3.0+ ... The request
should come to me for approval. Requesting approval does not confirm them for a
clinic. I also want to be able to go directly into someone's profile and
approve them myself. Their actual rating should stay 2.5, but their profile
should clearly show: 'Approved to attend: Ladies 3.0+' ... That approval stays
until I remove it, and they should be notified when approved."*

By text, 2026-11-04: *"someone as a 2.5 level can request a spot in the 3.0+
clinic. I'd have to approve. Same for 4.0 clinic, 3.5 player needs to ask. And
that it's a one time approval. Doesn't need to happen every time"*.

And the price, same thread: *"All clinics starting next week for nonmembers
will go from $28 to $30"*.

## The rule

- **A clinic's level is the NTRP number in its name**: "Ladies 3.0+" is 3.0,
  "4.0 Clinic" is 4.0, "All-Level" and "105" have none. `clinics.min_rating` is
  a stored generated column, so Tara sets it by naming the clinic the way she
  already does, and every path that makes or renames a clinic carries it.
- **Rated below it, with no approval at that level or above**: the server
  refuses Register and the late request (`level_approval_required`, a
  before-insert trigger beside decision 0044's audience trigger). The app and
  `/play` show her sentence and her button instead.
- **Asking** (`request_level_approval`) records one request and tells Tara
  once: "{Name} ({rating}) asked to attend {level}+ clinics." It registers
  them for nothing.
- **Tara answers** in Action Needed (phone and laptop) or on the player's page,
  where she can also approve with no request first ("Approve for"). One
  approval per level, kept until she removes it, and it covers that level and
  everything below. The player is told once: question 123's sentence, "You're
  approved to attend Ladies 3.0+ clinics."
- **Their profile shows** "Approved to attend: Ladies 3.0+" (Men's for men, the
  bare level for an unanswered gender). Their rating never moves.
- **Tara places anyone anywhere** (decision 4): her Add player and her
  invitations are not gated.

## The rating became Tara's

Since 2026-09-02 a player could change their own rating on Edit details, which
would make the gate one edit deep. So the rating is now what membership became
on 2026-09-21: given at sign-up (or once, if never given), Tara's afterwards.
A trigger refuses a changed rating (`rating_set_by_tara`), not a revoked
column grant, because the 1.0.x app sends the rating unchanged with every Edit
details save and a revoked grant would fail the whole save. Tara changes it with
`admin_set_player_rating`, from the laptop's Players tab. The app and `/play`
show it with no caption (decision 0024 removed "Set by Tara").

## What review found

The sql-auditor (2026-11-05) walked round the first version: a 2.5 inserted a
second `players` row on her own account, rated 3.0, and registered that row.
No client inserts players, so the migration revokes INSERT on `players` from
`anon` and `authenticated`; `level_approval.sql` attacks it. It also moved the
price migration's snapshot update off any row already paid or charged, and put
the approval sentence back to question 123's.

## Defaults until Tara says otherwise

Questions 135 to 138 in `docs/questions-for-tara.md`: approval per level rather
than per category (question 121's default said per category); a player with no
rating is not gated; a player two levels below may still ask; Decline and
Remove both delete the row, so the player can ask again (hard rule 4 keeps
history for registrations and money, and a request is neither).

## Verified

`tests/sql/level_approval.sql` (41 checks; 6 red with the triggers disabled),
`testAdminK_ABelowLevelPlayerAsksAndTaraApproves` (Gina, a 2.5 in the seed,
asks; Tara approves from Action Needed; Gina sees Register and her profile
line), `LevelGateTests` (8), and four browser tests on `/play` and the laptop.

## Switched off, 2026-11-06

At noon on Friday, when non-members could first register, Tara saw players
below a clinic's level refused by the 1.0.1 app with "Sorry, someone beat you
to the punch" (the store app predates the Request Approval button and reads
an unknown refusal as a race), about 60 players were rated below 3.0, and
she texted *"A lot of people won't get in then right now ... Turn off now!"*.
`20261106000002` adds `app_settings.level_check_enabled`, set to false on
hosted the same hour: the trigger lets every registration through and the
clinic views hide `min_rating`, so the site and the app offer Register to
everyone. Approvals already given are kept. **The lesson:** a server refusal
the app in the store does not know becomes the wrong sentence on every
member's phone, so a new refusal ships after the app that explains it, or
behind a switch that starts off. Turning it back on (one migration) waits
for 1.0.2 in the store and Tara's yes.
