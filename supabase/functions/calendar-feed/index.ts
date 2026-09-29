// calendar-feed: a player's clinics as a subscribed calendar (decision 0029).
//
//   GET ?t=<token>  -> 200 text/calendar (the account's You're In! and
//                      Response Needed clinics; see calendar_feed_events)
//                   -> 404, empty body: a malformed or unknown token, or a
//                      deleted account. One answer for all three, and no
//                      detail, so a guess learns nothing.
//   HEAD            -> the same status and headers, no body
//   anything else   -> 405
//
// verify_jwt is off (config.toml): Apple's Calendar, Google and Outlook
// fetch the link with a plain GET and send nothing but the URL, so the token
// in it is the credential. It is 32 random bytes as hex, made by
// my_calendar_feed_token() and replaced by reset_my_calendar_feed().
//
// Reads with the service role, through one function that returns only the
// five columns the feed needs (name, start, end, status, registration id).
// The token is never logged.
//
// The empty 404 body is also how scripts/hosted-smoke.sh tells this
// function's refusal from the gateway's "function not found", which is a 404
// with a body.

import { admin } from "../_shared/supabase.ts";
import { buildCalendar, type FeedRow } from "./ics.ts";

const TOKEN_SHAPE = /^[0-9a-f]{64}$/;

const notFound = () => new Response(null, { status: 404, headers: { "Cache-Control": "no-store" } });

Deno.serve(async (req) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  const token = new URL(req.url).searchParams.get("t") ?? "";
  if (!TOKEN_SHAPE.test(token)) return notFound();

  const { data, error } = await admin.rpc("calendar_feed_events", { p_token: token });
  if (error) {
    if (error.code === "P0002") return notFound();
    console.error("calendar-feed: database error " + (error.code ?? "unknown"));
    return new Response(null, { status: 500, headers: { "Cache-Control": "no-store" } });
  }

  let body: string;
  try {
    body = buildCalendar((data ?? []) as FeedRow[], new Date());
  } catch (_) {
    console.error("calendar-feed: could not build the calendar");
    return new Response(null, { status: 500, headers: { "Cache-Control": "no-store" } });
  }
  return new Response(req.method === "HEAD" ? null : body, {
    status: 200,
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      // Personal: no shared cache may keep it.
      "Cache-Control": "no-store",
    },
  });
});
