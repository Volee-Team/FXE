// The members' website (web/play/, decision 0043), walked the way a member
// walks it, against a freshly reset local stack. Until 2026-10-25 it had no
// test at all: every browser test was Tara's side, so a page that served a
// bare logo (the /play slash bug) or kept Tara signed in on the members' site
// could only be found by Alex looking at it.
//
// Each test that needs a clinic makes its own through the REST API as
// service_role, 20+ days out so it is never in the admin's "This week", and
// deletes it again in finally (registrations, messages and late requests
// cascade), so a failure leaves nothing for the next test or the probe
// runner's DIRTY check. Expected values come from the rules (CLAUDE.md,
// Registration rules; hard rule 1), not from reading play.js.
import { test, expect } from "@playwright/test";
import { execSync } from "node:child_process";

const PW = "password";
const MARIA = { email: "maria@fxe.test", first: "Maria" };   // member
const THEO = { email: "theo@fxe.test", first: "Theo" };      // non-member
const LENA = { email: "lena@fxe.test", first: "Lena" };      // member
const TARA = { email: "tara@fxe.test" };
const P = {
  maria: "a0000000-0000-0000-0000-000000000001",
  ken: "a0000000-0000-0000-0000-000000000002",
  lena: "a0000000-0000-0000-0000-000000000007",
  theo: "a0000000-0000-0000-0000-000000000008",
};
const ACCOUNT = { maria: "22222222-2222-2222-2222-222222222222" };

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

const iso = (ms) => new Date(Date.now() + ms).toISOString();
const H = 3600_000, D = 24 * H;
const MEMBER_WINDOW = { memberOpens: -2 * H, publicOpens: 10 * H };

// A clinic of our own. Opens defaults to "both windows already open".
async function makeClinic(db, name, { startsIn = 22 * D, minutes = 60, capacity = 8,
    memberOpens = -2 * D, publicOpens = -1 * D, closesAt, audience = "coed" } = {}) {
  const row = {
    name, audience, category: "Clinic", description: "Made by play.spec.mjs.",
    starts_at: iso(startsIn), ends_at: iso(startsIn + minutes * 60_000), duration_minutes: minutes,
    member_opens_at: iso(memberOpens), public_opens_at: iso(publicOpens),
    internal_capacity: capacity, status: "published",
  };
  if (closesAt !== undefined) row.closes_at = closesAt;
  return db.insert("clinics", row);
}
async function seat(db, clinic, player, status = "in", member = true) {
  return db.insert("registrations", { clinic_id: clinic.id, player_id: player, status, source: "self",
    price_cents_charged: 1800, was_member: member, duration_minutes: 60 });
}
async function cleanUp(db, clinics) {
  for (const c of clinics.filter(Boolean)) {
    await db.del(`notifications?entity_id=eq.${c.id}`);
    const regs = await db.get(`registrations?clinic_id=eq.${c.id}&select=id`);
    for (const r of regs) await db.del(`notifications?entity_id=eq.${r.id}`);
    await db.del(`clinics?id=eq.${c.id}`);
  }
}

async function signIn(page, who) {
  await page.goto("/play/");
  await page.getByLabel("Email").fill(who.email);
  await page.getByLabel("Password").fill(PW);
  await page.getByRole("button", { name: "Sign In" }).click();
  if (who.first) await expect(page.locator("h2.display")).toContainText(`, ${who.first}!`);
}
const card = (page, name) => page.locator("a.card", { hasText: name });
async function openClinic(page, clinic) {
  await page.goto(`/play/#/clinic/${clinic.id}`);
  await expect(page.locator("h2.display")).toHaveText(clinic.name);
}

// ---------------------------------------------------------------------------
test.describe("signed out", () => {
  test("a fresh browser gets the sign-in screen, and runs only this site's scripts", async ({ page, baseURL }) => {
    const origin = new URL(baseURL).origin;
    const foreign = [], broken = [];
    page.on("request", (r) => {
      // Stripe's own script is the one outside file the page loads (card entry).
      if (r.resourceType() === "script" && new URL(r.url()).origin !== origin && !r.url().startsWith("https://js.stripe.com/")) foreign.push(r.url());
    });
    page.on("pageerror", (e) => broken.push(e.message));
    page.on("response", (r) => { if (new URL(r.url()).origin === origin && r.status() >= 400) broken.push(`${r.status()} ${r.url()}`); });
    await page.goto("/play/");
    await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
    await expect(page.getByText("Good ")).toHaveCount(0);
    expect(foreign).toEqual([]);
    expect(broken).toEqual([]);
  });

  test("a wrong password says so, and the page stays signed out", async ({ page }) => {
    await page.goto("/play/");
    await page.getByLabel("Email").fill(MARIA.email);
    await page.getByLabel("Password").fill("not-her-password");
    await page.getByRole("button", { name: "Sign In" }).click();
    await expect(page.locator("#auth-msg")).toHaveText("That email or password didn't work.");
    await page.reload();
    await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
  });

  test("Tara signed in on the admin site is not signed in on the members' site", async ({ page }) => {
    // 2026-10-25: Alex's browser, signed in to the admin as Tara since 09-22,
    // opened /play/ and was greeted "Good Evening, Tara!". Same origin, same
    // supabase-js storage key, so one sign-in served both sites, and signing
    // out of either signed out of both.
    await page.goto("/index.html");
    await page.getByLabel("Email").fill(TARA.email);
    await page.getByLabel("Password").fill(PW);
    await page.getByRole("button", { name: "Sign In" }).click();
    await expect(page.getByRole("tab", { name: "This week" })).toBeVisible();
    await page.goto("/play/");
    await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
    // And the other way: a member signed in here leaves the admin signed in as Tara.
    await signIn(page, MARIA);
    await page.goto("/index.html");
    await expect(page.getByRole("tab", { name: "This week" })).toBeVisible();
    await expect(page.getByText("not an administrator")).toHaveCount(0);
  });
});

// ---------------------------------------------------------------------------
test.describe("a member's clinics", () => {
  test("register with a note, see You're In!, cancel, and the row is kept as canceled", async ({ page, request }) => {
    const db = service(request);
    let c;
    try {
      // Inside the member-only window: a member with room is You're In!.
      // After the public opening she would be Player Pool (Registration rules).
      c = await makeClinic(db, "Play Spec Register", MEMBER_WINDOW);
      await signIn(page, LENA);
      await openClinic(page, c);
      await expect(page.locator(".chip")).toHaveCount(0);
      await page.locator("#note").fill("with my friend Jane");
      await page.getByRole("button", { name: "Register" }).click();
      await expect(page.locator(".chip").first()).toHaveText("You're In!");
      await expect(page.locator("#note")).toHaveValue("with my friend Jane");
      await expect(page.getByRole("button", { name: "Add to Calendar" })).toBeVisible();

      let rows = await db.get(`registrations?clinic_id=eq.${c.id}&select=status,player_note,player_id`);
      expect(rows).toEqual([{ status: "in", player_note: "with my friend Jane", player_id: P.lena }]);

      // The note can be changed after registering, and only Save sends it.
      await page.locator("#note").fill("with Jane please");
      await page.getByRole("button", { name: "Save" }).click();
      await expect(page.locator("#note")).toHaveValue("with Jane please");
      rows = await db.get(`registrations?clinic_id=eq.${c.id}&select=player_note`);
      expect(rows[0].player_note).toBe("with Jane please");

      // Home lists it under My Clinics.
      await page.goto("/play/#/home");
      await expect(page.locator("p.section", { hasText: "My Clinics" })).toBeVisible();
      await expect(card(page, c.name).locator(".chip")).toHaveText("You're In!");

      // Cancel, days out: a confirmation, no fee wording.
      await openClinic(page, c);
      await page.getByRole("button", { name: "Cancel Registration" }).click();
      await expect(page.locator("#confirm")).toBeVisible();
      await page.getByRole("button", { name: "Yes, cancel my spot" }).click();
      await expect(page.getByRole("button", { name: "Register" })).toBeVisible();
      await expect(page.getByText("full clinic fee")).toHaveCount(0);
      // Archive, never delete (hard rule 4).
      rows = await db.get(`registrations?clinic_id=eq.${c.id}&select=status,late_cancel`);
      expect(rows).toEqual([{ status: "canceled", late_cancel: false }]);
    } finally { await cleanUp(db, [c]); }
  });

  test("a full clinic puts her in the Player Pool, and she can leave it", async ({ page, request }) => {
    const db = service(request);
    let c;
    try {
      c = await makeClinic(db, "Play Spec Pool", { ...MEMBER_WINDOW, capacity: 1 });
      await seat(db, c, P.ken);
      await signIn(page, LENA);
      await openClinic(page, c);
      // Capacity is never shown (hard rule 1): the page offers Register, not "full".
      await expect(page.getByText(/full|spots?|capacity/i)).toHaveCount(0);
      await page.getByRole("button", { name: "Register" }).click();
      await expect(page.locator(".chip").first()).toHaveText("Player Pool");
      await page.getByRole("button", { name: "Leave Player Pool" }).click();
      await page.getByRole("button", { name: "Yes, leave the pool" }).click();
      await expect(page.getByRole("button", { name: "Register" })).toBeVisible();
      const rows = await db.get(`registrations?clinic_id=eq.${c.id}&player_id=eq.${P.lena}&select=status`);
      expect(rows).toEqual([{ status: "canceled" }]);
    } finally { await cleanUp(db, [c]); }
  });

  test("Tara's invitation is Response Needed, and Accept makes it You're In!", async ({ page, request }) => {
    const db = service(request);
    let c;
    try {
      c = await makeClinic(db, "Play Spec Invite", { capacity: 1 });
      await seat(db, c, P.ken);
      await seat(db, c, P.lena, "response_needed");
      await signIn(page, LENA);
      await expect(card(page, c.name).locator(".chip")).toHaveText("Response Needed");
      await openClinic(page, c);
      await page.getByRole("button", { name: "Accept" }).click();
      await expect(page.locator(".chip").first()).toHaveText("You're In!");
      // Capacity never blocks an accepted invitation (decision 4), and nothing
      // tells her the clinic is now over its number.
      const rows = await db.get(`registrations?clinic_id=eq.${c.id}&status=eq.in&select=player_id`);
      expect(rows.map(r => r.player_id).sort()).toEqual([P.ken, P.lena].sort());
    } finally { await cleanUp(db, [c]); }
  });

  test("Decline leaves her with no spot and nothing to accept", async ({ page, request }) => {
    const db = service(request);
    let c;
    try {
      c = await makeClinic(db, "Play Spec Decline");
      await seat(db, c, P.lena, "response_needed");
      await signIn(page, LENA);
      await openClinic(page, c);
      await page.getByRole("button", { name: "Decline" }).click();
      await expect(page.getByRole("button", { name: "Accept" })).toHaveCount(0);
      const rows = await db.get(`registrations?clinic_id=eq.${c.id}&player_id=eq.${P.lena}&select=status`);
      expect(rows[0].status).not.toBe("in");
    } finally { await cleanUp(db, [c]); }
  });

  test("inside 3 hours, Cancel shows Tara's fee sentence and records a late cancel with the note", async ({ page, request }) => {
    const db = service(request);
    let c;
    try {
      // Two hours from now: inside the 3-hour cutoff (decision 0013).
      c = await makeClinic(db, "Play Spec Late", { startsIn: 2 * H });
      await seat(db, c, P.lena);
      await signIn(page, LENA);
      await openClinic(page, c);
      await page.getByRole("button", { name: "Cancel Registration" }).click();
      await expect(page.getByText("This cancellation is within 3 hours of clinic and the full clinic fee will apply. If an emergency, please leave a note below.")).toBeVisible();
      // Keep my spot really keeps it.
      await page.getByRole("button", { name: "Keep my spot" }).click();
      await expect(page.locator(".chip").first()).toHaveText("You're In!");
      await page.getByRole("button", { name: "Cancel Registration" }).click();
      // The late-cancel box, not the registration note above it: both read
      // "Note for Tara (optional)" (backlog).
      await expect(page.locator("#lc-note")).toBeVisible();
      await page.locator("#lc-note").fill("sick kid");
      await page.getByRole("button", { name: "Cancel my spot" }).click();
      await expect(page.getByRole("button", { name: "Cancel Registration" })).toHaveCount(0);
      const rows = await db.get(`registrations?clinic_id=eq.${c.id}&player_id=eq.${P.lena}&select=status,late_cancel,cancel_note`);
      expect(rows).toEqual([{ status: "canceled", late_cancel: true, cancel_note: "sick kid" }]);
    } finally { await cleanUp(db, [c]); }
  });

  test("after registration closes she can only ask Tara, and the ask reaches Tara", async ({ page, request }) => {
    const db = service(request);
    let c;
    try {
      // Starts in 2 hours, so the default close (3 hours before) has passed.
      c = await makeClinic(db, "Play Spec Closed", { startsIn: 2 * H });
      await signIn(page, LENA);
      await openClinic(page, c);
      await expect(page.getByRole("button", { name: "Register" })).toHaveCount(0);
      await expect(page.getByText("Registration has closed for this clinic.")).toBeVisible();
      await page.getByRole("button", { name: "Message Tara" }).click();
      await expect(page.getByText("Tara has your message.")).toBeVisible();
      const asks = await db.get(`late_requests?clinic_id=eq.${c.id}&select=player_id`);
      expect(asks).toEqual([{ player_id: P.lena }]);
    } finally { await cleanUp(db, [c]); }
  });
});

// ---------------------------------------------------------------------------
test.describe("the windows (CLAUDE.md, Registration rules)", () => {
  test("in the member-only window a member can register and a non-member is told when it opens", async ({ browser, request }) => {
    const db = service(request);
    let c;
    try {
      c = await makeClinic(db, "Play Spec Members First", MEMBER_WINDOW);
      const member = await (await browser.newContext()).newPage();
      await signIn(member, LENA);
      await openClinic(member, c);
      await expect(member.getByRole("button", { name: "Register" })).toBeVisible();

      const outsider = await (await browser.newContext()).newPage();
      await signIn(outsider, THEO);
      await openClinic(outsider, c);
      await expect(outsider.getByRole("button", { name: "Register" })).toHaveCount(0);
      await expect(outsider.getByText(/^Registration opens /)).toBeVisible();
      // Home does not offer it to him as open.
      await outsider.goto("/play/#/home");
      await expect(card(outsider, c.name)).toHaveCount(0);
    } finally { await cleanUp(db, [c]); }
  });

  test("before the member opening nobody can register", async ({ page, request }) => {
    const db = service(request);
    let c;
    try {
      c = await makeClinic(db, "Play Spec Not Yet", { memberOpens: 2 * D, publicOpens: 3 * D });
      await signIn(page, LENA);
      await openClinic(page, c);
      await expect(page.getByRole("button", { name: "Register" })).toHaveCount(0);
      await expect(page.getByText(/^Registration opens /)).toBeVisible();
    } finally { await cleanUp(db, [c]); }
  });

  test("a canceled clinic says so and offers nothing", async ({ page, request }) => {
    const db = service(request);
    let c;
    try {
      c = await makeClinic(db, "Play Spec Canceled");
      await seat(db, c, P.lena);
      await db.patch(`clinics?id=eq.${c.id}`, { status: "canceled", canceled_at: new Date().toISOString() });
      await signIn(page, LENA);
      await openClinic(page, c);
      await expect(page.getByText("This clinic has been canceled.")).toBeVisible();
      await expect(page.locator("#view button.btn")).toHaveCount(0);
    } finally { await cleanUp(db, [c]); }
  });
});

// ---------------------------------------------------------------------------
test.describe("what a member must never see (hard rule 1)", () => {
  test("no other player's name, no count, no court, no location, on any page", async ({ page, request }) => {
    const db = service(request);
    let c;
    try {
      c = await makeClinic(db, "Play Spec Hidden", { capacity: 4 });
      const ken = await seat(db, c, P.ken);
      await db.patch(`registrations?id=eq.${ken.id}`, { court_number: 3 });
      await seat(db, c, P.theo, "pool", false);
      await seat(db, c, P.lena);
      await signIn(page, LENA);
      const forbidden = /\bKen\b|Whitfield|\bTheo\b|\bGrant\b|\bcourt\s*\d|capacity|spots? (left|remaining)|\bof \d+\b|\d+ (registered|players?|in the pool)|Foxcroft|Road|\bRd\b|maps\.|directions/i;
      for (const hash of ["#/home", "#/clinics", `#/clinic/${c.id}`, "#/my-clinics", "#/profile", "#/notifications"]) {
        await page.goto(`/play/${hash}`);
        await page.waitForLoadState("networkidle");
        await expect(page.locator(".placeholder")).toHaveCount(0);
        const text = await page.locator("main, body").first().innerText();
        expect(text, `on ${hash}`).not.toMatch(forbidden);
      }
    } finally { await cleanUp(db, [c]); }
  });
});

// ---------------------------------------------------------------------------
test.describe("the rest of a member's day", () => {
  test("the bell counts unread, opens the list, and Mark all read clears it", async ({ page, request }) => {
    const db = service(request);
    const made = [];
    try {
      made.push(await db.insert("notifications", { account_id: ACCOUNT.maria, type: "clinic_message",
        entity_type: "clinic", entity_id: "d0000000-0000-0000-0000-000000000001", body: "Play spec: first" }));
      made.push(await db.insert("notifications", { account_id: ACCOUNT.maria, type: "clinic_message",
        entity_type: "clinic", entity_id: "d0000000-0000-0000-0000-000000000001", body: "Play spec: second" }));
      await signIn(page, MARIA);
      await expect(page.locator("#bell")).toHaveAttribute("aria-label", /^Notifications, \d+ unread$/);
      await page.locator("#bell").click();
      await expect(page.getByText("Play spec: second")).toBeVisible();
      await page.getByRole("button", { name: "Mark all read" }).click();
      await expect(page.getByRole("button", { name: "Mark all read" })).toHaveCount(0);
      await page.goto("/play/#/home");
      await expect(page.locator("#bell")).toHaveAttribute("aria-label", "Notifications");
      const left = await db.get(`notifications?account_id=eq.${ACCOUNT.maria}&read_at=is.null&select=id`);
      expect(left).toEqual([]);
    } finally {
      for (const n of made) await db.del(`notifications?id=eq.${n.id}`);
      await db.patch(`notifications?account_id=eq.${ACCOUNT.maria}`, { read_at: null });
    }
  });

  test("Edit details saves her phone and rating, and membership is not hers to change", async ({ page, request }) => {
    const db = service(request);
    const [before] = await db.get(`accounts?id=eq.${ACCOUNT.maria}&select=phone`);
    const [pBefore] = await db.get(`players?id=eq.${P.maria}&select=adult_rating`);
    try {
      await signIn(page, MARIA);
      await page.getByRole("link", { name: "Profile" }).click();
      await page.getByRole("link", { name: "Edit details" }).click();
      await expect(page.locator("#view input[type=checkbox], #view [data-member]")).toHaveCount(0);
      await page.getByLabel("Phone").fill("704-555-0199");
      await page.getByRole("button", { name: "USTA 4.5" }).click();
      await page.getByRole("button", { name: "Save" }).click();
      await expect(page.locator("h2.display")).toHaveText("Maria Alvarez");
      await expect(page.getByText("704-555-0199")).toBeVisible();
      await expect(page.getByText("4.5", { exact: true })).toBeVisible();
    } finally {
      await db.patch(`accounts?id=eq.${ACCOUNT.maria}`, { phone: before.phone });
      await db.patch(`players?id=eq.${P.maria}`, { adult_rating: pBefore.adult_rating });
    }
  });

  test("sign out from Profile returns to sign-in and stays there", async ({ page }) => {
    await signIn(page, MARIA);
    await page.getByRole("link", { name: "Profile" }).click();
    await page.getByRole("button", { name: "Sign Out" }).click();
    await page.locator("#confirm").getByRole("button", { name: "Sign Out" }).click();
    await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
    await page.reload();
    await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
  });

  test("a new person signs up, fills the profile, signs the waiver, and lands on Home", async ({ page }) => {
    const email = `play-spec-${Date.now()}@fxe.test`;
    await page.goto("/play/");
    await page.getByRole("button", { name: "Create an account" }).click();
    await page.getByLabel("Email").fill(email);
    await page.getByLabel("Password").fill("secret123");
    await page.getByRole("button", { name: "Create Account" }).click();
    await expect(page.getByRole("heading", { name: "Almost there!" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Continue" })).toBeDisabled();
    await page.getByLabel("First Name").fill("Sam");
    await page.getByLabel("Last Name").fill("Spec");
    await page.getByLabel("Phone").fill("704-555-0142");
    await page.getByRole("button", { name: "No", exact: true }).click();
    await page.getByRole("button", { name: "USTA 3.5" }).click();
    // Decision 0044: the gender question is required too.
    await expect(page.getByRole("button", { name: "Continue" })).toBeDisabled();
    await page.getByRole("button", { name: "Male", exact: true }).click();
    await page.getByRole("button", { name: "Continue" }).click();
    // The waiver comes before anything else (decision 0013 §4).
    await expect(page.getByRole("button", { name: "Agree and sign" })).toBeDisabled();
    await page.locator("#w-agree").check();
    await page.getByLabel("Full legal name").fill("Sam Spec");
    await page.getByRole("button", { name: "Agree and sign" }).click();
    await expect(page.locator("h2.display")).toContainText(", Sam!");
    // A non-member sees what is open to the public, nothing member-only.
    await expect(page.getByText("Saturday Members Only")).toHaveCount(0);
  });

  // Decision 0044. Theo is seeded as a man; this clears his answer to meet
  // the one-time question, and puts it back in finally.
  test("someone who never answered is asked once, and a man then sees no Ladies clinic", async ({ page, request }) => {
    const db = service(request);
    const ladies = await makeClinic(db, "Spec Ladies Only", { audience: "ladies" });
    const coed = await makeClinic(db, "Spec Coed For All");
    try {
      await db.patch(`players?id=eq.${P.theo}`, { gender: null });
      await signIn(page, { email: THEO.email });
      await expect(page.getByRole("heading", { name: "Gender" })).toBeVisible();
      // The question holds even when another page is asked for.
      await page.goto("/play/#/clinics");
      await expect(page.getByRole("heading", { name: "Gender" })).toBeVisible();
      await expect(page.getByRole("button", { name: "Continue" })).toBeDisabled();
      await page.getByRole("button", { name: "Male", exact: true }).click();
      await page.getByRole("button", { name: "Continue" }).click();
      await expect(page.getByRole("heading", { name: "Gender" })).toHaveCount(0);
      await page.goto("/play/#/clinics");
      await expect(card(page, "Spec Coed For All")).toBeVisible();
      await expect(card(page, "Spec Ladies Only")).toHaveCount(0);
      // Answered: a reload does not ask again.
      await page.reload();
      await expect(card(page, "Spec Coed For All")).toBeVisible();
      await expect(page.getByRole("heading", { name: "Gender" })).toHaveCount(0);
      const [row] = await db.get(`players?id=eq.${P.theo}&select=gender`);
      expect(row.gender).toBe("male");
    } finally {
      await db.patch(`players?id=eq.${P.theo}`, { gender: "male" });
      await cleanUp(db, [ladies, coed]);
    }
  });
});

// ---------------------------------------------------------------------------
test.describe("on a phone", () => {
  test.use({ viewport: { width: 375, height: 812 } });
  test("no page scrolls sideways at phone width", async ({ page }) => {
    await signIn(page, MARIA);
    for (const hash of ["#/home", "#/clinics", "#/clinic/d0000000-0000-0000-0000-000000000002", "#/my-clinics", "#/profile", "#/edit", "#/notifications"]) {
      await page.goto(`/play/${hash}`);
      // The page's own loading placeholders gone, not "networkidle": seven
      // pages of waiting for every font and the Stripe script to go quiet
      // ran past 30 s on CI (2026-10-27, PR #113).
      await expect(page.locator("#view")).not.toBeEmpty();
      await expect(page.locator(".placeholder, .spinner")).toHaveCount(0);
      const wide = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      expect(wide, `on ${hash}`).toBeLessThanOrEqual(0);
    }
  });
});
