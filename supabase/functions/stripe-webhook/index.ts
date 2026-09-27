// stripe-webhook: Stripe tells us what happened; we record it. This is the
// only writer of a card summary and of a ledger outcome (succeeded, or a
// failure Stripe reports later), apart from admin RPCs that create pending
// rows, stripe-charge (processing, a synchronous failure, back to pending for
// a retry), a card summary cleared once its customer is gone (stripe-charge,
// stripe-setup-intent, delete-account), and the one-off live cutover.
// Signature verified with STRIPE_WEBHOOK_SECRET; an unsigned request changes
// nothing.
//
// Events handled:
//   setup_intent.succeeded          -> accounts.card_brand / card_last4 / card_added_at
//   payment_intent.succeeded        -> payments.status = succeeded
//   payment_intent.payment_failed   -> payments.status = failed, failure_reason, failure_code
//   charge.refunded / refund.updated -> refund row succeeded (when it clears)
// Every ledger write also records the event's livemode (20260927200001): the
// signed event is Stripe's word on which mode the money moved in, and test
// mode is never counted as money.
//
// A payment event can arrive before stripe-charge has stored the
// PaymentIntent's id, because Stripe may call back before paymentIntents.create
// returns. Matching by id alone then found no row and answered 200, so Stripe
// never retried and the row sat in processing forever: never paid, never
// retryable, missing from the board report (MVP audit 2026-09-27, item 4). A
// PaymentIntent this app made carries metadata.fxe_payment_id, so an event
// that matches no id is attached to that row and the id is stored, the same
// fallback recordRefund has used since 2026-09-26.
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
      // A PaymentIntent that failed and later went through (the cardholder
      // approved it, or fixed the card) must not keep reading "Declined".
      await recordPaymentOutcome(pi, { status: "succeeded", failure_code: null, failure_reason: null, ...mode(event) });
      break;
    }
    case "payment_intent.payment_failed": {
      const pi = event.data.object as Stripe.PaymentIntent;
      // failure_code (20260926000010) is Stripe's machine code: decline_code
      // when the bank gave one (insufficient_funds, expired_card, ...), else
      // the error code (card_declined, incorrect_cvc, ...). The web admin turns
      // it into words; failure_reason keeps Stripe's own sentence.
      await recordPaymentOutcome(pi, {
        status: "failed",
        failure_reason: pi.last_payment_error?.message ?? pi.last_payment_error?.code ?? "declined",
        failure_code: pi.last_payment_error?.decline_code ?? pi.last_payment_error?.code ?? null,
        ...mode(event),
      });
      break;
    }
    case "refund.updated":
    case "charge.refunded": {
      const obj = event.data.object as Stripe.Refund | Stripe.Charge;
      // Since API 2022-11-15 a Charge does not carry its refunds unless
      // expanded, so ask Stripe for them rather than mistaking the charge for
      // a refund (the old code did exactly that when `refunds` was absent).
      let refunds: Stripe.Refund[];
      if (obj.object === "refund") refunds = [obj as Stripe.Refund];
      else {
        const ch = obj as Stripe.Charge;
        refunds = ch.refunds?.data ?? (await getStripe().refunds.list({ charge: ch.id, limit: 100 })).data;
      }
      for (const r of refunds) await recordRefund(r, mode(event));
      break;
    }
    default:
      break;
  }
  return json({ received: true });
}

// The event's livemode, as a column value. Stripe sends it on every event; an
// event without it (none should exist) leaves the row's value alone.
function mode(event: Stripe.Event): { livemode?: boolean } {
  return typeof event.livemode === "boolean" ? { livemode: event.livemode } : {};
}

// One PaymentIntent outcome into the ledger: by the id stripe-charge stored,
// else (the event beat stripe-charge to it) by the row named in the
// PaymentIntent's metadata, storing the id on the way. Never a refund row, and
// never a row that already carries a different PaymentIntent.
async function recordPaymentOutcome(pi: Stripe.PaymentIntent, outcome: Record<string, unknown>) {
  const { data: byId } = await admin.from("payments").update(outcome)
    .eq("stripe_payment_intent_id", pi.id).select("id");
  if (byId && byId.length) return;
  const mine = pi.metadata?.fxe_payment_id;
  if (!mine) return;   // not a PaymentIntent this app made
  await admin.from("payments").update({ stripe_payment_intent_id: pi.id, ...outcome })
    .eq("id", mine).neq("kind", "refund").is("stripe_payment_intent_id", null);
}

// One Stripe refund into the ledger. Three cases, in this order:
//  1. A row already carries this refund's id (made by stripe-charge, or
//     recorded by an earlier delivery of this event): record the outcome.
//  2. The refund is ours (stripe-charge puts fxe_payment_id in its metadata)
//     but stripe-charge has not stored the id yet, because Stripe can call
//     back before refunds.create returns. Attach it to that row. Without this
//     case the race would fall through to 3 and be counted twice.
//  3. Nobody here asked for it: a refund made in Stripe's dashboard, which is
//     where refunds are made in v1 (Kat, 2026-09-22). Record it once it has
//     succeeded, linked to the charge it refunds, so the board report
//     (20260926000010) nets it out. Idempotent: stripe_refund_id is unique,
//     so a redelivered event inserts nothing. A refund for the whole amount
//     goes processing -> succeeded, the same path as an in-app refund, so the
//     trigger clears the Paid flag on a clinic fee; a partial one is recorded
//     as succeeded directly and leaves Paid alone.
async function recordRefund(r: Stripe.Refund, live: { livemode?: boolean }) {
  const outcome = r.status === "succeeded" ? { status: "succeeded", ...live }
    : (r.status === "failed" || r.status === "canceled") ? { status: "failed", failure_reason: r.failure_reason ?? r.status, ...live }
    : null;

  const { data: known } = await admin.from("payments").select("id").eq("stripe_refund_id", r.id);
  if (known && known.length) {
    if (outcome) await admin.from("payments").update(outcome).eq("stripe_refund_id", r.id);
    return;
  }

  const mine = r.metadata?.fxe_payment_id;
  if (mine) {
    await admin.from("payments").update({ stripe_refund_id: r.id, ...(outcome ?? live) })
      .eq("id", mine).eq("kind", "refund").is("stripe_refund_id", null);
    return;
  }

  if (r.status !== "succeeded") return;   // recorded when it clears
  const piId = typeof r.payment_intent === "string" ? r.payment_intent : r.payment_intent?.id;
  if (!piId) return;
  const { data: orig } = await admin.from("payments")
    .select("id, registration_id, account_id, amount_cents, currency")
    .eq("stripe_payment_intent_id", piId).neq("kind", "refund").maybeSingle();
  if (!orig) return;   // not a charge this app made
  const whole = r.amount >= orig.amount_cents;
  const { data: ins } = await admin.from("payments").upsert({
    registration_id: orig.registration_id,
    account_id: orig.account_id,
    kind: "refund",
    amount_cents: r.amount,
    currency: orig.currency,
    refunds_payment_id: orig.id,
    stripe_refund_id: r.id,
    status: whole ? "processing" : "succeeded",   // never 'pending': stripe-charge would refund it again
    ...live,
  }, { onConflict: "stripe_refund_id", ignoreDuplicates: true }).select("id");
  if (whole && ins && ins.length) {
    await admin.from("payments").update({ status: "succeeded" }).eq("id", ins[0].id);
  }
}
