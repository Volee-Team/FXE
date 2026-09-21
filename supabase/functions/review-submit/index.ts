// review-submit: saves and returns Tara's answers on the review page
// (web/review.html). She opens the page from a text message and has no
// account, so verify_jwt is off for this function (config.toml) and the
// credential is the token in the URL, minted by admin_create_review_link
// and checked here against review_links. No client role can read or write
// review_responses (20260921000010); this function, as service_role, is the
// only writer, and admin_review_responses is how Alex reads it back.
//
//   POST { token, page_version, answers }  -> { saved_at }
//   GET  ?token=&page_version=              -> { answers, saved_at }   (null, null when nothing saved yet)
//
// Errors: 404 unknown_link (no such token, or revoked), 400 bad_request
// (shape or size), 405 method_not_allowed. answers is one JSON object under
// 200 KB, replaced whole on every save; updated_at is stamped by the
// database.
//
// Not built: rate limiting. The token is 32 random URL-safe characters and
// a miss costs one primary-key lookup; a flood would be a nuisance, not a
// leak. Revisit if a link is ever shared beyond Tara.

import { admin, json } from "../_shared/supabase.ts";

// The page lives on fxe-tennis-admin.vercel.app (or localhost during tests)
// and this function on the Supabase origin, so every browser call is
// cross-origin. Any origin may call: the token is the credential, not the
// origin, and the response carries nothing but that token's own answers.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, authorization, apikey, x-client-info",
};

const MAX_ANSWERS_BYTES = 200 * 1024;
const TOKEN_SHAPE = /^[A-Za-z0-9_-]{16,128}$/;
const VERSION_SHAPE = /^[A-Za-z0-9._-]{1,32}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  try { return await handle(req); } catch (e) { return json({ error: String((e as Error).message ?? e) }, 500, CORS); }
});

async function liveLink(token: string): Promise<boolean> {
  const { data } = await admin.from("review_links").select("token").eq("token", token).is("revoked_at", null).maybeSingle();
  return !!data;
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "GET") {
    const url = new URL(req.url);
    const token = url.searchParams.get("token") ?? "";
    const version = url.searchParams.get("page_version") ?? "";
    if (!TOKEN_SHAPE.test(token) || !VERSION_SHAPE.test(version)) return json({ error: "bad_request" }, 400, CORS);
    if (!(await liveLink(token))) return json({ error: "unknown_link" }, 404, CORS);
    const { data, error } = await admin.from("review_responses")
      .select("answers, updated_at").eq("token", token).eq("page_version", version).maybeSingle();
    if (error) return json({ error: error.message }, 500, CORS);
    return json({ answers: data?.answers ?? null, saved_at: data?.updated_at ?? null }, 200, CORS);
  }

  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405, CORS);

  let body: { token?: unknown; page_version?: unknown; answers?: unknown };
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400, CORS); }
  const token = typeof body.token === "string" ? body.token : "";
  const version = typeof body.page_version === "string" ? body.page_version : "";
  const answers = body.answers;
  if (!TOKEN_SHAPE.test(token) || !VERSION_SHAPE.test(version)) return json({ error: "bad_request" }, 400, CORS);
  if (typeof answers !== "object" || answers === null || Array.isArray(answers)) return json({ error: "bad_request" }, 400, CORS);
  if (JSON.stringify(answers).length > MAX_ANSWERS_BYTES) return json({ error: "too_large" }, 400, CORS);
  if (!(await liveLink(token))) return json({ error: "unknown_link" }, 404, CORS);

  // One row per (token, page_version), replaced whole. The trigger stamps
  // updated_at, so nothing here has to remember to.
  const { data, error } = await admin.from("review_responses")
    .upsert({ token, page_version: version, answers }, { onConflict: "token,page_version" })
    .select("updated_at").single();
  if (error) return json({ error: error.message }, 500, CORS);
  return json({ saved_at: data.updated_at }, 200, CORS);
}
