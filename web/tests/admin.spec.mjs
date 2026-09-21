// The web admin, walked the way Tara walks it, against a freshly reset local
// stack. Each test signs in as the seeded admin and leaves the database in a
// state the next test can live with (no test depends on another's writes).
//
// What is NOT here: anything a player sees. The player surface is the iOS
// app, covered by XCUITests. This file is Tara's side only.
import { test, expect } from "@playwright/test";

const TARA = { email: "tara@fxe.test", password: "password" };
const MARIA = { email: "maria@fxe.test", password: "password" };

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
    await expect(money).toContainText("Expected");
    await expect(money).toContainText("Still owed");
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
    await page.getByRole("tab", { name: "Players" }).click();
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
    const items = page.locator("#panel-words .item");
    expect(await items.count()).toBeGreaterThan(100);
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
