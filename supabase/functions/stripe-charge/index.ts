// stripe-charge: executes what Tara asked for. Up to 25 'pending' rows per
// call (.limit(25) below; call again for the rest) each become one Stripe
// call: a PaymentIntent (off-session, on the customer's default card) for a
// fee, or a Refund for a refund row. The outcome is recorded by the webhook;
// here we move pending → processing, store the Stripe id and Stripe's
// livemode flag, and handle a call that threw (below). A crash between the
// claim and the store never double-charges: see the sweep.
//
// Invoked by the admin surfaces right after admin_charge_registration /
// admin_refund_payment returns, and safe to invoke again at any time (it
// only ever looks at pending rows, plus the stuck ones the sweep returns to
// pending). Requires an admin JWT.
//
// WHEN A CALL THROWS (MVP audit 2026-09-27, item 4; the rule is in
// _shared/stripe-errors.ts): a decline, a request Stripe refused, or our own
// refusal marks the row failed. Anything that may have reached Stripe (a
// dropped connection, a timeout, a 5xx) puts it back to pending, so the next
// call repeats it under the same idempotency key and Stripe answers with the
// first attempt's result. Before, every error was "failed", and Tara's
// second tap made a new row, a new key, and could charge a member twice.
//
// A customer Stripe does not have (deleted, or made with the sandbox key
// before the switch to live) is treated as no customer: the account's stale
// customer id and card summary are cleared, so the app asks for a card again,
// and the row fails as no_card_on_file. A deleted account is never charged.

import { getStripe, admin, callerId, json } from "../_shared/stripe.ts";
import { classifyChargeError, isMissingCustomer, RETRY_WINDOW_HOURS } from "../_shared/stripe-errors.ts";

Deno.serve(async (req) => { try { return await handle(req); } catch (e) { const m = String((e as Error).message ?? e); return json({ error: m }, m === "stripe_not_configured" ? 503 : 500); } });

// Longer than any call runs: a row processing this long with no Stripe id
// belongs to a call that died between the claim and storing the id.
const STUCK_AFTER_MS = 5 * 60_000;

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const uid = await callerId(req);
  if (!uid) return json({ error: "not_authenticated" }, 401);
  const { data: me } = await admin.from("accounts").select("role").eq("id", uid).single();
  if (me?.role !== "admin") return json({ error: "not_authorized" }, 403);

  await sweepStuck();

  const { data: rows, error } = await admin
    .from("payments")
    .select("id, kind, amount_cents, currency, account_id, registration_id, refunds_payment_id, created_at")
    .eq("status", "pending")
    .order("created_at")
    .limit(25);
  if (error) return json({ error: error.message }, 500);

  const results: Record<string, string> = {};
  for (const row of rows ?? []) {
    // Claim it first. If another invocation claimed it, skip.
    const { data: claimed } = await admin.from("payments")
      .update({ status: "processing" }).eq("id", row.id).eq("status", "pending").select("id");
    if (!claimed || claimed.length === 0) continue;

    try {
      if (row.kind === "refund") {
        const { data: orig } = await admin.from("payments")
          .select("stripe_payment_intent_id, livemode").eq("id", row.refunds_payment_id).single();
        if (!orig?.stripe_payment_intent_id) throw new Error("original_has_no_payment_intent");
        const refund = await getStripe().refunds.create({
          payment_intent: orig.stripe_payment_intent_id,
          amount: row.amount_cents,
          metadata: { fxe_payment_id: row.id },
        }, { idempotencyKey: `fxe-refund-${row.id}` });
        // A Stripe Refund carries no livemode; it is always in the mode of
        // the charge it refunds, so it takes that row's flag.
        await admin.from("payments").update({ stripe_refund_id: refund.id, livemode: orig.livemode ?? null }).eq("id", row.id);
        results[row.id] = refund.status ?? "processing";
      } else {
        const { data: acct } = await admin.from("accounts")
          .select("stripe_customer_id, deleted_at").eq("id", row.account_id).single();
        // Nothing is charged on the way out (item 11): once an account is
        // deleted, a fee still queued for it fails instead.
        if (acct?.deleted_at) throw new Error("account_deleted");
        if (!acct?.stripe_customer_id) throw new Error("no_card_on_file");
        const customerId = acct.stripe_customer_id as string;
        // Name the card. A PaymentIntent does NOT fall back to the customer's
        // invoice_settings.default_payment_method (that setting is for
        // invoices); without payment_method, confirm uses only a legacy
        // default_source, which a PaymentSheet card never is. The webhook sets
        // the default when the card is saved; read it back here, else the
        // customer's first card. Found 2026-09-26 by reading, not by the mock:
        // stripe-mock accepts a PaymentIntent with no payment method.
        let customer: { deleted?: boolean; invoice_settings?: { default_payment_method?: string | { id: string } | null } };
        try {
          customer = await getStripe().customers.retrieve(customerId) as typeof customer;
        } catch (e) {
          if (!isMissingCustomer(e)) throw e;
          customer = { deleted: true };
        }
        if (customer.deleted) {
          await forgetCustomer(row.account_id, customerId);
          throw new Error("no_card_on_file");
        }
        const d = customer.invoice_settings?.default_payment_method;
        let paymentMethod: string | null = typeof d === "string" ? d : d?.id ?? null;
        if (!paymentMethod) {
          const list = await getStripe().paymentMethods.list({ customer: customerId, type: "card", limit: 1 });
          paymentMethod = list.data[0]?.id ?? null;
        }
        if (!paymentMethod) throw new Error("no_card_on_file");
        const intent = await getStripe().paymentIntents.create({
          amount: row.amount_cents,
          currency: row.currency,
          customer: customerId,
          payment_method: paymentMethod,
          off_session: true,
          confirm: true,
          description: `FXE Tennis ${row.kind.replace("_", " ")}`,
          metadata: { fxe_payment_id: row.id, fxe_registration_id: row.registration_id, kind: row.kind },
        }, { idempotencyKey: `fxe-pay-${row.id}` });
        // Stripe's own flag (20260927200001): test-mode money never counts.
        // If the webhook got here first it has already stored the same id.
        await admin.from("payments").update({ stripe_payment_intent_id: intent.id, livemode: intent.livemode })
          .eq("id", row.id);
        results[row.id] = intent.status;
      }
    } catch (e) {
      const ageHours = (Date.now() - Date.parse(row.created_at)) / 3_600_000;
      const outcome = classifyChargeError(e, ageHours);
      // Every write below is conditional on 'processing': if the webhook
      // recorded an outcome meanwhile, that outcome stands (hard rule 3).
      if (outcome.kind === "failed") {
        await admin.from("payments").update({
          status: "failed",
          failure_reason: outcome.reason,
          failure_code: outcome.code,
        }).eq("id", row.id).eq("status", "processing");
        results[row.id] = "failed";
      } else if (outcome.kind === "retry") {
        console.error("stripe-charge: will retry", row.id, String((e as Error)?.message ?? e));
        await admin.from("payments").update({ status: "pending" }).eq("id", row.id).eq("status", "processing");
        results[row.id] = "pending";
      } else {
        await admin.from("payments").update({ failure_reason: outcome.reason })
          .eq("id", row.id).eq("status", "processing");
        results[row.id] = "held";
      }
    }
  }
  return json({ processed: results });
}

// A call that died between the claim and storing Stripe's id leaves its row
// in processing with no id: no webhook can find it by id, and the unique
// index keeps Tara from charging again. Inside the retry window such a row
// goes back to pending and is retried under the same idempotency key (Stripe
// answers a repeat with the first result). Past it, it is held for a person
// with retry_window_passed, because a retry could then charge twice. A row
// already held (failure_reason set) is left alone.
async function sweepStuck() {
  const stuckBefore = new Date(Date.now() - STUCK_AFTER_MS).toISOString();
  const windowStart = new Date(Date.now() - RETRY_WINDOW_HOURS * 3_600_000).toISOString();
  // A fee's Stripe id is its PaymentIntent; a refund's is its Refund.
  for (const [idColumn, kindOp] of [["stripe_payment_intent_id", "neq"], ["stripe_refund_id", "eq"]] as const) {
    await admin.from("payments").update({ status: "pending" })
      .eq("status", "processing").is(idColumn, null).is("failure_reason", null)
      .filter("kind", kindOp, "refund")
      .lt("updated_at", stuckBefore).gt("created_at", windowStart);
    await admin.from("payments").update({ failure_reason: "retry_window_passed" })
      .eq("status", "processing").is(idColumn, null).is("failure_reason", null)
      .filter("kind", kindOp, "refund")
      .lt("updated_at", stuckBefore).lte("created_at", windowStart);
  }
}

// The customer is gone at Stripe, so the card summary describes a card that
// no longer exists. Clear both, only if they still name that customer.
async function forgetCustomer(accountId: string, customerId: string) {
  await admin.from("accounts")
    .update({ stripe_customer_id: null, card_brand: null, card_last4: null, card_added_at: null })
    .eq("id", accountId).eq("stripe_customer_id", customerId);
}
