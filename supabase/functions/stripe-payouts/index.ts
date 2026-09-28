// stripe-payouts: what Stripe is holding for the club and what is on its way
// to Tara's bank, for the web admin's Money tab, so the day-to-day question
// needs no Stripe dashboard (Alex, 2026-09-27). Read-only: no database
// writes, and no call that can move money.
//
// POST with the caller's JWT. The caller must be an admin: is_admin() is
// asked AS the caller (the admin-reset-link pattern), so the database
// decides, not this code. A member is refused before Stripe is ever asked, so
// the answer never tells a member whether Stripe is connected.
//
// Answers 200:
//   { livemode,
//     available:   [{ amount, currency }],    // in Stripe now, can be paid out
//     pending:     [{ amount, currency }],    // charged, not yet available
//     next_payout: { amount, currency, arrival_date, status } | null,
//     recent:      [{ amount, currency, arrival_date, status }] }  // the last 10
// Amounts are in cents (Stripe's smallest unit). arrival_date is the bank day
// as "YYYY-MM-DD": Stripe sends midnight UTC of that day as a Unix time, which
// a browser in New York would otherwise show as the evening before. The next
// payout is the soonest-arriving one still pending or in transit. Status is
// Stripe's word: paid, pending, in_transit, canceled, failed.
//
// Never returned: a payout's destination (the bank account's id), its
// description, statement descriptor or trace id, and any key. Only the fields
// above are copied out of Stripe's objects.
//
// Errors: 401 not_authenticated, 403 not_authorized, 405 method_not_allowed,
// 503 stripe_not_configured (no STRIPE_SECRET_KEY, like the other Stripe
// functions), 502 stripe_unavailable (Stripe refused or could not be
// reached). Stripe's own message is not passed on: an authentication error
// quotes the end of the key.

import Stripe from "npm:stripe@17.5.0";
import { callerId, getStripe, json } from "../_shared/stripe.ts";
import { withCors } from "../_shared/cors.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// withCors: the web admin calls this from the browser (_shared/cors.ts).
Deno.serve(withCors(async (req) => {
  try { return await handle(req); }
  catch (e) {
    const m = String((e as Error).message ?? e);
    if (m === "stripe_not_configured") return json({ error: m }, 503);
    console.error("stripe-payouts:", m);
    return json({ error: "internal_error" }, 500);
  }
}));

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const uid = await callerId(req);
  if (!uid) return json({ error: "not_authenticated" }, 401);

  // The database decides who is an admin. Asked as the caller.
  const asUser = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization")! } },
    auth: { persistSession: false },
  });
  const { data: isAdmin, error: adminErr } = await asUser.rpc("is_admin");
  if (adminErr) return json({ error: "admin_check_failed" }, 500);
  if (isAdmin !== true) return json({ error: "not_authorized" }, 403);

  const stripe = getStripe();   // throws stripe_not_configured -> 503 above

  let balance: Stripe.Balance;
  let payouts: Stripe.ApiList<Stripe.Payout>;
  try {
    [balance, payouts] = await Promise.all([stripe.balance.retrieve(), stripe.payouts.list({ limit: 10 })]);
  } catch (e) {
    // The kind of failure only, never Stripe's sentence (it can quote the key).
    const x = e as { type?: string; statusCode?: number };
    console.error("stripe-payouts: Stripe call failed", x.type ?? "unknown", x.statusCode ?? "");
    return json({ error: "stripe_unavailable" }, 502);
  }

  const money = (b: { amount: number; currency: string }) => ({ amount: b.amount, currency: b.currency });
  const payout = (p: Stripe.Payout) => ({
    amount: p.amount,
    currency: p.currency,
    arrival_date: bankDay(p.arrival_date),
    status: p.status,
  });
  const onTheWay = payouts.data
    .filter((p) => p.status === "pending" || p.status === "in_transit")
    .sort((a, b) => a.arrival_date - b.arrival_date);

  return json({
    livemode: balance.livemode,
    available: (balance.available ?? []).map(money),
    pending: (balance.pending ?? []).map(money),
    next_payout: onTheWay.length ? payout(onTheWay[0]) : null,
    recent: payouts.data.map(payout),
  });
}

// Stripe's arrival_date: seconds since the epoch at midnight UTC of the day the
// money reaches the bank. The UTC calendar date is that day.
function bankDay(seconds: number): string | null {
  return Number.isFinite(seconds) ? new Date(seconds * 1000).toISOString().slice(0, 10) : null;
}
