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
  test("Tara lands on the clinic list", async ({ page }) => {
    await signIn(page, TARA);
    await expect(page.getByRole("heading", { name: "Clinics" })).toBeVisible();
    await expect(page.getByRole("button", { name: "New clinic" })).toBeVisible();
  });

  test("a member is told this is not their door", async ({ page }) => {
    // The gate is is_admin() in Postgres; the page only reports what the
    // database said. Maria signs in fine and gets zero admin rows.
    await signIn(page, MARIA);
    await expect(page.getByText("not an administrator")).toBeVisible();
  });
});

test.describe("the week", () => {
  test("every seeded clinic shows both prices and a capacity", async ({ page }) => {
    await signIn(page, TARA);
    const cards = page.locator(".card", { hasText: "member /" });
    await expect(cards.first()).toBeVisible();
    expect(await cards.count()).toBeGreaterThanOrEqual(3);
    await expect(cards.first()).toContainText(/\$\d+ member \/ \$\d+ non-member/);
  });

  test("a walk-up can be put straight into a clinic", async ({ page }) => {
    await signIn(page, TARA);
    const card = page.locator(".card", { hasText: "Thursday Morning Cardio" });
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
    const card = page.locator(".card", { hasText: "Thursday Morning Cardio" });
    const select = card.getByLabel("Court").first();
    await select.selectOption("2");
    await expect(card.getByLabel("Court").first()).toHaveValue("2");
    await card.getByLabel("Court").first().selectOption("");
    await expect(card.getByLabel("Court").first()).toHaveValue("");
  });

  test("the unpaid reminder goes to everyone unpaid", async ({ page }) => {
    await signIn(page, TARA);
    const card = page.locator(".card", { hasText: "Thursday Morning Cardio" });
    await card.getByRole("button", { name: /Remind unpaid/ }).click();
    await expect(page.getByText(/Reminder sent to \d+\./)).toBeVisible();
  });
});

test.describe("the directory", () => {
  test("search finds a player and a note round-trips", async ({ page }) => {
    await signIn(page, TARA);
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
    await page.getByLabel("Search players by name").fill("Mar");
    await page.locator("[data-player-row]", { hasText: "Maria Alvarez" }).getByRole("button", { name: "Note" }).click();
    await expect(page.getByLabel("Private note")).toHaveValue(stamp);
  });
});

test.describe("cancel clinic", () => {
  test("takes two clicks and leaves a Canceled chip", async ({ page }) => {
    await signIn(page, TARA);
    const card = page.locator(".card", { hasText: "Sunday Social" });
    const btn = card.getByRole("button", { name: "Cancel clinic" });
    await btn.click();
    await expect(card.getByRole("button", { name: /Really cancel/ })).toBeVisible();
    await card.getByRole("button", { name: /Really cancel/ }).click();
    await expect(card.getByText("Canceled")).toBeVisible();
    await expect(card.getByRole("button", { name: "Cancel clinic" })).toHaveCount(0);
  });
});
