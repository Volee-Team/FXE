// How the Stripe edge functions read an error (MVP audit, 2026-09-27, items
// 3 and 4). Pure on purpose: no imports, so tests/stripe/errors.test.ts can
// hand it the Stripe SDK's own error objects and pin every branch, including
// the ones stripe-mock can never produce (a decline, a dropped connection).
//
// THE RULE for a charge whose Stripe call threw:
//   * Stripe said no to the card (card_error): nothing was charged. The row
//     is failed, with the bank's reason, and Tara decides what next.
//   * Stripe refused the request itself (invalid_request_error, 400/404):
//     nothing was charged, and the same request can never succeed, so the row
//     is failed rather than retried forever.
//   * Our own refusals, raised before any call that could move money
//     (no_card_on_file, account_deleted, original_has_no_payment_intent):
//     failed.
//   * The same idempotency key sent with different parameters
//     (idempotency_error; the saved card changed between two attempts): the
//     first attempt may have charged, so neither a retry nor a new row is
//     safe. The row is HELD in processing with that reason for a person to
//     check in Stripe; the unique index keeps a second charge out meanwhile.
//   * Anything else (the connection dropped, a timeout, Stripe answered 5xx
//     or 429, the key was refused): the charge MAY have gone through. The row
//     goes back to pending, and the next stripe-charge call repeats the SAME
//     request under the SAME idempotency key (fxe-pay-<row id>), which Stripe
//     answers with the first attempt's result instead of charging again.
//     Before this, every one of these was marked failed, and Tara's second
//     tap made a new row, a new key, and a second charge.
//   * Stripe keeps an idempotency key for 24 hours. A row older than
//     RETRY_WINDOW_HOURS is therefore held (retry_window_passed), never
//     retried: past that point a retry could charge a second time.

export const RETRY_WINDOW_HOURS = 23;

export type ChargeOutcome =
  | { kind: "failed"; code: string | null; reason: string }
  | { kind: "retry" }
  | { kind: "hold"; reason: string };

type StripeishError = {
  type?: string;          // the SDK's class name: StripeCardError, ...
  rawType?: string;       // Stripe's own error type: card_error, ...
  statusCode?: number;
  code?: string;
  decline_code?: string;
  message?: string;
};

/** Our refusals: thrown by stripe-charge before any call that could move money. */
export const OWN_REFUSALS = ["no_card_on_file", "account_deleted", "original_has_no_payment_intent"];

export function classifyChargeError(e: unknown, rowAgeHours = 0): ChargeOutcome {
  const x = (e ?? {}) as StripeishError;
  const message = String(x.message ?? e);
  const raw = x.rawType ?? "";
  if (x.type === "StripeCardError" || raw === "card_error") {
    // decline_code is the bank's reason (insufficient_funds, expired_card);
    // code is Stripe's (card_declined, incorrect_cvc). Same rule as the webhook.
    return { kind: "failed", code: x.decline_code ?? x.code ?? null, reason: message };
  }
  if (x.type === "StripeIdempotencyError" || raw === "idempotency_error") {
    return { kind: "hold", reason: "idempotency_error" };
  }
  // By the SDK's class, never by the raw type: Stripe answers a refused key
  // (401) and a rate limit (429) with type invalid_request_error too, and the
  // SDK turns those into StripeAuthenticationError and StripeRateLimitError,
  // which must be retried, not failed. (Found by errors.test.ts.)
  if (x.type === "StripeInvalidRequestError") {
    return { kind: "failed", code: x.code ?? null, reason: message };
  }
  if (OWN_REFUSALS.includes(message)) {
    return { kind: "failed", code: null, reason: message };
  }
  if (rowAgeHours >= RETRY_WINDOW_HOURS) {
    return { kind: "hold", reason: "retry_window_passed" };
  }
  return { kind: "retry" };
}

/**
 * Stripe does not have this customer: deleted in the dashboard, or made
 * with the other mode's key (every sandbox customer, once the live key is in:
 * "No such customer ... a similar object exists in test mode"). Only for a
 * call whose subject IS the customer (retrieve, delete), where a 404 can
 * mean nothing else.
 */
export function isMissingCustomer(e: unknown): boolean {
  const x = (e ?? {}) as StripeishError;
  return x.statusCode === 404 || x.code === "resource_missing";
}
