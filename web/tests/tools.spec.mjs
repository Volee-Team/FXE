// Tara's three laptop tools (decision 0027): a player's history beside the
// name, Copy to next week as drafts, and a court sheet to print. Walked the
// way she walks them, against a freshly reset local stack.
//
// Every fixture is written through the REST API as service_role (never SQL on
// auth) and removed again in finally, so a failure cannot leave rows for the
// next test or the probe runner's DIRTY check. The rules themselves (which
// rows count as played, the New York wall clock across daylight saving, the
// skip on a second call, who may call either function) are the SQL probes'
// job: player_history.sql, copy_week.sql, copy_week_race.sh.
//
// Runs after admin.spec.mjs and pages.spec.mjs (files run in name order, one
// worker); like the rest of the suite it wants a fresh `supabase db reset`.
import { test, expect } from "@playwright/test";
import { execSync } from "node:child_process";

const TARA = { email: "tara@fxe.test", password: "password" };
const MARIA = { email: "maria@fxe.test", password: "password" };
const MARIA_P = "a0000000-0000-0000-0000-000000000001";
const KEN_P = "a0000000-0000-0000-0000-000000000002";
const ROB_P = "a0000000-0000-0000-0000-000000000003";
const DANA_P = "a0000000-0000-0000-0000-000000000004";
const PRIYA_P = "a0000000-0000-0000-0000-000000000005";
const TUESDAY = "d0000000-0000-0000-0000-000000000001";   // the seed's Tuesday Ladies 3.0+
const HOUR = 3_600_000, DAY = 24 * HOUR;

async function signIn(page, who) {
  await page.goto("/index.html");
  await page.getByLabel("Email").fill(who.email);
  await page.getByLabel("Password").fill(who.password);
  await page.getByRole("button", { name: "Sign In" }).click();
}

function stackEnv() {
  return Object.fromEntries(execSync("supabase status -o env", { cwd: "..", stdio: ["ignore", "pipe", "ignore"] })
    .toString().split("\n").filter(l => l.includes("="))
    .map(l => { const i = l.indexOf("="); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, "")]; }));
}
function service(request) {
  const env = stackEnv();
  const headers = { apikey: env.SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SERVICE_ROLE_KEY}`,
                    "Content-Type": "application/json", Prefer: "return=representation" };
  const go = async (method, path, body) => {
    const res = await request.fetch(`${env.API_URL}/rest/v1/${path}`, { method, headers, data: body });
    if (!res.ok()) throw new Error(`${method} ${path}: ${res.status()} ${await res.text()}`);
    return res.status() === 204 ? null : res.json();
  };
  return {
    insert: async (table, row) => (await go("POST", table, row))[0],
    del: (path) => go("DELETE", path),
    get: (path) => go("GET", path),
  };
}
const iso = (ms) => new Date(ms).toISOString();
// A published clinic starting `at` (ms), an hour long, registration open.
const clinicAt = (name, at) => ({
  name, audience: "coed", category: "Clinic", description: "browser test",
  starts_at: iso(at), ends_at: iso(at + HOUR),
  member_opens_at: iso(at - 9 * DAY), public_opens_at: iso(at - 8 * DAY),
  internal_capacity: 8, status: "published", duration_minutes: 60,
});
// New York weekday and time of an instant, e.g. "Tue 10:00".
const nyClock = (when) => new Date(when).toLocaleString("en-US",
  { timeZone: "America/New_York", weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });

test.describe("copy to next week", () => {
  test("copies this week's clinics as drafts, and a second click copies nothing", async ({ page, request }) => {
    const db = service(request);
    await signIn(page, TARA);
    await expect(page.locator("#clinics .card").first()).toBeVisible();
    // A clinic of the test's own in this service week (Tuesday, mid-morning
    // New York), so there is something to copy on any day the suite runs. The
    // week's start comes from the page's own week.js, the one the tab uses
    // (pinned by week.spec.mjs).
    const weekStart = await page.evaluate(async () => (await import("/week.js")).serviceWeekStart().getTime());
    const source = await db.insert("clinics", clinicAt("Browser Copy Clinic", weekStart + 2 * DAY + 10 * HOUR));
    // Every draft made after the source (the database's clock, not this one's).
    const drafts = () => db.get(`clinics?status=eq.draft&created_at=gte.${encodeURIComponent(source.created_at)}&select=id,name,starts_at`);
    try {
      await page.getByRole("button", { name: "Copy to next week" }).click();
      const msg = page.locator("#msg");
      await expect(msg).toHaveText(/^Copied \d+ clinics? to next week as (drafts|a draft)\.$/, { timeout: 15_000 });
      // The number on the page is the number of drafts the server made.
      const n = Number((await msg.textContent()).match(/\d+/)[0]);
      const made = await drafts();
      expect(made.length).toBe(n);
      const copy = made.filter(c => c.name === "Browser Copy Clinic");
      expect(copy).toHaveLength(1);
      // Same New York weekday and time, a week later.
      expect(nyClock(copy[0].starts_at)).toBe(nyClock(source.starts_at));
      const days = (new Date(copy[0].starts_at) - new Date(source.starts_at)) / DAY;
      expect(days).toBeGreaterThan(6.9);
      expect(days).toBeLessThan(7.1);
      // On the tab as a draft: it offers Publish, and the source does not.
      const named = page.locator("#clinics .card", { hasText: "Browser Copy Clinic" });
      await expect(named).toHaveCount(2);
      await expect(named.filter({ has: page.getByRole("button", { name: "Publish" }) })).toHaveCount(1);

      await page.getByRole("button", { name: "Copy to next week" }).click();
      await expect(msg).toHaveText("Nothing new to copy.", { timeout: 15_000 });
      expect((await drafts()).length).toBe(n);
      await expect(page.locator("#clinics .card", { hasText: "Browser Copy Clinic" })).toHaveCount(2);
    } finally {
      await db.del(`clinics?status=eq.draft&created_at=gte.${encodeURIComponent(source.created_at)}`);
      await db.del(`clinics?id=eq.${source.id}`);
    }
  });
});

test.describe("court sheet", () => {
  test("lists You're In! by court, then No court yet, with ratings, and prints without its button", async ({ page, request }) => {
    const db = service(request);
    const clinic = await db.insert("clinics", clinicAt("Browser Sheet Clinic", Date.now() + 4 * DAY));
    try {
      const reg = (player, status, court) => db.insert("registrations", { clinic_id: clinic.id, player_id: player,
        status, court_number: court, source: "admin", price_cents_charged: 1800, was_member: true, duration_minutes: 60 });
      await reg(KEN_P, "in", 1);
      await reg(MARIA_P, "in", 2);
      await reg(DANA_P, "in", 2);
      await reg(ROB_P, "in", null);
      await reg(PRIYA_P, "pool", null);   // not You're In!: not on the sheet

      await signIn(page, TARA);
      const link = page.locator("#clinics .card", { hasText: "Browser Sheet Clinic" }).getByRole("link", { name: "Court sheet" });
      await expect(link).toHaveAttribute("href", `sheet.html?clinic=${clinic.id}`);
      await expect(link).toHaveAttribute("target", "_blank");

      // The same tab, the same session: the page is on the admin's origin.
      await page.goto(`/sheet.html?clinic=${clinic.id}`);
      await expect(page.getByRole("heading", { level: 1 })).toHaveText("Browser Sheet Clinic");
      await expect(page.locator("#when")).toHaveText(/^\w+day, \w{3} \d{1,2}, \d{1,2}:\d{2}\s?[AP]M to \d{1,2}:\d{2}\s?[AP]M$/);
      const groups = page.locator("[data-court-group]");
      await expect(groups.locator("h2")).toHaveText(["Court 1", "Court 2", "No court yet"]);
      await expect(groups.nth(0).locator(".player")).toHaveText(["Ken Whitfield"]);
      await expect(groups.nth(0).locator(".rating")).toHaveText(["4.0"]);
      await expect(groups.nth(1).locator(".player")).toHaveText(["Dana Okonkwo", "Maria Alvarez"]);
      await expect(groups.nth(1).locator(".rating")).toHaveText(["3.5", "3.5"]);
      await expect(groups.nth(2).locator(".player")).toHaveText(["Rob Delgado"]);
      await expect(groups.nth(2).locator(".rating")).toHaveText(["3.0"]);
      await expect(page.locator("main")).not.toContainText("Priya");

      // Print calls the browser's print, and the printout carries no button.
      await page.evaluate(() => { window.__printed = 0; window.print = () => { window.__printed += 1; }; });
      await page.getByRole("button", { name: "Print" }).click();
      expect(await page.evaluate(() => window.__printed)).toBe(1);
      await page.emulateMedia({ media: "print" });
      await expect(page.getByRole("button", { name: "Print" })).toBeHidden();
      await expect(groups).toHaveCount(3);
      await page.emulateMedia({ media: "screen" });
    } finally {
      await db.del(`registrations?clinic_id=eq.${clinic.id}`);
      await db.del(`clinics?id=eq.${clinic.id}`);
    }
  });

  test("a member who opens a court sheet sees nothing, because the database gives her nothing", async ({ page, request }) => {
    const db = service(request);
    const clinic = await db.insert("clinics", clinicAt("Browser Sheet Private", Date.now() + 4 * DAY));
    try {
      await db.insert("registrations", { clinic_id: clinic.id, player_id: ROB_P, status: "in", court_number: 3,
        source: "admin", price_cents_charged: 2300, was_member: false, duration_minutes: 60 });
      await page.goto(`/sheet.html?clinic=${clinic.id}`);
      await expect(page.locator("#msg")).toHaveText("Sign in on the admin page first.");

      // Maria signs in through the page's own client and storage (the admin
      // page would sign a member straight back out). The database answers her
      // roster read with nothing: the refusal is Postgres's, not this page's.
      const rows = await page.evaluate(async ({ email, password, id }) => {
        const { createClient } = await import("/vendor/supabase-js.js");
        const { CONFIG } = await import("/config.js");
        const sb = createClient(CONFIG.url, CONFIG.key, { auth: { flowType: "implicit" } });
        const { error } = await sb.auth.signInWithPassword({ email, password });
        if (error) throw new Error(error.message);
        const regs = await sb.from("registrations_admin").select("id").eq("clinic_id", id);
        const clinics = await sb.from("clinics_admin").select("id").eq("id", id);
        return { regs: regs.data, clinics: clinics.data };
      }, { ...MARIA, id: clinic.id });
      expect(rows).toEqual({ regs: [], clinics: [] });

      await page.reload();
      await expect(page.locator("#msg")).toHaveText("Couldn't load this clinic.");
      await expect(page.locator("[data-court-group]")).toHaveCount(0);
      await expect(page.locator("main")).not.toContainText("Rob Delgado");
      await expect(page.locator("main")).not.toContainText("Browser Sheet Private");
    } finally {
      await db.del(`registrations?clinic_id=eq.${clinic.id}`);
      await db.del(`clinics?id=eq.${clinic.id}`);
    }
  });
});

test.describe("player history", () => {
  test("a Player Pool row and the Players tab carry the line; a player with no history reads New", async ({ page, request }) => {
    const db = service(request);
    const now = Date.now();
    const played = await db.insert("clinics", clinicAt("Browser History Played", now - 12 * DAY));
    const missed = await db.insert("clinics", clinicAt("Browser History Missed", now - 11 * DAY));
    const late = await db.insert("clinics", clinicAt("Browser History Late", now - 10 * DAY));
    const made = [];
    const reg = async (clinicId, player, status, extra = {}) => made.push(await db.insert("registrations", {
      clinic_id: clinicId, player_id: player, status, source: "admin",
      price_cents_charged: 2300, was_member: false, duration_minutes: 60, ...extra }));
    try {
      await reg(played.id, ROB_P, "in");
      await reg(missed.id, ROB_P, "in", { no_show: true });
      await reg(late.id, ROB_P, "canceled", { late_cancel: true, canceled_at: iso(now - 10 * DAY - HOUR) });
      await reg(TUESDAY, ROB_P, "pool");
      await reg(TUESDAY, DANA_P, "pool");

      await signIn(page, TARA);
      const card = page.locator("#clinics .card", { hasText: "Tuesday Ladies" });
      const rob = card.locator(".row", { hasText: "Rob Delgado" }).locator("[data-history]");
      await expect(rob).toHaveText("1 played, 1 no-show, 1 late cancel", { timeout: 15_000 });
      await expect(rob).toHaveAttribute("title", /^Last played \w{3} \d{1,2}, \d{4}$/);
      await expect(card.locator(".row", { hasText: "Dana Okonkwo" }).locator("[data-history]")).toHaveText("New");
      // Only the Player Pool carries it on a clinic card.
      await expect(card.locator("[data-history]")).toHaveCount(2);

      await page.getByRole("tab", { name: "Players" }).click();
      await page.getByLabel("Search players by name").fill("Rob");
      await expect(page.locator("[data-player-row]", { hasText: "Rob Delgado" }).locator("[data-history]"))
        .toHaveText("1 played, 1 no-show, 1 late cancel");
    } finally {
      for (const r of made) await db.del(`registrations?id=eq.${r.id}`);
      for (const c of [played, missed, late]) await db.del(`clinics?id=eq.${c.id}`);
    }
  });
});
