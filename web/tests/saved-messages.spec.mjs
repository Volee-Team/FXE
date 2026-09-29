// Tara's saved messages in the Message dialog (decision 0030), walked the way
// she uses them: type a message, save it, come back another day (a reload),
// choose it, and it fills the box; Remove takes it off the list and the row
// stays in the database, archived (hard rule 4).
//
// Its own file, not admin.spec.mjs, so that parallel branches appending tests
// to that file do not collide with this one. Writes rows through the page and
// deletes them at the end through the REST API as service_role (a test
// fixture, never Tara's data), so a rerun starts from the same empty list.
import { test, expect } from "@playwright/test";
import { execSync } from "node:child_process";

const TARA = { email: "tara@fxe.test", password: "password" };

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
  const headers = { apikey: env.SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SERVICE_ROLE_KEY}` };
  const go = async (method, path) => {
    const res = await request.fetch(`${env.API_URL}/rest/v1/${path}`, { method, headers });
    if (!res.ok()) throw new Error(`${method} ${path}: ${res.status()} ${await res.text()}`);
    return res.status() === 204 ? null : res.json();
  };
  return { get: (path) => go("GET", path), del: (path) => go("DELETE", path) };
}

async function openMessage(page) {
  const card = page.locator("#clinics .card", { hasText: "Thursday Morning Cardio" });
  await card.getByRole("button", { name: "Message" }).click();
  const dialog = page.locator("dialog#message");
  await expect(dialog).toBeVisible();
  return dialog;
}

test.describe("saved messages", () => {
  test("save one, reload, choose it and it fills the box; Remove takes it off the list", async ({ page, request }) => {
    const db = service(request);
    // Unique per run; a probe-style fixture, not copy anyone reads.
    const text = `Playwright saved message ${Date.now()}`;
    const enc = encodeURIComponent(text);
    try {
      await signIn(page, TARA);
      let dialog = await openMessage(page);
      const saved = dialog.getByRole("group", { name: "Saved" });
      const box = dialog.getByLabel("Message", { exact: true });
      const saveBtn = dialog.getByRole("button", { name: "Save this message" });

      // Nothing to save in an empty box.
      await expect(saveBtn).toBeDisabled();
      await box.fill(`  ${text}  `);
      await saveBtn.click();
      await expect(saved.getByRole("button", { name: text, exact: true })).toBeVisible();

      // The same text again is kept once.
      await saveBtn.click();
      await expect(saved.getByRole("button", { name: text, exact: true })).toHaveCount(1);

      // Another day: the database has it, not the page.
      await page.reload();
      dialog = await openMessage(page);
      await expect(dialog.getByLabel("Message", { exact: true })).toHaveValue("");
      const choice = dialog.getByRole("group", { name: "Saved" }).getByRole("button", { name: text, exact: true });
      await expect(choice).toBeVisible();
      await choice.click();
      await expect(dialog.getByLabel("Message", { exact: true })).toHaveValue(text);
      // Choosing only fills the box: sending is still hers to do.
      await expect(dialog).toBeVisible();

      // Remove: off the list, and archived, not deleted.
      const row = dialog.locator(".saved-row", { hasText: text });
      await row.getByRole("button", { name: "Remove" }).click();
      await expect(dialog.getByRole("group", { name: "Saved" }).getByRole("button", { name: text, exact: true })).toHaveCount(0);
      const rows = await db.get(`message_templates?body=eq.${enc}&select=archived_at`);
      expect(rows).toHaveLength(1);
      expect(rows[0].archived_at).not.toBeNull();
    } finally {
      await db.del(`message_templates?body=eq.${enc}`);
    }
  });

  test("with nothing saved the list says so", async ({ page, request }) => {
    const db = service(request);
    const live = await db.get("message_templates?archived_at=is.null&select=id");
    test.skip(live.length > 0, "live saved messages exist on this database; reset to see the empty state");
    await signIn(page, TARA);
    const dialog = await openMessage(page);
    await expect(dialog.getByRole("group", { name: "Saved" })).toContainText("No saved messages yet.");
  });
});
