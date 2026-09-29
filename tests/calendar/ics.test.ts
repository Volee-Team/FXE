// ics.test.ts: the iCalendar rules of supabase/functions/calendar-feed/ics.ts,
// written from RFC 5545, not from the code (decision 0029). Run by
// tests/calendar/run.sh:  deno test tests/calendar/ics.test.ts
//
//   §3.3.11  TEXT escapes backslash, semicolon, comma; a line break is \n
//   §3.1     content lines fold at 75 octets with CRLF + one space; octets,
//            not characters, and a character is never cut in half
//   §3.3.5   a UTC time is YYYYMMDDTHHMMSSZ

import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { buildCalendar, escapeText, foldLine, formatUtc } from "../../supabase/functions/calendar-feed/ics.ts";

const octets = (s: string) => new TextEncoder().encode(s).length;

Deno.test("text escaping: backslash first, then ; and , and every kind of line break", () => {
  assertEquals(escapeText("Ladies, 3.0+; drills \\ games"), "Ladies\\, 3.0+\\; drills \\\\ games");
  assertEquals(escapeText("one\ntwo\r\nthree\rfour"), "one\\ntwo\\nthree\\nfour");
  assertEquals(escapeText("colon: stays"), "colon: stays");
  assertEquals(escapeText("tab\tstays, bell\u0007 goes"), "tab\tstays\\, bell goes");
});

Deno.test("folding: nothing under 76 octets changes", () => {
  const line = "SUMMARY:" + "x".repeat(67); // 75 octets exactly
  assertEquals(octets(line), 75);
  assertEquals(foldLine(line), line);
});

Deno.test("folding: 75 octets, then a space and 74", () => {
  const line = "SUMMARY:" + "x".repeat(200);
  const parts = foldLine(line).split("\r\n");
  assertEquals(octets(parts[0]), 75);
  for (const p of parts.slice(1)) {
    assertEquals(p[0], " ");
    assertEquals(octets(p) <= 75, true);
  }
  assertEquals(parts.slice(1, -1).every((p) => octets(p) === 75), true);
  // Unfolding (§3.1: remove CRLF + one space) gives the line back.
  assertEquals(foldLine(line).replaceAll("\r\n ", ""), line);
});

Deno.test("folding counts octets and never cuts a character", () => {
  // é is 2 octets, 🎾 is 4 (a surrogate pair in JS). Every alignment from 0
  // to 7 extra characters is tried: with one alignment, a fold that cut pairs
  // in half happened to land between them every time (red-first, 2026-09-28).
  for (let pad = 0; pad < 8; pad++) {
    const line = "SUMMARY:" + "a".repeat(pad) + "é".repeat(40) + "🎾".repeat(30);
    const folded = foldLine(line);
    for (const p of folded.split("\r\n")) {
      assertEquals(octets(p) <= 75, true);
      // A lone surrogate would mean a character was split.
      assertEquals(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(p), false);
    }
    assertEquals(folded.replaceAll("\r\n ", ""), line);
  }
});

Deno.test("UTC times: whole seconds, Z, from PostgREST's six-digit fractions and offsets", () => {
  assertEquals(formatUtc("2026-10-06T22:00:00+00:00"), "20261006T220000Z");
  assertEquals(formatUtc("2026-11-07T00:32:15.987654+00:00"), "20261107T003215Z");
  assertEquals(formatUtc("2026-10-06T18:00:00-04:00"), "20261006T220000Z");
  assertThrows(() => formatUtc("not a time"));
});

Deno.test("a calendar: CRLF everywhere, the two statuses, nothing about where", () => {
  const cal = buildCalendar([
    { registration_id: "r1", status: "in", clinic_name: "Tuesday Ladies 3.0+", starts_at: "2026-10-06T22:00:00+00:00", ends_at: "2026-10-06T23:30:00+00:00" },
    { registration_id: "r2", status: "response_needed", clinic_name: "Evening Coed", starts_at: "2026-10-08T22:00:00+00:00", ends_at: "2026-10-08T23:00:00+00:00" },
  ], new Date("2026-09-28T12:00:00Z"));
  assertEquals(cal.endsWith("END:VCALENDAR\r\n"), true);
  assertEquals(cal.replaceAll("\r\n", "").includes("\n"), false);
  assertEquals(cal.includes("SUMMARY:Tuesday Ladies 3.0+\r\nSTATUS:CONFIRMED"), true);
  assertEquals(cal.includes("SUMMARY:Evening Coed (Response Needed)\r\nSTATUS:TENTATIVE"), true);
  assertEquals(cal.includes("UID:r2@fxetennis"), true);
  assertEquals(cal.includes("DTSTAMP:20260928T120000Z"), true);
  assertEquals(/^(LOCATION|URL|DESCRIPTION|GEO)[:;]/m.test(cal), false);
});

Deno.test("an account with no clinics is still a calendar", () => {
  const cal = buildCalendar([], new Date("2026-09-28T12:00:00Z"));
  assertEquals(cal.startsWith("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"), true);
  assertEquals(cal.includes("BEGIN:VEVENT"), false);
  assertEquals(cal.includes("X-WR-CALNAME:FXE Tennis\r\n"), true);
});
