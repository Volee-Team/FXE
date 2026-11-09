# 0052. Guests: a name on a clinic for someone not in the app (2026-11-07)

**Status:** accepted by John, 2026-11-07 (*"yeah build guests now"*); built in
`supabase/migrations/20261107000003_clinic_guests.sql` and the laptop site.
Tara's phone has them from 1.0.3 (build 17, decision 0054): Add guest in
More, the guest in You're In! with a Guest tag, counted in her total, a
Court menu with the five courts and Remove guest.

## Her words

Tara, by text, 2026-11-07, answering question 144:

> If somebody isn't in the app, I just want the capability of inputting their
> name first and last. And then I would just take care of the payment and
> getting from them. This won't happen much, but I have somebody today, for
> instance, that wants to come to the 430 coed tomorrow, but they don't want
> to input their credit card.

## What we chose

- **A guest is a name on one clinic, not a player.** Its own table,
  `clinic_guests`: first name, last name, court, added and removed times.
  Every player row belongs to an account, and the 1.0.1 and 1.0.2 apps decode
  `players.account_id` as required: a player without one would have failed
  Tara's whole roster on her phone for that clinic.
- **Nothing reaches a guest or touches money.** No notification, no charge, no
  registration, no player screen, no money report. Tara collects her own way.
- **A guest takes a spot.** Wherever the server asks "is there room" (a member
  in the window, a late request, its approval), `clinic_taken` counts You're
  In! plus live guests. Her counts on the laptop include them, and so does the
  clinic-full question (decision 0051).
- **On the laptop:** Add guest on a clinic (first and last name), the guest in
  You're In! with a Guest tag and the court menu, on the court sheet marked
  "(guest)", and Remove. Removed is a timestamp, never a delete (hard rule 4).
- **On the phone (1.0.3, build 17):** the same, on her clinic page: More >
  Add guest (with the full-clinic question, decision 0054), the Guest tag in
  You're In!, the Court menu, Remove guest. In the 105 rounds' pickers too.
- **Not yet:** guests on the pros' tab (`pro_week` lists You're In!
  registrations only; a guest reaches a pro only by name in the 105 rounds),
  and reusing a guest across clinics (each add is a new name on that clinic).

## Rejected

- **A player row owned by Tara's account:** her Profile and My Clinics would
  list every guest as her own, and notifications about them would reach her
  phone.
- **A player row with no account:** breaks the shipped apps (above).

## Tests

`tests/sql/clinic_guests.sql` from the rule; `web/tests/admin.spec.mjs`.
