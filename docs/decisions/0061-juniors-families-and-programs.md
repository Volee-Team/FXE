# 0061. Juniors phase 1, the server: children, a waiver per child, programs, Elite approvals (2026-11-17)

**Status:** accepted by John, 2026-11-17 (*"yes start phase 1"*). Built in
`supabase/migrations/20261118000001_juniors_family.sql`, pinned by
`tests/sql/juniors_family.sql`. Not pushed to hosted. The app, the members'
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
