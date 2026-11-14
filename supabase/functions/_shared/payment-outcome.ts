// What a PaymentIntent's state means for its ledger row, in one place.
//
// Two writers use it: stripe-webhook, when Stripe reports an outcome, and
// stripe-charge, when it asks Stripe about a fee still in processing long
// after it was sent (decision 0057). On 2026-11-13 a $23 fee reached Stripe,
// no webhook ever recorded its outcome, and the row sat in Processing with
// nothing anyone could click: Tara's held-charge buttons are only for rows
// we know are in doubt, and nobody on the team could open Stripe's dashboard.
// The answer has to be the same whichever writer asks, so it lives here.
//
// Pure: no database, no network. tests/stripe/outcome.test.ts pins it.

import type Stripe from "npm:stripe@17.5.0";

export type LedgerOutcome = {
  status: "succeeded" | "failed";
  failure_reason: string | null;
  failure_code: string | null;
};

// payment_intent.succeeded: the money moved. Clears any earlier failure text,
// so a PaymentIntent that failed and then went through stops reading
// "Declined".
export function succeededOutcome(): LedgerOutcome {
  return { status: "succeeded", failure_reason: null, failure_code: null };
}

// payment_intent.payment_failed. failure_code (20260926000010) is Stripe's
// machine code: decline_code when the bank gave one (insufficient_funds,
// expired_card, ...), else the error code (card_declined, incorrect_cvc, ...).
// Only for a card_error (20260928700001): a code means Stripe said no to the
// CARD, and the database then blocks the player's next registration
// (decision 0026). A request Stripe refused (invalid_request_error: our
// parameters, nothing reached the bank) keeps only its sentence.
export function failedOutcome(pi: Stripe.PaymentIntent): LedgerOutcome {
  const err = pi.last_payment_error;
  return {
    status: "failed",
    failure_reason: err?.message ?? err?.code ?? "declined",
    failure_code: err?.type === "card_error" ? (err.decline_code ?? err.code ?? null) : null,
  };
}

// The PaymentIntent as it stands now (stripe-charge's look-up). Null means
// "not decided yet, leave the row alone":
//   succeeded                                  -> succeeded
//   requires_payment_method with an error      -> failed (an off-session
//                                                 confirm that the bank or
//                                                 Stripe turned down lands here)
//   canceled                                   -> failed, no code: no money
//                                                 moved, and it is not the
//                                                 card's fault, so it blocks
//                                                 nobody
//   anything else (processing, requires_action,
//   requires_capture, requires_confirmation,
//   requires_payment_method with no error)     -> null
export function outcomeOf(pi: Stripe.PaymentIntent): LedgerOutcome | null {
  switch (pi.status) {
    case "succeeded":
      return succeededOutcome();
    case "requires_payment_method":
      return pi.last_payment_error ? failedOutcome(pi) : null;
    case "canceled":
      return { status: "failed", failure_reason: "canceled_at_stripe", failure_code: null };
    default:
      return null;
  }
}
