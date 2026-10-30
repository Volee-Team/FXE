# 0044. Clinics by gender: men see Men and Coed, women see Ladies and Coed (2026-10-30)

**Status:** accepted by John, 2026-10-30. John stands in for Alex on
engineering calls and copy while Alex is away (2026-10-30). Tara's rule,
relayed by John from her group text, with John's answers to how it is asked.

## Her words

> Can't believe I didn't think of this, but if you're a man, you should only
> be able to see the registration for coed or men's league. You shouldn't be
> able to see any ladies clinics.

John, 2026-10-30: the same for women (Ladies and Coed only); ask it at
sign-up; and for everyone already signed up, a one-time question the next
time they open the app.

## What was built

- **`players.gender`**, `female` or `male`, NULL until answered
  (`supabase/migrations/20261030000001_clinics_by_gender.sql`).
- **The rule lives in one function**, `audience_open_to(audience, gender)`:
  Coed (and Juniors) are open to everyone; Ladies to women; Men to men; an
  unanswered player to everything.
- **Hiding is the database's job** (hard rule 1). `clinics_public` drops a
  Ladies clinic from an account whose players are all men, and a Men clinic
  from one whose players are all women. A clinic the account already holds a
  registration in stays listed, so a spot Tara placed by hand never vanishes.
  Tara's own screens read `clinics_admin`, which is unchanged.
- **Registering is refused too**, not only hidden: a `before insert` trigger on
  `registrations` and `late_requests` raises `audience_mismatch` for a
  player's own insert. A trigger rather than a line in `register_for_clinic`,
  so every path that inserts is covered and that function's body is not copied
  a fourth time (decision 0041's rewrite of it is still to come). Tara is
  exempt: she places anyone anywhere (decision 4). The app and `/play` show the
  existing line "That just changed. Here's the latest." and reload, which
  drops the clinic; it is only met on a page loaded before the answer.
- **Who writes the answer.** The player, once, through `set_my_gender`
  (the same answer again is harmless; a different one is refused,
  `gender_already_set`). Tara changes or clears it with
  `admin_set_player_gender`, from a dropdown on each row of her Players tab.
  Hard rule 8's three layers: no column grant, the RPC's own checks, and a
  trigger backstop (`guard_player_gender`) for any future path. A player row
  inserted by its owner arrives unanswered (`guard_player_gender_insert`).
- **Asked at sign-up**: "Gender" with Female / Male on the profile form, app
  and `/play`, required like the membership question.
- **Asked once of everyone else**: `GenderQuestionView` (app) and the
  `/play` page of the same name, after the waiver and before Home, with the
  usual Sign out and Delete my account footer. Tara and her pros are not
  asked, as with the waiver.
- **The seed answers for every seed player**, so the question does not stand
  in front of every UI and browser test; a test that wants it clears one.

## Defaults chosen (questions 126 to 130 in `docs/questions-for-tara.md`)

1. Unanswered sees everything. The 1.0.0 app in the store has no question, so
   hiding from the unanswered would hide from every current member until they
   update.
2. The player answers once; changes are Tara's.
3. A clinic Tara placed someone in stays visible to them.
4. Wording "Gender", "Female", "Male" (approved by John, `docs/copy-review.md`).
5. **The app goes by the clinic's Audience box, never its name.** A clinic
   named "Ladies 3.0+" whose Audience is Coed shows to everyone. The seed's own
   "Tuesday Ladies 3.0+" is Coed, which is exactly the trap: hosted clinics
   must be checked, and corrected on Tara's clinic form, before this matters.

## Rejected

- Filtering in the clients only: hides nothing (hard rule 1).
- Deciding by clinic name ("Ladies" in the title): the Audience field exists
  for this and names are free text.
- `security_invoker` on the view: breaks the information-hiding model (hard
  rule 11).
- `is_admin()` inside `clinics_public`: Tara does not read it, and
  `pro_role.sql` treats any view naming `is_admin()` as admin-only.
- Adding a parameter to `create_my_account`: a second call
  (`set_my_gender`) keeps old clients working and the one-time question
  catches a save that failed.

## Checked

`tests/sql/clinics_by_gender.sql` (25 checks), each rule proven red by one
break at a time before it was trusted: the rule function opened, the view's
"already registered" clause removed, Tara's trigger exemption removed, either
trigger dropped, the owner check, the once-only check (with the backstop
trigger also dropped, since either alone holds), the insert guard, a column
grant, `require_admin`, and an anon grant. Four older probes used Ladies
clinics as neutral fixtures with men registering into them; those fixtures
are Coed now (`late_cancellation`, `late_requests`, `back_to_back_105`,
`card_consent`). On the simulator and on `/play` locally: the question
appears for an unanswered player, the clinic list then hides the Ladies
clinic from a man, and Tara's dropdown writes the column.
