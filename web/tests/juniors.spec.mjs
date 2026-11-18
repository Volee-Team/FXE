// Juniors phase 1 (decision 0061) on both websites: a parent's children, the
// parent/guardian waiver per child, the programs and Elite approvals on the
// members' site, and Tara's Juniors tab, Action Needed card and Players tab
// on the laptop. Against a freshly reset local stack.
//
// The parent is the seeded member Dana (no browser test uses her otherwise).
// Children the tests need ready-made are inserted as service_role; children a
// parent adds are added through the page. Every test leaves Dana as the seed
// has her: no children, no approvals, no signatures, an adult account, and no
// junior waiver published (cleanUp). Expected values come from the rules
// (decision 0061 and the juniors migrations), not from reading play.js.
import { test, expect } from "@playwright/test";
import { execSync } from "node:child_process";

const PW = "password";
const DANA = { email: "dana@fxe.test", first: "Dana", last: "Okonkwo", account: "66666666-6666-6666-6666-666666666666" };
const MARIA = { email: "maria@fxe.test", first: "Maria" };
const TARA = { email: "tara@fxe.test" };
const WAIVER = "spec-junior-1";

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

// A child on Dana's account, made the way add_my_child would leave it.
async function childOfDana(db, first, dob = "2016-04-02") {
  await db.patch(`accounts?id=eq.${DANA.account}`, { account_type: "both" });
  return db.insert("players", { account_id: DANA.account, kind: "junior", first_name: first, last_name: DANA.last, date_of_birth: dob });
}
async function publishJuniorWaiver(db) {
  await db.insert("waivers", { version: WAIVER, kind: "junior", title: "Junior Waiver For Tests",
    organizer: "FXE Tennis", body: "1  First part\n\nMade by juniors.spec.mjs.\n\n2  Second part\n\nNothing here is real." });
  const had = await db.get("app_settings?key=eq.junior_waiver_version&select=key");
  if (had.length) await db.patch("app_settings?key=eq.junior_waiver_version", { value: WAIVER });
  else await db.insert("app_settings", { key: "junior_waiver_version", value: WAIVER });
}
async function program(db, name) {
  return (await db.get(`junior_programs?name=eq.${encodeURIComponent(name)}&select=*`))[0];
}
async function cleanUp(db) {
  const kids = await db.get(`players?account_id=eq.${DANA.account}&kind=eq.junior&select=id`);
  for (const k of kids) {
    await db.del(`program_approvals?player_id=eq.${k.id}`);
    await db.del(`junior_waiver_acceptances?player_id=eq.${k.id}`);
    await db.del(`player_notes?player_id=eq.${k.id}`);
    await db.del(`players?id=eq.${k.id}`);
  }
  await db.patch(`accounts?id=eq.${DANA.account}`, { account_type: "adult" });
  await db.del("app_settings?key=eq.junior_waiver_version");
  await db.del(`waivers?version=eq.${WAIVER}`);
}

async function signInPlay(page, who) {
  await page.goto("/play/");
  await page.getByLabel("Email").fill(who.email);
  await page.getByLabel("Password").fill(PW);
  await page.getByRole("button", { name: "Sign In" }).click();
  await expect(page.locator("h2.display")).toContainText(`, ${who.first}!`);
}
async function signInAdmin(page) {
  await page.goto("/index.html");
  await page.getByLabel("Email").fill(TARA.email);
  await page.getByLabel("Password").fill(PW);
  await page.getByRole("button", { name: "Sign In" }).click();
  await expect(page.getByRole("tab", { name: "This week" })).toBeVisible();
}

test.describe("a parent on the members' site", () => {
  test.beforeEach(async ({ request }) => cleanUp(service(request)));
  test.afterEach(async ({ request }) => cleanUp(service(request)));

  test("adds a child from Profile, sees the birthday and age, and edits the name", async ({ page, request }) => {
    const db = service(request);
    await signInPlay(page, DANA);
    await page.getByRole("link", { name: "Profile" }).click();
    await page.getByRole("link", { name: "My Children" }).click();
    await expect(page.getByText("No children added yet")).toBeVisible();
    await page.getByRole("link", { name: "Add a Child" }).click();

    // Nothing typed: the page says so and the server is never asked.
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page.locator("#c-error")).toHaveText("Add the child's first and last name.");
    expect(await db.get(`players?account_id=eq.${DANA.account}&kind=eq.junior&select=id`)).toEqual([]);

    await page.getByLabel("First Name").fill("Specchild");
    await page.getByLabel("Last Name").fill(DANA.last);
    await page.getByLabel("Birthday").fill("2018-05-04");
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page.locator("h2.display")).toHaveText(`Specchild ${DANA.last}`);
    await expect(page.getByText("May 4, 2018")).toBeVisible();
    // No junior waiver is published in the seed: it says so, and offers no Sign.
    await expect(page.locator("#c-waiver")).toHaveText("The waiver isn't available yet.");
    await expect(page.getByRole("link", { name: "Sign the waiver" })).toHaveCount(0);

    const rows = await db.get(`players?account_id=eq.${DANA.account}&kind=eq.junior&select=id,first_name,date_of_birth,is_active`);
    expect(rows).toEqual([expect.objectContaining({ first_name: "Specchild", date_of_birth: "2018-05-04", is_active: true })]);
    // Decision 0061: an adult account becomes 'both' when it adds a child.
    expect((await db.get(`accounts?id=eq.${DANA.account}&select=account_type`))[0].account_type).toBe("both");

    await page.getByRole("link", { name: "Edit details" }).click();
    await page.getByLabel("First Name").fill("Renamedchild");
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page.locator("h2.display")).toHaveText(`Renamedchild ${DANA.last}`);
    await page.goto("/play/#/children");
    await expect(page.locator(`[data-child="${rows[0].id}"]`)).toContainText("Renamedchild");
    await expect(page.locator(`[data-child="${rows[0].id}"]`)).toContainText(/Age \d+/);
  });

  test("a future birthday and the same child twice are refused in words, and nothing is saved", async ({ page, request }) => {
    const db = service(request);
    await childOfDana(db, "Twinchild", "2017-09-09");
    await signInPlay(page, DANA);
    await page.goto("/play/#/child/new");
    await page.getByLabel("First Name").fill("Laterchild");
    await page.getByLabel("Last Name").fill(DANA.last);
    const next = new Date(Date.now() + 40 * 86_400_000).toISOString().slice(0, 10);
    await page.getByLabel("Birthday").fill(next);
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page.locator("#c-error")).toHaveText("Enter a birthday that isn't in the future.");
    // What she typed stays in the form.
    await expect(page.getByLabel("First Name")).toHaveValue("Laterchild");

    await page.getByLabel("First Name").fill("Twinchild");
    await page.getByLabel("Birthday").fill("2017-09-09");
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page.locator("#c-error")).toHaveText("That child is already on your account.");
    const rows = await db.get(`players?account_id=eq.${DANA.account}&kind=eq.junior&select=first_name`);
    expect(rows.map(r => r.first_name)).toEqual(["Twinchild"]);
  });

  test("signs the published junior waiver for one child; then only Tara can change the name", async ({ page, request }) => {
    const db = service(request);
    await publishJuniorWaiver(db);
    const kid = await childOfDana(db, "Signchild");
    await signInPlay(page, DANA);
    await page.goto(`/play/#/child/${kid.id}`);
    await expect(page.locator("#c-waiver")).toHaveText("Not signed yet");
    await page.getByRole("link", { name: "Sign the waiver" }).click();
    await expect(page.getByRole("heading", { name: "Junior Waiver For Tests" })).toBeVisible();
    await expect(page.getByText("Made by juniors.spec.mjs.")).toBeVisible();

    const sign = page.getByRole("button", { name: "Agree and sign" });
    await expect(sign).toBeDisabled();
    await page.getByLabel(`I have read and agree to this waiver for Signchild ${DANA.last}.`).check();
    await expect(sign).toBeDisabled();
    await page.getByLabel("Your full legal name").fill(`${DANA.first} ${DANA.last}`);
    await sign.click();
    await expect(page.locator("#c-waiver")).toHaveText("Signed");
    const sig = await db.get(`junior_waiver_acceptances?player_id=eq.${kid.id}&select=version,legal_name,account_id,app_version`);
    expect(sig).toEqual([{ version: WAIVER, legal_name: `${DANA.first} ${DANA.last}`, account_id: DANA.account, app_version: "web" }]);

    // Signed: the parent can no longer rename the child (child_locked).
    await page.getByRole("link", { name: "Edit details" }).click();
    await page.getByLabel("First Name").fill("Otherchild");
    await page.getByRole("button", { name: "Save" }).click();
    await expect(page.locator("#c-error")).toHaveText("Only Tara can change this child's name or birthday now.");
    expect((await db.get(`players?id=eq.${kid.id}&select=first_name`))[0].first_name).toBe("Signchild");
  });

  test("removes a child behind a confirmation; the row is archived, not deleted", async ({ page, request }) => {
    const db = service(request);
    const kid = await childOfDana(db, "Gonechild");
    await signInPlay(page, DANA);
    await page.goto(`/play/#/child/${kid.id}`);
    await page.getByRole("button", { name: "Remove Gonechild" }).click();
    await expect(page.locator("#confirm-title")).toHaveText("Remove Gonechild from your account?");
    await page.getByRole("button", { name: "Keep" }).click();
    expect((await db.get(`players?id=eq.${kid.id}&select=is_active`))[0].is_active).toBe(true);

    await page.getByRole("button", { name: "Remove Gonechild" }).click();
    await page.locator("#confirm-yes").click();
    await expect(page.getByText("No children added yet")).toBeVisible();
    expect((await db.get(`players?id=eq.${kid.id}&select=is_active`))[0].is_active).toBe(false);
  });

  test("another member opening a child's page finds nothing", async ({ page, request }) => {
    const db = service(request);
    const kid = await childOfDana(db, "Privatechild");
    await signInPlay(page, MARIA);
    await page.goto(`/play/#/child/${kid.id}`);
    await expect(page.locator("main .error")).toHaveText("Couldn't find that child.");
    await expect(page.getByText("Privatechild")).toHaveCount(0);
    await page.goto(`/play/#/children`);
    await expect(page.getByText("No children added yet")).toBeVisible();
  });
});

test.describe("Elite approvals, parent to Tara and back", () => {
  test.beforeEach(async ({ request }) => cleanUp(service(request)));
  test.afterEach(async ({ request }) => cleanUp(service(request)));

  test("a parent asks for Elite; Tara approves on Action Needed; the parent sees Approved", async ({ page, browser, request }) => {
    const db = service(request);
    const kid = await childOfDana(db, "Elitechild");
    const elite = await program(db, "Elite");
    const red = await program(db, "Red Dot");
    await signInPlay(page, DANA);
    await page.goto(`/play/#/child/${kid.id}`);
    // Her programs with her age guidance; only the two that need her approval offer a request.
    await expect(page.locator(`[data-program="${red.id}"]`)).toContainText("Ages 3-6");
    await expect(page.locator(`[data-program="${red.id}"] button`)).toHaveCount(0);
    await page.locator(`[data-program="${elite.id}"]`).getByRole("button", { name: "Request Approval" }).click();
    await expect(page.locator(`[data-approval="${elite.id}"]`)).toHaveText("Approval requested");
    expect(await db.get(`program_approvals?player_id=eq.${kid.id}&select=status,source`)).toEqual([{ status: "requested", source: "parent" }]);

    const tara = await (await browser.newContext()).newPage();
    await signInAdmin(tara);
    const ask = tara.locator(`#program-asks [data-program-request="${kid.id}"]`);
    await expect(ask).toContainText("Elitechild");
    await expect(ask).toContainText("asked for Elite");
    await expect(ask).toContainText(`Parent: ${DANA.first} ${DANA.last}`);
    await ask.getByRole("button", { name: "Approve" }).click();
    await expect(tara.locator("#program-asks")).toBeHidden({ timeout: 15_000 });
    expect(await db.get(`program_approvals?player_id=eq.${kid.id}&select=status`)).toEqual([{ status: "approved" }]);

    await page.reload();
    await expect(page.locator(`[data-approval="${elite.id}"]`)).toHaveText("Approved");
  });

  test("Tara declines a request on the Juniors tab, then approves the child herself", async ({ page, request }) => {
    const db = service(request);
    const kid = await childOfDana(db, "Declinechild");
    const junior = await program(db, "Junior Elite");
    await db.insert("program_approvals", { player_id: kid.id, program_id: junior.id, status: "requested", source: "parent",
      requested_by: DANA.account, requested_at: new Date().toISOString() });
    await signInAdmin(page);
    await page.getByRole("tab", { name: "Juniors" }).click();
    const ask = page.locator(`#jr-approvals [data-program-request="${kid.id}"]`);
    await expect(ask).toContainText("asked for Junior Elite");
    await ask.getByRole("button", { name: "Decline" }).click();
    const done = page.locator(`#jr-approvals [data-program-decided="${kid.id}"]`);
    await expect(done).toContainText("Declined");
    expect(await db.get(`program_approvals?player_id=eq.${kid.id}&select=status`)).toEqual([{ status: "declined" }]);

    // Decision 0061: after a decline only Tara approves, with Approve.
    await done.getByRole("button", { name: "Approve" }).click();
    await expect(done).not.toContainText("Declined");
    await expect(done).toContainText("Approved");
    expect(await db.get(`program_approvals?player_id=eq.${kid.id}&select=status,source`)).toEqual([{ status: "approved", source: "parent" }]);
  });

  test("Tara approves a child for Junior Elite before anyone asks", async ({ page, request }) => {
    const db = service(request);
    const kid = await childOfDana(db, "Preapprovedchild");
    const junior = await program(db, "Junior Elite");
    await signInAdmin(page);
    await page.getByRole("tab", { name: "Juniors" }).click();
    await page.getByLabel("Program").selectOption({ label: "Junior Elite" });
    await page.getByLabel("Search children by name").fill("Preapproved");
    const hit = page.locator(`#jr-results [data-child-result="${kid.id}"]`);
    await hit.getByRole("button", { name: "Approve" }).click();
    await expect(page.locator("#jr-pre-msg")).toHaveText("Approved.");
    await expect(page.locator(`#jr-approvals [data-program-decided="${kid.id}"]`)).toContainText("Approved by you");
    expect(await db.get(`program_approvals?player_id=eq.${kid.id}&select=program_id,status,source`))
      .toEqual([{ program_id: junior.id, status: "approved", source: "tara" }]);
  });
});

test.describe("Tara's programs", () => {
  test("she writes a program's description, which a parent then reads", async ({ page, browser, request }) => {
    const db = service(request);
    const red = await program(db, "Red Dot");
    try {
      await signInAdmin(page);
      await page.getByRole("tab", { name: "Juniors" }).click();
      const row = page.locator(`[data-program-row="${red.id}"]`);
      await expect(row).toContainText("No description yet");
      await row.getByRole("button", { name: "Edit" }).click();
      const dialog = page.locator("dialog#program");
      await expect(dialog.getByLabel("Name")).toHaveValue("Red Dot");
      await dialog.getByLabel("Description").fill("Written by juniors.spec.mjs.");
      await dialog.getByRole("button", { name: "Save" }).click();
      await expect(dialog).toBeHidden();
      await expect(row).toContainText("Written by juniors.spec.mjs.");
      expect((await program(db, "Red Dot")).description).toBe("Written by juniors.spec.mjs.");

      await cleanUp(db);
      const kid = await childOfDana(db, "Readerchild");
      const parent = await (await browser.newContext()).newPage();
      await signInPlay(parent, DANA);
      await parent.goto(`/play/#/child/${kid.id}`);
      await expect(parent.locator(`[data-program="${red.id}"]`)).toContainText("Written by juniors.spec.mjs.");
    } finally {
      await db.patch(`junior_programs?id=eq.${red.id}`, { description: red.description });
      await cleanUp(db);
    }
  });

  test("a new program needs a name, can be archived and restored, and a second one by that name is refused", async ({ page, request }) => {
    const db = service(request);
    try {
      await signInAdmin(page);
      await page.getByRole("tab", { name: "Juniors" }).click();
      await page.getByRole("button", { name: "New program" }).click();
      const dialog = page.locator("dialog#program");
      await dialog.getByRole("button", { name: "Save" }).click();
      await expect(dialog.locator("#program-msg")).toHaveText("A program needs a name.");
      await dialog.getByLabel("Name").fill("Spec Program");
      await dialog.getByLabel("Ages").fill("Ages 8-12");
      await dialog.getByLabel("Needs your approval").check();
      await dialog.getByRole("button", { name: "Save" }).click();
      await expect(dialog).toBeHidden();
      const made = await program(db, "Spec Program");
      expect(made).toEqual(expect.objectContaining({ age_guidance: "Ages 8-12", needs_approval: true, active: true }));
      const row = page.locator(`[data-program-row="${made.id}"]`);
      await expect(row).toContainText("needs your approval");
      // A program that needs approval is offered under Approve a child.
      await expect(page.getByLabel("Program").locator("option", { hasText: "Spec Program" })).toHaveCount(1);

      await row.getByRole("button", { name: "Archive" }).click();
      await expect(row).toBeHidden();
      expect((await program(db, "Spec Program")).active).toBe(false);
      await page.locator("#jr-show-archived").check();
      await expect(row).toContainText("(archived)");
      await row.getByRole("button", { name: "Restore" }).click();
      await expect(row).not.toContainText("(archived)");
      expect((await program(db, "Spec Program")).active).toBe(true);

      // The same name twice is refused in words.
      await page.getByRole("button", { name: "New program" }).click();
      await dialog.getByLabel("Name").fill("spec program");
      await dialog.getByRole("button", { name: "Save" }).click();
      await expect(dialog.locator("#program-msg")).toHaveText("A program already has that name.");
      await dialog.getByRole("button", { name: "Cancel" }).click();
    } finally {
      await db.del("junior_programs?name=eq.Spec%20Program");
    }
  });
});

test.describe("children on the Players tab", () => {
  test.beforeEach(async ({ request }) => cleanUp(service(request)));
  test.afterEach(async ({ request }) => cleanUp(service(request)));

  test("a child sits under the parent, with the parent's phone and none of the adult controls", async ({ page, request }) => {
    const db = service(request);
    await publishJuniorWaiver(db);
    const kid = await childOfDana(db, "Rosterchild", "2015-01-20");
    const elite = await program(db, "Elite");
    await db.insert("program_approvals", { player_id: kid.id, program_id: elite.id, status: "approved", source: "tara",
      decided_at: new Date().toISOString() });
    await signInAdmin(page);
    await page.getByRole("tab", { name: "Players" }).click();
    await page.getByLabel("Search players by name").fill(DANA.last);
    const child = page.locator(`[data-junior="${kid.id}"]`);
    await expect(child).toContainText("Rosterchild");
    await expect(child).toContainText("(junior)");
    await expect(child).toContainText("Waiver not signed");
    await expect(child).toContainText("Approved: Elite");
    await expect(child).toContainText(`Parent's phone (${DANA.first} ${DANA.last})`);
    // Right under Dana's own row.
    const order = await page.locator("#p-results [data-player-row]").evaluateAll(els => els.map(e => e.dataset.playerRow));
    const dana = (await db.get(`players?account_id=eq.${DANA.account}&kind=eq.adult&select=id`))[0].id;
    expect(order.indexOf(kid.id)).toBe(order.indexOf(dana) + 1);
    // None of an adult's controls.
    for (const name of ["Make member", "Make non-member", "Reset link", "Deactivate", "Approve"]) {
      await expect(child.getByRole("button", { name, exact: true })).toHaveCount(0);
    }
    await expect(child.locator("input[data-pro], select")).toHaveCount(0);
    await expect(child.getByRole("button", { name: /^Message/ })).toHaveCount(0);
    // Her note works on a child as on anyone.
    await child.getByRole("button", { name: "Note" }).click();
    await page.locator(`[data-notebody="${kid.id}"]`).fill("A note on a child, from juniors.spec.");
    await page.locator(`[data-savenote="${kid.id}"]`).click();
    await expect(page.locator("#players-msg")).toHaveText("Saved.");
  });
});
