// stripe-webhook: Stripe tells us what happened; we record it. This is the
// ONLY writer of card summaries and of ledger status, apart from admin RPCs
// that create pending rows. Signature verified with STRIPE_WEBHOOK_SECRET;
// an unsigned request changes nothing.
//
// Events handled:
//   setup_intent.succeeded          -> accounts.card_brand / card_last4 / card_added_at
//   payment_intent.succeeded        -> payments.status = succeeded
//   payment_intent.payment_failed   -> payments.status = failed, failure_reason
//   charge.refunded / refund.updated -> refund row succeeded (when it clears)
//
// verify_jwt is off for this function (config.toml): Stripe has no Supabase
// JWT. The signature check is the auth.

import Stripe from "npm:stripe@17.5.0";
import { getStripe, admin, json } from "../_shared/stripe.ts";

Deno.serve(async (req) => { try { return await handle(req); } catch (e) { const m = String((e as Error).message ?? e); return json({ error: m }, m === "stripe_not_configured" ? 503 : 500); } });

async function handle(req: Request): Promise<Response> {
  const sig = req.headers.get("stripe-signature");
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!sig || !secret) return json({ error: "no_signature" }, 400);

  let event: Stripe.Event;
  try {
    event = await getStripe().webhooks.constructEventAsync(await req.text(), sig, secret);
  } catch (e) {
    return json({ error: "bad_signature", detail: String(e) }, 400);
  }

  switch (event.type) {
    case "setup_intent.succeeded": {
      const si = event.data.object as Stripe.SetupIntent;
      const pmId = typeof si.payment_method === "string" ? si.payment_method : si.payment_method?.id;
      const customerId = typeof si.customer === "string" ? si.customer : si.customer?.id;
      if (!pmId || !customerId) break;
      const pm = await getStripe().paymentMethods.retrieve(pmId);
      // Make it the default so off-session charges need no payment_method.
      await getStripe().customers.update(customerId, { invoice_settings: { default_payment_method: pmId } });
      await admin.from("accounts").update({
        card_brand: pm.card?.brand ?? null,
        card_last4: pm.card?.last4 ?? null,
        card_added_at: new Date().toISOString(),
      }).eq("stripe_customer_id", customerId);
      break;
    }
    case "payment_intent.succeeded": {
      const pi = event.data.object as Stripe.PaymentIntent;
      await admin.from("payments").update({ status: "succeeded" }).eq("stripe_payment_intent_id", pi.id);
      break;
    }
    case "payment_intent.payment_failed": {
      const pi = event.data.object as Stripe.PaymentIntent;
      await admin.from("payments").update({
        status: "failed",
        failure_reason: pi.last_payment_error?.message ?? pi.last_payment_error?.code ?? "declined",
      }).eq("stripe_payment_intent_id", pi.id);
      break;
    }
    case "refund.updated":
    case "charge.refunded": {
      // A refund row was created pending by stripe-charge; mark it by id.
      const obj = event.data.object as Stripe.Refund | Stripe.Charge;
      const refunds = "refunds" in obj && obj.refunds ? obj.refunds.data : [obj as Stripe.Refund];
      for (const r of refunds) {
        if (r.status === "succeeded") {
          await admin.from("payments").update({ status: "succeeded" }).eq("stripe_refund_id", r.id);
        } else if (r.status === "failed" || r.status === "canceled") {
          await admin.from("payments").update({ status: "failed", failure_reason: r.failure_reason ?? r.status })
            .eq("stripe_refund_id", r.id);
        }
      }
      break;
    }
    default:
      break;
  }
  return json({ received: true });
}
