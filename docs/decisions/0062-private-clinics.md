# 0062. Private clinics (2026-11-27)

**Status:** approved by John, 2026-11-27 (a Private switch); built in
`supabase/migrations/20261127000003_private_clinics.sql`, Tara's phone (the
clinic page and her Manage cards) and the laptop site. The two new strings
wait for John in `docs/copy-review.md`.

## Her words

Tara, 2026-11-23, in her next-update note:

> private events/clinics and allow me to privately invite people to that
> clinic for payment. Maybe I still can do this actually but not 'publish' it?

She could not. A clinic she has not published refuses an invitation
(`admin_invite_player` raises `clinic_not_published`, because a player could
not open it), and a published clinic is listed to every member.

## What we chose

A switch on the clinic, **Private**, off for every clinic until she turns it
on (`clinics.is_private`, set only by `admin_set_clinic_private`).

- **Who sees it.** `clinics_public` lists a private clinic only to an account
  with a player on it in You're In!, Waitlist or Response Needed: whoever she
  invites, adds or moves there. Every other rule of the list is unchanged (a
  canceled clinic only for who was on it, no juniors, Ladies and Men by the
  player's answer, the level). Someone who cancels, declines or is removed no
  longer sees it.
- **Who gets on it.** Only Tara. `register_for_clinic` (so the Waitlist too)
  and `request_late_spot` refuse a private clinic to anyone not on it with
  `clinic_not_found`, exactly what an unpublished clinic says, so the refusal
  does not tell anyone it exists. Someone already on it hears
  `already_registered`, as any second sign-up does. A player's own call never
  adds a row on a private clinic: allowing "already on it, go ahead" would let
  a removal committing at the same moment put them back (the sql-auditor,
  2026-11-27). Tara registering someone is exempt, as she is from the other
  registration rules.
- **What keeps working, on purpose.** Her invitation (`admin_invite_player`)
  and the player's Accept (`respond_to_invitation`), adding someone
  (`place_player`), the Waitlist's Invite and Move In, guests, messages,
  courts, rounds, charging, the player's Cancel, the calendar feed, My Clinics
  and Past clinics. None of them reads the list.
- **Pros** still see a private clinic in their week (`pro_week`, `pro_today`,
  the rounds). They are staff working it, as Tara is, not players looking for
  a clinic. Pinned as `a_pro_sees_it_in_the_week` so a change is deliberate.
- **Nobody is told.** Switching it on or off sends nothing. Nothing else
  announces a clinic either: publishing tells nobody, and every notice about a
  clinic goes to who is on it, and (since `20261127000004`, decision 0025
  amended, Tara: "every pro sees every clinic message") to every pro: her
  messages to the clinic and its cancel notice. Pinned as
  `the_pros_are_told_of_a_private_message`.
- **Copy to next week keeps it** (`admin_copy_week`), so a private event
  copied with the week is not listed to everyone the day she publishes the
  copy. A clinic from a template, or a new one, starts not private.
- A private clinic can still be a draft; it becomes visible to who is on it
  once published, as now.

## Rejected

- **"Not published" as private.** Her own suggestion. A draft cannot be
  opened by a player, so an invitation to it would land on nothing; and
  "draft" already means "not ready", which her laptop treats differently
  (Publish button, copy week).
- **A per-clinic invite list** separate from registrations. Registrations
  already say who is on a clinic; a second list would drift from them.
- **Exempting the account's other players** (a parent's second child). Only
  people she invites or adds: a family asks her.
- **A Private flag in `clinics_public`.** A player never needs it; the list
  simply contains what they may see.

## How we would know we were wrong

She asks why someone she added cannot see the clinic (a gap in the
in/pool/response_needed rule), or a member who was never on a private clinic
mentions it. Or she wants pros kept out of one: then `pro_week` and
`pro_today` gain `not c.is_private` and the pin flips.

## Tests

`tests/sql/private_clinics.sql` (red first against the schema without the
column; each guard and the view's condition removed one at a time turns its
rows red); `web/tests/admin.spec.mjs` (private clinics);
`FXETennisUITests/AdminFlowUITests.swift` (`testAdminL_PrivateSwitchAndChip`).
