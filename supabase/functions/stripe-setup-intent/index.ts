// stripe-setup-intent: the app asks for a SetupIntent so PaymentSheet can
// collect a card once. We create (or reuse) the Stripe customer for the
// signed-in account and hand back the client secret. Nothing is charged.
//
// The card summary (brand, last4) is NOT written here: the webhook writes it
// on setup_intent.succeeded, because only Stripe knows the setup finished.
//
// A stored customer is checked before it is reused (MVP audit 2026-09-27,
// item 3). After the switch from the sandbox key to the live one, every
// customer made in test mode answers "No such customer", and reusing it made
// Change card fail with a 500 the app reads as "Check your connection", a
// dead end. A customer Stripe does not have (or has deleted) is treated as
// none: a fresh one is made, and the stale card summary, which described a
// card on the old customer, is cleared.

import { getStripe, admin, callerId, json } from "../_shared/stripe.ts";
import { isMissingCustomer } from "../_shared/stripe-errors.ts";

Deno.serve(async (req) => { try { return await handle(req); } catch (e) { const m = String((e as Error).message ?? e); return json({ error: m }, m === "stripe_not_configured" ? 503 : 500); } });

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const uid = await callerId(req);
  if (!uid) return json({ error: "not_authenticated" }, 401);

  const { data: account, error } = await admin
    .from("accounts")
    .select("id, email, first_name, last_name, stripe_customer_id, deleted_at")
    .eq("id", uid)
    .single();
  if (error || !account) { console.error("stripe-setup-intent: account lookup", error); return json({ error: "no_account", detail: error?.message ?? null }, 403); }
  // A deleted account gets no new Stripe customer (item 11: deleting removes
  // the person from Stripe; this must not put them back).
  if (account.deleted_at) return json({ error: "account_deleted" }, 403);

  // Decision 0015 §7 (Final Updates, 2026-09-26): "a check box that says I
  // give permission for my card to be charged and if deselected it does not
  // let them proceed." The screen's box is not the control; this is. No card
  // setup starts without a consent row for the CURRENT words, written by
  // record_card_consent() when the box was ticked.
  const { data: words } = await admin.from("app_settings").select("value").eq("key", "card_consent_text").maybeSingle();
  const { count: consents } = await admin.from("card_consents")
    .select("id", { count: "exact", head: true })
    .eq("account_id", uid).eq("consent_text", words?.value ?? "");
  if (!words?.value || !consents) return json({ error: "card_consent_required" }, 409);

  let customerId = account.stripe_customer_id as string | null;
  if (customerId && !(await customerExists(customerId))) {
    // Only if the row still names that customer (another tap may have fixed
    // it already).
    await admin.from("accounts")
      .update({ stripe_customer_id: null, card_brand: null, card_last4: null, card_added_at: null })
      .eq("id", uid).eq("stripe_customer_id", customerId);
    customerId = null;
  }
  if (!customerId) {
    const customer = await getStripe().customers.create({
      email: account.email ?? undefined,
      name: `${account.first_name} ${account.last_name}`,
      metadata: { fxe_account_id: account.id },
    });
    // Written now so a second tap reuses the customer even if the webhook
    // has not arrived yet. The card summary still waits for the webhook.
    // Conditional: if two taps raced, the first stored customer wins and this
    // request uses it, so the card is saved where the webhook will look.
    const { data: stored } = await admin.from("accounts").update({ stripe_customer_id: customer.id })
      .eq("id", uid).is("stripe_customer_id", null).select("stripe_customer_id");
    if (stored && stored.length) {
      customerId = customer.id;
    } else {
      const { data: again } = await admin.from("accounts").select("stripe_customer_id").eq("id", uid).single();
      customerId = (again?.stripe_customer_id as string | null) ?? null;
      if (!customerId) return json({ error: "customer_not_stored" }, 500);
    }
  }

  const intent = await getStripe().setupIntents.create({
    customer: customerId,
    usage: "off_session",
    payment_method_types: ["card"],
    metadata: { fxe_account_id: account.id },
  });

  // PaymentSheet also wants an ephemeral key for the customer.
  const ephemeral = await getStripe().ephemeralKeys.create({ customer: customerId }, { apiVersion: "2024-12-18.acacia" });

  return json({
    setupIntentClientSecret: intent.client_secret,
    ephemeralKeySecret: ephemeral.secret,
    customerId,
    publishableKey: Deno.env.get("STRIPE_PUBLISHABLE_KEY") ?? null,
  });
}

// Stripe still has this customer, in the mode of the key in use.
async function customerExists(id: string): Promise<boolean> {
  try {
    const c = await getStripe().customers.retrieve(id);
    return !("deleted" in c && c.deleted);
  } catch (e) {
    if (isMissingCustomer(e)) return false;
    throw e;
  }
}
