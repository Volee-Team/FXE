# 0037: Tara charges each person on their own tap

**Date:** 2026-10-02 · **Status:** Active · **Source:** Tara, relayed by Alex
2026-10-02: an admin view on her phone with *"a button next to every name and
she can just say 'charge charge charge' for each person, like a green button
next to them"*; then *"she wants it to be completely individual charging
people, OR she can cancel people on the clinic roster, for example this kid
was puking and she didnt charge that person"*.

Supersedes the one-tap-per-clinic part of decision 0012 ("Charge clinic").
What anyone owes is unchanged: came pays the clinic price, a no-show and a
late cancel pay the full fee, all after the clinic ends, all on her tap.

## What we chose

1. **One green Charge button per person, on the roster, after the clinic
   ends** ("Charge $18"), on the phone and the laptop. One tap charges that
   person, no confirmation, because her ask is speed. It then reads
   Processing until Stripe answers, then Charged; a declined card reads
   Declined beside the button, which charges again. "No card" where nothing
   is saved. A late cancel in the Canceled list gets the same button.
2. **Charge clinic is gone from both screens.** The phone's More menu holds
   only Cancel clinic; the laptop's Action Needed row says Open and scrolls
   to the roster instead of charging everyone. `admin_charge_clinic` stays on
   the server, unused, so nothing that calls it breaks (hard rule 6), and
   bringing the button back is a client change.
   After a clinic ends the row is Came / No-show, Remove and Charge; the
   Court menu is shown only before then (courts no longer matter, and the
   row cannot hold four controls on a small phone).
3. **"Don't charge this person" is Remove**, now a visible button on every
   row after the clinic (it was inside the Court menu on the phone; the
   laptop already showed it). The server already allowed it after a clinic
   ended: canceled, not late, no fee, and the player is told nothing.
4. **One rule for who owes, not two.** `admin_fees_due` and
   `admin_charge_player` (20261002000001) read `money_rows()`, the same
   definition the Money tab, Action Needed and Charge clinic use, rather than
   copying its CASE. The app draws a button for exactly the rows the server
   lists; the server re-checks on the tap.

## Since the review (2026-10-04, before hosted)

The sql-auditor found no critical issue and five worth fixing, all in
20261002000001 before it reached hosted: a draft Tara never published was
chargeable once its time passed (money_rows now counts published clinics
only); a rain-out cancel racing a Charge tap could both commit (the clinic
is locked FOR SHARE before the registration); one person could get two
late fees' buttons (only the newest late cancel owes); every per-clinic read
computed the whole club (money_rows takes an optional clinic). A late
canceller cannot be let off: that is question 106 for Tara.

## Rejected

- **Calling `admin_charge_registration` straight from the row.** It takes the
  kind from the caller and does not check the clinic has ended, so the
  client would be deciding what someone owes.
- **A confirmation per charge.** Safer against a mis-tap, slower than she
  asked for; a wrong charge is refunded in Stripe.
- **A separate "Waive" that keeps the player on the roster.** She described
  removing them. If she later wants the history to say "came, not charged",
  that is a new state and her call.

## How we would know we were wrong

- She charges someone by mistake more than once: add an undo window or a
  confirmation.
- She asks for Charge clinic back for big clinics: the server function is
  still there.

Pinned by `tests/sql/charge_each_player.sql` (27 checks, red on three
separate breaks), `web/tests/admin.spec.mjs` "charging each person" (red on
the old page), and `AdminFlowUITests.testAdminG_ChargesEachPlayerAndRemovesOne`.
