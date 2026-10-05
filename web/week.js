// Which clinics the web admin's This week tab lists. Pure functions, no
// network, so web/tests/week.spec.mjs can hold them to hand-worked answers
// in a real browser (MVP audit 2026-09-27, item 14).
//
// The service week is the club's: Sunday 00:00 through Saturday 23:59 in
// America/New_York (decision 0001; service_week_start() in the database). Two
// traps, the same two CLAUDE.md records for the SQL: take the weekday of the
// New York date, never the UTC one (Saturday 21:00 in New York is already
// Sunday in UTC), and anchor on Sunday, never an ISO Monday. This copy only
// decides what the tab shows; who may register is decided in Postgres alone.

const NY = "America/New_York";
const CLOCK = new Intl.DateTimeFormat("en-US", {
  timeZone: NY, hourCycle: "h23",
  year: "numeric", month: "numeric", day: "numeric",
  hour: "numeric", minute: "numeric", second: "numeric",
});

// The New York wall clock at an instant, as numbers.
function nyClock(date) {
  const out = {};
  for (const p of CLOCK.formatToParts(date)) if (p.type !== "literal") out[p.type] = Number(p.value);
  return out;
}

// The instant at which New York's clock reads y-m-d 00:00. Start from that
// wall time read as UTC, then move by whatever New York's clock is off by;
// the second pass settles a guess that landed across a daylight-saving change.
function nyMidnight(y, m, d) {
  return nyInstant(y, m, d, 0, 0);
}

// The instant at which New York's clock reads y-m-d hh:mi, by the same
// settle-twice method. A clinic's time is Charlotte's whatever zone the
// laptop is in (decision 0038, 2026-10-04: a laptop in California typed
// 10:00 and saved 13:00 Eastern).
export function nyInstant(y, m, d, hh = 0, mi = 0) {
  const want = Date.UTC(y, m - 1, d, hh, mi);
  let t = want;
  for (let i = 0; i < 3; i++) {
    const c = nyClock(new Date(t));
    const seen = Date.UTC(c.year, c.month - 1, c.day, c.hour, c.minute, c.second);
    if (seen === want) break;
    t += want - seen;
  }
  return new Date(t);
}

// Sunday 00:00 in New York of the service week containing `now`.
export function serviceWeekStart(now = new Date()) {
  const c = nyClock(now);
  // A calendar date's weekday is the same in every zone. 0 is Sunday, as in
  // Postgres DOW, so it is also the number of days back to the anchor.
  const dow = new Date(Date.UTC(c.year, c.month - 1, c.day)).getUTCDay();
  const sunday = new Date(Date.UTC(c.year, c.month - 1, c.day - dow));
  return nyMidnight(sunday.getUTCFullYear(), sunday.getUTCMonth() + 1, sunday.getUTCDate());
}

// Split clinics into the two lists the tab draws.
//   current: every clinic that ends after the week began, plus, while
//            payments are on, any earlier clinic that Charge clinic would
//            still charge someone for (`owed`: clinic ids), so a Saturday
//            nobody has charged does not vanish at midnight. Never a
//            canceled one: Charge clinic is not offered on those.
//   earlier: everything else, shown only behind Show earlier.
// current reads forward in time; earlier reads back from the week's start.
export function splitThisWeek(clinics, { weekStart, paymentsOn = false, owed = new Set() }) {
  const t0 = weekStart.getTime();
  const current = [], earlier = [];
  for (const c of clinics) {
    const inWeek = new Date(c.ends_at).getTime() > t0;
    const stillOwed = paymentsOn && owed.has(c.id) && c.status !== "canceled";
    (inWeek || stillOwed ? current : earlier).push(c);
  }
  const at = (c) => new Date(c.starts_at).getTime();
  const byTime = (a, b) => at(a) - at(b) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  current.sort(byTime);
  earlier.sort((a, b) => byTime(b, a));
  return { current, earlier };
}

// The heading over a week's clinics on the tab, in the phone's words
// (FXETennis/Models/ServiceWeek.swift): "This week", "Next week", else
// "Week of Nov 8" (the Sunday, New York). Both arguments are Sunday 00:00
// New York instants from serviceWeekStart; a week across a daylight-saving
// change is 167 or 169 hours, so weeks are counted by rounding, not dividing.
export function weekLabel(weekStart, thisWeekStart) {
  const weeks = Math.round((weekStart.getTime() - thisWeekStart.getTime()) / (7 * 86_400_000));
  if (weeks === 0) return "This week";
  if (weeks === 1) return "Next week";
  const day = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", month: "short", day: "numeric" })
    .format(weekStart);
  return `Week of ${day}`;
}

// A datetime-local input's value ("2026-11-10T10:00") read as New York wall
// time, and the value to show for an instant, on New York's clock. The
// input itself has no zone; these make it Charlotte's.
export function nyFromInput(value) {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(value || "");
  if (!m) return null;
  return nyInstant(+m[1], +m[2], +m[3], +m[4], +m[5]);
}
export function nyInputValue(iso) {
  const c = nyClock(new Date(iso));
  const p = (n) => String(n).padStart(2, "0");
  return `${c.year}-${p(c.month)}-${p(c.day)}T${p(c.hour)}:${p(c.minute)}`;
}
