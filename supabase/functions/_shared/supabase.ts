// Shared Supabase service-role client and the JSON response helper, for edge
// functions that do not talk to Stripe. _shared/stripe.ts exports the same
// two things but imports the Stripe SDK at load, which review-submit has no
// use for; a function should not pull in a payments library to save a form.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
// service_role bypasses RLS by design and holds DML on every table
// (20260912000002); it is the role that writes what no client may write.

import { createClient } from "npm:@supabase/supabase-js@2";

export const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

export const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...extra } });
