# FXE Tennis — Web Admin

Tara's laptop surface. **Needs no Apple account**, which is the whole reason it
exists right now: the iOS app is stuck behind Developer Program enrollment and
she can use this today.

Approved as the laptop half of a split admin surface (`docs/web-admin.md`,
`docs/for-tara.md` question 1). The phone app keeps the courtside work; this does
weekly setup.

## What she can do here

* See this week's clinics and everything after, including drafts, with capacity
  and both prices. Older clinics wait behind "Show earlier" (newest first), except
  that while payments are on, a finished clinic nobody has charged stays in view
* **Create and edit clinics** — the thing she asked for directly
* Publish a draft
* **Copy to next week**: every clinic of this week, canceled ones aside, copied
  seven days later on the same New York clock as drafts, with next week's
  windows and prices; a second click copies nothing (decision 0027)
* **Court sheet** on each clinic card: `sheet.html`, the You're In! players by
  court with their ratings, to print instead of the handwritten sheet
* A player's history beside the name in every Player Pool and on the Players
  tab: "12 played · 1 no-show · 2 late cancels", or "New"
* Invite from the Player Pool, mark no-shows, cancel an invitation. (The Paid toggle and "Remind unpaid" are gated on `zelle_allowed`, which decision 0013 set to `false`: the card is the only way to pay, so neither renders today.)
* Message any audience on a clinic
* **Action Needed** at the top: players asking in after the 3-hour close (Put
  them in / No room) and cancellations or invitation replies she has not seen
* **Money** on its own tab: the four counts, expected / collected / still owed,
  and a line per clinic. Three tabs across the top: This week · Players · Money;
  the last one opened is remembered
* Forgot password? on the sign-in card, landing on `reset.html`
* Canceled clinics are hidden until "Show canceled" is ticked; they stay in
  the database (archive, never delete)

Registration windows are computed for her: members Thursday 8am, everyone else
Friday 8am, for the whole service week the clinic falls in (decision 0001). She
never types a window. Prices come from clinic length, so a typo cannot
undercharge the club.

## Run it locally

```bash
supabase start && supabase db reset      # local stack + seed
python3 -m http.server 8765 --directory web
```

Open <http://localhost:8765>. `config.js` detects `localhost` and points at the
local stack automatically, so testing never requires editing a file that could
get committed aimed at the wrong project. Sign in as `tara@fxe.test` /
`password`.

## Test it

38 Playwright tests (`cat web/tests/*.spec.mjs | grep -cE '^\s*test\('`,
2026-09-28) walk this page the way Tara does, against the LOCAL stack on a
fresh seed. They are the only automated check on the web admin,
so they run in CI on every push (`web-browser-tests` in `probes.yml`).

```bash
supabase start && supabase db reset
cd web && npm ci && npx playwright install chromium && npx playwright test
```

`playwright.config.mjs` starts a `python3 -m http.server` on port 8790 for
you. Tests share one database, so they run in one worker, in file order, and
none depends on another's writes; run them after a reset.

## supabase-js lives in `vendor/`

The pages import `./vendor/supabase-js.js`, never a CDN. Until 2026-09-27 they
imported `https://esm.sh/@supabase/supabase-js@2`, whatever 2.x that site served
that day, running with Tara's session; a CDN outage or a bad release would have
taken this page and every password reset down on a day nobody deployed.

The file is the npm package's own browser bundle at the exact version pinned in
`package.json`, with two export lines added. To move to a new version (Dependabot
proposes it, and the web CI job stays red until this is done):

```bash
cd web && npm ci && cd .. && bash scripts/vendor-supabase-js.sh
supabase db reset && (cd web && npx playwright test)
git add web/vendor web/package.json web/package-lock.json
```

`bash scripts/vendor-supabase-js.sh --check` is what CI runs: it rebuilds the
file from the installed package and compares it byte for byte.

## Deploy it (free, ~5 minutes)

There is no build step and no server — just the static files in this folder.

**Live at <https://fxe-tennis-admin.vercel.app>** (Vercel project
`fxe-tennis-admin`, deployed 2026-08-28). Redeploy after changes with
`cd web && npx vercel --prod`. Do NOT connect the Git repo to Vercel: previews
would point at Tara's live data, and the repo root is not this folder.

**Vercel**

1. `npm i -g vercel` (once)
2. `cd web && vercel --prod`
3. Accept the defaults. It prints a URL. Send that to Tara.

**Or Netlify:** drag the `web/` folder onto <https://app.netlify.com/drop>.

**Or Cloudflare Pages**, which is what `docs/web-admin.md` originally specified.
Any static host works; nothing here depends on the platform.

Anything not on `localhost` talks to the hosted project automatically.

## Before Tara can actually use it

~~Two things~~ **Nothing — as of 2026-09-01 the path is fully open.** Hosted has
every migration, and sign-up exists in this page ("First time? Create your
account"). Her email self-promotes to admin at account creation
(`bootstrap_first_admin`, 20260828000001), so the whole bootstrap is: she opens
the live URL, creates her account, and builds her week from templates. Her real
clinics enter through this page, never a hand-written INSERT, so the path itself
gets exercised.

**Password reset** works on hosted: `https://fxe-tennis-admin.vercel.app/reset.html`
was added to the Supabase redirect allow-list on 2026-09-01 (`docs/backlog.md`).
If the URL ever changes, add the new one there first: Supabase silently falls
back to the Site URL for anything not on that list.

## Why the key in `config.js` is not a leak

It is the **publishable** key. It identifies the project, not a person. Every
request still carries the signed-in user's JWT, and Postgres decides what that
user may do through RLS and `require_admin()`. The same key ships inside the iOS
binary. Signing in as a non-admin here shows nothing: `clinics_admin` returns
zero rows and every admin RPC raises `not_authorized`.

The **secret** key must never appear in this folder. CI's `secret-scan` job
fails the build if it does.

## Design

Colours, radii and spacing come from `tokens.css`, transcribed from
`FXETennis/Resources/Brand.swift`, so the web admin and the phone app cannot
drift into looking like two different products. `tokens.css` sat on palette A
for two weeks after `Brand.swift` moved to B; **Brand.swift is the source of
truth**, change it there first.

Status chips use the locked terminology (**You're In!**, **Player Pool**,
**Response Needed**, **Canceled**) and pair colour with the label, never colour
alone.
