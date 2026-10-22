// The members' website: the iOS app's player side in a browser (roadmap
// v1.1, the call of 2026-10-19), for members on Android.
//
// The rules that keep it honest:
//   * Same Supabase project and the SAME reads and RPCs as the app
//     (FXETennis/Data/Repositories.swift), so information hiding holds by
//     construction (hard rule 1). This file never reads clinics,
//     registrations or any count. Display logic here is display only: the
//     server decides every registration (register_for_clinic and friends).
//   * Every word a player reads is the app's own, copied from the Swift view
//     named beside it (hard rule 13, docs/copy-approved.txt). Where the web
//     needed a word the app does not have, the line says so.
//   * Times are shown in the club's time zone, America/New_York.

import { createClient } from "../vendor/supabase-js.js";
import { CONFIG, ENV } from "../config.js";
import { serviceWeekStart, weekLabel } from "../week.js";

// implicit flow, like the admin: a reset emailed from here finishes on
// ../reset.html, and a reset started in the app finishes there too.
const sb = createClient(CONFIG.url, CONFIG.key, { auth: { flowType: "implicit" } });
const view = document.getElementById("view");
const TZ = "America/New_York";
const HORIZON_DAYS = 35;                       // ClinicRepository.upcoming
const NOTE_LIMIT = 300;                        // ClinicNote.limit
const CONTACT = "mailto:fersctennispro@gmail.com";   // ProfileView "Contact Tara"
const PRIVACY = "../privacy.html";

// Locked terminology (Brand.Status). Never synonyms.
const STATUS = {
  in: { label: "You're In!", cls: "in" },
  pool: { label: "Player Pool", cls: "pool" },
  response_needed: { label: "Response Needed", cls: "resp" },
  canceled: { label: "Canceled", cls: "canc" },
};

// NTRPRating.displayOrdered and .label.
const RATINGS = [2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0];
const ratingLabel = (r) => (r >= 5 ? "5.0+" : Number(r).toFixed(1));

// Tara and Kat's permission sentence (PaymentsRepository.CardConsent.words).
const CARD_CONSENT = "I give permission for my card to be charged";

// Stripe decline codes in Tara's approved words (CardDecline + DeclineReason).
const DECLINE = {
  insufficient_funds: "Insufficient funds (NSF)", expired_card: "Card expired",
  card_declined: "Card declined", generic_decline: "Card declined",
  do_not_honor: "Card declined by bank", incorrect_cvc: "Wrong security code",
  incorrect_number: "Wrong card number", authentication_required: "Needs the cardholder to approve",
  processing_error: "Processing error, try again",
};
const TOLD_AS_DECLINED = new Set(["lost_card", "stolen_card", "fraudulent", "merchant_blacklist", "pickup_card"]);
const declineLine = (code) =>
  "Declined: " + ((code && !TOLD_AS_DECLINED.has(code) && DECLINE[code]) || "Card declined");

// ---------------------------------------------------------------- state ----

const S = {
  user: null, account: null, player: null, waiver: null,
  cardConsent: false, paymentsEnabled: false, cardRequired: false,
  clinics: [], regs: [], unread: 0, loaded: false,
};
const isMember = () => S.player?.is_member === true;
const skipsPlayerSteps = () => S.account?.role === "admin" || S.account?.role === "pro";

// ------------------------------------------------------------- helpers ----

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const fmt = (iso, opts) => new Intl.DateTimeFormat("en-US", { timeZone: TZ, ...opts }).format(new Date(iso));
const dayLong = (iso) => fmt(iso, { weekday: "long", month: "short", day: "numeric" });
const dayFull = (iso) => fmt(iso, { weekday: "long", month: "long", day: "numeric" });
const dayShort = (iso) => fmt(iso, { weekday: "short", month: "short", day: "numeric" });
const time = (iso) => fmt(iso, { hour: "numeric", minute: "2-digit" });
const opensAt = (iso) => fmt(iso, { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
const price = (cents) => (cents % 100 === 0 ? `$${cents / 100}` : `$${(cents / 100).toFixed(2)}`);
const priceFor = (c) => (isMember() ? c.member_price_cents : c.nonmember_price_cents);
const durationLine = (c) => (c.duration_minutes ? `${c.duration_minutes} min` : "Clinic");
const now = () => Date.now();
const t = (iso) => (iso ? new Date(iso).getTime() : null);

function chip(status) {
  const s = STATUS[status];
  return s ? `<span class="chip ${s.cls}">${s.label}</span>` : "";
}

// RequestFailure: no answer reads as no answer, never as a race.
function failureLine(e) {
  const m = (e?.message || String(e || "")).toLowerCase();
  if (e?.status === 429 || m.includes("rate limit")) return "Too many attempts. Try again in a minute.";
  if (e instanceof TypeError || m.includes("failed to fetch") || m.includes("networkerror") || m.includes("load failed"))
    return "Couldn't reach the server. Check your connection.";
  return null;
}
const raw = (e) => [e?.message, e?.details, e?.hint, e?.code].filter(Boolean).join(" ");

// Session.friendly
function authFriendly(e) {
  const line = failureLine(e);
  if (line) return line;
  const m = raw(e);
  if (/weak_password|password should/i.test(m)) {
    const found = m.match(/Password should[^.]*\./);
    return found ? found[0] : "Password should be at least 6 characters.";
  }
  if (/already registered/i.test(m)) return "That email already has an account. Sign in instead.";
  if (/invalid/i.test(m)) return "That email or password didn't work.";
  return "Something went wrong. Please try again.";
}

// ClinicDetailModel.outcome(for:)
function actionOutcome(e) {
  const m = raw(e);
  if (m.includes("card_required")) return { notice: "Add a card on your Profile to register.", reopens: "card" };
  if (m.includes("card_declined")) return { notice: declineLine(e?.hint), reopens: "card" };
  if (m.includes("waiver_required")) return { notice: "Sign the waiver first.", reopens: "waiver" };
  if (m.includes("back_to_back_105")) return { notice: "Non-members can take one 105 a day until 48 hours before." };
  if (m.includes("clinic_canceled")) return { notice: "This clinic has been canceled." };
  if (m.includes("clinic_ended") || m.includes("registration_closed") || m.includes("clinic_already_started"))
    return { notice: "Registration has closed for this clinic." };
  if (m.includes("already_registered")) return { notice: null };
  if (m.includes("registration_not_open")) return { notice: "Registration isn't open yet." };
  if (m.includes("clinic_full")) return { notice: "That clinic is full now." };
  if (m.includes("clinic_not_found")) return { notice: "That just changed. Here's the latest." };
  if (m.includes("note_not_editable") || m.includes("note_too_long")) return { notice: "Couldn't save your note." };
  const line = failureLine(e);
  if (line) return { notice: line };
  return { notice: "Sorry, someone beat you to the punch. Here's the latest!" };
}

// ClinicPublic.door(isMember:now:)
function door(c, at = now()) {
  if (c.status === "canceled" || at >= t(c.starts_at)) return { kind: "none" };
  if (c.closes_at && at >= t(c.closes_at)) return { kind: "askTara" };
  const opens = isMember() ? c.member_opens_at : c.public_opens_at;
  if (opens && at < t(opens)) return { kind: "opens", at: opens };
  return { kind: "register" };
}
const isOpen = (c, at = now()) => door(c, at).kind === "register";

const regFor = (clinicId) => S.regs.find((r) => r.clinic_id === clinicId && r.status !== "canceled") || null;

function confirmDialog(title, yes, no) {
  const d = document.getElementById("confirm");
  document.getElementById("confirm-title").textContent = title;
  document.getElementById("confirm-yes").textContent = yes;
  document.getElementById("confirm-no").textContent = no;
  return new Promise((resolve) => {
    const done = (v) => { d.close(); resolve(v); };
    document.getElementById("confirm-yes").onclick = () => done(true);
    document.getElementById("confirm-no").onclick = () => done(false);
    d.oncancel = () => resolve(false);
    d.showModal();
  });
}

// ---------------------------------------------------------- data reads ----

async function loadProfile() {
  const { data: { user } } = await sb.auth.getUser();
  S.user = user;
  if (!user) return "signedOut";
  const { data: acct, error: aErr } = await sb.from("accounts").select("*").eq("id", user.id).maybeSingle();
  if (aErr) throw aErr;
  S.account = acct;
  if (!acct) return "needsProfile";
  // The account_id filter matters: without it an admin reads every player.
  const { data: players, error: pErr } = await sb.from("players").select("*").eq("account_id", user.id);
  if (pErr) throw pErr;
  S.player = (players || []).find((p) => p.kind === "adult") || (players || [])[0] || null;
  if (!S.player && !skipsPlayerSteps()) return "needsProfile";
  const [w, consent, settings] = await Promise.all([
    sb.rpc("my_waiver_accepted"),
    sb.rpc("my_card_consent"),
    sb.from("app_settings").select("key, value").in("key", ["payments_enabled", "card_required"]),
  ]);
  if (w.error) throw w.error;
  S.waiver = w.data === true;
  S.cardConsent = consent.data === true;
  const on = Object.fromEntries((settings.data || []).map((r) => [r.key, r.value === "true"]));
  S.paymentsEnabled = !!on.payments_enabled;
  S.cardRequired = !!on.payments_enabled && !!on.card_required;
  return "signedIn";
}

async function refreshAccount() {
  const { data } = await sb.from("accounts").select("*").eq("id", S.user.id).maybeSingle();
  if (data) S.account = data;
  return !!data?.card_last4 && !data?.card_declined_at;
}

async function loadClinics() {
  const horizon = new Date(now() + HORIZON_DAYS * 86_400_000).toISOString();
  const [list, regs] = await Promise.all([
    sb.from("clinics_public").select("*").lte("starts_at", horizon).order("starts_at"),
    sb.from("my_registrations").select("*"),
  ]);
  if (list.error) throw list.error;
  if (regs.error) throw regs.error;
  S.regs = regs.data || [];
  let clinics = list.data || [];
  // A clinic she holds that is past the horizon still shows (ClinicsViewModel).
  const held = new Set(S.regs.filter((r) => r.status !== "canceled").map((r) => r.clinic_id));
  const known = new Set(clinics.map((c) => c.id));
  if ([...held].some((id) => !known.has(id))) {
    const far = await sb.from("clinics_public").select("*").gt("starts_at", horizon).order("starts_at").limit(200);
    if (!far.error) clinics = clinics.concat((far.data || []).filter((c) => held.has(c.id)));
  }
  // Ended clinics are not upcoming.
  S.clinics = clinics.filter((c) => t(c.ends_at) > now());
  S.loaded = true;
}

async function refreshUnread() {
  const { count } = await sb.from("notifications").select("id", { count: "exact", head: true }).is("read_at", null);
  S.unread = count || 0;
  document.getElementById("bell-dot").hidden = S.unread === 0;
  document.getElementById("bell").setAttribute("aria-label", S.unread ? `Notifications, ${S.unread} unread` : "Notifications");
}

// ------------------------------------------------------------ chrome ----

function chrome({ title = "", back = false, tab = null, bell = false, mark = !title }) {
  document.getElementById("bar-title").textContent = title;
  document.getElementById("mark").hidden = !mark;
  document.getElementById("back").hidden = !back;
  document.getElementById("bell").hidden = !bell;
  if (bell) refreshUnread().catch(() => {});
  const tabs = document.getElementById("tabs");
  tabs.hidden = !tab;
  for (const a of tabs.querySelectorAll("a")) {
    if (a.dataset.tab === tab) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
  }
  document.title = title ? `${title} | FXE Tennis` : "FXE Tennis";
}
document.getElementById("back").onclick = () => (history.length > 1 ? history.back() : go("#/home"));
document.getElementById("bell").onclick = () => go("#/notifications");

const go = (hash) => { if (location.hash === hash) route(); else location.hash = hash; };

// --------------------------------------------------------------- views ----

// AuthView
function renderAuth(mode = "signIn", message = "", isError = true) {
  chrome({});
  const signUp = mode === "signUp";
  view.innerHTML = `
    <p class="tagline center" style="margin:12px 0 24px">Let's Play.</p>
    <form id="auth" class="stack" novalidate>
      <input type="email" id="email" autocomplete="email" placeholder="Email" aria-label="Email" required>
      <input type="password" id="password" autocomplete="${signUp ? "new-password" : "current-password"}" placeholder="Password" aria-label="Password" required>
      ${signUp ? `<p class="caption" style="margin:0">At least 6 characters.</p>` : ""}
      <p id="auth-msg" class="${isError ? "error" : "muted"}" role="status">${esc(message)}</p>
      <button class="btn primary" id="auth-go">${signUp ? "Create Account" : "Sign In"}</button>
    </form>
    <p class="center"><button class="link" id="toggle">${signUp ? "Sign in" : "Create an account"}</button></p>
    ${signUp ? "" : `<p class="center"><button class="link" id="forgot">Forgot password?</button></p>`}`;
  // The app's line under this form is about its notifications; this page has
  // no push (the bell only), so the line is not repeated here.
  const msg = document.getElementById("auth-msg");
  const busy = (on) => { const b = document.getElementById("auth-go"); b.disabled = on; b.innerHTML = on ? `<span class="spinner"></span>` : (signUp ? "Create Account" : "Sign In"); };
  document.getElementById("toggle").onclick = () => renderAuth(signUp ? "signIn" : "signUp");
  if (!signUp) document.getElementById("forgot").onclick = async () => {
    const email = document.getElementById("email").value.trim();
    if (!email) { document.getElementById("email").focus(); return; }
    const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: `${location.origin}/reset.html` });
    if (error && (String(error.code).startsWith("over_email") || /email rate limit/i.test(error.message))) {
      msg.className = "error"; msg.textContent = "Too many reset emails. Try again later.";
    } else if (error && failureLine(error)) {
      msg.className = "error"; msg.textContent = failureLine(error);
    } else {
      // Same answer whether or not the email has an account (no enumeration).
      msg.className = "muted"; msg.textContent = "Check your email for a reset link. It can take a few minutes.";
    }
  };
  document.getElementById("auth").onsubmit = async (ev) => {
    ev.preventDefault();
    const email = document.getElementById("email").value.trim();
    const password = document.getElementById("password").value;
    msg.textContent = ""; busy(true);
    const { data, error } = signUp
      ? await sb.auth.signUp({ email, password })
      : await sb.auth.signInWithPassword({ email, password });
    busy(false);
    if (error) { msg.className = "error"; msg.textContent = authFriendly(error); return; }
    // GoTrue answers an existing email's sign-up with a user and no identities.
    if (signUp && data?.user && (data.user.identities || []).length === 0) {
      msg.className = "error"; msg.textContent = "That email already has an account. Sign in instead."; return;
    }
    await boot();
  };
}

// CompleteProfileView
function renderCompleteProfile(error = "") {
  chrome({});
  let member = null, rating = null;
  view.innerHTML = `
    <h2 class="display">Almost there!</h2>
    <p class="muted" style="margin:0 0 20px">Members get 24-hour early access to all clinics</p>
    <div class="stack">
      <label class="field">First Name<input type="text" id="first" autocomplete="given-name"></label>
      <label class="field">Last Name<input type="text" id="last" autocomplete="family-name"></label>
      <label class="field">Phone<input type="tel" id="phone" autocomplete="tel"></label>
      <p class="emph" style="margin:12px 0 0">Are you currently a Foxcroft East Racquet &amp; Swim Club member?</p>
      <div class="two">
        <button type="button" class="choice" data-member="true" aria-pressed="false">Yes</button>
        <button type="button" class="choice" data-member="false" aria-pressed="false">No</button>
      </div>
      <p class="emph" style="margin:12px 0 0">Your tennis rating</p>
      <div class="pills" id="ratings">${RATINGS.map((r) =>
        `<button type="button" class="pill" data-rating="${r}" aria-pressed="false" aria-label="USTA ${ratingLabel(r)}">${ratingLabel(r)}</button>`).join("")}</div>
      <p class="emph" style="margin:12px 0 0">Note for Tara (optional)</p>
      <textarea id="level-note" placeholder="Just coming back from a back injury - probably a low 3.5" maxlength="${NOTE_LIMIT}"></textarea>
      <p class="caption" style="margin:0">Only Tara sees this.</p>
      <p class="error" id="cp-error">${esc(error)}</p>
      <button class="btn primary" id="cp-go" disabled>Continue</button>
      <p class="caption" id="cp-why">Add your name, phone number, and tennis rating. Please answer the membership question to continue</p>
    </div>
    ${exitFooter()}`;
  const v = (id) => document.getElementById(id).value.trim();
  const check = () => {
    const ok = v("first") && v("last") && v("phone") && member !== null && rating !== null;
    document.getElementById("cp-go").disabled = !ok;
    document.getElementById("cp-why").hidden = !!ok;
  };
  for (const id of ["first", "last", "phone"]) document.getElementById(id).oninput = check;
  for (const b of view.querySelectorAll("[data-member]")) b.onclick = () => {
    member = b.dataset.member === "true";
    for (const o of view.querySelectorAll("[data-member]")) o.setAttribute("aria-pressed", String(o === b));
    check();
  };
  for (const b of view.querySelectorAll("[data-rating]")) b.onclick = () => {
    rating = rating === Number(b.dataset.rating) ? null : Number(b.dataset.rating);
    for (const o of view.querySelectorAll("[data-rating]")) o.setAttribute("aria-pressed", String(Number(o.dataset.rating) === rating));
    check();
  };
  document.getElementById("cp-go").onclick = async () => {
    const btn = document.getElementById("cp-go");
    btn.disabled = true; btn.textContent = "Saving…";
    const note = v("level-note");
    const { error } = await sb.rpc("create_my_account", {
      p_first_name: v("first"), p_last_name: v("last"), p_phone: v("phone") || null,
      p_is_member: member, p_adult_rating: rating, p_level_note: note || null,
    });
    if (error) { renderCompleteProfile(authFriendly(error)); return; }
    await boot();
  };
  wireExitFooter();
}

// AccountExitFooter: a way off every onboarding step that is not finishing it.
function exitFooter() {
  return `<div class="center" style="margin-top:28px">
      <button class="link underline" id="exit-signout">Sign out</button>
      <p class="caption" style="margin:0">Signs you out, you can finish later if needed</p>
      <button class="link danger" id="exit-delete">Delete my account</button>
      <p class="error" id="exit-error"></p>
    </div>`;
}
function wireExitFooter() {
  document.getElementById("exit-signout").onclick = signOut;
  document.getElementById("exit-delete").onclick = () => deleteAccount("exit-error");
}

async function signOut() {
  await sb.auth.signOut();
  Object.assign(S, { user: null, account: null, player: null, clinics: [], regs: [], loaded: false });
  location.hash = "";
  renderAuth();
}

// ProfileView / AccountExitFooter delete
async function deleteAccount(errorId) {
  const ok = await confirmDialog(
    "Delete your account? Your name, phone, email and card are removed and you are signed out. This can't be undone.",
    "Delete my account", "Keep my account");
  if (!ok) return;
  const { error } = await sb.functions.invoke("delete-account", { method: "POST" });
  if (error) { const el = document.getElementById(errorId); if (el) el.textContent = "Couldn't delete your account."; return; }
  await signOut();
}

// WaiverView
async function renderWaiver(error = "") {
  chrome({ title: "Waiver" });
  view.innerHTML = `<div class="placeholder"></div><div class="placeholder"></div>`;
  const { data, error: loadErr } = await sb.rpc("current_waiver");
  const w = (data || [])[0];
  if (loadErr || !w) {
    view.innerHTML = `<p class="error">${esc(failureLine(loadErr) || "Couldn't load the waiver.")}</p>
      <button class="btn primary" id="w-retry">Try again</button>${exitFooter()}`;
    document.getElementById("w-retry").onclick = () => renderWaiver();
    wireExitFooter();
    return;
  }
  const paragraphs = w.body.split("\n\n").map((p) => p.trim()).filter(Boolean).map((p) => {
    const heading = p.length < 60 && (/^[0-9]+ {2}/.test(p) || p === "Participant Acknowledgment" || p.startsWith("IMPORTANT NOTICE"));
    return heading ? `<h3>${esc(p)}</h3>` : `<p>${esc(p)}</p>`;
  }).join("");
  view.innerHTML = `
    <div class="waiver">
      <h2 class="display" style="font-size:1.5rem">${esc(w.title)}</h2>
      <p class="muted">${esc(w.organizer)}</p>
      ${paragraphs}
    </div>
    <div class="card stack">
      <label class="check"><input type="checkbox" id="w-agree"><span>I have read and agree to the Adult Tennis Participation Waiver and Release.</span></label>
      <label class="field">Full legal name<input type="text" id="w-name" autocomplete="name" placeholder="First and last name"></label>
      <p class="error" id="w-error">${esc(error)}</p>
      <button class="btn primary" id="w-sign" disabled>Agree and sign</button>
    </div>
    ${exitFooter()}`;
  const name = () => document.getElementById("w-name").value.trim();
  const check = () => {
    document.getElementById("w-sign").disabled =
      !(document.getElementById("w-agree").checked && name().length >= 3 && name().includes(" "));
  };
  document.getElementById("w-agree").onchange = check;
  document.getElementById("w-name").oninput = check;
  document.getElementById("w-sign").onclick = async () => {
    const btn = document.getElementById("w-sign");
    btn.disabled = true; btn.innerHTML = `<span class="spinner"></span>`;
    const { error: e } = await sb.rpc("accept_waiver", { p_version: w.version, p_legal_name: name(), p_app_version: "web" });
    if (!e) { S.waiver = true; go("#/home"); return; }
    const m = raw(e);
    if (m.includes("legal_name_required")) renderWaiver("Type your first and last name.");
    else if (m.includes("waiver_version_stale")) renderWaiver("The waiver was updated. Read it again and sign.");
    else if (m.includes("account_not_found") || m.includes("not_authenticated")) renderWaiver("Couldn't find your account. Sign out and sign in again.");
    else renderWaiver(failureLine(e) || "Couldn't save your signature.");
  };
  wireExitFooter();
}

// A clinic as a list row (ClinicRow on Home, ClinicCard on Clinics).
function clinicCard(c) {
  const reg = regFor(c.id);
  const p = priceFor(c);
  let foot = "";
  if (c.status === "canceled") foot = "";
  else if (!reg) {
    const d = door(c);
    if (d.kind === "register") foot = `<div class="open-line">Registration open</div>`;
    else if (d.kind === "opens") foot = `<div class="line">Registration opens ${esc(fmt(d.at, { month: "short", day: "numeric" }))}</div>`;
  }
  const status = c.status === "canceled" ? chip("canceled") : reg ? chip(reg.status) : "";
  return `<a class="card" href="#/clinic/${c.id}">
      <div class="row"><span class="title grow">${esc(c.name)}</span>${status}</div>
      <div class="line">${icon("calendar")}<span>${esc(dayLong(c.starts_at))} at ${esc(time(c.starts_at))}</span></div>
      ${p != null ? `<div class="line">${icon("ball")}<span>${esc(durationLine(c))}, ${esc(price(p))}</span></div>` : ""}
      ${foot}
    </a>`;
}

function icon(name) {
  const paths = {
    calendar: `<rect x="3" y="5" width="18" height="16" rx="2"/><path d="m3 10h18M8 3v4M16 3v4"/>`,
    clock: `<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>`,
    ball: `<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6c3.5 3.5 3.5 9.3 0 12.8M18.4 5.6c-3.5 3.5-3.5 9.3 0 12.8"/>`,
  };
  return `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true">${paths[name]}</svg>`;
}

const greeting = () => {
  const h = Number(fmt(new Date().toISOString(), { hour: "numeric", hour12: false }));
  return h < 12 ? "Good Morning" : h < 17 ? "Good Afternoon" : "Good Evening";
};

// HomeView
async function renderHome() {
  chrome({ tab: "home", bell: true });
  const name = S.player?.first_name || S.account?.first_name || "";
  view.innerHTML = `<h2 class="display center" style="margin-top:8px">${esc(greeting())}, ${esc(name)}!</h2>
    <p class="tagline center">Let's Play.</p><div id="home-body"><div class="placeholder"></div><div class="placeholder"></div></div>`;
  let loadError = "";
  try { await loadClinics(); } catch (e) { loadError = failureLine(e) || "Couldn't load clinics."; }
  const mine = S.clinics.filter((c) => regFor(c.id) && c.status !== "canceled");
  const open = S.clinics.filter((c) => !regFor(c.id) && isOpen(c));
  let html = loadError ? `<p class="error">${esc(loadError)}</p>` : "";
  if (mine.length) html += `<p class="section">My Clinics</p>` + mine.map(clinicCard).join("");
  if (mine.length < 2) {
    if (!(open.length === 0 && loadError)) {
      html += `<p class="section">Open for Registration</p>` +
        (open.length ? open.map(clinicCard).join("") : `<p class="muted">No clinics currently open for registration</p>`);
    }
  } else {
    html += `<a class="btn primary" href="#/clinics" style="margin-top:16px">View Open Clinics</a>`;
  }
  document.getElementById("home-body").innerHTML = html;
}

// ClinicsView: grouped by service week, Sunday to Saturday in New York.
async function renderClinics() {
  chrome({ title: "Clinics", tab: "clinics", bell: true });
  view.innerHTML = `<div class="placeholder"></div><div class="placeholder"></div><div class="placeholder"></div>`;
  try { await loadClinics(); } catch (e) {
    view.innerHTML = `<p class="error">${esc(failureLine(e) || "Couldn't load clinics.")}</p>`; return;
  }
  if (!S.clinics.length) { view.innerHTML = `<p class="muted center">No clinics scheduled yet.</p>`; return; }
  const thisWeek = serviceWeekStart(new Date());
  const groups = new Map();
  for (const c of S.clinics) {
    const label = weekLabel(serviceWeekStart(new Date(c.starts_at)), thisWeek);
    if (!groups.has(label)) groups.set(label, []);
    groups.get(label).push(c);
  }
  view.innerHTML = [...groups].map(([label, list]) =>
    `<p class="section">${esc(label)}</p>${list.map(clinicCard).join("")}`).join("");
}

// ClinicDetailView: one clinic and the one action for this player's state.
async function renderClinic(id, notice = "") {
  chrome({ back: true, bell: true, mark: true, tab: "clinics" });
  view.innerHTML = `<div class="placeholder"></div><div class="placeholder"></div>`;
  let c, messages = [];
  try {
    const [one, regs, msgs] = await Promise.all([
      sb.from("clinics_public").select("*").eq("id", id).maybeSingle(),
      sb.from("my_registrations").select("*"),
      sb.from("my_clinic_messages").select("*").eq("clinic_id", id).order("sent_at"),
    ]);
    if (one.error) throw one.error;
    if (regs.error) throw regs.error;
    c = one.data; S.regs = regs.data || []; messages = msgs.data || [];
  } catch (e) {
    view.innerHTML = `<p class="error">${esc(failureLine(e) || "Couldn't load this clinic.")}</p>`; return;
  }
  if (!c) { view.innerHTML = `<p class="muted">That just changed. Here's the latest.</p>`; return; }
  const reg = regFor(c.id);
  const canceled = c.status === "canceled";
  const p = priceFor(c);
  const hasPlayer = !!S.player;
  const started = now() >= t(c.starts_at);
  const d = door(c);

  let action = "";
  if (canceled || !hasPlayer) action = "";
  else if (reg) {
    if (reg.status === "in" && !started) action = `<button class="btn danger" id="a-cancel">Cancel Registration</button>`;
    else if (reg.status === "pool") action = `<button class="btn danger" id="a-leave">Leave Player Pool</button>`;
    else if (reg.status === "response_needed") action = `<div class="two">
        <button class="btn primary" id="a-accept">Accept</button>
        <button class="btn secondary" id="a-decline">Decline</button></div>`;
  } else if (d.kind === "register") action = `<button class="btn primary" id="a-register">Register</button>`;
  else if (d.kind === "opens") action = `<p class="muted center card">Registration opens ${esc(opensAt(d.at))}</p>`;
  else if (d.kind === "askTara") action = `<div class="center stack" id="late">
        <p class="emph" style="margin:0">Registration has closed for this clinic.</p>
        <p class="muted" style="margin:0">You can still ask Tara to fit you in.</p>
        <button class="btn primary" id="a-late">Message Tara</button></div>`;

  // ClinicNote.offered
  const noteOffered = hasPlayer && !canceled && !started &&
    (reg ? ["in", "pool", "response_needed"].includes(reg.status) : d.kind === "register");
  const saved = reg?.player_note || "";
  const noteArea = noteOffered ? `<div class="stack" style="gap:6px">
      <label for="note">Note for Tara (optional)</label>
      <textarea id="note" maxlength="${NOTE_LIMIT}" placeholder="please put me on court with my friend Jane">${esc(saved)}</textarea>
      <span class="caption">Only Tara sees this</span>
      ${reg ? `<button class="btn quiet" id="note-save" hidden>Save</button>` : ""}
    </div>` : "";
  const calendar = reg?.status === "in" && !started && !canceled
    ? `<button class="btn quiet" id="a-ics">Add to Calendar</button>` : "";

  view.innerHTML = `
    <h2 class="display">${esc(c.name)}</h2>
    ${canceled ? chip("canceled") : reg ? chip(reg.status) : ""}
    ${canceled ? `<p class="banner" style="margin-top:16px">This clinic has been canceled.</p>` : ""}
    <div class="card" style="margin-top:16px">
      <div class="line">${icon("calendar")}<span>${esc(dayFull(c.starts_at))}</span></div>
      <div class="line">${icon("clock")}<span>${esc(time(c.starts_at))} – ${esc(time(c.ends_at))}</span></div>
      ${p != null ? `<div class="line">${icon("ball")}<span>${esc(durationLine(c))}, ${esc(price(p))}</span></div>` : ""}
      ${c.description ? `<hr style="border:0;border-top:1px solid var(--fxe-hairline);margin:14px 0"><p style="margin:0">${esc(c.description)}</p>` : ""}
    </div>
    ${messages.length ? `<p class="section">FROM TARA</p>${messages.map((m) => `<div class="card" style="border-radius:var(--fxe-radius-md)">
        <p style="margin:0">${esc(m.body)}</p><span class="caption">${esc(fmt(m.sent_at, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }))}</span></div>`).join("")}` : ""}
    ${notice ? `<p class="notice">${esc(notice)}</p>` : ""}
    <div class="stack" style="margin-top:16px">${noteArea}${action}${calendar}</div>
    <div id="late-cancel"></div>`;

  const run = async (work) => {
    for (const b of view.querySelectorAll("button")) b.disabled = true;
    const { error } = await work();
    if (!error) { await renderClinic(id); return; }
    const out = actionOutcome(error);
    if (out.reopens === "waiver") { S.waiver = false; await renderWaiver(); return; }
    if (out.reopens === "card") { await refreshAccount(); renderCardStep(id, out.notice); return; }
    await renderClinic(id, out.notice || "");
  };
  const noteValue = () => {
    const el = document.getElementById("note");
    const v = el ? el.value.replace(/\n/g, " ").trim() : "";
    return v ? v.slice(0, NOTE_LIMIT) : null;
  };
  const on = (bid, fn) => { const b = document.getElementById(bid); if (b) b.onclick = fn; };

  on("a-register", () => run(() => sb.rpc("register_for_clinic", { p_clinic: c.id, p_player: S.player.id, p_note: noteValue() }).single()));
  on("a-accept", () => run(() => sb.rpc("respond_to_invitation", { p_registration: reg.id, p_accept: true })));
  on("a-decline", () => run(() => sb.rpc("respond_to_invitation", { p_registration: reg.id, p_accept: false })));
  on("a-leave", async () => {
    if (await confirmDialog("Leave Player Pool", "Yes, leave the pool", "Keep my spot"))
      run(() => sb.rpc("leave_pool", { p_registration: reg.id }));
  });
  on("a-cancel", async () => {
    const { data: hours } = await sb.rpc("cancel_cutoff_hours");
    const cutoff = typeof hours === "number" ? hours : 3;
    const inside = () => t(c.starts_at) - now() < cutoff * 3600 * 1000;
    if (inside()) { lateCancelPanel(); return; }
    if (!(await confirmDialog("Cancel Registration", "Yes, cancel my spot", "Keep my spot"))) return;
    // The clock again at the confirm: late now means the note, never a silent fee.
    if (inside()) { lateCancelPanel(); return; }
    run(() => sb.rpc("cancel_registration", { p_registration: reg.id, p_note: null }));
  });
  on("a-late", async () => {
    const btn = document.getElementById("a-late"); btn.disabled = true;
    const { error } = await sb.rpc("request_late_spot", { p_clinic: c.id, p_player: S.player.id, p_message: null });
    if (error && !/23505|duplicate key/.test(raw(error))) { renderClinic(id, actionOutcome(error).notice); return; }
    document.getElementById("late").innerHTML = `<p class="emph" style="margin:0">Tara has your message.</p>
      <p class="muted" style="margin:0">She will let you know as soon as possible if there is room in this clinic</p>`;
  });
  on("a-ics", () => downloadIcs(c));
  const noteEl = document.getElementById("note");
  if (noteEl && reg) noteEl.oninput = () => {
    document.getElementById("note-save").hidden = (noteValue() || "") === (saved.trim() || "");
  };
  on("note-save", () => run(() => sb.rpc("set_my_registration_note", { p_registration: reg.id, p_note: noteValue() || "" })));

  // LateCancelSheet: Tara's sentence, verbatim, and an optional note.
  function lateCancelPanel() {
    const box = document.getElementById("late-cancel");
    box.innerHTML = `<div class="card stack" style="margin-top:16px">
        <p class="emph" style="margin:0">Cancel Registration</p>
        <p style="margin:0">This cancellation is within 3 hours of clinic and the full clinic fee will apply. If an emergency, please leave a note below.</p>
        <textarea id="lc-note" placeholder="Note for Tara (optional)" aria-label="Note for Tara (optional)"></textarea>
        <button class="btn solid-danger" id="lc-go">Cancel my spot</button>
        <button class="btn quiet" id="lc-keep">Keep my spot</button>
      </div>`;
    document.getElementById("lc-note").focus();
    document.getElementById("lc-keep").onclick = () => { box.innerHTML = ""; };
    document.getElementById("lc-go").onclick = () =>
      run(() => sb.rpc("cancel_registration", { p_registration: reg.id, p_note: document.getElementById("lc-note").value.trim() || null }));
  }
}

// Add to Calendar: the name and the times only, nothing about where
// (ClinicCalendarEvent, hard rule 1). An .ics opens the phone's calendar.
function downloadIcs(c) {
  const stamp = (iso) => new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const text = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//FXE Tennis//EN", "BEGIN:VEVENT",
    `UID:${c.id}@fxetennis`, `DTSTAMP:${stamp(new Date().toISOString())}`,
    `DTSTART:${stamp(c.starts_at)}`, `DTEND:${stamp(c.ends_at)}`,
    `SUMMARY:${c.name.replace(/[,;\\]/g, (m) => "\\" + m)}`, "END:VEVENT", "END:VCALENDAR"].join("\r\n");
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([text], { type: "text/calendar" }));
  a.download = "clinic.ics";
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

// CardStepView: opened when Register or Accept is refused for the card.
function renderCardStep(returnTo = null, notice = "") {
  chrome({ title: "Add a card", back: true });
  view.innerHTML = `${notice ? `<p class="notice">${esc(notice)}</p>` : ""}<div id="card-area"></div>
    ${returnTo ? `<a class="btn quiet" style="margin-top:16px" href="#/clinic/${returnTo}">Close</a>` : ""}`;
  mountCardOnFile(document.getElementById("card-area"));
}

// CardOnFileView, with Stripe's Payment Element in place of PaymentSheet.
// The card number goes to Stripe only; the webhook writes the summary.
function mountCardOnFile(el, afterRedirect = false) {
  const a = S.account || {};
  const hasCard = !!a.card_last4;
  el.innerHTML = `<div class="stack" style="gap:8px">
      <p class="emph" style="margin:0">Payment method</p>
      <p class="caption" style="margin:0">Your card will only be charged after a clinic you attended, a late cancellation or no-show. Cancel at least 3 hours before clinic and you will not be charged.</p>
      <label class="check"><input type="checkbox" id="c-perm" ${S.cardConsent ? "checked" : ""}><span>${CARD_CONSENT}</span></label>
      <div class="card row" style="border-radius:var(--fxe-radius-md)">
        <div class="grow"><div>${hasCard ? `•••• ${esc(a.card_last4)}` : `<span class="muted">No card on file</span>`}</div>
          ${hasCard && a.card_declined_at ? `<div class="error" style="font-size:var(--fxe-text-caption)">${esc(declineLine(a.card_decline_code))}</div>` : ""}</div>
        <button class="link" id="c-add">${hasCard ? "Change card" : "Add a card"}</button>
      </div>
      <div id="stripe-element"></div>
      <p class="caption" id="c-note"></p>
      <button class="link" id="c-refresh" hidden>Refresh</button>
    </div>`;
  const perm = document.getElementById("c-perm");
  const add = document.getElementById("c-add");
  const note = document.getElementById("c-note");
  const sync = () => { add.disabled = !perm.checked; add.style.opacity = perm.checked ? 1 : 0.4; };
  perm.onchange = sync; sync();

  const waitForCard = async () => {
    note.textContent = "Saved. It may take a moment to show here.";
    for (let i = 0; i < 15; i++) {          // CardSavePoll: every 2 s, about 30 s
      await new Promise((r) => setTimeout(r, 2000));
      if (await refreshAccount().catch(() => false)) { mountCardOnFile(el); document.getElementById("c-note").textContent = "Saved."; return; }
    }
    document.getElementById("c-refresh").hidden = false;
  };
  document.getElementById("c-refresh").onclick = async () => {
    if (await refreshAccount().catch(() => false)) { mountCardOnFile(el); document.getElementById("c-note").textContent = "Saved."; }
  };
  if (afterRedirect) waitForCard();

  add.onclick = async () => {
    if (!perm.checked) return;
    add.disabled = true; note.textContent = "";
    if (!S.cardConsent) {
      const { error } = await sb.rpc("record_card_consent", { p_app_version: "web" });
      if (error) { note.textContent = "That didn't work. Check your connection and try again."; sync(); return; }
      S.cardConsent = true;
    }
    const { data, error } = await sb.functions.invoke("stripe-setup-intent", { method: "POST" });
    if (error) {
      const status = error.context?.status;
      const body = await error.context?.text?.().catch(() => "") ?? "";
      if (status === 503 || body.includes("stripe_not_configured")) note.textContent = "Cards aren't set up yet.";
      else if (status === 409 || body.includes("card_consent_required")) { S.cardConsent = false; note.textContent = "Check the box to continue"; }
      else note.textContent = "That didn't work. Check your connection and try again.";
      sync(); return;
    }
    if (!window.Stripe) { note.textContent = "That didn't work. Check your connection and try again."; sync(); return; }
    const stripe = window.Stripe(data.publishableKey);
    const elements = stripe.elements({ clientSecret: data.setupIntentClientSecret, appearance: { theme: "stripe", variables: { colorPrimary: "#0A1B3D", borderRadius: "12px" } } });
    const payment = elements.create("payment");
    const box = document.getElementById("stripe-element");
    box.innerHTML = `<div id="pe"></div><button class="btn primary" id="c-save" style="margin-top:14px">Save</button>`;
    payment.mount("#pe");
    document.getElementById("c-save").onclick = async () => {
      const save = document.getElementById("c-save");
      save.disabled = true; save.innerHTML = `<span class="spinner"></span>`;
      // A bank's check (3-D Secure) may leave the page; it comes back here.
      const back = `${location.origin}${location.pathname}#/card-saved`;
      const { error: e } = await stripe.confirmSetup({ elements, confirmParams: { return_url: back }, redirect: "if_required" });
      if (e) { save.disabled = false; save.textContent = "Save"; note.textContent = `That didn't work. ${e.message || ""}`.trim(); return; }
      box.innerHTML = "";
      waitForCard();
    };
  };
}

// MyClinicsView: upcoming, then the past.
async function renderMyClinics() {
  chrome({ title: "My Clinics", back: true, tab: "profile" });
  view.innerHTML = `<div class="placeholder"></div>`;
  let past = [];
  try {
    await loadClinics();
    const r = await sb.from("my_past_clinics").select("*").order("starts_at", { ascending: false }).limit(40);
    if (r.error) throw r.error;
    past = r.data || [];
  } catch (e) {
    view.innerHTML = `<p class="error">${esc(failureLine(e) || "Couldn't load clinics.")}</p>`; return;
  }
  const mine = S.clinics.filter((c) => regFor(c.id));
  const outcome = (p) => {
    if (p.clinic_canceled) return "Canceled";
    if (p.status === "canceled") return p.late_cancel ? "Canceled late" : "Canceled";
    if (p.no_show) return "No-show";
    if (p.price_cents_charged != null) return `Played, ${price(p.price_cents_charged)}`;
    return "Played";
  };
  view.innerHTML = (mine.length ? mine.map(clinicCard).join("")
      : `<p class="muted center">You're not registered for any clinics this week</p>
         <a class="btn primary" href="#/clinics">View Open Clinics</a>`) +
    (past.length ? `<p class="section">PAST</p><div class="card">${past.map((p) => `<div class="list-row">
        <div class="grow"><div class="emph">${esc(p.name)}</div><div class="caption">${esc(dayShort(p.starts_at))}</div></div>
        <span class="chip plain" style="color:var(${outcome(p).startsWith("Played") ? "--fxe-status-in-ink" : "--fxe-status-canceled-ink"})">${esc(outcome(p))}</span>
      </div>`).join("")}</div>` : "");
}

// NotificationsView
async function renderNotifications(error = "") {
  chrome({ title: "Notifications", back: true });
  const { data, error: e } = await sb.from("notifications")
    .select("id,type,entity_type,entity_id,body,created_at,read_at").order("created_at", { ascending: false }).limit(50);
  if (e) { view.innerHTML = `<p class="error">${esc(failureLine(e) || "Couldn't load notifications. Pull to try again.")}</p>`; return; }
  const items = data || [];
  if (!items.length) { view.innerHTML = `<p class="muted center">No notifications yet</p>`; return; }
  const unread = items.some((n) => !n.read_at);
  view.innerHTML = `${unread ? `<p style="text-align:right;margin:0"><button class="link" id="n-all">Mark all read</button></p>` : ""}
    ${error ? `<p class="error">${esc(error)}</p>` : ""}
    <div class="card">${items.map((n) => `<button class="list-row" data-n="${n.id}" style="width:100%;background:none;border:0;text-align:left;cursor:pointer;font:inherit"
        aria-label="${n.read_at ? "" : "Unread. "}${esc(n.body)}">
        <span style="width:9px;height:9px;border-radius:50%;flex:none;background:${n.read_at ? "transparent" : "var(--fxe-court)"}"></span>
        <span class="grow"><span style="display:block;${n.read_at ? "" : "font-weight:600"}">${esc(n.body)}</span>
        <span class="caption">${esc(fmt(n.created_at, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }))}</span></span>
      </button>`).join("")}</div>`;
  const all = document.getElementById("n-all");
  if (all) all.onclick = async () => {
    const { error: me } = await sb.from("notifications").update({ read_at: new Date().toISOString() }, { returning: "minimal" }).is("read_at", null);
    renderNotifications(me ? "That didn't save. Check your connection and try again." : "");
  };
  for (const b of view.querySelectorAll("[data-n]")) b.onclick = async () => {
    const n = items.find((x) => x.id === b.dataset.n);
    if (!n.read_at) await sb.from("notifications").update({ read_at: new Date().toISOString() }, { returning: "minimal" }).eq("id", n.id);
    // NotificationRouter: a registration points at its clinic.
    let clinicId = null;
    if (n.entity_type === "clinic") clinicId = n.entity_id;
    else if (n.entity_type === "registration") {
      const { data: r } = await sb.from("my_registrations").select("clinic_id").eq("id", n.entity_id).maybeSingle();
      clinicId = r?.clinic_id || null;
    }
    if (clinicId) go(`#/clinic/${clinicId}`); else renderNotifications();
  };
}

// ProfileView
function renderProfile() {
  chrome({ title: "Profile", tab: "profile", bell: true });
  const a = S.account || {}, p = S.player;
  const name = p ? `${p.first_name} ${p.last_name}` : `${a.first_name || ""} ${a.last_name || ""}`;
  view.innerHTML = `
    <h2 class="display">${esc(name)}</h2>
    ${p ? `<p class="muted" style="margin:0 0 16px">${p.is_member ? "FXE Member" : "Non-member"}</p>` : ""}
    <div class="card stack" style="gap:12px">
      <div><div class="caption">Email</div><div>${esc(a.email || S.user?.email || "")}</div></div>
      <div><div class="caption">Phone</div><div>${esc(a.phone || "")}</div></div>
      ${p ? `<div><div class="caption">Rating</div><div>${p.adult_rating != null ? esc(ratingLabel(p.adult_rating)) : ""}</div></div>` : ""}
    </div>
    ${S.paymentsEnabled && p ? `<div class="card" id="card-area"></div>` : ""}
    <div class="stack" style="margin-top:12px">
      ${p ? `<a class="btn quiet" href="#/my-clinics">My Clinics</a>` : ""}
      <button class="btn quiet" id="p-cal">Subscribe in Calendar</button>
      <p class="error" id="p-cal-error"></p>
      ${p ? `<a class="btn primary" href="#/edit">Edit details</a>` : ""}
    </div>
    <div class="center stack" style="margin-top:20px;gap:4px">
      <button class="link underline" id="p-signout">Sign Out</button>
      <a class="link" href="${CONTACT}">Contact Tara</a>
      <a class="link" href="${PRIVACY}">Privacy Policy</a>
      <button class="link danger" id="p-delete">Delete my account</button>
      <p class="error" id="p-error"></p>
    </div>`;
  if (S.paymentsEnabled && p) mountCardOnFile(document.getElementById("card-area"));
  document.getElementById("p-signout").onclick = async () => {
    if (await confirmDialog("Sign Out", "Sign Out", "Cancel")) signOut();
  };
  document.getElementById("p-delete").onclick = () => deleteAccount("p-error");
  // Subscribe in Calendar: the same feed the app hands iOS. Android's calendar
  // is Google Calendar, which subscribes to a feed by its address.
  document.getElementById("p-cal").onclick = async () => {
    const { data: token, error } = await sb.rpc("my_calendar_feed_token");
    if (error || !token) { document.getElementById("p-cal-error").textContent = failureLine(error) || "Couldn't load your calendar link."; return; }
    const host = new URL(CONFIG.url).host;
    const webcal = `webcal://${host}/functions/v1/calendar-feed?t=${token}`;
    const android = /android/i.test(navigator.userAgent);
    location.href = android ? `https://calendar.google.com/calendar/r?cid=${encodeURIComponent(webcal)}` : webcal;
  };
}

// EditProfileView
function renderEdit(error = "") {
  chrome({ title: "Edit details", back: true });
  const a = S.account, p = S.player;
  let rating = p.adult_rating;
  view.innerHTML = `<div class="stack">
      <label class="field">First Name<input type="text" id="e-first" value="${esc(p.first_name)}" autocomplete="given-name"></label>
      <label class="field">Last Name<input type="text" id="e-last" value="${esc(p.last_name)}" autocomplete="family-name"></label>
      <label class="field">Phone<input type="tel" id="e-phone" value="${esc(a.phone || "")}" autocomplete="tel"></label>
      <p class="emph" style="margin:12px 0 0">Your tennis rating</p>
      <div class="pills">${RATINGS.map((r) =>
        `<button type="button" class="pill" data-rating="${r}" aria-pressed="${Number(rating) === r}" aria-label="USTA ${ratingLabel(r)}">${ratingLabel(r)}</button>`).join("")}</div>
      <p class="emph" style="margin:12px 0 0">Note for Tara (optional)</p>
      <textarea id="e-note" maxlength="${NOTE_LIMIT}" placeholder="Just coming back from a back injury - probably a low 3.5">${esc(p.level_note || "")}</textarea>
      <p class="caption" style="margin:0">Only Tara sees this.</p>
      <!-- Membership is Tara's (decision 5); no caption (Tara, 2026-09-28, decision 0024). -->
      <div class="card" style="margin:8px 0 0;border-radius:var(--fxe-radius-md)">${p.is_member ? "FXE Member" : "Non-member"}</div>
      <p class="error">${esc(error)}</p>
      <button class="btn primary" id="e-save">Save</button>
      <a class="btn quiet" href="#/profile">Cancel</a>
    </div>`;
  for (const b of view.querySelectorAll("[data-rating]")) b.onclick = () => {
    rating = Number(b.dataset.rating);
    for (const o of view.querySelectorAll("[data-rating]")) o.setAttribute("aria-pressed", String(Number(o.dataset.rating) === rating));
  };
  document.getElementById("e-save").onclick = async () => {
    const v = (id) => document.getElementById(id).value.trim();
    if (!v("e-first") || !v("e-last")) { renderEdit("Add your first and last name."); return; }
    const btn = document.getElementById("e-save"); btn.disabled = true; btn.textContent = "Saving…";
    const one = await sb.from("accounts").update({ first_name: v("e-first"), last_name: v("e-last"), phone: v("e-phone") || null }).eq("id", a.id);
    const two = one.error ? one : await sb.from("players").update({
      first_name: v("e-first"), last_name: v("e-last"), adult_rating: rating, level_note: v("e-note") || null,
    }).eq("id", p.id);
    if (one.error || two.error) { renderEdit("That didn't save. Check your connection and try again."); return; }
    await loadProfile();
    go("#/profile");
  };
}

// --------------------------------------------------------------- router ----

async function route() {
  if (!S.user) return;
  if (S.waiver === false && !skipsPlayerSteps()) { renderWaiver(); return; }
  const [, page, arg] = (location.hash || "#/home").split("/");
  window.scrollTo(0, 0);
  switch (page) {
    case "clinics": return renderClinics();
    case "clinic": return renderClinic(arg);
    case "profile": return renderProfile();
    case "my-clinics": return renderMyClinics();
    case "notifications": return renderNotifications();
    case "edit": return S.player ? renderEdit() : renderProfile();
    case "card": return renderCardStep();
    case "card-saved": {
      chrome({ title: "Add a card", back: true });
      view.innerHTML = `<div id="card-area"></div>`;
      return mountCardOnFile(document.getElementById("card-area"), true);
    }
    default: return renderHome();
  }
}
window.addEventListener("hashchange", route);
// Coming back to the tab shows what changed meanwhile (reloadOnForeground).
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && S.user && S.waiver !== false) route();
});

async function boot() {
  view.innerHTML = `<div class="center" style="padding:48px"><span class="spinner"></span></div>`;
  let phase;
  try { phase = await loadProfile(); } catch (e) {
    chrome({});
    view.innerHTML = `<p class="error">${esc(failureLine(e) || "Something went wrong. Please try again.")}</p>
      <button class="btn primary" id="retry">Try again</button>`;
    document.getElementById("retry").onclick = boot;
    return;
  }
  if (phase === "signedOut") return renderAuth();
  if (phase === "needsProfile") return renderCompleteProfile();
  route();
}

if (ENV === "local") window.__fxe = { sb, S };
boot();
