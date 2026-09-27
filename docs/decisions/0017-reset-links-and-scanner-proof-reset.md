# 0017: Tara can make a reset link for a member; the reset page takes scanner-proof links

**Date:** 2026-09-27 · **Status:** Active · **Decided by:** Alex (engineering), on *"for the password reset, i thoguht it was smth super simple and free u build for volee? like it can be ultra simple for now but i want YOU to do as much as possible"*

## The problem

"Forgot password?" reached no member. Verified 2026-09-27 through the
management API: hosted has no custom SMTP (`smtp_host` null), so Supabase's
built-in sender is used, which delivers only to the Supabase project's own
team at 2 an hour. The Site URL was `http://localhost:3000`. The reset email's
link is GoTrue's `{{ .ConfirmationURL }}`, a one-time link that an email
scanner or link preview can spend before the member taps it: the failure
Volee hit and fixed with a token-hash link (Volee `CLAUDE.md`, "Email
template").

## What we chose

1. **A reset link Tara makes by hand.** Players tab → **Reset link**. The
   `admin-reset-link` edge function checks `is_admin()` as the caller, makes a
   GoTrue recovery token with `auth.admin.generateLink` (which sends nothing),
   and returns `https://fxe-tennis-admin.vercel.app/reset.html#token_hash=…&type=recovery`.
   Tara copies it and texts it. It works once, within the project's OTP
   lifetime (`mailer_otp_exp`, 3600 seconds). It needs no email at all, so it
   works today, and it keeps working after SMTP exists for the member whose
   email is misspelled or whose mail goes to spam.
2. **What a link really is: a full session for that member**, not a
   password-only permission. Nothing in the schema narrows a recovery
   session, and the token can be exchanged with a bare request, without the
   page (sql-auditor, 2026-09-27). Everything below follows from that:
   - **An admin account is never a target** (403 `admin_target`): a leaked
     link would be a full admin session, which sees all nine hidden facts.
   - **The token rides in the URL fragment** (`#token_hash=`), which no
     browser sends in any request, so it never reaches a server log or a
     link-preview fetcher.
   - **Every link handed out is recorded** in `reset_links_issued` (whose
     account, who made it, when), after the sign-in the token belongs to is
     checked against the account (`identity_mismatch` otherwise: nothing keeps
     `accounts.email` in step with the sign-in's email) and before the link is
     returned. A token that is never returned cannot be used by anyone. The
     record says a link was made, not that it was used; it answers "did anyone
     ever make a link for my account?", which is the question that matters.
   - **The reset page keeps the member's session in memory only**
     (`persistSession: false`, its own storage key). The admin site shares
     that origin: a stored session would outlive the page, or replace Tara's
     own if she opened a link herself.
   - **Saving the new password signs the account out everywhere.** GoTrue
     v2.195.0 already ends a user's other sessions on a password change
     (checked locally 2026-09-27: a phone session's refresh answers 200
     before and 400 after), and the page also calls `signOut({ scope: "global" })`
     so the outcome does not depend on the server's version and the page's own
     session ends too. The member's phone asks for the new password once.
     The browser test pins the outcome.
   - The page sends no Referer (`<meta name="referrer" content="no-referrer">`).
3. **The reset page takes token-hash links.** `web/reset.html` calls
   `verifyOtp({ token_hash, type: "recovery" })`, so nothing is spent until the
   page runs in a real browser. It still accepts the email's current link
   (the `#access_token` redirect) and says "expired" for `#error_code`.
4. **The reset email moves to the token-hash link** once custom SMTP exists
   (checklist D1): template `{{ .SiteURL }}/reset.html#token_hash={{ .TokenHash }}&type=recovery`,
   Site URL `https://fxe-tennis-admin.vercel.app`. Set through the management
   API by the model, with the before and after values in the changelog.
5. **Email itself**: a Gmail account made for the app, with an app password,
   as Supabase's custom SMTP (`docs/for-alex.md` §6). Free, about ten minutes,
   no domain. Resend with the club's own domain stays the later option.
6. **CORS for every function the web admin calls** (`supabase/functions/_shared/cors.ts`): the
   admin site and the functions are different origins, and hosted's gateway
   does not answer preflights for a function. Found by the sql-auditor on this
   function, then confirmed on hosted for `stripe-charge`, which answered the
   preflight with 405 and no header: Charge clinic on the web would have queued
   fees that never reached Stripe. Local tests could never see it, because the
   local gateway answers preflights itself. `scripts/hosted-smoke.sh` now sends
   a preflight to each browser-called function and requires a 2xx and the
   origin; the status matters, because hosted answers a function that does not
   exist with 404 and `allow-origin: *`.
7. **The member is not notified that a link was made.** The link exists
   because the member asked Tara for it; a notice would tell them what they
   already know. If Tara ever makes links unasked, that is her call to change.

## Rejected

- **Waiting for SMTP.** Leaves every member locked out until Alex has ten
  free minutes, and leaves the misspelled-email member locked out forever.
- **Tara types a new password for the member.** She would know it, and the
  member would have to be told it, in a text, in clear.
- **Admin link that also emails the member.** Needs SMTP, which is the problem.
- **Allowing links for admin accounts** because "it is the same as Forgot
  password" (the first draft). It is not: Forgot password sends the link to
  her inbox, this puts it on a screen and a clipboard. Refused (point 2).
- **The token in the query string** (Volee's shape). It reaches Vercel's
  request logs and every link-preview fetcher. The fragment reaches neither.
- **PKCE on the reset page.** A reset started on the phone must finish in a
  browser; PKCE binds the code to the device that asked (the 2026-09-01
  lesson in `CLAUDE.md`).

## How it is tested

- `tests/reset/run.sh` (CI job "Reset link"): 25 checks. Signed out 401, a
  member 403, a deleted admin 403, bad input and a JSON null 400, unknown
  player 404, deleted account 409, an admin account with a player row 403
  `admin_target`, each refusal with no audit row; the link is the page with
  the hash in the fragment and nothing in the query, no email or access token
  in it; one audit row naming Dana and Tara; the token works once; the new
  password signs in and the old one does not. Red with the admin check removed
  (3 checks), the audit insert removed (1) and the admin-target guard removed
  (3).
- `web/tests/admin.spec.mjs` "reset page": a fragment link opens the form,
  leaves the address bar, stores nothing in the browser, saves, ends the
  member's other session, the new password signs in, and the same link a
  second time says expired. Red against the old page, and red with the
  session stored again. Removing the page's own global sign-out stays green,
  because GoTrue ends the other sessions itself (point 2).
- `tests/sql/grants_are_explicit.sql`: the base tables a member can read are
  an allowlist, and REFERENCES and TRIGGER are now in the enumerated lists.
  Red when SELECT or REFERENCES is granted on `reset_links_issued`.
- `scripts/hosted-smoke.sh`: the function and the table answer a signed-out
  caller with 401/403, and the three browser-called functions answer a
  preflight from the admin site.

## How we would know this was wrong

A member reports a link that "didn't work" (expired before they opened it:
raise `mailer_otp_exp`), or the audit table shows links Tara does not
remember making.
