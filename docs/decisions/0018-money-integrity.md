# 0018: Money integrity: one fee per player per clinic, Tara's late cancel, Money from the ledger, only clinics after payments went on

**Date:** 2026-09-27 · **Status:** Active (defaults until Tara answers questions 80 to 84) · **Source:** the MVP audit of 2026-09-27 (build-now items 2, 5, 6, 13), built on branch `money-integrity`, fixed on `fix-sql` after adversarial review · **Supersedes:** decision 0010 §6 ("Tara's own removals are never late")

## What we chose

1. **One fee per player per clinic.** A fee is *live* while pending, processing,
   or succeeded and not refunded in full. While a live fee exists, no second fee
   of any kind is charged to that player for that clinic, on any of their rows.
   Enforced in `admin_charge_registration` under an advisory lock keyed on
   player and clinic (20260927100001), pinned by `tests/sql/one_fee_race.sh`
   (two concurrent charges of different kinds: exactly one lives). It only ever
   prevents a charge. The way to change a label after charging is refund, then
   change it, then charge.
2. **A charged row is not relabelled.** A no-show flip, Tara's Late cancel, or
   her Remove on a row that holds a live fee is refused with
   `charged_refund_first` ("Already charged: refund it first.").
3. **A canceled clinic is never charged** (`clinic_canceled`), including late
   cancels made before it was canceled (question 82).
4. **Tara can record a late cancellation** (`admin_mark_late_cancel`), inside
   the cutoff or later, with an optional note; the full fee then applies at
   Charge clinic. Her plain Remove stays free and never late. Her own words,
   2026-09-22: pros *"can label them as no show, late cancellation"*.
5. **Her removals tell nobody**, and no longer land in her own Action Needed as
   the player canceling: `cancel_registration` notifies the admins only when
   the caller owns the player. Telling the player needs her words (question 79).
6. **Money numbers come from the ledger** (20260927100003): Charged is succeeded
   fees minus their succeeded refunds, all time, the same as the board report's
   collected. Declined and Not charged yet count only ended, not canceled
   clinics. Each owing row is exactly one of charged, refunded (settled),
   declined (counted once) or not charged, decided by existence, not by the
   latest timestamp. `revenue_summary` stays (hard rule 6) for the four counts.
7. **Only clinics that ended after payments went on are owed.**
   `app_settings.payments_enabled_at` is set in the same migration that turns
   payments on (checklist A9); `money_rows`, Action Needed, Charge clinic and
   the web's This week all use that one definition, and a registration Tara
   marked Paid with no live fee is settled. Found by the review: without it,
   switching payments on would have prompted, and one tap would have charged,
   every clinic ever played, including ones already paid by Zelle.
8. **Action Needed shows "{clinic} ended, not charged yet"** only while
   payments are on and only when one more Charge clinic would charge someone
   with a card, and **"{name}'s card was declined"** for each decline. Declines
   of deleted accounts stay out of Action Needed.
9. **A player cancelling their own spot is not told their court number**:
   `cancel_registration` returns the row with `court_number` and `canceled_by`
   blanked unless the caller is an admin (decision 17), pinned by
   `information_hiding.sql`.

## Rejected

- **"Not charged yet" read literally as "no live charge"**: it counted a declined
  fee twice and nagged forever about a fee refunded on purpose.
- **"Declined" as "the latest charge failed"**: rows inserted in one transaction
  share one `now()`, so "latest" was a coin toss.
- **A fee per registration row** (the unique index of 20260926000010): a late
  cancel followed by Tara putting the player back made two rows and two fees.

## How we would know this was wrong

Tara says someone who canceled late and came anyway should pay twice (question
80), or a clinic canceled for rain should still charge its late cancels
(question 82), or she needs a way to write off a declined fee (question 83).
