// Which clinics the web admin's This week tab lists. Pure functions, no
// network, so web/tests/admin.spec.mjs can hold them to hand-worked answers
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
  const want = Date.UTC(y, m - 1, d);
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
