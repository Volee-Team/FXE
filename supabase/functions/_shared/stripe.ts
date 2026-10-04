// Shared Stripe + Supabase clients for the edge functions (decision 0009).
//
// STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET live in Supabase secrets, set
// by Alex from the dashboard; they are never in the repo, the app, or a log.
// SUPABASE_SERVICE_ROLE_KEY is injected by the platform and is what lets
// these functions write the ledger rows that no client may write.

import Stripe from "npm:stripe@17.5.0";
import { createClient } from "npm:@supabase/supabase-js@2";

// Lazy: the Stripe client throws at construction when the key is missing,
// which would take the whole function down at load. Built on first use, so
// an unconfigured deploy still answers "stripe_not_configured" cleanly
// instead of "Function exited due to an error".
let _stripe: Stripe | null = null;
export function getStripe(): Stripe {
  const key = Deno.env.get("STRIPE_SECRET_KEY");
  if (!key) throw new Error("stripe_not_configured");
  if (!_stripe) {
    // STRIPE_API_HOST points the SDK at stripe-mock (tests/stripe/run.sh and
    // CI) instead of api.stripe.com. Never set on hosted: the harness sets it
    // in a local env file, and the Supabase secrets dashboard does not carry it.
    const mockHost = Deno.env.get("STRIPE_API_HOST");
    _stripe = new Stripe(key, {
      apiVersion: "2024-12-18.acacia",
      httpClient: Stripe.createFetchHttpClient(),
      ...(mockHost ? { host: mockHost, port: Number(Deno.env.get("STRIPE_API_PORT") ?? "12111"), protocol: "http" as const } : {}),
    });
  }
  return _stripe;
}

export const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

/// The signed-in caller, from the JWT the app sends. Null for anon.
export async function callerId(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  const user = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data } = await user.auth.getUser();
  return data.user?.id ?? null;
}

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// What a caller is told when something throws. Our own refusals are
// snake_case codes and pass through; anything else (Stripe's sentences,
// which can quote the end of a key) is logged here and answered with a
// plain code (review, 2026-10-04; stripe-payouts already did this).
export function safeError(e: unknown, where: string): string {
  const m = String((e as Error)?.message ?? e);
  if (/^[a-z][a-z0-9_]*$/.test(m)) return m;
  console.error(`${where}:`, m);
  return "stripe_error";
}

// The secret and publishable keys must be the same mode. Swapping only some
// of the three secrets at the live switch would otherwise show members
// Stripe's "a similar object exists in live mode" in the card sheet.
export function keyModesAgree(): boolean {
  const sk = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  const pk = Deno.env.get("STRIPE_PUBLISHABLE_KEY") ?? "";
  if (!sk || !pk) return true;
  const skLive = /^(sk|rk)_live_/.test(sk), pkLive = pk.startsWith("pk_live_");
  return skLive === pkLive;
}
