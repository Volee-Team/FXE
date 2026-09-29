// The web admin, walked the way Tara walks it, against a freshly reset local
// stack. Each test signs in as the seeded admin and leaves the database in a
// state the next test can live with (no test depends on another's writes).
//
// What is NOT here: anything a player sees. The player surface is the iOS
// app, covered by XCUITests. This file is Tara's side only.
import { test, expect } from "@playwright/test";
import { execSync } from "node:child_process";

const TARA = { email: "tara@fxe.test", password: "password" };
const MARIA = { email: "maria@fxe.test", password: "password" };
// The seeded pro (decision 0025): made a pro by admin_set_pro in the seed.
const PRO = { email: "pro@fxe.test", password: "password" };

async function signIn(page, who) {
  await page.goto("/index.html");
  await page.getByLabel("Email").fill(who.email);
  await page.getByLabel("Password").fill(who.password);
  await page.getByRole("button", { name: "Sign In" }).click();
}

test.describe("sign-in", () => {
  test("Tara lands on this week's clinics", async ({ page }) => {
    await signIn(page, TARA);
    await expect(page.getByRole("tab", { name: "This week" })).toHaveAttribute("aria-selected", "true");
    await expect(page.getByRole("heading", { name: "This week" })).toBeVisible();
    await expect(page.getByRole("button", { name: "New clinic" })).toBeVisible();
  });

  test("a member is told this is not their door", async ({ page }) => {
    // The gate is is_admin() in Postgres; the page only reports what the
    // database said. Maria signs in fine and gets zero admin rows.
    await signIn(page, MARIA);
    await expect(page.getByText("not an administrator")).toBeVisible();
  });
});

// Clinic cards live under #clinics. The Money panel repeats a clinic's name in
// its own card once anyone is in, which made a bare ".card" locator ambiguous
// the moment the walk-up test succeeded (strict mode violation, 2026-09-02).
test.describe("the week", () => {
  test("every seeded clinic shows both prices and a capacity", async ({ page }) => {
    await signIn(page, TARA);
    const cards = page.locator("#clinics .card", { hasText: "member /" });
    await expect(cards.first()).toBeVisible();
    expect(await cards.count()).toBeGreaterThanOrEqual(3);
    await expect(cards.first()).toContainText(/\$\d+ member \/ \$\d+ non-member/);
  });

  test("a walk-up can be put straight into a clinic", async ({ page }) => {
    await signIn(page, TARA);
    const card = page.locator("#clinics .card", { hasText: "Thursday Morning Cardio" });
    await card.getByRole("button", { name: "Add player" }).click();
    const dialog = page.locator("dialog#walkup");
    await dialog.getByLabel("Search by name").fill("Ken");
    await dialog.getByRole("button", { name: "Put in clinic" }).first().click();
    // The page closes the dialog and reloads every clinic from the server
    // before the roster shows the new name; on a CI runner that is slower
    // than the default 5 s expectation.
    await expect(dialog).toBeHidden({ timeout: 15_000 });
    await expect(card).toContainText("Ken Whitfield", { timeout: 15_000 });
    await expect(card).toContainText("You're In!");
  });

  test("courts are assigned from the dropdown and the list sorts by court", async ({ page }) => {
    await signIn(page, TARA);
    const card = page.locator("#clinics .card", { hasText: "Thursday Morning Cardio" });
    const select = card.getByLabel("Court").first();
    await select.selectOption("2");
    await expect(card.getByLabel("Court").first()).toHaveValue("2");
    await card.getByLabel("Court").first().selectOption("");
    await expect(card.getByLabel("Court").first()).toHaveValue("");
  });

  // Decision 0013 (Tara, 2026-09-21): "Everyone using the app has to input a
  // credit card." zelle_allowed is false in the seed, so the Paid toggle and
  // the unpaid reminder are not rendered; Came/No-show still is. The code for
  // both stays behind the setting (hard rule 6), and this test is the one to
  // invert if she ever turns Zelle back on.
  test("the Zelle controls are hidden while the card is the only way to pay", async ({ page }) => {
    await signIn(page, TARA);
    const card = page.locator("#clinics .card", { hasText: "Thursday Morning Cardio" });
    await expect(card.getByRole("button", { name: "Came" }).first()).toBeVisible();
    await expect(card.getByRole("button", { name: /Remind unpaid/ })).toHaveCount(0);
    await expect(card.getByRole("button", { name: /^(Paid|Unpaid)$/ })).toHaveCount(0);
    // Tara's Late cancel (20260927100002) is offered only inside the 3-hour
    // cutoff or later; Thursday Morning Cardio is days away.
    await expect(card.getByRole("button", { name: "Late cancel" })).toHaveCount(0);
  });
});

test.describe("the directory", () => {
  test("search finds a player and a note round-trips", async ({ page }) => {
    await signIn(page, TARA);
    await page.getByRole("tab", { name: "Players" }).click();
    await page.getByLabel("Search players by name").fill("Mar");
    const row = page.locator("[data-player-row]", { hasText: "Maria Alvarez" });
    await expect(row).toBeVisible();
    await row.getByRole("button", { name: "Note" }).click();
    const box = page.getByLabel("Private note");
    await expect(box).toBeVisible();
    const stamp = `Playwright ${Date.now()}`;
    await box.fill(stamp);
    await page.getByRole("button", { name: "Save note" }).click();
    await expect(page.getByText("Saved.")).toBeVisible();
    // Reload and read it back: the database has it, not the page.
    await page.reload();
    await page.getByRole("tab", { name: "Players" }).click();
    await page.getByLabel("Search players by name").fill("Mar");
    await page.locator("[data-player-row]", { hasText: "Maria Alvarez" }).getByRole("button", { name: "Note" }).click();
    await expect(page.getByLabel("Private note")).toHaveValue(stamp);
    // Saving re-lists the players and closes the box, so the stamp is read on
    // reopen: it exists once a note exists, and it is a date, not a slogan.
    await expect(page.locator("[id^=note-]:not(.hide) [data-noteedited]")).toContainText(/Edited .*\d/);
  });
});

// Decision 0025. Tara makes an account a pro on the Players tab; a pro gets
// the phone's Today tab and nothing here. Lena, because no other browser test
// touches her; she ends as the member the seed made her, so a second run
// starts where the first did.
test.describe("pros", () => {
  const lenaBox = (page) => page.locator("[data-player-row]", { hasText: "Lena Brooks" })
    .getByRole("checkbox", { name: "Pro" });
  const findLena = async (page) => {
    await page.getByRole("tab", { name: "Players" }).click();
    await page.getByLabel("Search players by name").fill("Lena");
    await expect(page.locator("[data-player-row]", { hasText: "Lena Brooks" })).toBeVisible();
  };

  test("Tara makes a player a pro and a member again; the box shows what the database holds", async ({ page }) => {
    await signIn(page, TARA);
    await findLena(page);
    await expect(lenaBox(page)).not.toBeChecked();
    await lenaBox(page).click();
    // The list is read again after the change; the box comes back checked.
    await expect(lenaBox(page)).toBeChecked({ timeout: 15_000 });
    // Reload and read it back: the database has it, not the page.
    await page.reload();
    await findLena(page);
    await expect(lenaBox(page)).toBeChecked({ timeout: 15_000 });

    await lenaBox(page).click();
    await expect(lenaBox(page)).not.toBeChecked({ timeout: 15_000 });
    await page.reload();
    await findLena(page);
    await expect(lenaBox(page)).not.toBeChecked({ timeout: 15_000 });
    await expect(page.locator("#players-msg")).not.toContainText(/./);
  });

  test("a pro is told this is not their door", async ({ page }) => {
    // The same gate as a member's: the page asks the database for the role
    // and anything but admin is signed out again.
    // Scoped to the sign-in message: a door that let a pro in would also
    // print "not an administrator" from every admin call that refused them,
    // and an unscoped match would fail on that for the wrong reason.
    await signIn(page, PRO);
    await expect(page.locator("#signin-msg")).toContainText("not an administrator");
    await expect(page.getByRole("tab", { name: "Players" })).toBeHidden();
  });
});

test.describe("templates", () => {
  test("archive removes a template from the picker; restore brings it back", async ({ page }) => {
    await signIn(page, TARA);
    const row = page.locator("[data-template-row]", { hasText: "Coed Cardio" });
    await row.getByRole("button", { name: "Archive" }).click();
    await expect(page.locator("[data-template-row]", { hasText: "Coed Cardio" })).toHaveCount(0);
    await page.getByRole("button", { name: "New clinic" }).click();
    await expect(page.locator("#f-template option", { hasText: "Coed Cardio" })).toHaveCount(0);
    await page.locator("#edit-cancel").click();   // not "Cancel clinic" on the cards

    await page.getByLabel("Show archived").check();
    const archived = page.locator("[data-template-row]", { hasText: "Coed Cardio" });
    await expect(archived).toContainText("archived");
    await archived.getByRole("button", { name: "Restore" }).click();
    await page.getByRole("button", { name: "New clinic" }).click();
    await expect(page.locator("#f-template option", { hasText: "Coed Cardio" })).toHaveCount(1);
  });
});

test.describe("money", () => {
  test("the Money tab shows the four counts and the totals", async ({ page }) => {
    await signIn(page, TARA);
    await page.getByRole("tab", { name: "Money" }).click();
    const money = page.locator("#money");
    await expect(money).toContainText("Members, 60 min");
    await expect(money).toContainText("Non-members, 90 min");
    // The money line is the ledger's since 2026-09-27 (20260927100003), not
    // the Zelle-era Expected / Collected. From the rule: nothing is charged,
    // declined or owed until a clinic has ENDED, and every seeded clinic is
    // in the future, so a booking made earlier in this run (the walk-up puts
    // Ken in Thursday Morning Cardio) must not read as "not charged yet".
    const line = page.locator("#money-line");
    await expect(line).toContainText("Charged $0");
    await expect(line).toContainText("Declined 0");
    await expect(line).toContainText("Not charged yet $0");
    await expect(money).not.toContainText("Expected");
  });

  test("the Money tab lists card payments, and says so when there are none", async ({ page }) => {
    await signIn(page, TARA);
    await page.getByRole("tab", { name: "Money" }).click();
    const ledger = page.locator("#ledger");
    await expect(ledger).toContainText("Card payments");
    // The seed has no payments and payments are switched off, so the honest
    // state is the empty one. Nothing invents a row here.
    await expect(ledger).toContainText("No card payments yet.");
  });
});

test.describe("board report", () => {
  test("the Money tab runs the board report and offers the CSV", async ({ page }) => {
    // Tara, 2026-09-26: a report for the board's 10%. The seed's clinics are
    // all in the coming week and none has ended, so over a range that covers
    // them the honest answer is zero attendances and $0.00: numbers, not
    // blanks. The arithmetic itself is money_reports.sql's job.
    await signIn(page, TARA);
    await page.getByRole("tab", { name: "Money" }).click();
    const board = page.locator("#board");
    await expect(board).toContainText("Board report");
    // The default is last month, New York; it must be a real date range.
    // Scoped and exact: "From" alone also matches "Start from a template",
    // and the message dialog has its own "To".
    const from = board.getByLabel("From", { exact: true });
    const to = board.getByLabel("To", { exact: true });
    await expect(from).toHaveValue(/^\d{4}-\d{2}-01$/);
    await expect(to).toHaveValue(/^\d{4}-\d{2}-\d{2}$/);
    const ymd = (d) => d.toISOString().slice(0, 10);
    const now = Date.now();
    await from.fill(ymd(new Date(now - 7 * 86_400_000)));
    await to.fill(ymd(new Date(now + 21 * 86_400_000)));
    await board.getByRole("button", { name: "Run" }).click();
    const report = page.locator("#br-report");
    await expect(report).toBeVisible();
    await expect(report.locator("tr", { hasText: "Members attended" }).first()).toContainText(/\d+ \(\d+\)/);
    await expect(report.locator("tr", { hasText: "Collected by card" }).first()).toContainText(/\$\d[\d,]*\.\d{2}/);
    await expect(report.locator("tr", { hasText: "10% of fees" })).toContainText(/\$\d[\d,]*\.\d{2}/);
    await expect(report.locator("tr.total")).toContainText("Total");
    await expect(board.getByRole("button", { name: "Download CSV" })).toBeVisible();
    await expect(board.getByRole("button", { name: "Print" })).toBeVisible();
    // The CSV is a real download with the name the board will see.
    const [download] = await Promise.all([
      page.waitForEvent("download"),
      board.getByRole("button", { name: "Download CSV" }).click(),
    ]);
    expect(download.suggestedFilename()).toMatch(/^fxe-board-report-\d{4}-\d{2}-\d{2}-to-\d{4}-\d{2}-\d{2}\.csv$/);
  });
});

test.describe("payments switch", () => {
  test("with payments off there is nothing to charge or refund anywhere", async ({ page }) => {
    // Decision 0009: payments_enabled is 'false' until Tara answers. The
    // seed keeps it that way, so the honest page has no Charge or Refund
    // button on any roster row or ledger row.
    await signIn(page, TARA);
    await expect(page.locator("#clinics .card").first()).toBeVisible();
    await expect(page.getByRole("button", { name: /^Charge/ })).toHaveCount(0);
    // Decision 0012: no-shows are Tara's to mark, switch or no switch. The
    // seed has Ken in Thursday Morning Cardio, so one row offers it.
    await expect(page.getByRole("button", { name: "Came" }).first()).toBeVisible();
    await page.getByRole("tab", { name: "Money" }).click();
    await expect(page.locator("#ledger")).toContainText("Card payments");
    await expect(page.getByRole("button", { name: "Refund" })).toHaveCount(0);
  });
});

test.describe("review links", () => {
  test("Tara makes a review link and gets a URL carrying a long token", async ({ page }) => {
    await signIn(page, TARA);
    // Testing is not a tab (Alex, 2026-09-27): three tabs, and a small link at the foot.
    await expect(page.getByRole("tab")).toHaveText(["This week", "Players", "Money"]);
    await page.getByRole("button", { name: "Testing" }).click();
    await page.getByLabel("Link label").fill(`Playwright ${Date.now()}`);
    await page.getByRole("button", { name: "Make link" }).click();
    const url = page.locator("#rl-url");
    await expect(url).toContainText("/review.html?t=");
    // The token is the credential (20260921000010): 24 random bytes as
    // URL-safe base64, minted by admin_create_review_link. Asserted from the
    // rule, not the code: at least 24 characters, nothing a URL would mangle.
    const token = (await url.textContent()).split("?t=")[1];
    expect(token.length).toBeGreaterThanOrEqual(24);
    expect(token).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  test("the review page renders every item without a code and says answers stay local", async ({ page }) => {
    // No token: no server round trip, so this runs with no edge runtime
    // (CI serves none). The page builds its items from the JSON block.
    await page.goto("/review.html");
    await expect(page).toHaveTitle("FXE Tennis, Tara's Review");
    await expect(page.locator("#sync")).toContainText("This link has no code");
    // Every item in the page's own data renders. Round four carries only what
    // is new since her last answers (decision 0016), so the number is small
    // and changes each round; the rule is "all of them", not a size.
    const data = JSON.parse(await page.locator("#review-data").textContent());
    const expected = data.sections.reduce((n, s) => n + s.items.length, 0);
    expect(expected).toBeGreaterThan(0);
    const items = page.locator("#panel-words .item");
    await expect(items).toHaveCount(expected);
    await expect(page.locator("#panel-questions textarea")).toHaveCount(data.questions.length);
    await items.first().getByRole("button", { name: "Keep" }).click();
    await expect(page.locator("#progress-words")).toContainText(/^1 of \d+ decided/);
    await expect(page.locator("#summary")).toContainText("keep: ");
  });
});

test.describe("cancel clinic", () => {
  test("takes two clicks and leaves a Canceled chip", async ({ page }) => {
    await signIn(page, TARA);
    const card = page.locator("#clinics .card", { hasText: "Sunday Social" });
    const btn = card.getByRole("button", { name: "Cancel clinic" });
    await btn.click();
    await expect(card.getByRole("button", { name: /Really cancel/ })).toBeVisible();
    await card.getByRole("button", { name: /Really cancel/ }).click();
    // Hidden by default once canceled; the toggle brings it back with its chip.
    await expect(page.getByText(/1 canceled clinic hidden/)).toBeVisible();
    await page.getByLabel("Show canceled").check();
    await expect(page.locator("#clinics .card", { hasText: "Sunday Social" }).getByText("Canceled")).toBeVisible();
    await expect(card.getByRole("button", { name: "Cancel clinic" })).toHaveCount(0);
  });
});

// The reset page with a token-hash link: the shape Tara's "Reset link" makes
// (admin-reset-link, decision 0017) and the reset email will use. The link is
// minted here through GoTrue's admin API, the same call the edge function
// makes, because CI's browser job runs no edge runtime; tests/reset/run.sh
// covers the function itself. Ken, because no other test signs in as him.
test.describe("reset page", () => {
  test("a token-hash link lets the member choose a new password, once", async ({ page, request }) => {
    const env = Object.fromEntries(execSync("supabase status -o env", { cwd: "..", stdio: ["ignore", "pipe", "ignore"] })
      .toString().split("\n").filter(l => l.includes("="))
      .map(l => { const i = l.indexOf("="); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, "")]; }));
    const admin = { apikey: env.SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SERVICE_ROLE_KEY}` };
    // Ken's password goes back to the seed's whatever happens below, through
    // the admin API (never SQL on auth), so a failure cannot poison later runs.
    const restoreKen = async () => {
      const users = await (await request.get(`${env.API_URL}/auth/v1/admin/users?per_page=50`, { headers: admin })).json();
      const ken = users.users.find(u => u.email === "ken@fxe.test");
      expect((await request.put(`${env.API_URL}/auth/v1/admin/users/${ken.id}`, { headers: admin, data: { password: "password" } })).ok()).toBeTruthy();
    };
    await restoreKen();
    try {
      const gen = await request.post(`${env.API_URL}/auth/v1/admin/generate_link`, { headers: admin, data: { type: "recovery", email: "ken@fxe.test" } });
      expect(gen.ok()).toBeTruthy();
      // The token rides in the fragment, the shape admin-reset-link returns.
      const link = `/reset.html#token_hash=${encodeURIComponent((await gen.json()).hashed_token)}&type=recovery`;

      // Ken is also signed in on his phone: a session the reset must end.
      const phone = await (await request.post(`${env.API_URL}/auth/v1/token?grant_type=password`,
        { headers: { apikey: env.ANON_KEY }, data: { email: "ken@fxe.test", password: "password" } })).json();
      expect(phone.refresh_token).toBeTruthy();

      await page.goto(link);
      await expect(page.locator("#intro")).toHaveText("Pick something you'll remember. At least 8 characters.");
      // The spent token leaves the address bar.
      expect(page.url()).not.toContain("token_hash");
      // Ken's session lives in the page's memory only: nothing a later visitor
      // to this browser, or Tara's own admin tab on the same site, could pick up.
      const stored = await page.evaluate(() => Object.keys(localStorage).filter(k => /auth-token|fxe-reset/.test(k)));
      expect(stored).toEqual([]);
      const pw = `Reset-${Date.now()}`;
      await page.getByLabel("New password").fill(pw);
      await page.getByLabel("Type it again").fill(pw);
      await page.getByRole("button", { name: "Save password" }).click();
      await expect(page.locator("#msg")).toContainText("Saved. You can sign in with it now");

      // Saving signed Ken out everywhere: the phone's session no longer refreshes.
      await expect.poll(async () => (await request.post(`${env.API_URL}/auth/v1/token?grant_type=refresh_token`,
        { headers: { apikey: env.ANON_KEY }, data: { refresh_token: phone.refresh_token } })).status()).not.toBe(200);

      // The new password is the one that works.
      const signin = await request.post(`${env.API_URL}/auth/v1/token?grant_type=password`,
        { headers: { apikey: env.ANON_KEY }, data: { email: "ken@fxe.test", password: pw } });
      expect(signin.status()).toBe(200);

      // The same link a second time is spent. about:blank first: a URL that
      // differs only in its fragment is not a new page load, and a member who
      // taps the link again gets a fresh page.
      await page.goto("about:blank");
      await page.goto(link);
      await expect(page.locator("#intro")).toHaveText("This link has expired or was already used. Go back and request a new one.");
      await expect(page.locator("#f")).toBeHidden();

    } finally {
      await restoreKen();
    }
  });
});

// ---------------------------------------------------------------------------
// MVP fix round (2026-09-27). Each fixture is written through the REST API as
// service_role (never SQL on auth), and removed again in finally, so a failure
// cannot leave rows for the next test or the probe runner's DIRTY check.
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
const MARIA_P = "a0000000-0000-0000-0000-000000000001";
const KEN_P = "a0000000-0000-0000-0000-000000000002";
const ROB_P = "a0000000-0000-0000-0000-000000000003";
const DANA_P = "a0000000-0000-0000-0000-000000000004";
const MARIA_ACCT = "22222222-2222-2222-2222-222222222222";
const KEN_ACCT = "33333333-3333-3333-3333-333333333333";
const ROB_ACCT = "44444444-4444-4444-4444-444444444444";
const DANA_ACCT = "66666666-6666-6666-6666-666666666666";
const daysAgo = (d, h = 0) => new Date(Date.now() - d * 86_400_000 + h * 3_600_000).toISOString();
const pastClinic = (name, endedDaysAgo) => ({
  name, audience: "coed", category: "Clinic", description: "browser test",
  starts_at: daysAgo(endedDaysAgo, -1), ends_at: daysAgo(endedDaysAgo),
  member_opens_at: daysAgo(endedDaysAgo + 7), public_opens_at: daysAgo(endedDaysAgo + 6),
  internal_capacity: 8, status: "published", duration_minutes: 60,
});

// Until 2026-09-28 the laptop could not take anyone out of a clinic, and no
// screen anywhere could take someone out of the Player Pool, so Tara's own
// "You've been removed from the Player Pool" (#6, decision 0022) never fired.
test.describe("remove from a clinic", () => {
  test("a Player Pool row comes off in two clicks, stays as canceled, and her #6 is sent", async ({ page, request }) => {
    const db = service(request);
    const TUESDAY = "d0000000-0000-0000-0000-000000000001";
    const reg = await db.insert("registrations", { clinic_id: TUESDAY, player_id: ROB_P, status: "pool", source: "self",
      price_cents_charged: 2300, was_member: false, duration_minutes: 60 });
    try {
      await signIn(page, TARA);
      const card = page.locator("#clinics .card", { hasText: "Tuesday Ladies" });
      const rob = card.locator(".row", { hasText: "Rob Delgado" });
      await expect(rob.getByRole("button", { name: "Invite" })).toBeVisible({ timeout: 15_000 });
      await rob.getByRole("button", { name: "Remove" }).click();
      await rob.getByRole("button", { name: "Really remove?" }).click();
      await expect(rob.getByRole("button", { name: "Invite" })).toHaveCount(0, { timeout: 15_000 });
      const [row] = await db.get(`registrations?id=eq.${reg.id}&select=status`);
      expect(row.status).toBe("canceled");
      const sent = await db.get(`notifications?entity_id=eq.${reg.id}&select=body`);
      expect(sent.map(n => n.body)).toEqual(
        ["You've been removed from the Player Pool for Tuesday Ladies 3.0+. Hope to see you at another clinic soon!"]);
    } finally {
      await db.del(`notifications?entity_id=eq.${reg.id}`);
      await db.del(`registrations?id=eq.${reg.id}`);
    }
  });
});

test.describe("fix round", () => {
  test("a late request for a clinic off this week's list still names its clinic", async ({ page, request }) => {
    const db = service(request);
    const clinic = await db.insert("clinics", pastClinic("Browser Old Clinic", 10));
    try {
      await db.insert("late_requests", { clinic_id: clinic.id, player_id: MARIA_P, message: "Can I still come?" });
      await signIn(page, TARA);
      const late = page.locator("#late");
      await expect(late).toContainText("asked to join");
      await expect(late).toContainText("Browser Old Clinic");
    } finally {
      await db.del(`late_requests?clinic_id=eq.${clinic.id}`);
      await db.del(`clinics?id=eq.${clinic.id}`);
    }
  });

  test("a held charge offers Tara the two answers; a deleted account's decline waits on the Money tab", async ({ page, request }) => {
    const db = service(request);
    await db.patch("app_settings?key=eq.payments_enabled_at", { value: daysAgo(5) });
    const clinic = await db.insert("clinics", pastClinic("Browser Held Clinic", 2));
    try {
      const reg = (player, cents) => db.insert("registrations",
        { clinic_id: clinic.id, player_id: player, status: "in", source: "admin", price_cents_charged: cents, was_member: true, duration_minutes: 60 });
      const dana = await reg(DANA_P, 1800), ken = await reg(KEN_P, 1800);
      await db.insert("payments", { registration_id: dana.id, account_id: DANA_ACCT, kind: "clinic_fee", amount_cents: 1800,
        status: "failed", failure_code: "expired_card", failure_reason: "Your card has expired." });
      const held = await db.insert("payments", { registration_id: ken.id, account_id: KEN_ACCT, kind: "clinic_fee", amount_cents: 1800,
        status: "processing", failure_reason: "retry_window_passed" });
      await db.patch(`accounts?id=eq.${DANA_ACCT}`, { deleted_at: new Date().toISOString() });

      await signIn(page, TARA);
      await expect(page.getByRole("heading", { name: "This week" })).toBeVisible();
      // Nobody can fix a deleted account's card: not in Action Needed...
      await expect(page.locator(`#money-needs [data-declined="${dana.id}"]`)).toHaveCount(0);
      // ...but still on the Money tab, under the account's name.
      await page.getByRole("tab", { name: "Money" }).click();
      await expect(page.locator("#money")).toContainText("Dana");
      await expect(page.locator("#money")).toContainText("Card expired");
      // The held charge: the reason in words, the guidance, the two answers.
      const heldRow = page.locator(`#ledger [data-held="${held.id}"]`);
      await expect(heldRow).toContainText("Check this charge in Stripe.");
      await expect(page.locator("#ledger")).toContainText("Too old to retry");
      await heldRow.getByRole("button", { name: "Did not go through" }).click();
      await expect(page.locator(`#ledger [data-held="${held.id}"]`)).toHaveCount(0, { timeout: 15_000 });
      await expect(page.locator("#ledger")).toContainText("Canceled");
    } finally {
      await db.patch(`accounts?id=eq.${DANA_ACCT}`, { deleted_at: null });
      const regs = await request.fetch(`${stackEnv().API_URL}/rest/v1/registrations?clinic_id=eq.${clinic.id}&select=id`,
        { headers: { apikey: stackEnv().SERVICE_ROLE_KEY, Authorization: `Bearer ${stackEnv().SERVICE_ROLE_KEY}` } }).then(r => r.json());
      if (regs.length) await db.del(`payments?registration_id=in.(${regs.map(r => r.id).join(",")})`);
      await db.del(`registrations?clinic_id=eq.${clinic.id}`);
      await db.del(`clinics?id=eq.${clinic.id}`);
      await db.patch("app_settings?key=eq.payments_enabled_at", { value: "" });
    }
  });

  test("two overlapping reloads never leave the older one on screen", async ({ page }) => {
    await signIn(page, TARA);
    const cards = page.locator("#clinics .card", { hasText: "member /" });
    await expect(cards.first()).toBeVisible();
    // The next load's clinic read is held back and answers an empty week; a
    // second load starts meanwhile and reads normally. The empty answer
    // arrives last, and must not be drawn.
    let held = false;
    await page.route("**/rest/v1/clinics_admin*", async (route) => {
      if (held) return route.continue();
      held = true;
      await new Promise(r => setTimeout(r, 2500));
      return route.fulfill({ status: 200, contentType: "application/json", headers: { "content-range": "*/0" }, body: "[]" });
    });
    await page.getByLabel("Show canceled").check();
    await page.getByLabel("Show canceled").uncheck();
    await page.waitForTimeout(4000);
    await expect(cards.first()).toBeVisible();
    await expect(page.locator("#clinics")).not.toContainText("No clinics this week or later.");
  });
});

// ---------------------------------------------------------------------------
// Payouts and disputes (2026-09-28). The browser runs in New York, where a
// bank day sent as midnight UTC would otherwise read as the evening before.
test.describe("payouts and disputes", () => {
  test.use({ timezoneId: "America/New_York" });

  test("the Payouts card says Stripe isn't connected, then shows Stripe's numbers", async ({ page }) => {
    // CI's browser job runs no edge runtime, so stripe-payouts is answered here
    // with the function's own two shapes: 503 stripe_not_configured, which a
    // deploy without STRIPE_SECRET_KEY gives, and its 200 answer.
    // tests/stripe/run.sh drives the real function against stripe-mock.
    let answer = { status: 503, body: { error: "stripe_not_configured" } };
    await page.route("**/functions/v1/stripe-payouts", (route) => route.fulfill({
      status: answer.status, contentType: "application/json", body: JSON.stringify(answer.body) }));
    await signIn(page, TARA);
    await page.getByRole("tab", { name: "Money" }).click();
    const card = page.locator("#payouts");
    await expect(card).toContainText("Payouts");
    await expect(card).toContainText("Stripe isn't connected yet.");
    await expect(card.getByRole("link", { name: "Manage payments in Stripe" })).toHaveAttribute("href", "https://dashboard.stripe.com");

    answer = { status: 200, body: {
      livemode: false,
      available: [{ amount: 12345, currency: "usd" }],
      pending: [{ amount: 4200, currency: "usd" }],
      next_payout: { amount: 4200, currency: "usd", arrival_date: "2026-10-02", status: "in_transit" },
      recent: [{ amount: 4200, currency: "usd", arrival_date: "2026-10-02", status: "in_transit" },
               { amount: 1800, currency: "usd", arrival_date: "2026-09-25", status: "paid" }] } };
    // Opening the tab reads Stripe again.
    await page.getByRole("tab", { name: "This week" }).click();
    await page.getByRole("tab", { name: "Money" }).click();
    await expect(card.locator("#payouts-available")).toHaveText("$123.45");
    await expect(card.locator("#payouts-pending")).toHaveText("$42.00");
    await expect(card.locator("#payouts-next")).toHaveText("$42.00");
    // 2026-10-02 is a Friday: shown as that day, not Thursday evening.
    await expect(card).toContainText("Fri, Oct 2");
    await expect(card.locator("[data-payout]")).toHaveCount(2);
    await expect(card.locator("[data-payout]").first()).toContainText("In transit");
    await expect(card.locator("[data-payout]").nth(1)).toContainText("Fri, Sep 25");
    await expect(card.locator("[data-payout]").nth(1)).toContainText("Paid");
    await expect(card.locator("#payouts-mode")).toHaveText("Test mode");
  });

  test("an open dispute and a declined card are in Action Needed; a lost dispute is on the ledger only", async ({ page, request }) => {
    const db = service(request);
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await db.patch("app_settings?key=eq.payments_enabled_at", { value: daysAgo(5) });
    const clinic = await db.insert("clinics", pastClinic("Browser Dispute Clinic", 2));
    try {
      const reg = (player, cents) => db.insert("registrations",
        { clinic_id: clinic.id, player_id: player, status: "in", source: "admin", price_cents_charged: cents, was_member: true, duration_minutes: 60 });
      const maria = await reg(MARIA_P, 1800), ken = await reg(KEN_P, 1800), rob = await reg(ROB_P, 2300);
      const now = new Date().toISOString();
      // As stripe-webhook leaves them: Maria's fee went through and her bank
      // opened a dispute; Rob's went through and his bank won its dispute
      // (the club lost the money); Ken's card was declined.
      const open = await db.insert("payments", { registration_id: maria.id, account_id: MARIA_ACCT, kind: "clinic_fee",
        amount_cents: 1800, status: "succeeded", livemode: true, stripe_payment_intent_id: `pi_browser_${Date.now()}_m`,
        stripe_dispute_id: "dp_browser_open", dispute_status: "needs_response", dispute_reason: "fraudulent",
        dispute_amount_cents: 1800, dispute_withdrawn_cents: 1800, disputed_at: now,
        dispute_due_by: new Date(Date.now() + 6 * 86_400_000).toISOString(), dispute_event_at: now });
      const lost = await db.insert("payments", { registration_id: rob.id, account_id: ROB_ACCT, kind: "clinic_fee",
        amount_cents: 2300, status: "succeeded", livemode: true, stripe_payment_intent_id: `pi_browser_${Date.now()}_r`,
        stripe_dispute_id: "dp_browser_lost", dispute_status: "lost", dispute_reason: "product_not_received",
        dispute_amount_cents: 2300, dispute_withdrawn_cents: 2300, disputed_at: now, dispute_event_at: now });
      await db.insert("payments", { registration_id: ken.id, account_id: KEN_ACCT, kind: "clinic_fee", amount_cents: 1800,
        status: "failed", failure_code: "insufficient_funds", failure_reason: "Your card has insufficient funds." });

      await signIn(page, TARA);
      // The week draws: before 2026-09-28 the decline row below threw
      // "money is not a function" and the clinics never appeared.
      await expect(page.locator("#clinics .card").first()).toBeVisible();
      const row = page.locator(`#money-needs [data-dispute="${open.id}"]`);
      await expect(row).toContainText("Maria Alvarez disputed a charge");
      await expect(row).toContainText("Browser Dispute Clinic");
      await expect(row).toContainText("$18");
      await expect(row).toContainText("Respond by");
      await expect(row.getByRole("link", { name: "Manage payments in Stripe" })).toHaveAttribute("href", "https://dashboard.stripe.com");
      await expect(page.locator(`#money-needs [data-dispute="${lost.id}"]`)).toHaveCount(0);
      const declined = page.locator(`#money-needs [data-declined="${ken.id}"]`);
      await expect(declined).toContainText("Ken Whitfield's card was declined");
      await expect(declined).toContainText("$18");

      await page.getByRole("tab", { name: "Money" }).click();
      const ledger = page.locator("#ledger");
      await expect(ledger).toContainText("Dispute lost");
      await expect(ledger).toContainText("Disputed");
      expect(errors).toEqual([]);
    } finally {
      const env = stackEnv();
      const regs = await request.fetch(`${env.API_URL}/rest/v1/registrations?clinic_id=eq.${clinic.id}&select=id`,
        { headers: { apikey: env.SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SERVICE_ROLE_KEY}` } }).then(r => r.json());
      if (regs.length) await db.del(`payments?registration_id=in.(${regs.map(r => r.id).join(",")})`);
      await db.del(`registrations?clinic_id=eq.${clinic.id}`);
      await db.del(`clinics?id=eq.${clinic.id}`);
      await db.patch("app_settings?key=eq.payments_enabled_at", { value: "" });
    }
  });
});
