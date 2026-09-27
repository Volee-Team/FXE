// A stand-in for api.push.apple.com, for tests/push/run.sh and CI.
//
//   deno run --allow-net --allow-read --allow-write tests/push/mock-apns.ts <env-file> <log-file> [port]
//
// Apple offers no sandbox that works without a paid developer account and a
// real device token, so this answers the way APNs documents it does, by
// token prefix:
//   good...  200 {}
//   gone...  410 {"reason":"Unregistered"}
//   bad...   400 {"reason":"BadDeviceToken"}
// and 403 {"reason":"InvalidProviderToken"} for any request whose bearer
// token is not an ES256 JWT with the expected kid and team, signed by the
// key in <env-file> (the one tests/push/make-env.sh generated). Verifying the
// signature, not just the header, is the point: ES256 signing is the part of
// the function most likely to be subtly wrong, and Apple would only say 403.
//
// Every request is appended to <log-file> as JSON so the harness can count
// them and read back exactly what was sent. Plain HTTP/1.1: the function's
// fetch talks whatever the server speaks; Apple's side is HTTP/2 over TLS.

const [envFile, logFile, portArg] = Deno.args;
if (!envFile || !logFile) {
  console.error("usage: mock-apns.ts <env-file> <log-file> [port]");
  Deno.exit(2);
}
const env = Object.fromEntries(
  (await Deno.readTextFile(envFile)).split("\n").filter((l) => l.includes("="))
    .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]),
);
const KID = env.APNS_KEY_ID, TEAM = env.APNS_TEAM_ID;

// The public half of the generated key: import the private key, export it as
// a JWK (which carries x and y), and re-import only x and y for verifying.
const der = Uint8Array.from(
  atob(env.APNS_PRIVATE_KEY.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "")),
  (c) => c.charCodeAt(0),
);
const priv = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, true, ["sign"]);
const jwk = await crypto.subtle.exportKey("jwk", priv);
const pub = await crypto.subtle.importKey("jwk", { kty: "EC", crv: "P-256", x: jwk.x, y: jwk.y },
  { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);

const log: unknown[] = [];
await Deno.writeTextFile(logFile, "[]");

const b64urlDecode = (s: string) =>
  Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));

async function providerTokenOk(auth: string | null): Promise<string> {
  const m = /^bearer (.+)$/i.exec(auth ?? "");
  if (!m) return "no bearer";
  const parts = m[1].split(".");
  if (parts.length !== 3) return "not a JWT";
  try {
    const head = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[0])));
    const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1])));
    if (head.alg !== "ES256") return `alg ${head.alg}`;
    if (head.kid !== KID) return `kid ${head.kid}`;
    if (claims.iss !== TEAM) return `iss ${claims.iss}`;
    if (typeof claims.iat !== "number" || Math.abs(Date.now() / 1000 - claims.iat) > 3600) return "iat";
    const sig = b64urlDecode(parts[2]);
    if (sig.length !== 64) return `signature is ${sig.length} bytes, not raw r||s`;
    const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pub, sig,
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
    return ok ? "" : "bad signature";
  } catch (e) {
    return `unparseable: ${(e as Error).message}`;
  }
}

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve({ port: Number(portArg ?? 12222), hostname: "0.0.0.0" }, async (req) => {
  const url = new URL(req.url);
  const m = /^\/3\/device\/(.+)$/.exec(url.pathname);
  const text = await req.text();
  let body: unknown = null;
  try { body = JSON.parse(text); } catch { body = text; }
  const tokenProblem = await providerTokenOk(req.headers.get("authorization"));
  const deviceToken = m ? decodeURIComponent(m[1]) : null;

  let status: number, answer: unknown;
  if (req.method !== "POST" || !deviceToken) { status = 404; answer = { reason: "BadPath" }; }
  else if (tokenProblem) { status = 403; answer = { reason: "InvalidProviderToken" }; }
  else if (deviceToken.startsWith("good")) { status = 200; answer = {}; }
  else if (deviceToken.startsWith("gone")) { status = 410; answer = { reason: "Unregistered", timestamp: Date.now() }; }
  else if (deviceToken.startsWith("bad")) { status = 400; answer = { reason: "BadDeviceToken" }; }
  else { status = 400; answer = { reason: "BadDeviceToken" }; }

  log.push({
    at: new Date().toISOString(),
    path: url.pathname,
    token: deviceToken,
    token_problem: tokenProblem || null,
    headers: {
      "apns-topic": req.headers.get("apns-topic"),
      "apns-push-type": req.headers.get("apns-push-type"),
      "apns-priority": req.headers.get("apns-priority"),
      "apns-collapse-id": req.headers.get("apns-collapse-id"),
    },
    body,
    status,
  });
  await Deno.writeTextFile(logFile, JSON.stringify(log, null, 1));
  return reply(status, answer);
});
