# FXE Tennis — Web Admin

> **The members' website** is `play/` in this folder: the app's player side
> for members on Android, at `/play/` on the same deploy (decision 0043).
> Everything below is about Tara's admin.

Tara's laptop surface. **Needs no Apple account**: she opens a bookmark.

Approved as the laptop half of a split admin surface (`docs/web-admin.md`,
question 1 of her first list, now `docs/archive/for-tara.md`; every question
since lives in `docs/questions-for-tara.md`). The phone app keeps the
courtside work; this does weekly setup.

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
  tab: "12 played, 5 canceled (2 late), 1 no-show", or "New" (decision 0040)
* On each roster: courts, **Add player** (a walk-up), invite from the Player
  Pool, cancel an invitation, Remove, Came / No-show, **Late cancel** for
  someone who told her, and the player's private note under the name
  (decision 0039). A late cancel stays in the Canceled list with a red **Late
  cancellation** flag, and **Waive** with Undo drops its fee while no charge is
  taken (decision 0040)
* After a clinic, while payments are on: **Charge $N** on each row that owes,
  one person at a time (decision 0037), with Declined or No card beside it.
  (The Paid toggle and "Remind unpaid" are gated on `zelle_allowed`, which
  decision 0013 set to `false`: the card is the only way to pay, so neither
  renders today.)
* Message any audience on a clinic, starting from one of her **saved messages**
  if she likes (her own text, kept with Save this message; decision 0030)
* **Action Needed** at the top: players asking in after the 3-hour close (Put
  them in / No room), cancellations or invitation replies she has not seen, a
  clinic that ended and is not charged yet, a declined card (with Resolved),
  and an open dispute
* **Players** tab: search, member and active switches, her private note per
  player, the Pro box (decision 0025), a one-time Reset link for a member who
  cannot sign in (decision 0017), Review links, and the QR code for the app
  with how often it was opened
* **Money** tab: the board report (Download CSV, Print, Foxcroft's share),
  Charged / Declined / Not charged yet, Payouts from Stripe, the card-payments
  list with Refund, and a line per clinic. Three tabs across the top: This
  week, Players, Money; the last one opened is remembered
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

68 Playwright tests (`cat web/tests/*.spec.mjs | grep -cE '^\s*test\('`,
2026-10-12) walk this page the way Tara does, against the LOCAL stack on a
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

## Deploy it

There is no build step and no server, just the static files in this folder.

**Live at <https://fxe-tennis-admin.vercel.app>** (Vercel project
`fxe-tennis-admin`, first deployed 2026-08-28). Deploy only with this, from
the repo root:

```bash
bash scripts/deploy-web.sh
```

It deploys to Vercel production, then fetches every live page, script and
stylesheet and compares it with this folder byte for byte, deploying once
more if the first deploy silently did nothing (three times in September a
plain deploy printed nothing and changed nothing). It exits red if the
live site still differs, and it checks that `.vercelignore` keeps the test
tooling off the site. Do NOT connect the Git repo to Vercel: previews would
point at Tara's live data, and the repo root is not this folder.

Anything not on `localhost` talks to the hosted project automatically.

## How Tara got in

Sign-up exists in this page ("First time? Create your account"). Her email
self-promotes to admin at account creation (`bootstrap_first_admin`,
20260828000001), so the whole bootstrap is: she opens the live URL, creates
her account, and builds her week from templates. Her real clinics enter
through this page, never a hand-written INSERT, so the path itself gets
exercised (checklist D5).

**Password reset** on hosted lands on `https://fxe-tennis-admin.vercel.app/reset.html`,
which is on the Supabase redirect allow-list (checklist D2, D11).
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

Kat's style guide, `docs/style-guide.md`, is the source of truth for style
(Alex, 2026-09-22). `FXETennis/Resources/Brand.swift` carries it into code,
and `tokens.css` follows `Brand.swift`: colours, radii and spacing are
transcribed from it, so the web admin and the phone app cannot drift into
looking like two different products. `tokens.css` once sat on palette A for
two weeks after `Brand.swift` moved to B, so a style change goes into the
guide's mapping and `Brand.swift` first, then here.

Status chips use the locked terminology (**You're In!**, **Player Pool**,
**Response Needed**, **Canceled**) and pair colour with the label, never colour
alone.
