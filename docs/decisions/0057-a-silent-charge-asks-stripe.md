# 0057. A charge Stripe never answered for is asked about (2026-11-14)

**Status:** accepted by John, 2026-11-14 (*"yeah build the fix"*); built in
`supabase/functions/stripe-charge/index.ts` (`askStripeAboutSilent`) and
`supabase/functions/_shared/payment-outcome.ts`. No migration. Narrows the
"only writer of ledger outcomes" line of decision 0009: the webhook is still
the first writer, and stripe-charge now records the same outcome when the
webhook never did.

## What happened

On 2026-11-13 at 11:46 ET Tara charged a player $23 for an 8am clinic.
`stripe-charge` sent it and stored the PaymentIntent id; the row went to
Processing, and no webhook ever moved it. A day later Tara asked whether the
player's card worked. It did: a $28 charge on the same card at 1:11 pm went
through normally, and 214 other charges in the ten days before had all been
settled by the webhook.

The row had nowhere to go:

- not paid, so the clinic's money was short;
- not chargeable again, since the unique index allows one live charge;
- not held, because held rows are the ones `stripe-charge` knows are in
  doubt (`retry_window_passed`, `idempotency_error`, 20260927300003).
  Tara's "Went through / Did not go through" buttons are only on those, so she
  had nothing to click.

The only way to learn the truth was Stripe's dashboard. Nobody who works on
the app could open it: the account is under Alex, who is out.

## Decision

Each time `stripe-charge` runs (every Charge Tara taps, on the phone or the
laptop), before it sends anything new, it looks for fees that meet all of
these:

- in processing with a PaymentIntent id;
- not held;
- not a refund;
- not touched for 30 minutes.

For up to 25 of them it asks Stripe for the PaymentIntent. It records the
answer by the same rule the webhook uses, which now lives in one place,
`supabase/functions/_shared/payment-outcome.ts`:

| PaymentIntent | The row |
|---|---|
| `succeeded` | succeeded; failure text cleared; the paid flag and the declined-card triggers run as for the webhook |
| `requires_payment_method` with an error | failed: Stripe's sentence, plus the bank's code for a `card_error` only (0024, 0026) |
| `canceled` | failed, `canceled_at_stripe`, no code: no money moved and it is not the card's fault, so nobody is blocked |
| anything else (still processing, needs action, never confirmed) | left alone, asked again next time |

The safety rules:

- **It only reads from Stripe.** It never charges, confirms or cancels anything.
- **The webhook always wins.** Each write requires that the row is still in processing with the same PaymentIntent id, so an outcome the webhook recorded in the meantime stands (hard rule 3).
- **A failed look-up never blocks charging.** It is logged, tried again on the next call, and the charges after it go out as before.
- **Livemode comes from the PaymentIntent.** The value Stripe returns is stored, so test-mode money still never counts.

## Rejected

- **A nightly job.** It would settle the row without anyone tapping anything, but it is a new scheduled function with its own secrets and failure mode. Tara charges every clinic day, so the Charge call already comes round daily.
- **Showing the held buttons on any old processing row.** It still needs someone who can see Stripe, and nobody can.
- **Writing the PaymentIntent's status straight from `paymentIntents.create`.** Most off-session card charges answer `succeeded` there. It would have settled this row at once, but it adds a second outcome path at send time. The look-up covers that case within 30 minutes and also covers rows already stuck. It can be revisited if 30 minutes proves too long.

## Tests

- **`tests/stripe/outcome.test.ts` (deno):** every row of the table above, plus a check that the webhook's two outcomes and the look-up's are the same rule.
- **`tests/stripe/run.sh` section 9c:** the wiring against stripe-mock.
  - The look-up runs, and the charge call still answers.
  - An undecided PaymentIntent changes nothing.
  - A held fee and one sent moments ago are never looked up.
  - stripe-mock answers every retrieve with the same undecided fixture, so a late success or decline is pinned by the unit test, not the mock.
