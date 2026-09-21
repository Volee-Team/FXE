// delete-account: the second half of account deletion (decision 0013 §5,
// App Store guideline 5.1.1(v)). The signed-in caller has already had, or
// now gets, their personal data scrubbed by delete_my_account() in Postgres
// (history stays: registrations, ledger, Tara's notes). Then the sign-in
// itself is removed through Supabase's admin API with soft delete, which
// keeps the auth row (so accounts.id and everything cascading from it
// survive) while making the credentials unusable. Nothing here, and
// nothing in SQL, writes to the auth schema directly.
//
// Requires the caller's JWT. Admins are refused by the RPC.

import { admin, callerId, json } from "../_shared/stripe.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => { try { return await handle(req); } catch (e) { return json({ error: String((e as Error).message ?? e) }, 500); } });

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
  if (rpcError) {
    const m = rpcError.message ?? "delete_failed";
    return json({ error: m }, m.includes("admin_cannot_delete") ? 403 : 400);
  }

  // Step 2 with the service role: soft delete keeps the auth row, ends every
  // session, and blocks sign-in. Idempotent: a second call answers the same.
  const { error: authError } = await admin.auth.admin.deleteUser(uid, true);
  if (authError) return json({ error: authError.message, stage: "auth" }, 500);
  return json({ deleted: uid });
}
