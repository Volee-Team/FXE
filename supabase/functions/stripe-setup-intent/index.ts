// stripe-setup-intent: the app asks for a SetupIntent so PaymentSheet can
// collect a card once. We create (or reuse) the Stripe customer for the
// signed-in account and hand back the client secret. Nothing is charged.
//
// The card summary (brand, last4) is NOT written here: the webhook writes it
// on setup_intent.succeeded, because only Stripe knows the setup finished.

import { getStripe, admin, callerId, json } from "../_shared/stripe.ts";

Deno.serve(async (req) => { try { return await handle(req); } catch (e) { const m = String((e as Error).message ?? e); return json({ error: m }, m === "stripe_not_configured" ? 503 : 500); } });

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const uid = await callerId(req);
  if (!uid) return json({ error: "not_authenticated" }, 401);

  const { data: account, error } = await admin
    .from("accounts")
    .select("id, email, first_name, last_name, stripe_customer_id")
    .eq("id", uid)
    .single();
  if (error || !account) { console.error("stripe-setup-intent: account lookup", error); return json({ error: "no_account", detail: error?.message ?? null }, 403); }

  let customerId = account.stripe_customer_id as string | null;
  if (!customerId) {
    const customer = await getStripe().customers.create({
      email: account.email ?? undefined,
      name: `${account.first_name} ${account.last_name}`,
      metadata: { fxe_account_id: account.id },
    });
    customerId = customer.id;
    // Written now so a second tap reuses the customer even if the webhook
    // has not arrived yet. The card summary still waits for the webhook.
    await admin.from("accounts").update({ stripe_customer_id: customerId }).eq("id", uid);
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
