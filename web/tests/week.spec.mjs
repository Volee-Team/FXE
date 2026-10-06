// This week, bounded (MVP audit 2026-09-27, item 14). The tab listed every
// clinic ever made, oldest first, and read every registration ever in one
// request that PostgREST caps at 1000 rows without a word. Expected values
// here are worked out by hand from the rule (decision 0001: the service week
// is Sunday 00:00 to Saturday 23:59 in New York), never read off week.js.
//
// Runs after admin.spec.mjs (files run in name order, one worker) and writes
// two past clinics and one walk-up, so like the rest of the suite it wants a
// fresh `supabase db reset` before each full run.
import { test, expect } from "@playwright/test";

const TARA = { email: "tara@fxe.test", password: "password" };
const DAY = 86_400_000;

async function signIn(page, who) {
  await page.goto("/index.html");
  await page.getByLabel("Email").fill(who.email);
  await page.getByLabel("Password").fill(who.password);
  await page.getByRole("button", { name: "Sign In" }).click();
}

// The page's own modules, run inside a browser in the given time zone.
async function inBrowser(browser, baseURL, timezoneId, fn, arg) {
  const context = await browser.newContext({ baseURL, timezoneId });
  const page = await context.newPage();
  await page.goto("/review.html");   // any page of the site; it only needs the origin
  const out = await page.evaluate(fn, arg);
  await context.close();
  return out;
}

test.describe("the rule", () => {
  test("the service week starts Sunday 00:00 in New York, whatever the laptop's zone", async ({ browser, baseURL }) => {
    // [an instant, the Sunday 00:00 New York time its week began]
    const cases = [
      ["2026-09-27T03:30:00Z", "2026-09-20T04:00:00.000Z"], // Sat 23:30 EDT: already Sunday in UTC
      ["2026-09-27T03:59:59Z", "2026-09-20T04:00:00.000Z"], // the last second of Saturday
      ["2026-09-27T04:00:00Z", "2026-09-27T04:00:00.000Z"], // Sunday 00:00 EDT starts the week
      ["2026-09-28T12:00:00Z", "2026-09-27T04:00:00.000Z"], // Monday, where an ISO week would start
      ["2026-11-01T12:00:00Z", "2026-11-01T04:00:00.000Z"], // fall-back Sunday: midnight was still EDT
      ["2026-11-07T12:00:00Z", "2026-11-01T04:00:00.000Z"], // the Saturday after, in EST
      ["2026-11-08T05:00:00Z", "2026-11-08T05:00:00.000Z"], // Sunday 00:00 EST
      ["2026-03-08T12:00:00Z", "2026-03-08T05:00:00.000Z"], // spring-forward Sunday: midnight was EST
      ["2026-03-14T23:00:00Z", "2026-03-08T05:00:00.000Z"], // the Saturday after, in EDT
      ["2027-01-01T12:00:00Z", "2026-12-27T05:00:00.000Z"], // a week across New Year
    ];
    for (const zone of ["America/New_York", "UTC", "Asia/Tokyo"]) {
      const got = await inBrowser(browser, baseURL, zone, async (nows) => {
        const { serviceWeekStart } = await import("/week.js");
        return nows.map(n => serviceWeekStart(new Date(n)).toISOString());
      }, cases.map(c => c[0]));
      expect(got.map((g, i) => `${zone} ${cases[i][0]} -> ${g}`))
        .toEqual(cases.map(([n, w]) => `${zone} ${n} -> ${w}`));
    }
  });

  test("week headings read This week, Next week, then Week of the Sunday, across the time change", async ({ browser, baseURL }) => {
    // This week began Sunday 2026-10-25 00:00 EDT (04:00Z). Worked by hand:
    // Nov 1 is the fall-back Sunday (midnight still EDT), Nov 8 is in EST.
    const cases = [
      ["2026-10-25T04:00:00Z", "This week"],
      ["2026-11-01T04:00:00Z", "Next week"],   // 168 hours later
      ["2026-11-08T05:00:00Z", "Week of Nov 8"], // 337 hours later: two weeks, not 2.006
      ["2026-12-27T05:00:00Z", "Week of Dec 27"],
    ];
    for (const zone of ["America/New_York", "UTC", "Asia/Tokyo"]) {
      const got = await inBrowser(browser, baseURL, zone, async (starts) => {
        const { weekLabel } = await import("/week.js");
        return starts.map(s => weekLabel(new Date(s), new Date("2026-10-25T04:00:00Z")));
      }, cases.map(c => c[0]));
      expect(got).toEqual(cases.map(c => c[1]));
    }
  });

  test("the tab lists what ends after the week began, plus uncharged clinics while payments are on", async ({ browser, baseURL }) => {
    // The week that began Sunday 2026-09-27 00:00 EDT.
    const clinics = [
      { id: "a-ends-at-midnight", starts_at: "2026-09-27T03:00:00Z", ends_at: "2026-09-27T04:00:00Z", status: "published" },
      { id: "b-ends-a-second-in", starts_at: "2026-09-27T03:30:00Z", ends_at: "2026-09-27T04:00:01Z", status: "published" },
      { id: "c-saturday-owed", starts_at: "2026-09-26T22:00:00Z", ends_at: "2026-09-26T23:30:00Z", status: "published" },
      { id: "d-canceled-owed", starts_at: "2026-09-26T13:00:00Z", ends_at: "2026-09-26T14:00:00Z", status: "canceled" },
      { id: "e-thursday", starts_at: "2026-10-01T12:00:00Z", ends_at: "2026-10-01T13:00:00Z", status: "published" },
      { id: "f-last-month", starts_at: "2026-08-30T12:00:00Z", ends_at: "2026-08-30T13:00:00Z", status: "published" },
      { id: "g-monday", starts_at: "2026-09-28T12:00:00Z", ends_at: "2026-09-28T13:00:00Z", status: "draft" },
    ];
    const got = await inBrowser(browser, baseURL, "UTC", async (clinics) => {
      const { splitThisWeek } = await import("/week.js");
      const weekStart = new Date("2026-09-27T04:00:00Z");
      const owed = new Set(["c-saturday-owed", "d-canceled-owed", "e-thursday"]);
      const ids = ({ current, earlier }) => ({ current: current.map(c => c.id), earlier: earlier.map(c => c.id) });
      return {
        off: ids(splitThisWeek(clinics, { weekStart, paymentsOn: false, owed })),
        on: ids(splitThisWeek(clinics, { weekStart, paymentsOn: true, owed })),
      };
    }, clinics);
    // Payments off: nothing is ever charged, so owing decides nothing.
    // current forward in time, earlier back from the week's start.
    expect(got.off).toEqual({
      current: ["b-ends-a-second-in", "g-monday", "e-thursday"],
      earlier: ["a-ends-at-midnight", "c-saturday-owed", "d-canceled-owed", "f-last-month"],
    });
    // Payments on: Saturday's uncharged clinic stays on the tab; the canceled
    // one does not, because Charge clinic is never offered on a canceled clinic.
    expect(got.on).toEqual({
      current: ["c-saturday-owed", "b-ends-a-second-in", "g-monday", "e-thursday"],
      earlier: ["a-ends-at-midnight", "d-canceled-owed", "f-last-month"],
    });
  });

  test("a list longer than the server's 1000-row cap comes back whole and in order", async ({ browser, baseURL }) => {
    const got = await inBrowser(browser, baseURL, "UTC", async () => {
      const { readAll, readByIds } = await import("/read.js");
      // A fake PostgREST: 1203 rows, at most 1000 per answer, and silent about it.
      const table = Array.from({ length: 1203 }, (_, i) => ({ id: i }));
      const asked = [];
      const server = (rows) => ({ range: async (from, to) => {
        asked.push(`${from}-${to}`);
        return { data: rows.slice(from, Math.min(to + 1, from + 1000)), error: null };
      } });
      const all = await readAll(() => server(table));
      const pages = [...asked];
      // 250 clinic ids, each with two rows: three URLs of at most 100 ids.
      const ids = Array.from({ length: 250 }, (_, i) => i);
      const slices = [];
      const byIds = await readByIds(ids, (part) => { slices.push(part.length); return server(part.flatMap(i => [{ id: `${i}a` }, { id: `${i}b` }])); });
      // A failure on the second page is an error, never half a list.
      let n = 0;
      const broken = await readAll(() => ({ range: async (from) => (++n === 2
        ? { data: null, error: { message: "boom" } }
        : { data: table.slice(from, from + 500), error: null }) }));
      return {
        count: all.data.length, inOrder: all.data.every((r, i) => r.id === i), pages,
        slices, byIdsCount: byIds.data.length,
        broken: { data: broken.data ?? null, error: broken.error?.message ?? null },
      };
    });
    expect(got).toEqual({
      count: 1203, inOrder: true, pages: ["0-499", "500-999", "1000-1499"],
      slices: [100, 100, 50], byIdsCount: 500,
      broken: { data: null, error: "boom" },
    });
  });
});

test.describe("the tab", () => {
  // Wall-clock times typed into the form are New York's, as Tara's are.
  test.use({ timezoneId: "America/New_York" });

  test("a clinic from before this week stays off the tab until Show earlier, roster and all", async ({ page }) => {
    // Eight and fifteen days back at 10:00 New York. Whatever today is, both
    // end more than seven days ago, so before this week's Sunday 00:00.
    const nyDay = (msAgo) => new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit",
    }).format(new Date(Date.now() - msAgo));
    const stamp = Date.now();
    const recent = `Earlier clinic ${stamp} (8 days)`;
    const older = `Earlier clinic ${stamp} (15 days)`;

    await signIn(page, TARA);
    await expect(page.locator("#clinics .card", { hasText: "Thursday Morning Cardio" })).toBeVisible();
    for (const [name, ago] of [[recent, 8 * DAY], [older, 15 * DAY]]) {
      await page.getByRole("button", { name: "New clinic" }).click();
      await page.locator("#f-name").fill(name);
      await page.locator("#f-starts").fill(`${nyDay(ago)}T10:00`);
      await page.locator("#f-duration").fill("60");
      await page.locator("#edit-save").click();
      await expect(page.locator("dialog#edit")).toBeHidden({ timeout: 15_000 });
    }

    // Saved, and not on the tab: the tab is this week and after.
    await expect(page.locator("#clinics .card", { hasText: "Thursday Morning Cardio" })).toBeVisible();
    await expect(page.locator("#clinics .card", { hasText: recent })).toHaveCount(0);
    await expect(page.locator("#clinics .card", { hasText: older })).toHaveCount(0);
    await expect(page.locator("#clinics h2", { hasText: "Earlier" })).toHaveCount(0);

    // Show earlier: after this week's clinics, under Earlier, newest first.
    await page.getByLabel("Show earlier").check();
    await expect(page.locator("#clinics .card", { hasText: recent })).toBeVisible();
    const order = await page.locator("#clinics").evaluate(el => [...el.children]
      .map(c => c.tagName === "H2" ? "# " + c.textContent : (c.querySelector(".name")?.textContent ?? "")));
    const at = (s) => order.indexOf(s);
    expect(at("Thursday Morning Cardio")).toBeGreaterThanOrEqual(0);
    expect(at("# Earlier")).toBeGreaterThan(at("Thursday Morning Cardio"));
    expect(at(recent)).toBeGreaterThan(at("# Earlier"));
    expect(at(older)).toBeGreaterThan(at(recent));

    // Its roster is read too: a walk-up shows on it.
    const card = page.locator("#clinics .card", { hasText: recent });
    await card.getByRole("button", { name: "Add player" }).click();
    const dialog = page.locator("dialog#walkup");
    await dialog.getByLabel("Search by name").fill("Ken");
    await dialog.getByRole("button", { name: "Put in clinic" }).first().click();
    await expect(dialog).toBeHidden({ timeout: 15_000 });
    await expect(card).toContainText("Ken Whitfield", { timeout: 15_000 });
    await expect(card).toContainText("You're In!");

    // And it goes away again.
    await page.getByLabel("Show earlier").uncheck();
    await expect(page.locator("#clinics .card", { hasText: recent })).toHaveCount(0);
    await expect(page.locator("#clinics .card", { hasText: "Thursday Morning Cardio" })).toBeVisible();
  });
});

// Decision 0038 on the laptop (2026-10-04): a clinic's time is Charlotte's,
// whatever zone the laptop is in. Kat in California, or Tara at an away
// tournament with her Mac on local time, typed 10:00 and saved 13:00
// Eastern, which every phone then showed. From the rule: 10:00 New York on
// Tuesday 2026-11-10 is EST (UTC-5), so 15:00Z.
test.describe("a laptop outside Eastern time", () => {
  test.use({ timezoneId: "America/Los_Angeles" });

  test("a clinic typed as 10:00 is saved as 10:00 Charlotte time, and reads back as 10:00", async ({ page, request }) => {
    const { execSync } = await import("node:child_process");
    const env = Object.fromEntries(execSync("supabase status -o env", { cwd: "..", stdio: ["ignore", "pipe", "ignore"] })
      .toString().split("\n").filter(l => l.includes("="))
      .map(l => { const i = l.indexOf("="); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, "")]; }));
    const headers = { apikey: env.SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SERVICE_ROLE_KEY}` };
    const name = `LA laptop clinic ${Date.now()}`;
    try {
      await signIn(page, TARA);
      await expect(page.getByRole("button", { name: "New clinic" })).toBeVisible();
      await page.getByRole("button", { name: "New clinic" }).click();
      await page.locator("#f-name").fill(name);
      await page.locator("#f-starts").fill("2026-11-10T10:00");
      await page.locator("#f-duration").fill("60");
      await page.locator("#edit-save").click();
      await expect(page.locator("dialog#edit")).toBeHidden({ timeout: 15_000 });

      const rows = await request.fetch(`${env.API_URL}/rest/v1/clinics?name=eq.${encodeURIComponent(name)}&select=starts_at`, { headers })
        .then(r => r.json());
      expect(rows.map(r => new Date(r.starts_at).toISOString())).toEqual(["2026-11-10T15:00:00.000Z"]);

      // The card and the edit form read it back as 10:00, not 7:00.
      const card = page.locator("#clinics .card", { hasText: name });
      await expect(card).toContainText("10:00");
      await card.getByRole("button", { name: "Edit" }).click();
      await expect(page.locator("#f-starts")).toHaveValue("2026-11-10T10:00");
    } finally {
      await request.fetch(`${env.API_URL}/rest/v1/clinics?name=eq.${encodeURIComponent(name)}`, { method: "DELETE", headers });
    }
  });
});
