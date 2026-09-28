# 0019: Stripe: test money is never money, the key swap, and when a charge is retried, failed or held

**Date:** 2026-09-27 · **Status:** Active · **Source:** the MVP audit of 2026-09-27 (build-now items 3, 4, 11), built on branch `stripe-robustness`, fixed on `fix-sql` after adversarial review

## What we chose

1. **Test-mode money is never money** (20260927200001). `payments.livemode` is
   Stripe's own flag. The board report and the Money numbers exclude
   `livemode = false`; a test-mode fee never marks anyone paid; the one-live-fee
   index and duplicate checks ignore test rows, so a clinic charged in the
   sandbox during the test weeks can still be charged for real after the switch
   if Tara chooses (question 85, default: it is not charged again).
   `payments_ledger` lists test rows until `stripe_live_since`, then hides them,
   so the sandbox payment test (A2) can watch them.
2. **The key swap has one procedure**, and it writes hosted only through
   `supabase db push`: at the swap, a dated migration sets `payments_enabled`
   false, runs `stripe_cutover_to_live()` (clears every account's Stripe customer
   and card summary so everyone adds a real card; refuses a second run and
   refuses after any live payment), and a second migration turns payments on
   with `payments_enabled_at` once the live secrets are confirmed and a test
   event from the Stripe dashboard reaches the live webhook with a 200.
   Rejected: running it by hand in the SQL editor (the reviewer's objection:
   CLAUDE.md allows no hand-written hosted writes).
3. **How a charge attempt ends** (`supabase/functions/_shared/stripe-errors.ts`):
   - *Failed* (the member's card or our request is wrong; Stripe guarantees
     nothing was charged): `card_error`, `invalid_request_error`, or our own
     refusal (`no_card_on_file`, `account_deleted`).
   - *Retried as pending under the same idempotency key*: connection errors,
     timeouts, 5xx, 429, 401, 403.
   - *Held* in processing for a person to check in Stripe:
     `idempotency_error`, or any attempt whose first try is older than 23 hours
     (`payments.first_attempted_at`), because Stripe's idempotency key expires
     after 24 and a resend could charge twice. Tara resolves a held row on the
     Money tab with **Went through** / **Did not go through**
     (`admin_resolve_held_payment`), never with SQL.
   - Rows stuck in processing with no Stripe id are swept after 5 minutes.
   - A webhook that arrives before the PaymentIntent id was stored is matched by
     `metadata.fxe_payment_id`.
4. **The card step waits for a saved card** for about 30 seconds after Stripe's
   sheet completes, then offers Refresh; the webhook is still the only writer
   of the card summary, so a broken live webhook would strand new members: the
   dashboard test event in point 2 is the control.
5. **Deleting an account deletes the Stripe customer** and nulls the id; a fee
   still queued fails as `account_deleted`, and nothing is charged on the way
   out (question 84, default: let it go).
6. **A signed waiver survives a hard delete** (20260927200002, RESTRICT, like
   `card_consents`); only the soft path deletes an account.
7. **Profile shows the card section only while payments are on**, reading
   Tara's *"Let's only do if stripe is connected"* (decision 0016) as applying
   to the whole section.

## How we would know this was wrong

A member is charged twice for one clinic (the ledger shows two succeeded fees
for one player and clinic), a held row sits unresolved for days, or a new member
reports being stuck on the card step after the live swap.
