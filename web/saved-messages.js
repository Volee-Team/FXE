// Tara's saved messages in the Message dialog (decision 0030).
//
// The words are hers: this stores what she typed and offers it back; it never
// writes or suggests one (hard rule 13). Choosing one only fills the box; the
// send is still send_clinic_message with the audience she picks.
//
// Kept apart from index.html so the dialog's wiring lives in one place. It
// reads the list fresh every time the dialog opens (a MutationObserver on the
// dialog's `open` attribute), so it does not depend on which button opened it.

// The server keeps 1 to 1000 characters after trimming (20260928900001).
// Postgres length() counts code points, so count them the same way here: a
// string's .length counts UTF-16 units and would call an emoji two.
const MAX = 1000;
export const savable = (text) => {
  const t = String(text ?? "").trim();
  const n = [...t].length;
  return n >= 1 && n <= MAX ? t : null;
};

// dialog, box (textarea), list (container), save (button), say(text, ok) for
// the dialog's message line, friendly(err) for server errors in words.
export function wireSavedMessages(sb, { dialog, box, list, save, say, friendly }) {
  let generation = 0;

  const refreshSave = () => { save.disabled = savable(box.value) === null; };

  function render(rows) {
    list.replaceChildren();
    if (!rows.length) {
      const p = document.createElement("p");
      p.className = "muted saved-empty";
      p.textContent = "No saved messages yet.";
      list.append(p);
      return;
    }
    for (const m of rows) {
      const row = document.createElement("div");
      row.className = "saved-row";
      row.dataset.savedRow = m.id;
      const use = document.createElement("button");
      use.type = "button";
      use.className = "saved-use";
      use.id = `saved-${m.id}`;
      use.textContent = m.body;            // text, never HTML: her words as typed
      use.addEventListener("click", () => {
        box.value = m.body;
        refreshSave();
        box.focus();
      });
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "small";
      remove.textContent = "Remove";
      remove.setAttribute("aria-describedby", use.id);   // "Remove", then which one
      remove.addEventListener("click", async () => {
        remove.disabled = true;
        // False means it was already removed elsewhere: the reload shows that.
        const { error } = await sb.rpc("admin_archive_message_template", { p_id: m.id });
        if (error) { say(friendly(error)); remove.disabled = false; return; }
        await load();
      });
      row.append(use, remove);
      list.append(row);
    }
  }

  async function load() {
    const mine = ++generation;
    const { data, error } = await sb.rpc("admin_message_templates");
    if (mine !== generation) return;       // an older read never overwrites a newer one
    if (error) { list.replaceChildren(); say(friendly(error)); return; }
    render(data || []);
  }

  box.addEventListener("input", refreshSave);

  save.addEventListener("click", async () => {
    const text = savable(box.value);
    if (text === null) return;
    save.disabled = true;
    const { error } = await sb.rpc("admin_save_message_template", { p_body: text });
    if (error) say(friendly(error));
    await load();
    refreshSave();
  });

  new MutationObserver(() => {
    if (!dialog.open) return;
    refreshSave();
    load();
  }).observe(dialog, { attributes: true, attributeFilter: ["open"] });
}
