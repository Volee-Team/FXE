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
    page.on("console", (m) => { if (m.type() === "error") broken.push(m.text()); });

    // The admin site, signed in: supabase-js has to work, not just load.
    await signIn(page, TARA);
    await expect(page.locator("#clinics .card").first()).toBeVisible();
    // The reset page with no link in the URL, and the review page.
    await page.goto("/reset.html");
    await page.waitForLoadState("networkidle");
    await page.goto("/review.html");
    await page.waitForLoadState("networkidle");

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
    await expect(page.locator("#signin-msg")).toHaveText("Too many attempts: wait a minute and try again.");
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
});
