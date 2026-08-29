# FXE Tennis — Web Admin

Tara's laptop surface. **Needs no Apple account**, which is the whole reason it
exists right now: the iOS app is stuck behind Developer Program enrollment and
she can use this today.

Approved as the laptop half of a split admin surface (`docs/web-admin.md`,
`for-tara.md` question 1). The phone app keeps the courtside work; this does
weekly setup.

## What she can do here

* See every clinic, including drafts, with capacity and both prices
* **Create and edit clinics** — the thing she asked for directly
* Publish a draft
* Invite from the Player Pool, mark players paid, cancel an invitation
* Message any audience on a clinic

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

## Deploy it (free, ~5 minutes)

There is no build step and no server. It is three static files.

**Vercel**

1. `npm i -g vercel` (once)
2. `cd web && vercel --prod`
3. Accept the defaults. It prints a URL. Send that to Tara.

**Or Netlify:** drag the `web/` folder onto <https://app.netlify.com/drop>.

**Or Cloudflare Pages**, which is what `docs/web-admin.md` originally specified.
Any static host works; nothing here depends on the platform.

Anything not on `localhost` talks to the hosted project automatically.

## Before Tara can actually use it

Hosted currently has **0 accounts and 0 clinics**, so she would sign in to an
empty page. Two things, in order:

1. **Create her admin account.** She signs up in the iOS app or via Supabase
   Auth, then her `accounts.role` is set to `admin` once, by hand. There is no
   RPC for granting admin on purpose: hard rule 8 says a privilege column is
   never writable by the role it grants privilege to, and an admin-maker RPC
   would be exactly that.
2. **Her real clinics** go in through this page, not a hand-written INSERT, so
   the path itself gets exercised. Her week is in `docs/taras-real-week.md` and
   the descriptions are in `docs/copy.md`.

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
