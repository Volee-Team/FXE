// Tara's Courts tab (decision 0058, docs/courts/plan.md step 3), walked the
// way she walks it against a freshly reset local stack: the day, booking for
// someone and canceling it, a block over a booking (listed, never canceled),
// a clinic published over a booking (warned), and the court rules with the
// switch that lets members book.
//
// Fixtures go in through the REST API as service_role and come out again in
// finally, so a failure leaves nothing for the next test or the probe
// runner's DIRTY check. The rules themselves (no double booking, limits,
// hours, what a clinic holds, who may call what) are the SQL probes' job:
// tests/sql/court_reservations.sql and court_booking_race.sh.
import { test, expect } from "@playwright/test";
import { execSync } from "node:child_process";

const TARA = { email: "tara@fxe.test", password: "password" };
const MARIA_A = "22222222-2222-2222-2222-222222222222";
const KEN_A = "33333333-3333-3333-3333-333333333333";
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
    patch: (path, body) => go("PATCH", path, body),
    del: (path) => go("DELETE", path),
    get: (path) => go("GET", path),
  };
}

// New York's calendar: a day two ahead of today, and an instant on it.
const nyDate = (ms) => new Date(ms).toLocaleDateString("en-CA", { timeZone: "America/New_York" });
const DAY_UNDER_TEST = nyDate(Date.now() + 2 * DAY);
// The instant New York's clock reads DAY_UNDER_TEST hh:00, settled twice
// across a daylight-saving change, as week.js does.
function nyAt(hh, mi = 0) {
  const [y, m, d] = DAY_UNDER_TEST.split("-").map(Number);
  const want = Date.UTC(y, m - 1, d, hh, mi);
  let t = want;
  for (let i = 0; i < 3; i++) {
    const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", hourCycle: "h23",
      year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric" })
      .formatToParts(new Date(t)).filter(x => x.type !== "literal").map(x => [x.type, Number(x.value)]));
    const seen = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
    if (seen === want) break;
    t += want - seen;
  }
  return new Date(t).toISOString();
}

async function openCourts(page, day = DAY_UNDER_TEST) {
  await signIn(page, TARA);
  await page.getByRole("tab", { name: "Courts" }).click();
  await page.locator("#ct-day").fill(day);
  await expect(page.locator("#ct-grid .ct-head")).toHaveCount(6);   // the time column and five courts
}
// Every confirm() accepted, its words kept for the test to read.
function acceptDialogs(page) {
  const seen = [];
  page.on("dialog", d => { seen.push(d.message()); d.accept(); });
  return seen;
}

test.describe("courts tab", () => {
  test("shows the day: five courts, the switch off, and a seed clinic holding its courts", async ({ page, request }) => {
    const db = service(request);
    const [clinic] = await db.get(`clinics?status=eq.published&canceled_at=is.null&starts_at=gt.${encodeURIComponent(new Date().toISOString())}&order=starts_at&limit=1&select=id,name,starts_at`);
    await openCourts(page, nyDate(new Date(clinic.starts_at).getTime()));
    await expect(page.locator("#ct-live")).toContainText("Off for members. Court booking is in testing");
    for (const n of [1, 2, 3, 4, 5]) await expect(page.locator("#ct-grid .ct-head", { hasText: `Court ${n}` })).toBeVisible();
    const row = page.locator(`[data-ct-row="clinic:${clinic.id}"]`);
    await expect(row).toContainText(clinic.name);
    await expect(row).toContainText("Clinic");
    await expect(page.locator(`#ct-grid [data-ct-item="clinic:${clinic.id}"]`).first()).toBeVisible();
  });

  test("books a court for a member with a private note, then cancels it", async ({ page, request }) => {
    const db = service(request);
    const dialogs = acceptDialogs(page);
    await openCourts(page);
    let id = null;
    try {
      await page.getByRole("button", { name: "Book a court" }).click();
      const dlg = page.locator("#court-book");
      await dlg.getByLabel("Who is it for?").fill("Whitf");
      await dlg.getByRole("button", { name: "Choose Ken Whitfield" }).click();
      await expect(dlg.locator("#cb-who")).toHaveText("For Ken Whitfield");
      await dlg.getByLabel("Court", { exact: true }).selectOption("1");
      await dlg.getByLabel("Start").selectOption("09:00");
      await dlg.getByLabel("Length").selectOption("60");
      await dlg.getByLabel("Note (only you see this)").fill("Browser test note");
      await dlg.getByRole("button", { name: "Book", exact: true }).click();
      await expect(page.locator("#ct-msg")).toContainText("Booked for Ken Whitfield.");

      const rows = await db.get(`court_bookings?account_id=eq.${KEN_A}&status=eq.booked&select=id,court,starts_at,ends_at,admin_note,made_by_admin`);
      expect(rows).toHaveLength(1);
      id = rows[0].id;
      expect(rows[0]).toMatchObject({ court: 1, admin_note: "Browser test note", made_by_admin: true });
      expect(new Date(rows[0].starts_at).toISOString()).toBe(nyAt(9));
      expect(new Date(rows[0].ends_at).toISOString()).toBe(nyAt(10));

      const row = page.locator(`[data-ct-row="booking:${id}"]`);
      await expect(row).toContainText("Ken Whitfield");
      await expect(row).toContainText("Court 1");
      await expect(row).toContainText("booked by you");
      await expect(row).toContainText("Your note: Browser test note");
      await expect(page.locator(`#ct-grid [data-ct-item="booking:${id}"]`)).toContainText("Ken Whitfield");

      await row.getByRole("button", { name: "Cancel booking" }).click();
      await expect(page.locator("#ct-msg")).toContainText("Booking canceled.");
      expect(dialogs.at(-1)).toContain("Cancel Ken Whitfield's booking");
      await expect(page.locator(`[data-ct-row="booking:${id}"]`)).toHaveCount(0);
      const [after] = await db.get(`court_bookings?id=eq.${id}&select=status,canceled_by`);
      expect(after.status).toBe("canceled");
    } finally {
      await db.del(`court_bookings?account_id=eq.${KEN_A}`);
    }
  });

  test("a block lists the booking under it, cancels nobody, and she cancels it herself", async ({ page, request }) => {
    const db = service(request);
    const dialogs = acceptDialogs(page);
    const booking = await db.insert("court_bookings", { court: 2, account_id: MARIA_A, starts_at: nyAt(10), ends_at: nyAt(11) });
    try {
      await openCourts(page);
      await page.getByRole("button", { name: "Block courts" }).click();
      const dlg = page.locator("#court-block");
      await dlg.getByLabel("Court").selectOption("");          // All courts
      await dlg.getByLabel("From").fill("09:30");
      await dlg.getByLabel("To").fill("11:00");
      await dlg.getByLabel("Reason").fill("Resurfacing");
      await dlg.getByRole("button", { name: "Block", exact: true }).click();

      await expect(page.locator("#court-block")).toContainText("Blocked. These bookings are under it.");
      await expect(page.locator("#court-block")).toContainText("Nobody was canceled.");
      const listed = page.locator(`[data-conflict="${booking.id}"]`);
      await expect(listed).toContainText("Maria Alvarez");
      await expect(listed).toContainText("Court 2");
      await expect(listed).toContainText("704-555-0101");
      expect((await db.get(`court_bookings?id=eq.${booking.id}&select=status`))[0].status).toBe("booked");

      // The day behind the dialog warns about it too.
      await expect(page.locator("#ct-warn")).toContainText("Maria Alvarez, Court 2");
      await expect(page.locator("#ct-warn")).toContainText("your block (Resurfacing)");

      await listed.getByRole("button", { name: "Cancel booking" }).click();
      await expect(listed).toContainText("Canceled");
      expect(dialogs.at(-1)).toContain("Cancel Maria Alvarez's booking");
      expect((await db.get(`court_bookings?id=eq.${booking.id}&select=status`))[0].status).toBe("canceled");
      await dlg.getByRole("button", { name: "Close" }).click();
      await expect(page.locator("#ct-warn")).toBeHidden();

      const [block] = await db.get(`court_blocks?reason=eq.Resurfacing&select=id,court,removed_at`);
      expect(block.court).toBeNull();
      const blockRow = page.locator(`[data-ct-row="block:${block.id}"]`);
      await expect(blockRow).toContainText("Courts 1, 2, 3, 4, 5");
      await blockRow.getByRole("button", { name: "Remove block" }).click();
      await expect(page.locator("#ct-msg")).toContainText("Block removed.");
      await expect(blockRow).toHaveCount(0);
      expect((await db.get(`court_blocks?id=eq.${block.id}&select=removed_at`))[0].removed_at).not.toBeNull();
    } finally {
      await db.del(`court_blocks?reason=eq.Resurfacing`);
      await db.del(`court_bookings?id=eq.${booking.id}`);
    }
  });

  test("warns when a clinic is published over a booking", async ({ page, request }) => {
    const db = service(request);
    const booking = await db.insert("court_bookings", { court: 1, account_id: KEN_A, starts_at: nyAt(18), ends_at: nyAt(19) });
    // Twenty spots hold all five courts, so court 1 is under it.
    const at = new Date(nyAt(18)).getTime();
    const clinic = await db.insert("clinics", {
      name: "Browser Court Clinic", audience: "coed", category: "Clinic", description: "browser test",
      starts_at: nyAt(18), ends_at: nyAt(19),
      member_opens_at: new Date(at - 9 * DAY).toISOString(), public_opens_at: new Date(at - 8 * DAY).toISOString(),
      internal_capacity: 20, status: "published", duration_minutes: 60,
    });
    try {
      await openCourts(page);
      await expect(page.locator("#ct-warn")).toContainText("Ken Whitfield, Court 1");
      await expect(page.locator("#ct-warn")).toContainText("overlaps the clinic Browser Court Clinic");
      await expect(page.locator(`#ct-grid [data-ct-item="booking:${booking.id}"]`)).toHaveClass(/clash/);
      await expect(page.locator(`[data-ct-row="clinic:${clinic.id}"]`)).toContainText("Courts 1, 2, 3, 4, 5");
      if (process.env.COURTS_SHOT) await page.locator("#tab-courts").screenshot({ path: process.env.COURTS_SHOT });
    } finally {
      await db.del(`clinics?id=eq.${clinic.id}`);
      await db.del(`court_bookings?id=eq.${booking.id}`);
    }
  });

  // The members switch is locked (John, 2026-11-16: TestFlight testers
  // only until he is sure): words, not a control, and never sent.
  test("court rules: the members switch is locked; a bad value is refused, then the rules and an hour save", async ({ page, request }) => {
    const db = service(request);
    const before = await db.get(`app_settings?key=like.court*&select=key,value`);
    try {
      await openCourts(page);
      await page.getByRole("button", { name: "Court rules" }).click();
      await expect(page.locator("#rs-live")).toContainText("Off for members. Court booking is in testing with the testers below.");
      await expect(page.locator("#court-rules input#rs-live, #court-rules [role=switch]")).toHaveCount(0);
      await expect(page.getByLabel("Lengths (minutes, comma between)")).toHaveValue("60,90");
      await expect(page.locator("#rs-open-1")).toHaveValue("07:00");

      await page.getByLabel("Lengths (minutes, comma between)").fill("sixty");
      await page.getByRole("button", { name: "Save" }).click();
      await expect(page.locator("#rs-msg")).toContainText("One of the rules isn't valid.");
      expect((await db.get(`app_settings?key=eq.court_lengths&select=value`))[0].value).toBe("60,90");

      await page.getByLabel("Lengths (minutes, comma between)").fill("60, 90");
      await page.getByLabel("Upcoming at once, per person").fill("3");
      await page.getByLabel("Monday opens").fill("08:00");
      await page.getByRole("button", { name: "Save" }).click();
      await expect(page.locator("#ct-msg")).toContainText("Court rules saved.");
      await expect(page.locator("#ct-live")).toContainText("Off for members.");

      const after = Object.fromEntries((await db.get(`app_settings?key=like.court*&select=key,value`)).map(r => [r.key, r.value]));
      expect(after).toMatchObject({ courts_live: "false", court_max_upcoming: "3", court_lengths: "60,90" });
      const [monday] = await db.get(`court_hours?weekday=eq.1&select=opens,closes`);
      expect(monday).toEqual({ opens: "08:00:00", closes: "21:00:00" });
    } finally {
      await db.patch(`court_hours?weekday=eq.1`, { opens: "07:00", closes: "21:00" });
      for (const r of before) await db.patch(`app_settings?key=eq.${r.key}`, { value: r.value });
    }
  });

  // John, 2026-11-16: court booking only in TestFlight until he is sure.
  // Tara picks the testers; each add or remove is saved at once.
  test("testers: add a member, see them listed, take them off (kept as removed)", async ({ page, request }) => {
    const db = service(request);
    try {
      await openCourts(page);
      await page.getByRole("button", { name: "Court rules" }).click();
      const dlg = page.locator("#court-rules");
      await expect(dlg.getByText("Can book while courts are off (TestFlight)")).toBeVisible();
      await expect(dlg.locator("#rs-testers")).toContainText("No testers yet.");
      await dlg.getByLabel("Add a tester").fill("Whitf");
      await dlg.getByRole("button", { name: "Add Ken Whitfield as a tester" }).click();
      await expect(dlg.locator(`[data-tester="${KEN_A}"]`)).toContainText("Ken Whitfield");
      let rows = await db.get(`court_testers?account_id=eq.${KEN_A}&select=removed_at,added_by`);
      expect(rows).toEqual([{ removed_at: null, added_by: "11111111-1111-1111-1111-111111111111" }]);

      // A reopened dialog reads the list again from the server.
      await dlg.getByRole("button", { name: "Cancel" }).click();
      await page.getByRole("button", { name: "Court rules" }).click();
      await expect(dlg.locator(`[data-tester="${KEN_A}"]`)).toContainText("Ken Whitfield");

      await dlg.getByRole("button", { name: "Remove Ken Whitfield as a tester" }).click();
      await expect(dlg.locator("#rs-testers")).toContainText("No testers yet.");
      rows = await db.get(`court_testers?account_id=eq.${KEN_A}&select=removed_at`);
      expect(rows).toHaveLength(1);
      expect(rows[0].removed_at).not.toBeNull();
    } finally {
      await db.del(`court_testers?account_id=eq.${KEN_A}`);
    }
  });
});
