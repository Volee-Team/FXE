// outcome.test.ts: what a PaymentIntent's state means for its ledger row
// (supabase/functions/_shared/payment-outcome.ts, decision 0057). stripe-mock
// answers every retrieve with the same fixture, so it can never show a fee
// that succeeded or was declined after the fact; this is where those
// branches are pinned. Run by tests/stripe/run.sh:
//
//   deno test --allow-env --allow-read tests/stripe/outcome.test.ts
//
// Expected outcomes are written out here, not read back from the rule:
//   succeeded -> succeeded, failure text cleared; declined (requires_payment_method
//   with an error) -> failed, with the bank's code for a card_error only;
//   canceled -> failed with no code (blocks nobody); anything still in
//   flight -> null (the row is left alone).

import type Stripe from "npm:stripe@17.5.0";
import { outcomeOf, failedOutcome, succeededOutcome } from "../../supabase/functions/_shared/payment-outcome.ts";

function eq(actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(`expected ${b}, got ${a}`);
}
const pi = (status: string, last_payment_error: unknown = null) =>
  ({ id: "pi_test", object: "payment_intent", status, last_payment_error, livemode: true }) as unknown as Stripe.PaymentIntent;

Deno.test("a PaymentIntent that went through is succeeded, with no failure text", () => {
  eq(outcomeOf(pi("succeeded")), { status: "succeeded", failure_reason: null, failure_code: null });
});

Deno.test("a decline is failed, with the bank's decline_code and Stripe's sentence", () => {
  eq(outcomeOf(pi("requires_payment_method", {
    type: "card_error", code: "card_declined", decline_code: "insufficient_funds", message: "Your card has insufficient funds.",
  })), { status: "failed", failure_reason: "Your card has insufficient funds.", failure_code: "insufficient_funds" });
});

Deno.test("a card_error with no decline_code keeps the error code", () => {
  eq(outcomeOf(pi("requires_payment_method", { type: "card_error", code: "expired_card", message: "Your card has expired." })),
    { status: "failed", failure_reason: "Your card has expired.", failure_code: "expired_card" });
});

Deno.test("a request Stripe refused is failed with its sentence and no code (not the card's fault)", () => {
  eq(outcomeOf(pi("requires_payment_method", { type: "invalid_request_error", code: "parameter_missing", message: "Missing x." })),
    { status: "failed", failure_reason: "Missing x.", failure_code: null });
});

Deno.test("a canceled PaymentIntent is failed with no code", () => {
  eq(outcomeOf(pi("canceled")), { status: "failed", failure_reason: "canceled_at_stripe", failure_code: null });
});

for (const s of ["processing", "requires_action", "requires_capture", "requires_confirmation"]) {
  Deno.test(`${s} is not decided: the row is left alone`, () => eq(outcomeOf(pi(s)), null));
}

Deno.test("requires_payment_method with no error (never confirmed) is left alone", () => {
  eq(outcomeOf(pi("requires_payment_method")), null);
});

Deno.test("the webhook's two outcomes are the same rule", () => {
  eq(succeededOutcome(), outcomeOf(pi("succeeded")));
  const err = { type: "card_error", code: "card_declined", decline_code: "do_not_honor", message: "Declined." };
  eq(failedOutcome(pi("requires_payment_method", err)), outcomeOf(pi("requires_payment_method", err)));
  eq(failedOutcome(pi("requires_payment_method")), { status: "failed", failure_reason: "declined", failure_code: null });
});
