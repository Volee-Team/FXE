# 0061. Juniors phase 1, the server: children, a waiver per child, programs, Elite approvals (2026-11-17)

**Status:** accepted by John, 2026-11-17 (*"yes start phase 1"*). Built in
`supabase/migrations/20261118000001_juniors_family.sql` and its review
fixes `20261118000002_juniors_family_review.sql`, pinned by
`tests/sql/juniors_family.sql`, `tests/sql/juniors_review.sql`,
`pro_role.sql` r10 and three race scripts (`remove_child_race.sh`,
`membership_accept_race.sh`, `child_lock_race.sh`). Not pushed to hosted. The app, the members'
site and Tara's laptop come next, in the same phase.

## What her document asks (spec 01)

- *"Profile → My Children → Add a Child. Collect child name and birthday.
  Support multiple children."*
- *"Require a parent-signed waiver for each child."* Question 145: "Yes" to
  the tennis camp parent/guardian form, once per child per year (decision
  0060).
- Five programs with her age guidance; *"Never assign a group automatically
  from a birthday."*
- *"Junior Elite and Elite approvals are specific to the program and carry
  between school-year and summer offerings. Tara can preapprove current
  players."*

## Decision

**Phase 0's rule stands.** An app already on a phone reads `players` and
sees the adult alone. A child is reached only through new functions, which
only the 1.0.5 app, the members' site and the laptop call. None of the three
new tables has a client grant.

1. **A child is a `players` row** (kind `junior`, first and last name, a
   birthday) on the parent's account.
   - Adding one turns an `adult` account into `both`. A `parent` account
     stays `parent`.
   - The same name and birthday twice on one account is refused
     (`child_exists`): *"avoid duplicate child profiles"*.
   - Removing a child archives the row (hard rule 4). It is refused while
     the child holds an upcoming spot (`child_has_upcoming`).
   - The birthday may not be missing or in the future. No age limit:
     programs are chosen by hand, never from the birthday.
   - **At most 10 children per account** (`too_many_children`). A default,
     not her rule: John can change it.
2. **The junior waiver is a `waivers` row of kind `junior`.**
   - The key `junior_waiver_version` in `app_settings` makes it current.
   - Signatures go in `junior_waiver_acceptances`: one per child per
     version, signed by the parent with their typed legal name, the
     account's email and the time.
   - "Once per year" means Tara publishes a new version each year. There is
     no date math.
   - **Her text is not in the repo yet, so this migration inserts none.**
     Until it does, every child reads `not_available`, never `needed`.
   - Phase 2's registration check refuses with `junior_waiver_not_available`,
     a different error from the one a parent can fix. A missing text is
     loud, not a silent block.
   - The text goes in with a small migration, the way the adult waiver did
     (20260921000002).
   - Each acceptance table carries its kind in a composite foreign key, so
     an adult signature cannot sit on junior text, or the reverse.
3. **`junior_programs`** holds her five, in her order:
   - Red Dot, ages 3-6;
   - Orange Dot, ages 6-10;
   - Recreational Yellow, ages 10+;
   - Junior Elite and Elite, which need her approval.

   Descriptions are empty for Tara to write. Only she edits them, and she
   archives rather than deletes.
4. **`program_approvals`** has one row per child and program, with no season
   in it, so an approval covers school year and summer alike.
   - The parent asks; a second tap changes nothing.
   - Tara answers a request once (`approval_already_decided`), or approves
     a child directly (preapprove), which is also how she changes her mind
     after a decline.
   - The parent cannot ask again after a decline (`approval_declined`).
     That default is question 169.
5. **No notifications yet.**
   - A parent's request shows in Tara's list (`admin_program_approvals`),
     for her Action Needed on the laptop.
   - A push to Tara or the parent needs wording John signs off (hard rule
     13), so it waits for that.

## Who sees a child

Only the child's own parent account and Tara. Another member, a pro and a
signed-out caller get `not_your_child`, `not_authorized` or
`not_authenticated`, never a row; the probe checks each. Pros see a child in
phase 3, on a day the child is rostered.

## Open

- **Question 169:** after Tara declines, may the parent ask again?
- **Question 170:** should Tara get a notification when a parent asks for
  Elite approval, and the parent one when she answers?
- **The parent/guardian text itself:** John to get the file, the way the
  adult waiver came (`FXE_Adult_Tennis_Participation_Waiver.docx`).

## Review (2026-11-18)

The sql-auditor read `20261118000001` before it went anywhere. Every
finding is fixed in `20261118000002`, each pinned red first. Each refusal
is also checked by the state it leaves (hard rule 9).

| # | Finding | Fix | Probe rows |
|---|---|---|---|
| H1 | A parent could put an unsigned child on a juniors clinic: `register_for_clinic`, `request_late_spot` and the Accept of `respond_to_invitation` took a child through `owns_player()` and asked only the account's adult waiver | A child needs a signature on the current junior waiver (`junior_waiver_required`). While none is published: `junior_waiver_not_available`. Tara is exempt, as from the adult waiver. A child no longer needs the parent's adult waiver, which is about an adult playing; the adult still needs her own. A child in an adult clinic hears `wrong_player_kind` first, before any waiver question | `juniors_review` h1a to h1p |
| M2 | An archived child could still be registered, ask late or accept | Each reads the player `FOR SHARE` and only while active (`player_not_found`). `FOR SHARE` waits for `remove_my_child`'s `FOR UPDATE`. Removing also waits for a pending late request | m2a to m2h |
| M3 | A parent could rename a child, or change the birthday, after Tara decided a program or after a waiver was signed | `child_locked`; Tara corrects such a child. The signature keeps the child's name and birthday as signed, so `delete_my_account`'s blanking leaves the record whole | m3a to m3h |
| M4 | `pro_today`, `pro_week` and `clinic_round_people` showed a rostered child's full name to every pro | Until phase 3 a pro sees a juniors clinic, not its children. Tara still sees them | `pro_role` r10 |
| L5 | `my_news` counted an archived child for juniors news; `my_clinic_messages` showed a child's clinic messages to the apps already on phones | Active rows and the adult's clinics only (phase 0's rule). The new apps read the family's messages in phase 2 | l5a to l5d |
| L6 | `set_my_gender` and `request_level_approval` accepted a child | `wrong_player_kind` | l6a to l6d |
| L7 | `waiver_version()` and `current_waiver()` would read junior text if the setting named it | Adult text only | l7a, l7b |
| L8 | Only the function guarded who signs for which child | Trigger `guard_junior_waiver_acceptance`: the child is an active junior of the signing account, on any path, and a signature is never edited (`signature_is_final`) | l8a to l8e |
| L9 | No ceiling on children per account | 10 (`too_many_children`), John's to change | l9a to l9c |
| 10 | Seven refusals in `juniors_family` were checked by their error alone | Each also asserts the state after it | a4b, a5e, a6d, w4b, c10a2, p5a2, p5b2 |

### Second pass (2026-11-18)

The sql-auditor read `20261118000002` too. Its four findings are fixed in
the same file: it is on no database yet, and the "No edits to existing
migrations" check compares only against `main`.

| # | Finding | Fix | Probe |
|---|---|---|---|
| S1 | `clinic_rounds` still gave a pro a seated child's name and registration id. With that id, `admin_set_round_court`, `pro_assign_court` and Came / No-show (`require_pro_today`) let a pro move or mark the child | A pro sees adults and guests in the rounds. Each move answers its existing single refusal on a child: `not_in_clinic`, `not_this_week`, `not_today` | `pro_role` r10 (six red before), each red under its own mutation |
| S2 | The new active check refused an adult Tara had deactivated with her Active switch: an adult regression | The check is the child's alone: an adult registers, asks late and accepts as before | a2a to a2c (red before) |
| S3 | `FOR SHARE` on the player deadlocked with Tara's membership switch, which updates the player and then locks the member's clinics through `follow_membership` | `FOR KEY SHARE`: it still waits for `remove_my_child`'s `FOR UPDATE`, but not for a plain update | `membership_accept_race.sh` (a deadlock before); `remove_child_race.sh`, six orders, red with the lock taken out |
| S4 | Tara's decision did not lock the child, so a rename could commit beside her approval of the old name | `admin_decide_program_approval` and `admin_preapprove_program` take the child `FOR KEY SHARE` first | `child_lock_race.sh` (both of Tara's orders red before) |

**Not changed, noted:** if a pro re-saves a court on which Tara seated a
child, the save replaces the whole court and the child's seat goes with
it. Juniors 105 rounds are not in use before phase 3, which decides what a
pro sees of children.

**For John:** a signed junior waiver keeps the child's name and birthday,
beside the parent's typed name and email, after the account is deleted. It
is the legal record, as the adult waiver keeps the adult's. The privacy
policy should say so; that wording is his to write and approve (plan,
phase 1, item 5).

Before the fix, 39 of `juniors_review`'s 50 rows and `pro_role`'s three r10
rows were red. The rest are "still works" rows and states that already held.
Each fix also went red under a single-rule mutation, 27 in all, except two
layers that each stay green alone because the other holds:
`current_waiver`'s kind filter (behind `waiver_version`) and
`accept_child_waiver`'s owner check (behind the trigger). The fix
migration rewrites the six existing functions from their latest bodies,
adding only the marked lines.
