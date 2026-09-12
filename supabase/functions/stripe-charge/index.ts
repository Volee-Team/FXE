// stripe-charge: executes what Tara asked for. Every 'pending' row in the
// ledger becomes one Stripe call: a PaymentIntent (off-session, on the
// customer's default card) for a fee, or a Refund for a refund row. The
// outcome is recorded by the webhook; here we only move pending → processing
// and store the Stripe id, so a crash between the two never double-charges.
//
// Invoked by the admin surfaces right after admin_charge_registration /
// admin_refund_payment returns, and safe to invoke again at any time (it
// only ever looks at pending rows). Requires an admin JWT.

import { getStripe, admin, callerId, json } from "../_shared/stripe.ts";

Deno.serve(async (req) => { try { return await handle(req); } catch (e) { const m = String((e as Error).message ?? e); return json({ error: m }, m === "stripe_not_configured" ? 503 : 500); } });

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const uid = await callerId(req);
  if (!uid) return json({ error: "not_authenticated" }, 401);
  const { data: me } = await admin.from("accounts").select("role").eq("id", uid).single();
  if (me?.role !== "admin") return json({ error: "not_authorized" }, 403);

  const { data: rows, error } = await admin
    .from("payments")
    .select("id, kind, amount_cents, currency, account_id, registration_id, refunds_payment_id")
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
          .select("stripe_payment_intent_id").eq("id", row.refunds_payment_id).single();
        if (!orig?.stripe_payment_intent_id) throw new Error("original_has_no_payment_intent");
        const refund = await getStripe().refunds.create({
          payment_intent: orig.stripe_payment_intent_id,
          amount: row.amount_cents,
          metadata: { fxe_payment_id: row.id },
        }, { idempotencyKey: `fxe-refund-${row.id}` });
        await admin.from("payments").update({ stripe_refund_id: refund.id }).eq("id", row.id);
        results[row.id] = refund.status ?? "processing";
      } else {
        const { data: acct } = await admin.from("accounts")
          .select("stripe_customer_id").eq("id", row.account_id).single();
        if (!acct?.stripe_customer_id) throw new Error("no_card_on_file");
        const intent = await getStripe().paymentIntents.create({
          amount: row.amount_cents,
          currency: row.currency,
          customer: acct.stripe_customer_id,
          off_session: true,
          confirm: true,
          description: `FXE Tennis ${row.kind.replace("_", " ")}`,
          metadata: { fxe_payment_id: row.id, fxe_registration_id: row.registration_id, kind: row.kind },
        }, { idempotencyKey: `fxe-pay-${row.id}` });
        await admin.from("payments").update({ stripe_payment_intent_id: intent.id }).eq("id", row.id);
        results[row.id] = intent.status;
      }
    } catch (e) {
      // A decline arrives here synchronously for off-session charges.
      await admin.from("payments").update({ status: "failed", failure_reason: String((e as Error).message ?? e) })
        .eq("id", row.id);
      results[row.id] = "failed";
    }
  }
  return json({ processed: results });
}
