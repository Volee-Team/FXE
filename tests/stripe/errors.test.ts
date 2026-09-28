// errors.test.ts: what stripe-charge does with each kind of Stripe error,
// pinned with the Stripe SDK's OWN error objects (the same npm:stripe@17.5.0
// the functions import), built the way the SDK builds them from an HTTP
// answer. stripe-mock can never produce a decline, an idempotency error or a
// 5xx, so this is the only place those branches are exercised before real
// money. Run by tests/stripe/run.sh:
//
//   deno test --allow-env --allow-read tests/stripe/errors.test.ts
//
// Expected outcomes are the rule in supabase/functions/_shared/stripe-errors.ts
// (MVP audit 2026-09-27, item 4), written out here, not read back from it:
//   decline -> failed with the bank's code; Stripe refused the request ->
//   failed; our own refusal -> failed; idempotency error -> held; anything
//   that may have reached Stripe -> retry, until 23 hours, then held.

import Stripe from "npm:stripe@17.5.0";
import { classifyChargeError, isMissingCustomer } from "../../supabase/functions/_shared/stripe-errors.ts";

const E = Stripe.errors;
// The SDK builds this one itself when a request never gets an answer
// (RequestSender: `new StripeConnectionError({ message, detail })`, under a
// @ts-ignore, since there is no raw Stripe error to carry a type). Same here.
const connectionError = (message: string) =>
  new E.StripeConnectionError({ message } as unknown as ConstructorParameters<typeof E.StripeConnectionError>[0]);
function eq(actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(`expected ${b}, got ${a}`);
}

Deno.test("a decline is failed, with the bank's decline_code", () => {
  const e = E.StripeError.generate({ type: "card_error", code: "card_declined", decline_code: "insufficient_funds",
    message: "Your card has insufficient funds.", statusCode: 402 });
  eq(e.type, "StripeCardError");
  eq(classifyChargeError(e), { kind: "failed", code: "insufficient_funds", reason: "Your card has insufficient funds." });
});

Deno.test("a decline without a bank code is failed with Stripe's code", () => {
  const e = E.StripeError.generate({ type: "card_error", code: "authentication_required",
    message: "This payment requires authentication.", statusCode: 402 });
  eq(classifyChargeError(e), { kind: "failed", code: "authentication_required", reason: "This payment requires authentication." });
});

Deno.test("a dropped connection is retried, never failed (it may have charged)", () => {
  const e = connectionError("An error occurred with our connection to Stripe. Request was retried 2 times.");
  eq(classifyChargeError(e), { kind: "retry" });
});

Deno.test("a timeout is retried", () => {
  const e = connectionError("Request aborted due to timeout being reached (80000ms)");
  eq(classifyChargeError(e), { kind: "retry" });
});

Deno.test("Stripe's own 500 is retried", () => {
  const e = E.StripeError.generate({ type: "api_error", message: "Something went wrong on Stripe's end.", statusCode: 500 });
  eq(e.type, "StripeAPIError");
  eq(classifyChargeError(e), { kind: "retry" });
});

Deno.test("a rate limit is retried", () => {
  const e = new E.StripeRateLimitError({ type: "invalid_request_error", message: "Too many requests.", statusCode: 429 });
  eq(classifyChargeError(e), { kind: "retry" });
});

Deno.test("a refused key is retried (nothing charged; works once the key is fixed)", () => {
  const e = new E.StripeAuthenticationError({ type: "invalid_request_error", message: "Invalid API Key provided.", statusCode: 401 });
  eq(classifyChargeError(e), { kind: "retry" });
});

Deno.test("an idempotency error is held for a person, neither retried nor failed", () => {
  const e = E.StripeError.generate({ type: "idempotency_error",
    message: "Keys for idempotent requests can only be used with the same parameters they were first used with.", statusCode: 400 });
  eq(e.type, "StripeIdempotencyError");
  eq(classifyChargeError(e), { kind: "hold", reason: "idempotency_error" });
});

Deno.test("a request Stripe refused is failed (nothing was charged)", () => {
  const e = E.StripeError.generate({ type: "invalid_request_error", code: "resource_missing", param: "payment_method",
    message: "No such PaymentMethod: 'pm_gone'", statusCode: 400 });
  eq(classifyChargeError(e), { kind: "failed", code: "resource_missing", reason: "No such PaymentMethod: 'pm_gone'" });
});

Deno.test("our own refusals are failed", () => {
  for (const m of ["no_card_on_file", "account_deleted", "original_has_no_payment_intent"]) {
    eq(classifyChargeError(new Error(m)), { kind: "failed", code: null, reason: m });
  }
});

Deno.test("an unconfigured key is retried: the row waits for the key", () => {
  eq(classifyChargeError(new Error("stripe_not_configured")), { kind: "retry" });
});

Deno.test("past the idempotency window a retry is held (23 hours)", () => {
  const e = connectionError("An error occurred with our connection to Stripe.");
  eq(classifyChargeError(e, 22.9), { kind: "retry" });
  eq(classifyChargeError(e, 23), { kind: "hold", reason: "retry_window_passed" });
  // A decline is still a decline, however old the row.
  const d = E.StripeError.generate({ type: "card_error", code: "expired_card", message: "Your card has expired.", statusCode: 402 });
  eq(classifyChargeError(d, 48), { kind: "failed", code: "expired_card", reason: "Your card has expired." });
});

Deno.test("a customer the key cannot see is missing; other errors are not", () => {
  // Stripe's answer to a test-mode customer under the live key.
  const live = E.StripeError.generate({ type: "invalid_request_error", code: "resource_missing", param: "id",
    message: "No such customer: 'cus_x'; a similar object exists in test mode, but a live mode key was used to make this request.",
    statusCode: 404 });
  eq(isMissingCustomer(live), true);
  // stripe-mock's 404 (the harness's stand-in) carries no code.
  eq(isMissingCustomer(E.StripeError.generate({ type: "invalid_request_error", message: "Unrecognized request URL", statusCode: 404 })), true);
  eq(isMissingCustomer(connectionError("connection")), false);
  eq(isMissingCustomer(E.StripeError.generate({ type: "api_error", message: "boom", statusCode: 500 })), false);
});
