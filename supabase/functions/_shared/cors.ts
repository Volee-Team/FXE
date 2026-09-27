// CORS for the functions the web admin calls from the browser.
//
// The admin site (fxe-tennis-admin.vercel.app) and the functions
// (<project>.supabase.co) are different origins, so a browser sends a
// preflight OPTIONS before every call and refuses the call unless the answer
// names the origin. Locally the Kong gateway answers the preflight itself, so
// a function without this works in every local test and fails on hosted:
// found 2026-09-27 by the sql-auditor on admin-reset-link, then confirmed on
// hosted for stripe-charge (preflight 405, no header), which meant Tara's
// Charge clinic on the web admin would queue fees that never reached Stripe.
// Pinned by the preflight checks in scripts/hosted-smoke.sh.
//
// Only the admin site and a local page may call. This is defence in depth:
// the credential is the admin's JWT, which a foreign page cannot read, and a
// non-browser caller ignores CORS entirely.

const ALLOWED = [/^https:\/\/fxe-tennis-admin\.vercel\.app$/, /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/];

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  if (!ALLOWED.some((re) => re.test(origin))) return {};
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Vary": "Origin",
  };
}

/// Wraps a handler: answers the preflight, and adds the headers to every
/// response the handler returns.
export function withCors(handler: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    const cors = corsHeaders(req);
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    const res = await handler(req);
    for (const [k, v] of Object.entries(cors)) res.headers.set(k, v);
    return res;
  };
}
