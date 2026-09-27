// What every page of the admin site loads (MVP audit 2026-09-27, item 17).
// Reads only; writes nothing.
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
