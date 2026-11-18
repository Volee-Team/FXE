// Tara's Juniors tab (juniors phase 1, decision 0061; spec 01). Three cards:
// the parents' approval requests for Junior Elite and Elite, approving a child
// herself (preapprove), and her programs (name, ages, description, whether it
// needs her approval, order, archive).
//
// The server decides everything: who may ask, whether a request is still
// open, what a program needs. This page draws admin_program_approvals and
// admin_junior_programs and calls admin_decide_program_approval,
// admin_preapprove_program and admin_save_junior_program; every action
// reloads from the server rather than patching the screen (hard rule 3).
//
// The same open requests are an Action Needed card on This week
// (requestRows below, drawn by index.html's loadActionNeeded).

// A program's refusals in words, then the page's own friendly(). Program
// errors come first because friendly() reads name_required as a clinic's.
function programLine(e, friendly) {
  const m = (e?.message || String(e || "")).toLowerCase();
  if (m.includes("name_required")) return "A program needs a name.";
  if (m.includes("program_name_taken")) return "A program already has that name.";
  if (m.includes("program_not_found")) return "Couldn't find that program.";
  if (m.includes("child_not_found")) return "Couldn't find that child.";
  if (m.includes("approval_not_needed")) return "That program doesn't need approval.";
  if (m.includes("approval_already_decided")) return "Someone already handled that one.";
  if (m.includes("approval_not_found")) return "That just changed. Here's the latest.";
  return friendly(e);
}

const day = (iso) => new Date(iso).toLocaleDateString("en-US",
  { timeZone: "America/New_York", month: "short", day: "numeric" });
const dialable = (phone) => {
  const v = (phone || "").trim(), digits = v.replace(/\D/g, "");
  return digits.length >= 7 ? (v.startsWith("+") ? "+" : "") + digits : null;
};

// One parent's request, the same row on Action Needed and on the Juniors tab.
export function requestRow(r, esc) {
  const parent = [r.parent_first_name, r.parent_last_name].filter(Boolean).join(" ");
  const dial = dialable(r.parent_phone);
  const phone = r.parent_phone
    ? (dial ? ` <a href="tel:${esc(dial)}" style="white-space:nowrap">${esc(r.parent_phone)}</a>` : ` ${esc(r.parent_phone)}`)
    : "";
  return `<div class="row" data-program-request="${esc(r.player_id)}" data-program="${esc(r.program_id)}">
    <span class="grow"><span class="name">${esc(r.child_first_name + " " + r.child_last_name)}</span> <span class="muted">(age ${esc(r.age)})</span>
      <span class="muted"> asked for </span><span class="name">${esc(r.program_name)}</span><br>
      <span class="muted">Parent: ${esc(parent)}${phone}${r.requested_at ? `, asked ${esc(day(r.requested_at))}` : ""}</span></span>
    <button class="small primary" data-progapprove="${esc(r.player_id)}" data-program="${esc(r.program_id)}">Approve</button>
    <button class="small" data-progdecline="${esc(r.player_id)}" data-program="${esc(r.program_id)}">Decline</button>
  </div>`;
}

// What the Players tab says about a child's programs.
export function approvalWords(rows, esc) {
  const by = { approved: [], requested: [], declined: [] };
  for (const r of rows || []) by[r.status]?.push(r.program_name);
  return [
    by.approved.length ? `Approved: ${esc(by.approved.join(", "))}` : "",
    by.requested.length ? `Asked for ${esc(by.requested.join(", "))}` : "",
    by.declined.length ? `Declined: ${esc(by.declined.join(", "))}` : "",
  ].filter(Boolean);
}

export function wireJuniors(sb, { $, esc, friendly, note, reloadWeek, reloadPlayers }) {
  let programs = [];
  let editing = null;
  let seq = 0;

  async function readApprovals() {
    const { data, error } = await sb.rpc("admin_program_approvals");
    return { rows: data || [], error };
  }

  function drawApprovals(rows) {
    const open = rows.filter(r => r.status === "requested");
    const done = rows.filter(r => r.status !== "requested");
    const decided = (r) => {
      const parent = [r.parent_first_name, r.parent_last_name].filter(Boolean).join(" ");
      const how = r.status === "approved"
        ? (r.source === "tara" ? "Approved by you" : "Approved")
        : "Declined";
      return `<div class="row" data-program-decided="${esc(r.player_id)}" data-program="${esc(r.program_id)}">
        <span class="grow"><span class="name">${esc(r.child_first_name + " " + r.child_last_name)}</span>
          <span class="muted"> ${esc(r.program_name)}</span><br>
          <span class="muted">${how}${r.decided_at ? ", " + esc(day(r.decided_at)) : ""}${parent ? `. Parent: ${esc(parent)}` : ""}</span></span>
        ${r.status === "declined" ? `<button class="small" data-progpre="${esc(r.player_id)}" data-program="${esc(r.program_id)}">Approve</button>` : ""}
      </div>`;
    };
    $("jr-approvals").innerHTML =
      (open.length ? open.map(r => requestRow(r, esc)).join("") : `<p class="muted">No requests waiting.</p>`)
      + (done.length ? `<p class="name" style="margin:16px 0 4px">Decided</p>` + done.map(decided).join("") : "");
  }

  function drawPrograms() {
    const showArchived = $("jr-show-archived").checked;
    const shown = programs.filter(g => showArchived || g.active);
    $("jr-programs").innerHTML = shown.length ? shown.map(g => `<div class="row" data-program-row="${esc(g.id)}">
        <span class="grow"><span class="name">${esc(g.name)}</span>${g.active ? "" : ' <span class="muted">(archived)</span>'}<br>
          <span class="muted">${g.age_guidance ? esc(g.age_guidance) : "No ages yet"}${g.needs_approval ? ", needs your approval" : ""}</span>
          ${g.description ? `<br><span class="muted" style="white-space:pre-wrap">${esc(g.description)}</span>` : `<br><span class="muted">No description yet</span>`}</span>
        <button class="small" data-progedit="${esc(g.id)}">Edit</button>
        ${g.active
          ? `<button class="small" data-progarchive="${esc(g.id)}">Archive</button>`
          : `<button class="small" data-progrestore="${esc(g.id)}">Restore</button>`}
      </div>`).join("") : `<p class="muted">No programs yet.</p>`;
    // Approve a child: only programs that need approval, and only live ones.
    const pick = $("jr-program"), was = pick.value;
    const asks = programs.filter(g => g.active && g.needs_approval);
    pick.innerHTML = asks.map(g => `<option value="${esc(g.id)}">${esc(g.name)}</option>`).join("");
    if (asks.some(g => g.id === was)) pick.value = was;
  }

  async function load() {
    const gen = ++seq;
    const [a, g] = await Promise.all([readApprovals(), sb.rpc("admin_junior_programs")]);
    if (gen !== seq) return;
    if (a.error || g.error) return note($("jr-msg"), programLine(a.error || g.error, friendly));
    note($("jr-msg"), "");
    programs = g.data || [];
    drawApprovals(a.rows);
    drawPrograms();
    searchChildren();
  }

  // Approve a child: her search over children only (search_players, juniors).
  let childSeq = 0, childTimer;
  async function searchChildren() {
    const q = $("jr-query").value.trim();
    const gen = ++childSeq;
    if (q.length < 2) { $("jr-results").innerHTML = ""; return; }
    const { data, error } = await sb.rpc("search_players", { p_query: q, p_include_inactive: false });
    if (gen !== childSeq) return;
    if (error) return note($("jr-pre-msg"), friendly(error));
    const kids = (data || []).filter(p => p.kind === "junior");
    $("jr-results").innerHTML = kids.length ? kids.map(k => `<div class="row" data-child-result="${esc(k.id)}">
        <span class="grow"><span class="name">${esc(k.first_name + " " + k.last_name)}</span> <span class="muted">(age ${esc(k.age)})</span></span>
        <button class="small primary" data-progpre="${esc(k.id)}">Approve</button>
      </div>`).join("") : `<p class="muted">No child by that name.</p>`;
  }
  $("jr-query").addEventListener("input", () => { clearTimeout(childTimer); childTimer = setTimeout(searchChildren, 250); });
  $("jr-show-archived").addEventListener("change", drawPrograms);

  function openProgram(g) {
    editing = g ? g.id : null;
    $("pg-title").textContent = g ? "Edit program" : "New program";
    $("pg-name").value = g ? g.name : "";
    $("pg-ages").value = g ? g.age_guidance : "";
    $("pg-desc").value = g ? g.description : "";
    $("pg-order").value = g ? g.sort_order : (programs.reduce((n, x) => Math.max(n, x.sort_order), 0) + 1);
    $("pg-approval").checked = g ? g.needs_approval : false;
    note($("program-msg"), "");
    $("program").showModal(); $("pg-name").focus();
  }
  $("jr-new").addEventListener("click", () => openProgram(null));
  $("pg-cancel").addEventListener("click", () => $("program").close());
  $("pg-save").addEventListener("click", async () => {
    const name = $("pg-name").value.trim();
    if (!name) return note($("program-msg"), "A program needs a name.");
    const g = programs.find(x => x.id === editing);
    $("pg-save").disabled = true;
    try {
      const { error } = await sb.rpc("admin_save_junior_program", {
        p_id: editing, p_name: name, p_description: $("pg-desc").value, p_age_guidance: $("pg-ages").value,
        p_needs_approval: $("pg-approval").checked, p_sort_order: Number($("pg-order").value) || 0,
        p_active: g ? g.active : true });
      if (error) throw error;
      $("program").close();
      await load();
    } catch (err) { note($("program-msg"), programLine(err, friendly)); }
    finally { $("pg-save").disabled = false; }
  });

  // Every Juniors button, here or on Action Needed. After each one, the
  // tab, the week's Action Needed and the Players tab are read again.
  document.addEventListener("click", async (e) => {
    const b = e.target.closest("button"); if (!b) return;
    const d = b.dataset;
    if (!(d.progapprove || d.progdecline || d.progpre || d.progedit || d.progarchive || d.progrestore)) return;
    if (d.progedit) return openProgram(programs.find(g => g.id === d.progedit));
    const onWeek = !!b.closest("#action");
    const msg = onWeek ? $("msg") : (d.progpre && b.closest("#jr-results") ? $("jr-pre-msg") : $("jr-msg"));
    b.disabled = true;
    let said = "", ok = false;
    try {
      let r;
      if (d.progapprove || d.progdecline) {
        r = await sb.rpc("admin_decide_program_approval",
          { p_child: d.progapprove || d.progdecline, p_program: d.program, p_approve: !!d.progapprove });
      } else if (d.progpre) {
        const program = d.program || $("jr-program").value;
        if (!program) { note(msg, "Choose a program."); b.disabled = false; return; }
        r = await sb.rpc("admin_preapprove_program", { p_child: d.progpre, p_program: program });
      } else {
        const g = programs.find(x => x.id === (d.progarchive || d.progrestore));
        r = await sb.rpc("admin_save_junior_program", {
          p_id: g.id, p_name: g.name, p_description: g.description, p_age_guidance: g.age_guidance,
          p_needs_approval: g.needs_approval, p_sort_order: g.sort_order, p_active: !!d.progrestore });
      }
      if (r.error) throw r.error;
      if (d.progpre && b.closest("#jr-results")) { said = "Approved."; ok = true; }
    } catch (err) { said = programLine(err, friendly); }
    // Read everything again first: the week's reload clears its message line.
    await Promise.all([load(), reloadWeek(), reloadPlayers()]);
    b.disabled = false;
    note(msg, said, ok);
  });

  return { load, readApprovals };
}
