// delete-account: the second half of account deletion (decision 0013 §5,
// App Store guideline 5.1.1(v)). The signed-in caller has already had, or
// now gets, their personal data scrubbed by delete_my_account() in Postgres
// (history stays: registrations, ledger, Tara's notes). Then the sign-in
// itself is removed through Supabase's admin API with soft delete, which
// keeps the auth row (so accounts.id and everything cascading from it
// survive) while making the credentials unusable. Nothing here, and
// nothing in SQL, writes to the auth schema directly.
//
// In between, the person is removed from Stripe (MVP audit 2026-09-27, item
// 11). The dialog says "Your name, phone, email and card are removed", but
// until now the Stripe customer, made with their name and email, kept the
// saved card in the club's Stripe account. customers.del removes the
// customer and detaches its cards; payments and refunds already made stay in
// Stripe for the books, and our ledger keeps its rows. The stored customer id
// is then cleared. A customer Stripe no longer has counts as already removed,
// so a retry after a half-finished attempt goes through. Any other Stripe
// failure stops here, before the sign-in is removed, so the member can try
// again and the promise in the dialog holds. Nothing is charged on the way
// out: a fee still queued for a deleted account is refused by stripe-charge.
//
// An account with no profile row (signed up, never finished the profile)
// has nothing to scrub: the RPC answers account_not_found, and the sign-in
// is still removed. Before, that answer stopped the whole request with a
// 400, and the person could not delete what they had just made.
//
// Requires the caller's JWT. Admins are refused by the RPC.

import { admin, callerId, getStripe, json, safeError } from "../_shared/stripe.ts";
import { isMissingCustomer } from "../_shared/stripe-errors.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => { try { return await handle(req); } catch (e) { return json({ error: safeError(e, "delete-account") }, 500); } });

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const uid = await callerId(req);
  if (!uid) return json({ error: "not_authenticated" }, 401);

  // Step 1 as the caller, so the RPC's own auth.uid() checks apply.
  const asUser = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization")! } },
    auth: { persistSession: false },
  });
  const { error: rpcError } = await asUser.rpc("delete_my_account");
  const noProfile = !!rpcError && (rpcError.message ?? "").includes("account_not_found");
  if (rpcError && !noProfile) {
    const m = rpcError.message ?? "delete_failed";
    return json({ error: m }, m.includes("admin_cannot_delete") ? 403 : 400);
  }

  // Step 2, Stripe. Read with the service role: the id is not the member's
  // to see or change.
  let stripe: "none" | "deleted" | "already_gone" = "none";
  if (!noProfile) {
    const { data: acct } = await admin.from("accounts").select("stripe_customer_id").eq("id", uid).single();
    const customerId = acct?.stripe_customer_id as string | null | undefined;
    if (customerId) {
      try {
        await getStripe().customers.del(customerId);
        stripe = "deleted";
      } catch (e) {
        if (!isMissingCustomer(e)) {
          console.error("delete-account: Stripe customer not deleted", String((e as Error)?.message ?? e));
          return json({ error: "stripe_delete_failed", stage: "stripe" }, 502);
        }
        stripe = "already_gone";
      }
      await admin.from("accounts").update({ stripe_customer_id: null })
        .eq("id", uid).eq("stripe_customer_id", customerId);
    }
  }

  // Step 3 with the service role: soft delete keeps the auth row, ends every
  // session, and blocks sign-in. Idempotent: a second call answers the same.
  const { error: authError } = await admin.auth.admin.deleteUser(uid, true);
  if (authError) return json({ error: authError.message, stage: "auth" }, 500);
  return json({ deleted: uid, stripe });
}
