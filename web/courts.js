// Tara's Courts tab (court reservations step 3, docs/courts/plan.md; decision
// 0058). A day of all five courts: members' bookings, clinics holding their
// courts, and her blocks, from admin_court_day. She books for anyone, cancels,
// blocks a court or every court, and sets the rules.
//
// The server decides everything: what a clinic holds, whether a court is
// taken, who may book. This page only draws admin_court_day and calls the
// admin_* functions; every action reloads the day rather than patching it.
//
// A block never cancels anyone (admin_block_courts returns the bookings under
// it): the dialog lists them so she can call or cancel each one herself. A
// clinic published, or a court assigned, over a booking is not refused by the
// server either (decision 0058, the auditor's low item), so the day warns her
// about every overlap it can see.

import { nyInstant } from "./week.js";

const NY = "America/New_York";
const MIN = 60_000;
const SLOT = 15;                     // minutes per grid row
const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

// "YYYY-MM-DD" of an instant on New York's calendar (en-CA writes it so).
export const nyDate = (d = new Date()) => d.toLocaleDateString("en-CA", { timeZone: NY });
// A calendar date moved by n days, as text, with no zone involved.
export const addDays = (ymd, n) => {
  const [y, m, d] = ymd.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
};
const weekdayOf = (ymd) => { const [y, m, d] = ymd.split("-").map(Number); return new Date(Date.UTC(y, m - 1, d)).getUTCDay(); };
// The instant New York's clock reads ymd hh:mi.
export const nyAt = (ymd, hhmm) => {
  const [y, m, d] = ymd.split("-").map(Number);
  const [hh, mi] = hhmm.split(":").map(Number);
  return nyInstant(y, m, d, hh, mi);
};
export const fmtTime = (iso) => new Date(iso).toLocaleTimeString("en-US",
  { timeZone: NY, hour: "numeric", minute: "2-digit" });
const fmtDay = (ymd) => new Date(nyAt(ymd, "12:00")).toLocaleDateString("en-US",
  { timeZone: NY, weekday: "long", month: "long", day: "numeric" });
const hhmm = (iso) => new Date(iso).toLocaleTimeString("en-GB",
  { timeZone: NY, hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
const range = (t) => `${fmtTime(t.starts_at)} to ${fmtTime(t.ends_at)}`;
const overlaps = (a, b) => new Date(a.starts_at) < new Date(b.ends_at) && new Date(b.starts_at) < new Date(a.ends_at);
const courtsText = (nums) => nums.length === 1 ? `Court ${nums[0]}` : `Courts ${nums.join(", ")}`;

// Every overlap on a court that involves a booking: a clinic or a block put
// over it, or (should the constraint ever be bypassed) another booking.
export function overlapsOnDay(day) {
  const out = [];
  for (const c of day.courts || []) {
    const items = c.taken || [];
    for (const b of items.filter(t => t.kind === "booking")) {
      for (const o of items) {
        if (o === b || !overlaps(b, o)) continue;
        if (o.kind === "booking" && o.id < b.id) continue;   // each pair once
        out.push({ court: c.number, booking: b, other: o });
      }
    }
  }
  return out;
}

// One entry per thing on the day: a block over every court or a clinic on
// three courts is one row with its courts listed, not five rows.
export function dayList(day) {
  const byId = new Map();
  for (const c of day.courts || []) for (const t of c.taken || []) {
    const key = `${t.kind}:${t.id}`;
    if (!byId.has(key)) byId.set(key, { ...t, courts: [] });
    byId.get(key).courts.push(c.number);
  }
  return [...byId.values()].sort((a, b) =>
    new Date(a.starts_at) - new Date(b.starts_at) || a.courts[0] - b.courts[0]);
}

const COURT_ERRORS = [
  ["court_taken", "That court is taken then. Pick another court or time."],
  ["no_such_court", "That court is closed or doesn't exist."],
  ["no_such_account", "Couldn't find that player's account."],
  ["bad_length", "The end has to be after the start."],
  ["bad_block", "A block needs a reason, and its end after its start."],
  ["not_cancelable", "That booking is already canceled."],
  ["not_found", "That block is already removed."],
  ["bad_hours", "Closing has to be after opening."],
  ["unknown_setting", "One of the rules isn't one the server knows."],
  ["bad_setting", "One of the rules isn't valid. Check the numbers."],
  ["bad_day", "Pick a day."],
  ["courts_live_locked", "Court booking for members can't be turned on from here yet."],
];

export function wireCourts(sb, { $, esc, friendly, note }) {
  const words = (e) => {
    const m = (e?.message || String(e)).toLowerCase();
    const hit = COURT_ERRORS.find(([code]) => m.includes(code));
    return hit ? hit[1] : friendly(e);
  };
  let day = nyDate();
  let current = null;          // the last admin_court_day answer
  let settings = {};           // app_settings court keys, as text
  let gen = 0;

  async function readSettings() {
    const { data, error } = await sb.from("app_settings").select("key,value")
      .in("key", ["courts_live", "court_members_only", "court_lengths", "court_start_step",
                  "court_advance_days", "court_day_opens_at", "court_max_per_day",
                  "court_max_upcoming", "court_players_per_court"]);
    if (error) throw error;
    settings = Object.fromEntries((data || []).map(r => [r.key, r.value]));
    return settings;
  }

  async function load() {
    const mine = ++gen;
    $("ct-day").value = day;
    $("ct-title").textContent = fmtDay(day);
    note($("ct-msg"), "");
    const [{ data, error }] = await Promise.all([
      sb.rpc("admin_court_day", { p_day: day }),
      readSettings().catch(() => {}),
    ]);
    if (mine !== gen) return;      // she moved to another day meanwhile
    if (error) { $("ct-grid").innerHTML = ""; $("ct-list").innerHTML = ""; return note($("ct-msg"), words(error)); }
    current = data;
    drawLive(data.live);
    drawWarnings(data);
    drawGrid(data);
    drawList(data);
  }

  function drawLive(live) {
    $("ct-live").innerHTML = live
      ? `<span class="chip in">On</span> <span>Members can book courts.</span>`
      : `<span class="chip pool">Off</span> <span>Off for members. Court booking is in testing: only you, and the testers in Court rules on the TestFlight app, can book.</span>`;
  }

  function drawWarnings(d) {
    const list = overlapsOnDay(d);
    $("ct-warn").classList.toggle("hide", !list.length);
    $("ct-warn").innerHTML = list.length ? `<div class="name">Check these bookings</div>` + list.map(({ court, booking, other }) => {
      const what = other.kind === "clinic" ? `the clinic ${esc(other.label)}`
        : other.kind === "block" ? `your block (${esc(other.label)})` : `${esc(other.label)}'s booking`;
      return `<div class="row" data-overlap="${booking.id}">
        <span class="grow">${esc(booking.label)}, Court ${court}, ${range(booking)}, overlaps ${what}. Call them or cancel the booking.</span>
        <button class="small danger" data-ct-cancel="${booking.id}" data-name="${esc(booking.label)}" data-when="${esc(`Court ${court}, ${range(booking)}`)}">Cancel booking</button>
      </div>`;
    }).join("") : "";
  }

  function drawGrid(d) {
    const grid = $("ct-grid");
    if (!d.opens_at || !d.closes_at) { grid.innerHTML = `<p class="muted">No court hours for this day.</p>`; return; }
    const open = new Date(d.opens_at).getTime(), close = new Date(d.closes_at).getTime();
    const rows = Math.max(1, Math.round((close - open) / (SLOT * MIN)));
    const rowOf = (iso, up) => {
      const r = (new Date(iso).getTime() - open) / (SLOT * MIN);
      return 2 + Math.min(rows, Math.max(0, up ? Math.ceil(r) : Math.floor(r)));
    };
    const cells = [`<div class="ct-head" style="grid-column:1;grid-row:1"><span class="sr-only">Time</span></div>`];
    d.courts.forEach((c, i) => {
      cells.push(`<div class="ct-head" style="grid-column:${i + 2};grid-row:1">${esc(c.name)}${c.is_active ? "" : " (closed)"}</div>`);
      cells.push(`<div class="ct-col${c.is_active ? "" : " closed"}" style="grid-column:${i + 2};grid-row:2 / ${rows + 2}"></div>`);
    });
    for (let t = open, r = 2; t < close; t += 60 * MIN) {
      const span = Math.min(60 / SLOT, rows + 2 - r);
      cells.push(`<div class="ct-time" style="grid-column:1;grid-row:${r} / span ${span}">${fmtTime(new Date(t).toISOString())}</div>`);
      r += 60 / SLOT;
    }
    d.courts.forEach((c, i) => {
      // Two lanes, so a clinic or a block over a booking shows both, side by side.
      const items = [...(c.taken || [])].sort((a, b) => new Date(a.starts_at) - new Date(b.starts_at));
      for (const t of items) {
        if (new Date(t.ends_at).getTime() <= open || new Date(t.starts_at).getTime() >= close) continue;
        const clash = items.some(o => o !== t && overlaps(o, t));
        const lane = clash && items.findIndex(o => o !== t && overlaps(o, t)) < items.indexOf(t) ? 1 : 0;
        const kind = t.kind === "clinic" ? "Clinic" : t.kind === "block" ? "Blocked" : "Booked";
        const text = t.label;
        cells.push(`<div class="ct-item ${t.kind}${clash ? " clash" : ""}${clash ? (lane ? " lane1" : " lane0") : ""}"
            style="grid-column:${i + 2};grid-row:${rowOf(t.starts_at, false)} / ${rowOf(t.ends_at, true)}"
            data-ct-item="${t.kind}:${t.id}" title="${esc(`${kind}: ${text}, ${range(t)}`)}">
          <span class="ct-kind">${kind}</span> <span class="ct-label">${esc(text)}</span>
          <span class="ct-when">${range(t)}</span>
        </div>`);
      }
    });
    grid.style.gridTemplateRows = `32px repeat(${rows}, 14px)`;
    grid.innerHTML = cells.join("");
    grid.setAttribute("aria-label", `Courts on ${fmtDay(day)}, ${fmtTime(d.opens_at)} to ${fmtTime(d.closes_at)}`);
  }

  function drawList(d) {
    const items = dayList(d);
    $("ct-list").innerHTML = items.length ? items.map(t => {
      const where = courtsText(t.courts);
      if (t.kind === "booking") return `<div class="row" data-ct-row="booking:${t.id}">
          <span class="grow"><span class="name">${esc(t.label)}</span> <span class="chip in">Booked</span><br>
          <span class="muted">${where}, ${range(t)}${t.made_by_admin ? ", booked by you" : ""}</span>
          ${t.playing_with ? `<br><span class="muted">Playing with: ${esc(t.playing_with)}</span>` : ""}
          ${t.admin_note ? `<br><span class="player-note">Your note: ${esc(t.admin_note)}</span>` : ""}</span>
          <button class="small danger" data-ct-cancel="${t.id}" data-name="${esc(t.label)}" data-when="${esc(`${where}, ${range(t)}`)}">Cancel booking</button>
        </div>`;
      if (t.kind === "block") return `<div class="row" data-ct-row="block:${t.id}">
          <span class="grow"><span class="name">${esc(t.label)}</span> <span class="chip done">Blocked</span><br>
          <span class="muted">${where}, ${range(t)}</span></span>
          <button class="small" data-ct-unblock="${t.id}" data-when="${esc(`${where}, ${range(t)}`)}">Remove block</button>
        </div>`;
      return `<div class="row" data-ct-row="clinic:${t.id}">
          <span class="grow"><span class="name">${esc(t.label)}</span> <span class="chip resp">Clinic</span><br>
          <span class="muted">${where}, ${range(t)}. Change it on This week.</span></span>
        </div>`;
    }).join("") : `<p class="muted">Nothing on the courts this day.</p>`;
  }

  // ---------------------------------------------------- moving between days
  $("ct-day").addEventListener("change", () => { if ($("ct-day").value) { day = $("ct-day").value; load(); } });
  $("ct-prev").onclick = () => { day = addDays(day, -1); load(); };
  $("ct-next").onclick = () => { day = addDays(day, 1); load(); };
  $("ct-today").onclick = () => { day = nyDate(); load(); };

  // ------------------------------------------------------ cancel and unblock
  async function cancelBooking(btn) {
    if (!confirm(`Cancel ${btn.dataset.name}'s booking (${btn.dataset.when})? They aren't told by the app, so let them know.`)) return;
    btn.disabled = true;
    const { error } = await sb.rpc("admin_cancel_court_booking", { p_booking: btn.dataset.ctCancel });
    btn.disabled = false;
    const inBlock = btn.closest("#court-block");
    if (error) return note(inBlock ? $("bk-msg") : $("ct-msg"), words(error));
    if (inBlock) {
      // The block's list keeps the others; this one says what happened.
      btn.closest(".row").querySelector(".grow").insertAdjacentHTML("beforeend", `<br><span class="ok">Canceled</span>`);
      btn.remove();
    }
    await load();
    if (!inBlock) note($("ct-msg"), "Booking canceled.", true);
  }
  document.addEventListener("click", async (e) => {
    const cancel = e.target.closest("[data-ct-cancel]");
    if (cancel) return cancelBooking(cancel);
    const unblock = e.target.closest("[data-ct-unblock]");
    if (unblock) {
      if (!confirm(`Remove the block on ${unblock.dataset.when}? Members can book that time again.`)) return;
      unblock.disabled = true;
      const { error } = await sb.rpc("admin_remove_court_block", { p_block: unblock.dataset.ctUnblock });
      unblock.disabled = false;
      if (error) return note($("ct-msg"), words(error));
      await load();
      note($("ct-msg"), "Block removed.", true);
    }
  });

  // ------------------------------------------------------- shared pickers
  const courtOptions = (withAll) =>
    (withAll ? `<option value="">All courts</option>` : "")
    + (current?.courts || []).filter(c => c.is_active).map(c => `<option value="${c.number}">${esc(c.name)}</option>`).join("");
  // Start times from the day's opening, every court_start_step minutes, up to
  // the shortest length before closing.
  function startOptions() {
    if (!current?.opens_at) return "";
    const step = Number(settings.court_start_step || 30) * MIN;
    const shortest = Math.min(...String(settings.court_lengths || "60").split(",").map(Number)) * MIN;
    const out = [];
    for (let t = new Date(current.opens_at).getTime(); t + shortest <= new Date(current.closes_at).getTime(); t += step)
      out.push(`<option value="${hhmm(new Date(t).toISOString())}">${fmtTime(new Date(t).toISOString())}</option>`);
    return out.join("");
  }

  // ------------------------------------------------------------- book
  let bookFor = null;   // { playerId, name }
  $("ct-book").onclick = () => {
    bookFor = null;
    $("cb-query").value = ""; $("cb-results").innerHTML = ""; $("cb-who").textContent = "Nobody chosen yet.";
    $("cb-court").innerHTML = courtOptions(false);
    $("cb-day").value = day;
    $("cb-start").innerHTML = startOptions();
    $("cb-length").innerHTML = String(settings.court_lengths || "60,90").split(",")
      .map(n => `<option value="${n}">${n} minutes</option>`).join("");
    $("cb-note").value = "";
    note($("cb-msg"), "");
    $("court-book").showModal();
  };
  let timer = null;
  $("cb-query").addEventListener("input", () => {
    clearTimeout(timer);
    timer = setTimeout(async () => {
      const q = $("cb-query").value.trim();
      if (q.length < 2) { $("cb-results").innerHTML = ""; return; }
      const { data, error } = await sb.rpc("search_players", { p_query: q, p_include_inactive: false });
      if (q !== $("cb-query").value.trim()) return;
      if (error) return note($("cb-msg"), words(error));
      const adults = (data || []).filter(p => p.kind === "adult");
      $("cb-results").innerHTML = adults.length ? adults.map(p => {
        const name = `${p.first_name} ${p.last_name}`;
        return `<div class="row"><span class="grow"><span class="name">${esc(name)}</span><br>
          <span class="muted">${p.is_member ? "Member" : "Non-member"}</span></span>
          <button type="button" class="small" data-cb-pick="${p.id}" data-name="${esc(name)}" aria-label="Choose ${esc(name)}">Choose</button></div>`;
      }).join("") : `<p class="muted">Nobody by that name yet. They may need to sign up in the app first.</p>`;
    }, 250);
  });
  $("cb-results").addEventListener("click", (e) => {
    const b = e.target.closest("[data-cb-pick]");
    if (!b) return;
    bookFor = { playerId: b.dataset.cbPick, name: b.dataset.name };
    $("cb-who").textContent = `For ${bookFor.name}`;
    $("cb-results").innerHTML = "";
    $("cb-query").value = "";
  });
  $("cb-cancel").onclick = () => $("court-book").close();
  $("cb-save").onclick = async () => {
    if (!bookFor) return note($("cb-msg"), "Choose who the court is for.");
    const btn = $("cb-save"); btn.disabled = true;
    try {
      const { data: pl, error: pe } = await sb.from("players").select("account_id").eq("id", bookFor.playerId).single();
      if (pe) throw pe;
      const starts = nyAt($("cb-day").value, $("cb-start").value);
      const ends = new Date(starts.getTime() + Number($("cb-length").value) * MIN);
      const { error } = await sb.rpc("admin_book_court", {
        p_account: pl.account_id, p_court: Number($("cb-court").value),
        p_starts_at: starts.toISOString(), p_ends_at: ends.toISOString(),
        p_admin_note: $("cb-note").value,
      });
      if (error) throw error;
      $("court-book").close();
      day = $("cb-day").value;
      await load();
      note($("ct-msg"), `Booked for ${bookFor.name}.`, true);
    } catch (err) { note($("cb-msg"), words(err)); }
    finally { btn.disabled = false; }
  };
  $("cb-day").addEventListener("change", async () => {
    // Another day can have other hours: read them before offering times.
    const { data } = await sb.rpc("admin_court_day", { p_day: $("cb-day").value });
    if (data) { current = { ...current, opens_at: data.opens_at, closes_at: data.closes_at }; $("cb-start").innerHTML = startOptions(); }
  });

  // ------------------------------------------------------------- block
  $("ct-block").onclick = () => {
    $("bk-court").innerHTML = courtOptions(true);
    $("bk-day").value = day;
    $("bk-from").value = current?.opens_at ? hhmm(current.opens_at) : "07:00";
    $("bk-to").value = current?.closes_at ? hhmm(current.closes_at) : "21:00";
    $("bk-reason").value = "";
    $("bk-form").classList.remove("hide"); $("bk-after").classList.add("hide");
    $("bk-save").classList.remove("hide");
    note($("bk-msg"), "");
    $("court-block").showModal();
  };
  $("bk-cancel").onclick = () => $("court-block").close();
  $("bk-save").onclick = async () => {
    const btn = $("bk-save"); btn.disabled = true;
    try {
      const d = $("bk-day").value;
      const { data, error } = await sb.rpc("admin_block_courts", {
        p_court: $("bk-court").value ? Number($("bk-court").value) : null,
        p_starts_at: nyAt(d, $("bk-from").value).toISOString(),
        p_ends_at: nyAt(d, $("bk-to").value).toISOString(),
        p_reason: $("bk-reason").value,
      });
      if (error) throw error;
      day = d;
      await load();
      const conflicts = data?.conflicts || [];
      if (!conflicts.length) { $("court-block").close(); note($("ct-msg"), "Blocked.", true); return; }
      // Nobody is canceled by a block: she decides about each one.
      $("bk-form").classList.add("hide"); $("bk-save").classList.add("hide");
      $("bk-after").classList.remove("hide");
      $("bk-conflicts").innerHTML = conflicts.map(c => `<div class="row" data-conflict="${c.booking_id}">
          <span class="grow"><span class="name">${esc(c.name)}</span><br>
          <span class="muted">Court ${c.court}, ${range(c)}${c.phone ? `, ${esc(c.phone)}` : ""}</span></span>
          <button class="small danger" data-ct-cancel="${c.booking_id}" data-name="${esc(c.name)}" data-when="${esc(`Court ${c.court}, ${range(c)}`)}">Cancel booking</button>
        </div>`).join("");
    } catch (err) { note($("bk-msg"), words(err)); }
    finally { btn.disabled = false; }
  };

  // ---------------------------------------------------------- settings
  const RULES = [
    ["court_lengths", "rs-lengths"], ["court_start_step", "rs-step"],
    ["court_advance_days", "rs-advance"], ["court_day_opens_at", "rs-opens"],
    ["court_max_per_day", "rs-per-day"], ["court_max_upcoming", "rs-upcoming"],
    ["court_players_per_court", "rs-per-court"],
  ];
  let hoursRead = [];   // [{ opens, closes }] by weekday, as read
  $("ct-settings").onclick = async () => {
    note($("rs-msg"), "");
    try {
      await readSettings();
      $("rs-live-text").textContent = settings.courts_live === "true"
        ? "On for members." : "Off for members. Court booking is in testing with the testers below.";
      $("rs-members").checked = settings.court_members_only !== "false";
      for (const [k, id] of RULES) $(id).value = settings[k] ?? "";
      // The hours of each weekday: the next seven days cover all of them.
      const days = [0, 1, 2, 3, 4, 5, 6].map(n => addDays(nyDate(), n));
      const answers = await Promise.all(days.map(d => sb.rpc("admin_court_day", { p_day: d })));
      hoursRead = [];
      answers.forEach(({ data }, i) => {
        const wd = weekdayOf(days[i]);
        hoursRead[wd] = data?.opens_at ? { opens: hhmm(data.opens_at), closes: hhmm(data.closes_at) } : { opens: "", closes: "" };
      });
      $("rs-hours").innerHTML = WEEKDAYS.map((name, wd) => `<div class="row" data-hours="${wd}">
          <span style="width:7em">${name}</span>
          <label class="sr-only" for="rs-open-${wd}">${name} opens</label>
          <input id="rs-open-${wd}" type="time" step="900" value="${hoursRead[wd].opens}" style="width:auto">
          <span>to</span>
          <label class="sr-only" for="rs-close-${wd}">${name} closes</label>
          <input id="rs-close-${wd}" type="time" step="900" value="${hoursRead[wd].closes}" style="width:auto">
        </div>`).join("");
      $("rs-tester-query").value = ""; $("rs-tester-results").innerHTML = "";
      await loadTesters();
      $("court-rules").showModal();
    } catch (err) { note($("ct-msg"), words(err)); }
  };

  // ------------------------------------------------------------ testers
  // Each add or remove is saved at once, apart from the rules' Save.
  async function loadTesters() {
    const { data, error } = await sb.rpc("admin_court_testers");
    if (error) { $("rs-testers").innerHTML = ""; return note($("rs-msg"), words(error)); }
    $("rs-testers").innerHTML = (data || []).length ? data.map(t => {
      const name = `${t.first_name} ${t.last_name}`;
      return `<div class="row" data-tester="${t.account_id}">
        <span class="grow"><span class="name">${esc(name)}</span>${t.is_member ? "" : `<br><span class="muted">Not a member: can book only if an administrator.</span>`}</span>
        <button type="button" class="small" data-tester-off="${t.account_id}" aria-label="Remove ${esc(name)} as a tester">Remove</button>
      </div>`;
    }).join("") : `<p class="muted" style="margin:0">No testers yet.</p>`;
  }
  async function setTester(accountId, on) {
    const { error } = await sb.rpc("admin_set_court_tester", { p_account: accountId, p_on: on });
    if (error) return note($("rs-msg"), words(error));
    note($("rs-msg"), "");
    await loadTesters();
  }
  let testerTimer = null;
  $("rs-tester-query").addEventListener("input", () => {
    clearTimeout(testerTimer);
    testerTimer = setTimeout(async () => {
      const q = $("rs-tester-query").value.trim();
      if (q.length < 2) { $("rs-tester-results").innerHTML = ""; return; }
      const { data, error } = await sb.rpc("search_players", { p_query: q, p_include_inactive: false });
      if (q !== $("rs-tester-query").value.trim()) return;
      if (error) return note($("rs-msg"), words(error));
      const adults = (data || []).filter(p => p.kind === "adult");
      $("rs-tester-results").innerHTML = adults.length ? adults.map(p => {
        const name = `${p.first_name} ${p.last_name}`;
        return `<div class="row"><span class="grow"><span class="name">${esc(name)}</span><br>
          <span class="muted">${p.is_member ? "Member" : "Non-member"}</span></span>
          <button type="button" class="small" data-tester-on="${p.id}" aria-label="Add ${esc(name)} as a tester">Add</button></div>`;
      }).join("") : `<p class="muted">Nobody by that name yet. They may need to sign up in the app first.</p>`;
    }, 250);
  });
  $("rs-tester-results").addEventListener("click", async (e) => {
    const b = e.target.closest("[data-tester-on]");
    if (!b) return;
    b.disabled = true;
    const { data: pl, error } = await sb.from("players").select("account_id").eq("id", b.dataset.testerOn).single();
    if (error) { b.disabled = false; return note($("rs-msg"), words(error)); }
    await setTester(pl.account_id, true);
    $("rs-tester-query").value = ""; $("rs-tester-results").innerHTML = "";
  });
  $("rs-testers").addEventListener("click", async (e) => {
    const b = e.target.closest("[data-tester-off]");
    if (!b) return;
    b.disabled = true;
    await setTester(b.dataset.testerOff, false);
  });
  $("rs-cancel").onclick = () => $("court-rules").close();
  $("rs-save").onclick = async () => {
    // courts_live is never sent: the server refuses it (courts_live_locked).
    const btn = $("rs-save"); btn.disabled = true;
    try {
      const payload = { court_members_only: String($("rs-members").checked) };
      for (const [k, id] of RULES) payload[k] = $(id).value.trim().replace(/\s+/g, "");
      const { error } = await sb.rpc("admin_set_court_settings", { p_settings: payload });
      if (error) throw error;
      for (let wd = 0; wd < 7; wd++) {
        const opens = $(`rs-open-${wd}`).value, closes = $(`rs-close-${wd}`).value;
        if (opens === hoursRead[wd].opens && closes === hoursRead[wd].closes) continue;
        const { error: he } = await sb.rpc("admin_set_court_hours", { p_weekday: wd, p_opens: opens || null, p_closes: closes || null });
        if (he) return note($("rs-msg"), `${WEEKDAYS[wd]}: ${words(he)}`);
      }
      $("court-rules").close();
      await load();
      note($("ct-msg"), "Court rules saved.", true);
    } catch (err) { note($("rs-msg"), words(err)); }
    finally { btn.disabled = false; }
  };

  return { load };
}
