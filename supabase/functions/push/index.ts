// push: delivers one notification row to the recipient's phones through
// Apple Push Notification service (decision 0008).
//
// Called by the database, not by a person. The AFTER INSERT trigger
// push_on_notification (20260923000001) posts {notification_id} here through
// pg_net whenever any RPC writes a notification, so the copy, the audience
// and the timing all stay where they already live, and no client can
// fabricate a push. The database has no JWT to send, so JWT verification is
// off for this function and the credential is a shared secret header that
// only the vault and this function's environment hold.
//
// The text on the lock screen is the row's `body`, verbatim. Every one of
// those sentences was written by Tara or approved by Alex (hard rule 13);
// nothing here may add to it, trim it, or "improve" it.
//
// Idempotent: pg_net may retry, and a row that already has delivered_at is
// answered with `skipped` and never sent twice.
//
// Nothing here throws at load. Until Apple issues the key the function
// deploys, answers, and records `apns_not_configured` on the row, the same
// shape as stripe_not_configured.

import { admin, json } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  try { return await handle(req); } catch (e) { return json({ error: String((e as Error).message ?? e) }, 500); }
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // An unset PUSH_WEBHOOK_SECRET refuses everyone, including an empty header.
  const expected = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
  const given = req.headers.get("X-Push-Secret") ?? "";
  if (!expected || !timingSafeEqual(given, expected)) return json({ error: "not_authorized" }, 401);

  let body: { notification_id?: unknown };
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const id = typeof body?.notification_id === "string" ? body.notification_id : "";
  if (!UUID.test(id)) return json({ error: "bad_request" }, 400);

  const { data: row, error: rowError } = await admin
    .from("notifications")
    .select("id, account_id, type, entity_type, entity_id, body, delivered_at")
    .eq("id", id)
    .maybeSingle();
  if (rowError) return json({ error: rowError.message }, 500);
  if (!row) return json({ error: "not_found" }, 404);
  if (row.delivered_at) return json({ skipped: "already_delivered" });

  const { data: devices, error: devError } = await admin
    .from("devices").select("apns_token").eq("account_id", row.account_id);
  if (devError) return json({ error: devError.message }, 500);
  if (!devices || devices.length === 0) {
    await record(id, { delivery_error: "no_device" });
    return json({ sent: 0 });
  }

  const cfg = apnsConfig();
  if (!cfg) {
    await record(id, { delivery_error: "apns_not_configured" });
    return json({ error: "apns_not_configured" }, 503);
  }

  // The badge is what the bell shows: the account's unread rows, this one
  // included (it was inserted before the trigger fired).
  const { count: unread } = await admin
    .from("notifications").select("id", { count: "exact", head: true })
    .eq("account_id", row.account_id).is("read_at", null);

  const payload = JSON.stringify({
    aps: { alert: { body: row.body }, sound: "default", badge: unread ?? 0 },
    notification_id: row.id,
    type: row.type,
    entity_type: row.entity_type,
    entity_id: row.entity_id,
  });

  let sent = 0;
  const errors: string[] = [];
  for (const d of devices) {
    const out = await sendOne(cfg, d.apns_token, row.id, payload);
    if (out.ok) { sent++; continue; }
    errors.push(out.reason);
    // Decision 0008: "Old tokens are pruned by APNs feedback." 410 is Apple
    // saying the app is gone from that phone; BadDeviceToken is a token that
    // was never valid for this topic and environment. Either way, sending to
    // it again can only fail again.
    if (out.status === 410 || (out.status === 400 && out.reason === "BadDeviceToken")) {
      await admin.from("devices").delete().eq("account_id", row.account_id).eq("apns_token", d.apns_token);
    }
  }

  if (sent > 0) await record(id, { delivered_at: new Date().toISOString(), delivery_error: null });
  else await record(id, { delivery_error: errors[0] ?? "unknown" });
  return json({ sent, failed: errors.length, errors });
}

async function record(id: string, patch: Record<string, unknown>) {
  await admin.from("notifications").update(patch).eq("id", id);
}

// Length leaks, content does not: the loop always walks the longer string.
function timingSafeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

// ------------------------------------------------------------------ APNs

type Apns = { keyId: string; teamId: string; pem: string; topic: string; host: string };

function apnsConfig(): Apns | null {
  const keyId = Deno.env.get("APNS_KEY_ID"), teamId = Deno.env.get("APNS_TEAM_ID");
  const pem = Deno.env.get("APNS_PRIVATE_KEY"), topic = Deno.env.get("APNS_TOPIC");
  if (!keyId || !teamId || !pem || !topic) return null;
  // Production by default. A TestFlight or App Store build gets production
  // tokens; only a build run from Xcode gets sandbox ones, and that is the
  // case for setting APNS_HOST=https://api.sandbox.push.apple.com.
  const host = (Deno.env.get("APNS_HOST") || "https://api.push.apple.com").replace(/\/+$/, "");
  return { keyId, teamId, pem, topic, host };
}

async function sendOne(cfg: Apns, token: string, collapseId: string, payload: string):
    Promise<{ ok: true } | { ok: false; status: number; reason: string }> {
  let res: Response;
  try {
    // Deno's fetch negotiates HTTP/2 over TLS, which APNs requires. The local
    // mock speaks plain HTTP/1.1; Apple never would.
    res = await fetch(`${cfg.host}/3/device/${encodeURIComponent(token)}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await providerToken(cfg)}`,
        "apns-topic": cfg.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": collapseId,
        "content-type": "application/json",
      },
      body: payload,
    });
  } catch (e) {
    return { ok: false, status: 0, reason: `request_failed: ${String((e as Error).message ?? e)}` };
  }
  const text = await res.text();
  if (res.status === 200) return { ok: true };
  let reason = String(res.status);
  try { const r = JSON.parse(text)?.reason; if (r) reason = String(r); } catch { /* status stands */ }
  // A rejected provider token will be rejected again until it is re-signed.
  if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken") cached = null;
  return { ok: false, status: res.status, reason };
}

// Provider token: an ES256 JWT, {alg, kid} over {iss: team, iat}. Apple
// accepts one for up to an hour and rejects a new one more often than every
// twenty minutes (TooManyProviderTokenUpdates), so it is cached for the life
// of the worker and re-signed after 50 minutes.
let cached: { jwt: string; iat: number; keyId: string } | null = null;
const TOKEN_TTL_S = 50 * 60;

async function providerToken(cfg: Apns): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.keyId === cfg.keyId && now - cached.iat < TOKEN_TTL_S) return cached.jwt;
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(cfg.pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const head = b64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: cfg.keyId })));
  const claims = b64url(new TextEncoder().encode(JSON.stringify({ iss: cfg.teamId, iat: now })));
  // WebCrypto's ECDSA signature is already the raw 64-byte r||s that JOSE
  // wants; no DER unwrapping (unlike OpenSSL's output).
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key,
    new TextEncoder().encode(`${head}.${claims}`));
  const jwt = `${head}.${claims}.${b64url(new Uint8Array(sig))}`;
  cached = { jwt, iat: now, keyId: cfg.keyId };
  return jwt;
}

// Accepts the .p8 file as Apple issues it (PEM with real newlines), a PEM
// whose newlines were flattened to "\n" by a secrets UI, or the bare base64.
function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/\\n/g, "\n").replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
