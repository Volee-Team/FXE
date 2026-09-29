// What every page of the admin site loads, and what a refused sign-in says
// (MVP audit 2026-09-27, items 17 and 15). Reads only; writes nothing.
import { test, expect } from "@playwright/test";

const TARA = { email: "tara@fxe.test", password: "password" };

async function signIn(page, who) {
  await page.goto("/index.html");
  await page.getByLabel("Email").fill(who.email);
  await page.getByLabel("Password").fill(who.password);
  await page.getByRole("button", { name: "Sign In" }).click();
}

test.describe("scripts", () => {
  test("the admin site and the reset page run supabase-js from this site, never a CDN", async ({ page, baseURL }) => {
    // Item 17: both pages imported https://esm.sh/@supabase/supabase-js@2,
    // whatever 2.x that CDN served that day, running with Tara's session.
    // Every script a page runs must now come from the site itself.
    const origin = new URL(baseURL).origin;
    const foreign = [], broken = [], vendored = [];
    page.on("request", (r) => {
      if (r.resourceType() === "script" && new URL(r.url()).origin !== origin) foreign.push(r.url());
    });
    page.on("response", (r) => {
      if (new URL(r.url()).pathname === "/vendor/supabase-js.js") vendored.push(r.status());
    });
    page.on("pageerror", (e) => broken.push(e.message));
    // Errors raised by this site's own files. A Google Fonts hiccup logs an
    // error too, located at fonts.googleapis.com, and is not this test's business.
    page.on("console", (m) => {
      const at = m.location().url;
      if (m.type() === "error" && (!at || new URL(at).origin === origin)) broken.push(m.text());
    });

    // The admin site, signed in: supabase-js has to work, not just load.
    await signIn(page, TARA);
    await expect(page.locator("#clinics .card").first()).toBeVisible();
    // The reset page with no link in the URL, the review page, and the court
    // sheet (decision 0027 §3) naming no clinic, signed in as Tara.
    await page.goto("/reset.html");
    await page.waitForLoadState("networkidle");
    await page.goto("/review.html");
    await page.waitForLoadState("networkidle");
    await page.goto("/sheet.html");
    await page.waitForLoadState("networkidle");
    await expect(page.locator("#msg")).toHaveText("Couldn't load this clinic.");

    expect(foreign).toEqual([]);
    expect(broken).toEqual([]);
    expect(vendored.length).toBeGreaterThanOrEqual(1);
    expect(vendored.every(s => s === 200 || s === 304)).toBe(true);
  });
});

test.describe("sign-in", () => {
  // Supabase Auth's refusal as it sends it: HTTP 429, the error-code header,
  // and the 2024-01-01 body shape the local stack returns for every auth
  // error ({"code":"invalid_credentials","message":...} for a wrong password).
  const refuse = (code, message) => (route) => route.fulfill({
    status: 429,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
      "access-control-expose-headers": "X-Total-Count, Link, X-Supabase-Api-Version",
      "x-supabase-api-version": "2024-01-01",
      "x-sb-error-code": code,
    },
    body: JSON.stringify({ code, message }),
  });

  test("a sign-in refused for too many attempts says to wait, in one plain line", async ({ page }) => {
    // Item 15: 30 sign-ins per 5 minutes per IP, and the launch party is one
    // Wi-Fi. The old line was whatever GoTrue said.
    await page.route("**/auth/v1/token?grant_type=password", refuse("over_request_rate_limit", "Request rate limit reached"));
    await signIn(page, TARA);
    await expect(page.locator("#signin-msg")).toHaveText("Too many attempts. Try again in a minute.");
  });

  test("a reset email refused by the hourly email limit does not promise a minute", async ({ page }) => {
    // Email sends are limited per hour, not per minute, so this 429 keeps
    // its own words.
    await page.route("**/auth/v1/recover**", refuse("over_email_send_rate_limit", "email rate limit exceeded"));
    await page.goto("/index.html");
    await page.getByLabel("Email").fill(TARA.email);
    await page.getByRole("button", { name: "Forgot password?" }).click();
    await expect(page.locator("#signin-msg")).toHaveText("email rate limit exceeded");
  });

  test("an email limit whose code cannot be read still keeps its own words", async ({ page }) => {
    // The same 429 without the version header a cross-origin page may not be
    // able to read: supabase-js then has no error code, and only the message
    // tells an hourly send limit from the per-minute one (fix round 2026-09-27).
    await page.route("**/auth/v1/recover**", (route) => route.fulfill({
      status: 429,
      headers: { "content-type": "application/json", "access-control-allow-origin": "*" },
      body: JSON.stringify({ msg: "email rate limit exceeded" }),
    }));
    await page.goto("/index.html");
    await page.getByLabel("Email").fill(TARA.email);
    await page.getByRole("button", { name: "Forgot password?" }).click();
    await expect(page.locator("#signin-msg")).toHaveText("email rate limit exceeded");
  });
});

// The QR code's link (question 75, decision 0024). The code Tara prints says
// /app, and /app forwards to wherever the app installs from. The forwarding is
// tested before the real link exists: a test that waited for it would be
// testing nothing tonight and failing silently at the party.
test.describe("the QR code's link", () => {
  test("/app says the app is not available yet while no install link is set", async ({ page }) => {
    await page.goto("/app/");
    await expect(page.getByRole("heading", { name: "FXE Tennis" })).toBeVisible();
    await expect(page.getByText("Not available yet.")).toBeVisible();
    await expect(page.getByRole("link", { name: "Get the app" })).toBeHidden();
  });

  test("once an install link is set, /app forwards to it", async ({ page }) => {
    await page.route("**/app/target.js", (route) => route.fulfill({
      contentType: "application/javascript",
      body: 'export const INSTALL_URL = "https://install.example/join/ABC123";',
    }));
    await page.route("https://install.example/**", (route) => route.fulfill({ contentType: "text/html", body: "<title>arrived</title>" }));
    await page.goto("/app/");
    await page.waitForURL("https://install.example/join/ABC123");
  });

  test("the QR card shows the code, the link written out, Print and the PNG", async ({ page, request }) => {
    await page.goto("/qr.html");
    await expect(page.getByRole("img", { name: /QR code for fxe-tennis-admin\.vercel\.app\/app/ })).toBeVisible();
    await expect(page.getByText("fxe-tennis-admin.vercel.app/app")).toBeVisible();
    await expect(page.getByRole("button", { name: "Print" })).toBeVisible();
    const png = page.getByRole("link", { name: "Download for email" });
    await expect(png).toHaveAttribute("href", "app-qr.png");
    const res = await request.get("/app-qr.png");
    expect(res.status()).toBe(200);
    expect(res.headers()["content-type"]).toContain("image/png");
  });
});
