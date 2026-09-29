// app-visit: counts one open of the app link (web/app/index.html).
// Kat, 2026-09-29: "The QR code though needs to track # of scans".
// A scan comes from a phone with no account, so verify_jwt is off
// (config.toml) and there is no credential: the body is only which way they
// came, and the database keeps only a day and that word (20260929000005).
//
//   POST { via: "qr" | "link" }  ->  204
//
// Nothing about the visitor is read or stored: no IP, no user agent.
import { admin } from "../_shared/supabase.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return new Response(null, { status: 405, headers: CORS });
  let via = "link";
  try {
    const body = await req.json();
    if (body && body.via === "qr") via = "qr";
  } catch { /* a beacon with no JSON body counts as a plain link */ }
  const { error } = await admin.rpc("record_app_link_visit", { p_via: via });
  return new Response(null, { status: error ? 500 : 204, headers: CORS });
});
