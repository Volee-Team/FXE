// Reading a list that can grow, without losing rows (MVP audit 2026-09-27,
// item 14). Pure over a query builder, so web/tests/week.spec.mjs can run it
// against a fake server with the same cap as the real one.
//
// PostgREST answers at most max_rows rows (1000: supabase/config.toml, and the
// hosted default) and says nothing when it stops there. The web admin once read
// every registration in one request and, ten to twelve weeks in, would have
// drawn rosters with players silently missing.

// A page of 500 is under the cap, so a page shorter than 500 really is the end.
const PAGE = 500;

// `build` returns a fresh query with a total order (ends in .order("id") or
// similar), or a row can land on two pages or on none. Returns { data } with
// every row, or { error } and no rows: a partial list is never handed back.
export async function readAll(build) {
  const rows = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await build().range(from, from + PAGE - 1);
    if (error) return { error };
    rows.push(...data);
    if (data.length < PAGE) return { data: rows };
  }
}

// .in() carries every id in the URL. A hundred ids at a time keeps it near
// 4 KB, well inside what the gateway accepts. `build(ids)` returns a query for
// that slice of ids.
export async function readByIds(ids, build) {
  const rows = [];
  for (let i = 0; i < ids.length; i += 100) {
    const r = await readAll(() => build(ids.slice(i, i + 100)));
    if (r.error) return r;
    rows.push(...r.data);
  }
  return { data: rows };
}
