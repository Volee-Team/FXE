// Which Supabase project the web admin talks to.
//
// The publishable ("anon") key is SAFE in a client. It identifies the project,
// not a person: every request still carries the signed-in user's JWT, and
// Postgres decides what that user may do via RLS and require_admin(). The same
// key ships inside the iOS binary. The SECRET key must never appear here.
//
// Auto-detects rather than needing an edit before every test, because a manual
// switch is the kind of thing that gets committed pointing at the wrong project.
// Served from localhost -> local stack. Anywhere else -> hosted.
const isLocal = ["localhost", "127.0.0.1"].includes(location.hostname);

export const ENV = isLocal ? "local" : "hosted";

export const CONFIG = {
  hosted: {
    url: "https://amnaxvznkadkgzdxzegw.supabase.co",
    key: "sb_publishable_J-UBIJSqeljvVuyb4P27Jg_jLngLuBW",
  },
  local: {
    url: "http://localhost:54321",
    key: "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
  },
}[ENV];
