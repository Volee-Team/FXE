// ics.ts: turns the calendar feed's rows into iCalendar text (RFC 5545).
// Pure, no I/O: tests/calendar/ics.test.ts pins the escaping and folding,
// tests/calendar/run.sh the served result. Decision 0029.
//
// What an event holds is decided by the database (calendar_feed_events);
// this file adds nothing about the clinic. In particular there is no
// LOCATION, URL or DESCRIPTION property anywhere below, and there must never
// be one: where the club is never reaches a player (decision 10), the court
// is hidden (decision 17), and a calendar syncs to other devices and other
// people.

export type FeedRow = {
  registration_id: string;
  status: "in" | "response_needed";
  clinic_name: string;
  starts_at: string; // timestamptz as PostgREST sends it
  ends_at: string;
};

// The two player-facing words in the feed, both chrome listed in
// docs/copy-review.md: the calendar's name, and Tara's locked term for an
// invitation waiting on an answer.
export const CALENDAR_NAME = "FXE Tennis";
export const RESPONSE_NEEDED_SUFFIX = " (Response Needed)";

const CRLF = "\r\n";

/// A TEXT value per RFC 5545 §3.3.11: backslash, semicolon and comma
/// escaped, every line break as \n, and the other control characters (which
/// TEXT may not carry) dropped. The backslash goes first, or the escapes
/// added after it would be doubled.
export function escapeText(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r\n|\r|\n/g, "\\n")
    // deno-lint-ignore no-control-regex
    .replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, "");
}

/// A content line folded at 75 octets (RFC 5545 §3.1): CRLF plus one space
/// starts each continuation, so continuation lines carry 74 octets of
/// content. Counted in UTF-8 octets, never splitting a character.
export function foldLine(line: string): string {
  const enc = new TextEncoder();
  const parts: string[] = [];
  let current = "";
  let octets = 0;
  let limit = 75;
  for (const ch of line) { // by code point, so a surrogate pair stays whole
    const n = enc.encode(ch).length;
    if (octets + n > limit) {
      parts.push(current);
      current = "";
      octets = 0;
      limit = 74;
    }
    current += ch;
    octets += n;
  }
  parts.push(current);
  return parts.join(CRLF + " ");
}

/// 20261006T220000Z: UTC, whole seconds (fractions dropped, as Postgres's
/// to_char does), so no time zone block is needed and every client agrees.
export function formatUtc(value: string | Date): string {
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) throw new Error("bad_timestamp");
  return d.toISOString().replace(/\.\d{3}Z$/, "Z").replace(/[-:]/g, "");
}

export function buildCalendar(rows: FeedRow[], now: Date): string {
  const stamp = formatUtc(now);
  const lines: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//FXE Tennis//Clinic Calendar//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:" + escapeText(CALENDAR_NAME),
    // Hints only: Apple's Calendar and Outlook honour them, Google refreshes
    // on its own schedule.
    "X-PUBLISHED-TTL:PT1H",
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
  ];
  for (const r of rows) {
    const tentative = r.status === "response_needed";
    lines.push(
      "BEGIN:VEVENT",
      // The registration, not the clinic: when Response Needed becomes
      // You're In! it is the same event, updated in place.
      "UID:" + r.registration_id + "@fxetennis",
      "DTSTAMP:" + stamp,
      "DTSTART:" + formatUtc(r.starts_at),
      "DTEND:" + formatUtc(r.ends_at),
      "SUMMARY:" + escapeText(r.clinic_name + (tentative ? RESPONSE_NEEDED_SUFFIX : "")),
      "STATUS:" + (tentative ? "TENTATIVE" : "CONFIRMED"),
      "END:VEVENT",
    );
  }
  lines.push("END:VCALENDAR");
  return lines.map(foldLine).join(CRLF) + CRLF;
}
