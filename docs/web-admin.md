# Web Admin: Architecture Decision Record

**Status:** accepted, not yet built
**Date:** 2026-08-02
**Decision owner:** Alex
**Approved by:** Tara (split admin surface, per `for-tara.md` question 1)

---

## Context

Tara approved splitting the admin surface in two.

* **Phone (existing iOS app):** courtside work. Invitations from the Player Pool, clinic messages, marking players paid, walk-up placement. Things done standing on a court with one hand free.
* **Laptop (this document):** weekly setup and court assignment. Creating a week of clinics from templates, editing templates, working the player directory, dragging players across courts 1 to 5.

The database is already built and locked down. Three migrations exist:

* `supabase/migrations/20260728000001_core_schema.sql`
* `supabase/migrations/20260728000002_helpers_views_rls.sql`
* `supabase/migrations/20260728000003_rpcs.sql`

The security model is settled and this document does not reopen it. Clients have no direct table access to `clinics`, `registrations`, `player_notes`, `clinic_templates`, `clinic_messages`, `clinic_message_recipients`, or `news_posts`. Reads go through narrow views. Writes go through `SECURITY DEFINER` RPCs that call `require_admin()`, which calls `is_admin()`, which reads `accounts.role` for `auth.uid()`.

Everything below is downstream of that. The web admin is a client. It gets no more authority than the phone does.

---

## 1. Decision: static single-page app, no server

**Build a static SPA with Vite plus TypeScript plus React, compiled to plain files, hosted free on Cloudflare Pages, talking directly to Supabase with `@supabase/supabase-js`.**

There is no application server. There is no backend to deploy. The build output is HTML, JS, and CSS on a CDN. Every privileged operation is a PostgREST call to an RPC that Postgres itself authorizes.

### Why this is right, argued rather than assumed

The system has exactly one user. That single fact kills most of the reasons anyone reaches for infrastructure:

* No horizontal scaling concern. One session, a few hundred rows.
* No SEO, so no server rendering.
* No caching layer, no CDN strategy beyond "put the files somewhere."
* No background jobs. Nothing in the admin flow is asynchronous.
* No multi-tenant isolation. `is_admin()` already is the isolation.

What is left is a form-and-table application over an existing API. That is the smallest thing a browser can do.

The load-bearing argument is not "less code is nicer." It is this: **a server would be a second place authorization lives.** The moment there is a Node process holding a service-role key, the `is_admin()` gate stops being the whole story, and every route on that server becomes a thing that must be independently audited for whether it checked who was calling. Today the answer to "can this caller do that?" is one function in Postgres, pinned by `tests/sql/information_hiding.sql`. Adding a server means that probe no longer proves what it currently proves. That is a real, permanent tax paid forever, for one user.

So the burden of proof runs the other way. Infrastructure must earn its place. Nothing in the admin screens earns it.

### Honest tradeoffs of the static SPA

* **The Supabase URL and anon key ship in the bundle.** This is correct and intended, not a leak. The anon key grants the `anon` role and nothing more. It cannot read `clinics`, cannot read `registrations`, cannot execute `notify_account`. Authority comes entirely from the signed JWT that Supabase Auth issues after a real password login. Anyone can read the anon key out of the JavaScript and get exactly what a logged-out stranger gets, which is `clinics_public` and nothing else. Verify this claim once with a probe rather than trusting the paragraph.
* **No server-side validation layer.** Every validation must exist in Postgres, because the client can be bypassed with `curl`. This is already how the schema is written: check constraints, the partial unique index `registrations_one_live`, the `FOR UPDATE` lock in `register_for_clinic`. Client-side validation in the web admin is a courtesy to Tara, never a control.
* **Cold data on every page load.** No server cache means every screen refetches. At this row count that is tens of milliseconds. Irrelevant.
* **React costs about 45 KB gzipped for one user.** A no-build vanilla page would be smaller. It would also mean hand-rolling list reconciliation across seven screens plus drag state, which is exactly where bugs live and exactly what React is for. The 45 KB buys correctness, not speed. Take the trade.
* **Build-time environment variables.** Changing the Supabase project means a rebuild, not a config edit. Acceptable: it happens approximately never.
* **No offline capability.** If the club Wi-Fi is down, the laptop page does nothing. Mitigation is the phone app, which is the courtside surface anyway.

### Alternatives considered and rejected

| Option | Why rejected |
|---|---|
| **Next.js / SvelteKit / any SSR framework on Vercel** | Adds a runtime, a deploy pipeline, and a place a service-role key can end up. Buys SEO and server rendering, neither of which exists as a requirement. Rejected. |
| **Supabase Studio table editor as the admin UI** | Free, zero build, available today. Fails on two counts: it connects with the service role and therefore bypasses `is_admin()` entirely, creating the second security model this design exists to avoid, and it would have Tara editing raw enum values in a grid. Rejected as the product, kept as the emergency fallback if the web app slips a week. |
| **Retool, Airtable, or any no-code admin builder** | Requires a service key or a direct Postgres connection string, so again it routes around the grant model. Also a monthly bill and a vendor dependency for a page with seven screens. Rejected. |
| **Native Mac app or Electron** | Install friction, code signing, an update mechanism, and a second Swift or JS codebase. A bookmark is strictly better than an installer. Rejected. |
| **Extend the iOS app and run it on an iPad** | Technically possible and it reuses the Swift client. Rejected because it does not solve the actual problem: typing a week of clinic details and dragging twenty players across five courts is bad on touch and good with a keyboard and a mouse. Solving that is the entire premise of the split. |
| **Vanilla TypeScript, no framework** | Genuinely tempting. Rejected on the drag-and-drop screen specifically: manual DOM reconciliation while a drag is in flight and an optimistic update is pending is the single highest-bug-density code in this project. Let a renderer own it. |

### Concrete stack

```
web-admin/
├── index.html
├── src/
│   ├── main.tsx
│   ├── lib/supabase.ts        # single client instance, session persisted
│   ├── lib/db.types.ts        # generated: supabase gen types typescript
│   ├── screens/               # one file per screen in section 3
│   └── styles/tokens.css      # navy / cream / green, plain CSS custom properties
├── public/_headers            # CSP, see section 5
├── vite.config.ts
└── package.json
```

Dependencies: `react`, `react-dom`, `@supabase/supabase-js`, `vite`, `typescript`. That is the whole list. No component library, no CSS framework, no state manager, no router beyond a `useState` screen switch or `wouter` if a real URL per screen turns out to matter. No date library: `Intl.DateTimeFormat` with `timeZone: 'America/New_York'` handles every display need here, and all window math already lives in Postgres.

Types come from `supabase gen types typescript` against the local stack, committed to the repo. This is the quiet win of the static SPA: the schema is the type system on both ends, and a column rename breaks the build instead of breaking Tara's Tuesday.

---

## 2. Auth: one gate, two front doors

### How Tara signs in

The same email and password she uses in the phone app. There is one `auth.users` row, one `accounts` row, `role = 'admin'`. Supabase Auth issues a JWT plus a refresh token. `@supabase/supabase-js` persists the session in `localStorage` and rotates the refresh token in the background, so she signs in once on her laptop and stays signed in indefinitely.

No separate admin credential. No second account. No invite link, no magic link, no SSO. Adding any of those creates a second identity to keep in sync with the first, and the first one already works.

### How the admin role is proven

Not by the client. Ever.

The JWT carries `sub`, which becomes `auth.uid()` inside Postgres. Every admin RPC opens with `perform public.require_admin()`, which raises `not_authorized` with SQLSTATE `42501` unless `is_admin()` returns true, and `is_admin()` is:

```sql
select exists (
  select 1 from public.accounts
  where id = auth.uid() and role = 'admin'
);
```

The web app calls `is_admin()` once at startup to decide whether to render the admin UI or an "access denied" panel. **That call is cosmetic.** It controls pixels, not permissions. If someone patched the JavaScript to skip the check, they would see the admin chrome and every single request behind it would fail in the database. This distinction is worth stating in a code comment at the call site, because the next person to read it will assume it is the gate.

The admin views work the same way. `clinics_admin` and `registrations_admin` are `select * from <table> where public.is_admin()`. Postgres views default to `security_invoker = false`, so they execute with the owner's rights and can read base tables the client cannot. **The `where public.is_admin()` predicate is therefore the entire access control on those views.** Delete it and the view leaks the full roster to every authenticated player. That is worth an explicit probe assertion, not just a comment.

### Why the same gate covers both surfaces

Because the web admin is not a new kind of thing. It is a second client of an API that already exists.

Identical Supabase project. Identical PostgREST endpoint. Identical anon key. Identical grants. Identical RPCs. The only difference between the iOS app and the web app is which HTTP library formats the request. Postgres cannot tell them apart, and it does not need to, because it was never trusting the caller in the first place.

Write this rule down and keep it:

> **The web admin never holds a key more powerful than the phone does.**

That single sentence is what keeps the security model singular. The instant a service-role key touches this project, `information_hiding.sql` stops being a complete proof, because it authenticates as a player and probes the database, and it cannot probe a bypass route that exists somewhere else. There would then be two models, one of them untested.

Practical enforcement: a CI step greps the build output for `service_role` and for a JWT payload containing that role, and fails the build on a hit. Cheap, and it catches the mistake at the only moment it is easy to fix.

### Threat model, briefly

The realistic threat is not a crafted request. It is an unlocked laptop in a tennis club office.

* Ship a visible sign-out button. Not buried in a menu.
* Do not implement "remember me" as anything beyond the default session persistence, and document that she should sign out on any machine that is not hers.
* Supabase supports TOTP MFA. It is a v1.1 item, not v1: it protects against remote credential theft, which is not the leading risk here, and it adds an enrollment flow that must also work on the phone.
* Shortening JWT expiry does nothing useful. Refresh tokens make it transparent, and the attacker in the realistic scenario is sitting at the already-signed-in browser.

---

## 3. Web versus phone, screen by screen

Mapped to the admin screens in the developer guide. "Primary" means that surface owns the workflow, gets the full feature set, and is where Tara is expected to do the work. The other surface may still show the data.

| Guide screen | Web | Phone | Reasoning |
|---|---|---|---|
| **Dashboard / Action Needed** | Read plus act | **Primary** | This is a glance-and-tap surface. Pool invitations, cancellations to acknowledge, unanswered invitations. It happens between courts, not at a desk. Web shows the same list because if she has the laptop open she should not have to reach for her phone, but the phone is the one that gets push notifications. |
| **Clinic Management** | **Primary for setup:** create from template, edit details, set capacity, adjust windows, publish, cancel. | **Primary for day-of:** open a clinic, see the roster, place a walk-up, invite from the Pool. | This is the split that motivated the whole project. Building next week's schedule is ten forms and a lot of typing. Running today's clinic is a list and some buttons. |
| **Templates** | **Web only** | Not present | Templates are pure configuration, edited rarely, mostly at the start of a season. Long text fields, prices, durations, capacities. Zero reason to build this twice, and no reason it ever gets touched courtside. |
| **Player Directory** | **Primary.** Full search, filters, member status, activate and deactivate, and the private coaching notes editor. | Search plus view. Read notes, but composing a paragraph of notes belongs on a keyboard. | `search_players` already exists and is admin-gated. Note that it deliberately returns `has_notes` as a boolean and never the note body: the note body needs its own RPC, see section 6. |
| **Court Assignment** | **Web only for editing.** Drag and drop across courts 1 to 5. | Read-only view of today's assignment. | Detailed below in section 4. Editing five columns of players is a laptop task. Glancing at "who is on court 3" while standing on court 3 is a phone task, and the phone should never let her drag by accident. |
| **Messaging** | Present, same audiences | **Primary** | "Running fifteen minutes late" is typed on a phone, from a car. The web version exists because composing a longer message is nicer with a keyboard, and both call the same `send_clinic_message` RPC with the same `message_audience` enum. |
| **News** | **Primary for compose and publish** | Read the published list | News posts are paragraphs. Nobody writes a club announcement on a phone if a laptop is open. |

Two rules that fall out of this table:

1. **No screen is web-only by accident.** Templates, note editing, and court editing are web-only because a deliberate decision was made. Everything else exists on both.
2. **Both surfaces call identical RPCs.** There is no `web_send_message` and no `admin_web_*` anything. If a behaviour differs between the two, that difference lives in the UI, never in the database. Otherwise the two surfaces drift and the schema grows a wart per divergence.

---

## 4. Court assignment

### What exists today

`registrations.court_number` is a `smallint`, nullable, constrained to `between 1 and 5`. The write path is one RPC:

```sql
assign_court(p_registration uuid, p_court smallint)
```

`p_court` accepts `NULL`, which the check constraint permits, so "drag back to unassigned" needs no new function. Court assignment is a column on the row that already joins clinic and player, deliberately, and not its own table.

### Recommendation

**Build six columns: Unassigned, then Court 1 through Court 5. Every player card is draggable with the native HTML5 drag-and-drop API. Every player card also carries a permanently visible court `<select>` showing the same value. Both paths call the same `assign_court` RPC.**

The dropdown is not a fallback that appears when drag fails. It is always there, always in sync, and it is the path that gets built and tested first. Drag-and-drop is added on top as an accelerator once the dropdown path is proven. If drag-and-drop is not working by ship day, the screen still ships, complete, and the drag lands in the next deploy.

That sequencing is the actual recommendation. The technology choice is secondary.

### Why native HTML5 drag-and-drop, not a library

This is laptop-only, mouse-only, one browser, one user. `dragstart`, `dragover`, `drop`, and `dragend` cover it in roughly eighty lines. `react-dnd` and `dnd-kit` are excellent and solve problems this screen does not have: touch input, nested sortable trees, virtualized lists, keyboard reordering, accessible live regions. Importing 30 KB and a mental model to move a name between five boxes on a laptop is not a good trade.

### What native drag-and-drop costs, stated plainly

* **Touch does not work.** HTML5 drag events do not fire on iOS Safari or Android Chrome. This is a real limitation and it is fine, because the phone gets a read-only view by decision. The dropdown covers a touch laptop or an iPad if either ever appears.
* **`dragover` must call `preventDefault()` or `drop` never fires.** The single most common bug with this API. Worth a comment at the handler, since the line looks like dead code.
* **The drag image is the browser's default ghost.** Styling it means `setDragImage` with an off-screen node. Skip it. It looks acceptable as-is.
* **No animation.** Cards do not slide into place, they appear. Acceptable and arguably clearer.
* **Keyboard accessibility is zero.** The dropdown is the keyboard and screen-reader path, which is another reason it stays permanent rather than being a fallback.
* **`dragenter` and `dragleave` fire on child elements too,** so a naive "highlight the drop target" implementation flickers. Counter enter and leave events per drop zone, or set `pointer-events: none` on the column's children during a drag. Also worth a comment.

### Write strategy: one RPC call per drop, optimistic, with rollback

On drop: move the card in local state immediately, then `await assign_court(...)`. On error, put the card back and show the error. Do not spin, do not disable the board, do not batch.

Rejected alternatives:

* **Batch into a "Save Layout" button.** Introduces unsaved state, which introduces "did I save?", which introduces a leave-page warning, which introduces a bug where she closes the tab and loses twenty minutes of arranging. Per-drop persistence means the board on screen is always the board in the database. For one user with no concurrent editor, there is no reason to batch.
* **A bulk `assign_courts_bulk(jsonb)` RPC.** Not needed for drag, since a drag moves one player. It becomes worth building only if a "clear all courts" or "copy last week's layout" button is requested, and neither is in v1.

Concurrency is a non-issue here by construction: one admin, and `assign_court` is a last-write-wins single-column update with no state machine. This is the one place in the schema where an unconditional update is correct, and it is worth a comment saying so, because hard rule 3 says every state transition is conditional and a reader will flag this as a violation. Court number is not a state transition, it is a value.

### Data the screen needs

One flat payload per clinic: registration id, player first and last name, current status, paid flag, court number. `registrations_admin` returns the registration rows but not the names, and relying on PostgREST to auto-detect an embeddable relationship through a view is fragile. Build an explicit RPC, `admin_clinic_roster(p_clinic uuid)`, returning a table. See section 6.

Only `status = 'in'` players appear on the board. Pool and Response Needed players are not on a court, by definition.

---

## 5. Deployment and how Tara opens it

### Hosting

**Cloudflare Pages, free tier.** The repo gains a `web-admin/` directory. Pages connects to the GitHub repo, build command `npm run build`, output directory `web-admin/dist`, root directory `web-admin`. Push to `main` deploys. Netlify is an equivalent choice and the decision does not matter much: pick Cloudflare because there is no build-minute cap to think about.

The URL is a `*.pages.dev` address on day one. A custom domain, `admin.fxetennis.com` or similar, is a five-minute DNS change whenever someone wants one and is not a v1 requirement.

### What Tara actually does

She opens a bookmark. That is the entire interaction model.

1. One-time: Alex sends her the URL, she bookmarks it in Chrome or Safari on her laptop.
2. First visit: email and password, the same ones as the phone app.
3. Every visit after: the bookmark opens straight to the dashboard. The session persists and refreshes silently.

No app install. No App Store review. No update prompt, ever: a deploy is live on her next page load. No VPN, no IP allowlist, no separate password to remember, no browser extension.

Being genuinely blunt about the one downside: because there is no install step, there is also no offline mode and no "the app is open in my dock" affordance. If the club internet is down the page is blank. The phone app on cellular is the answer, and the phone app owns the time-sensitive courtside work precisely for reasons like this.

### Build hygiene

* `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` set in the Pages dashboard. Both are public values by design and both end up in the bundle. That is expected.
* CI greps `dist/` for `service_role` and fails on a hit. See section 2.
* `public/_headers` sets a CSP restricting `connect-src` to the Supabase project origin, `default-src 'self'`, and `frame-ancestors 'none'`. Cheap and it makes an injected script's exfiltration options much worse.
* No analytics. No error reporting service. One user who can be texted directly does not need Sentry.
* Preview deployments on pull requests are on by default and point at the same production Supabase project. Either turn them off or point them at a separate project. Do not leave PR previews writing to Tara's live data.

---

## 6. Database work this requires

The current migrations do not yet support the full web admin. These gaps are real and should be scoped before the UI work starts, because several screens are unbuildable without them. Every one follows the existing pattern: `SECURITY DEFINER`, `set search_path = public, pg_temp`, opening with `perform public.require_admin()`, and `grant execute ... to authenticated`.

1. **`admin_upsert_template` and `archive_template`.** `clinic_templates` is revoked from `authenticated` and no RPC writes it. The Templates screen cannot exist today. Blocking.
2. **`admin_upsert_clinic`.** `create_clinic_from_template` is the only path that creates a clinic, and nothing edits one after creation. Tara needs to adjust a time, a capacity, or an override window. Blocking for Clinic Management.
3. **`admin_upsert_news`.** `publish_news` transitions a draft to published, but nothing creates the draft. Blocking for News.
4. **`admin_get_player_note` and `admin_set_player_note`.** `player_notes` is revoked and RLS-admin-only, so it is currently unreachable from any client. `search_players` correctly returns only `has_notes`. Blocking for the notes feature on Player Directory.
5. **`admin_clinic_roster(p_clinic uuid)`.** A flat join of registrations and player names for one clinic. Needed by both the roster view and the court board. Blocking for Court Assignment.
6. **`admin_action_needed()`.** Optional. The dashboard can be composed client-side from `registrations_admin` plus `notifications`. Build the RPC only if the client-side composition turns into three round trips.

Every one of these gets a probe in `tests/sql/`, and `information_hiding.sql` gets re-run afterward, because each new RPC is a new potential leak path. The note RPCs in particular deserve an explicit probe asserting a non-admin cannot call them.

---

## 7. Deliberately not in v1

Each of these is a decision, not an oversight.

* **No offline support, no service worker, no PWA install.** The phone is the offline-tolerant surface.
* **No realtime subscriptions.** One admin means nothing changes underneath her except a player registering or answering an invitation. Refetch on tab focus via `visibilitychange`, plus a visible refresh button. Realtime on RLS-protected tables also needs publication configuration that would have to be audited against the information-hiding rules, which is real work for a benefit of "the number updates without clicking."
* **No admin-side push or email.** Notifications reach her phone. The laptop page is opened deliberately.
* **No multi-admin UI, no roles beyond `member` and `admin`, no permission editor.** `accounts.role` already supports a second admin as an `UPDATE` statement. Do not build a screen for it before a second admin exists.
* **No CSV import or export, no reporting, no charts.** Nobody has asked. The data is in Postgres and can be queried directly if a one-off question comes up.
* **No payment processing.** `registrations.paid` is a checkbox Tara ticks. It stays a checkbox.
* **No print stylesheet or printable court sheet.** Flagged as the most likely first request after launch, because a paper sheet on a clipboard is a real thing at tennis clubs. Cheap to add later, roughly a `@media print` block. Not built until asked.
* **No undo, no audit log, no change history.** `canceled_at`, `canceled_by`, `invited_at`, and `responded_at` already record the transitions that matter. A general audit trail is a different project.
* **No touch or keyboard drag-and-drop.** The dropdown covers both, permanently.
* **No dark mode, no theming, no internationalization.** Navy and cream, English, as specified in `CLAUDE.md`.
* **No component library and no design system package.** Plain CSS custom properties in one `tokens.css`, matching the iOS palette by hand. Seven screens do not amortize a design system.
* **No test framework for the web UI.** The invariants that matter are in Postgres and are covered by `tests/run-probes.sh`. A React component test suite for a one-user internal tool is effort spent in the wrong place. This is a deliberate trade and it should be revisited the moment a second admin or a second developer appears.

---

## 8. Open questions

* **Custom domain now or later?** Defaulting to the `*.pages.dev` URL. Trivial to change.
* **Do PR preview deploys get their own Supabase project, or are they disabled?** Must be resolved before the first pull request, not after.
* **Does Tara want the court board grouped by anything within a court,** for example rating or age, or is a flat list per court correct? Assuming flat until told otherwise.
* **Adult rating value list** is still open in `for-tara.md` question 6 and blocks the Player Directory filter UI, though not the rest of the screen.
