// admin-reset-link: Tara makes a one-time password-reset link for a member
// and texts it to them (decision 0017). No email is sent.
//
// Why: until custom SMTP is set (launch checklist D1), Supabase's built-in
// sender delivers only to the project's own team, so "Forgot password?"
// reaches no member. And after it is set, a member whose email is misspelled
// or whose mail goes to spam still needs a way back in.
//
// POST { player_id } with the caller's JWT. The caller must be an admin
// (is_admin(), called AS the caller, so the database decides, not this code).
// The link is GoTrue's own recovery token (generateLink returns its hash; no
// email goes out), pointed at the web reset page, which exchanges it with
// verifyOtp. It works once and expires with the project's OTP lifetime
// (mailer_otp_exp, 3600 seconds on hosted).
//
// Whoever opens a link holds a full session for that member until the page
// saves the new password and signs the member out everywhere. So:
//   * an admin account is never a target: a leaked link would be a full admin
//     session, which sees all nine hidden facts (sql-auditor, 2026-09-27);
//   * the token travels in the URL fragment (#token_hash=...), which no
//     browser sends in any request, so it never reaches a server log or a
//     link-preview fetcher;
//   * every link handed out is recorded in reset_links_issued (whose account,
//     who made it, when). The row is written after the token exists and before
//     it is returned: a token that is never returned cannot be used by anyone.
//
// Answers: 200 { link }, 400 bad_request, 401 not_authenticated,
// 403 not_authorized | admin_target, 404 no_such_player,
// 409 account_deleted, 500 identity_mismatch.

import { admin, callerId, json } from "../_shared/stripe.ts";
import { withCors } from "../_shared/cors.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// The page that finishes the reset. Hosted: the admin site. The local harness
// sets RESET_PAGE_URL to the local page.
const RESET_PAGE = Deno.env.get("RESET_PAGE_URL") ?? "https://fxe-tennis-admin.vercel.app/reset.html";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// withCors: the web admin calls this from the browser (_shared/cors.ts).
Deno.serve(withCors(async (req) => { try { return await handle(req); } catch (e) { return json({ error: String((e as Error).message ?? e) }, 500); } }));

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
  if (adminErr) return json({ error: adminErr.message }, 500);
  if (isAdmin !== true) return json({ error: "not_authorized" }, 403);

  let body: unknown;
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const playerId = body && typeof body === "object" && typeof (body as { player_id?: unknown }).player_id === "string"
    ? (body as { player_id: string }).player_id : "";
  if (!UUID.test(playerId)) return json({ error: "bad_request" }, 400);

  const { data: player, error: pErr } = await admin
    .from("players").select("account_id").eq("id", playerId).maybeSingle();
  if (pErr) return json({ error: pErr.message }, 500);
  if (!player) return json({ error: "no_such_player" }, 404);

  const { data: account, error: aErr } = await admin
    .from("accounts").select("id, email, role, deleted_at").eq("id", player.account_id).maybeSingle();
  if (aErr) return json({ error: aErr.message }, 500);
  if (!account) return json({ error: "no_such_player" }, 404);
  if (account.deleted_at) return json({ error: "account_deleted" }, 409);
  if (account.role === "admin") return json({ error: "admin_target" }, 403);

  const { data: gen, error: gErr } = await admin.auth.admin.generateLink({ type: "recovery", email: account.email });
  if (gErr || !gen?.properties?.hashed_token) return json({ error: gErr?.message ?? "no_token", stage: "generate" }, 500);
  // The sign-in the token belongs to must be the account the audit row names.
  // accounts.email is not kept in step with the sign-in's email by any trigger.
  if (gen.user?.id !== account.id) return json({ error: "identity_mismatch" }, 500);

  // Recorded before it is returned; if the record fails, nobody gets the link.
  const { error: logErr } = await admin
    .from("reset_links_issued").insert({ account_id: account.id, issued_by: uid });
  if (logErr) return json({ error: logErr.message, stage: "audit" }, 500);

  const link = `${RESET_PAGE}#token_hash=${encodeURIComponent(gen.properties.hashed_token)}&type=recovery`;
  return json({ link });
}
