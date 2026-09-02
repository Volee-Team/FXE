# FXE Tennis: Architecture

The one document to read before touching this system. Written for a product
manager or a new engineer who needs to understand what FXE Tennis is, how it is
built, and, just as important, what is deliberately not built yet.

Regenerated 2026-09-01 from the live schema, the file tree, and the probe
suite. The previous version (2026-08) predated sign-up, the admin tab, the live
web admin, late requests, templates and the explicit-grants work. Where this
document and the code disagree, the code wins and this file gets fixed; the
changelog in `CLAUDE.md` is the day-by-day record.

> This is **FXE Tennis**, a clinic-registration app for a single tennis pro
> (Tara) and her members. It is a separate product from Volee. Where a design
> choice was learned from Volee it is noted, but the two share no code and no
> database.

---

## 1. What FXE Tennis is

Tara runs weekly tennis clinics at a member club. Until now she ran them from
text messages, a spreadsheet, and a handwritten court sheet. FXE Tennis replaces
that notebook.

A **player** browses the clinics coming up, registers, and either lands a spot
(`You're In!`) or joins the **Player Pool**. Tara, the single **admin**, builds
the weekly schedule, decides who comes off the Pool, assigns courts, sends
clinic messages, and reconciles who has paid. The app manages information; Tara
manages tennis. Nothing is ever auto-promoted off the Pool: she picks every
player by hand, on purpose.

The product has three surfaces on one backend:

- **The player iOS app** (SwiftUI). Section 4.
- **The admin tab inside that same app**, for what Tara does standing on a
  court: rosters, invitations, courts, paid, reminders, late requests, the
  player directory. Section 4.
- **The web admin**, a static page for the laptop half of her week: building
  clinics from templates, Action Needed, Money, and the same directory. Live
  at `fxe-tennis-admin.vercel.app`. Section 8.

Everything of consequence, every rule about who can see what and who can do
what, lives in the Postgres database, not in any client. That is the single
most important thing to understand here, and it is section 5.

---

## 2. Status at a glance

| Area | State |
|---|---|
| Postgres schema, RLS, narrow views, RPCs | **Built**, 20 migrations, all applied to hosted |
| Security model (explicit grants, revoked base tables, admin gate, anon executes nothing) | **Built**, enumerated by probes |
| Pricing (member/non-member x 60/90 min), snapshot, revenue report | **Built** |
| SQL probe suite (13 probes, 313 checks) + concurrency probe, in CI | **Built** |
| iOS: sign-in, sign-up with profile, password reset, three tabs | **Built** |
| iOS: browse by week, per-viewer pricing, register / cancel / leave pool / respond, closed-clinic "Message Tara" | **Built** |
| iOS admin tab: rosters, invite, courts, paid, unpaid reminder, message audiences, late requests, Action Needed, player directory | **Built** |
| Web admin: clinic + template CRUD, rosters, walk-up, courts, reminder, Action Needed, Money, directory, password reset | **Built**, live on Vercel |
| Nightly `pg_dump` backup + keep-warm | **Built**, first artifact 2026-09-01 |
| APNs push delivery | **Not built.** `notifications` rows are written; nothing delivers them |
| Stripe card payments | **v1.1** (v1 is Zelle + a report, decision 0003) |
| Juniors / parent accounts | **Deferred** to November or the spring session (decision 0007) |
| App Store / TestFlight | **Blocked** on Apple Developer enrollment for FXE Tennis, LLC |

---

## 3. System diagram

```mermaid
flowchart TD
    subgraph ios["iOS app  -  SwiftUI, iOS 17"]
        views["Views (player + admin)"]
        session["SessionStore"]
        repos["Repositories / AdminRepository"]
        views --> repos
        session --> repos
    end

    subgraph web["Web admin  -  static HTML + supabase-js, Vercel"]
        page["index.html / reset.html"]
    end

    repos -->|"supabase-swift, publishable key + JWT"| supa
    page -->|"supabase-js, same key, same RPCs"| supa

    subgraph supa["Supabase project amnaxvznkadkgzdxzegw"]
        auth["Auth  -  issues JWT (sub = auth.uid)"]
        subgraph pg["Postgres 17 + Row Level Security"]
            vws["Narrow views<br/>clinics_public, my_registrations, my_clinic_messages, my_news<br/>clinics_admin, registrations_admin, templates_admin, revenue_*"]
            rpc["SECURITY DEFINER RPCs<br/>every write in the system"]
            tbl[("Base tables<br/>no client grants except accounts, players, notifications")]
            vws --> tbl
            rpc --> tbl
        end
        auth -.->|"auth.uid() read by is_admin() / owns_player()"| pg
    end

    gha["GitHub Actions<br/>probes, iOS build + tests, copy gate, secret scan,<br/>migration immutability, nightly backup"] -.-> supa
```

The phone and the web page are two clients of one API. Postgres cannot tell
them apart and does not need to, because it never trusts the caller.

---

## 4. The client (iOS app)

SwiftUI, deployment target **iOS 17.0**. iPhone only for v1. One dependency,
**supabase-swift**, configured for the *implicit* auth flow because the
password-reset email must be finishable in a browser on another device (PKCE
binds the one-time code to the device that asked). Light appearance is forced
at the root; the palette has no dark variant.

### Project generation: XcodeGen

The `.xcodeproj` is **generated** from `project.yml`, never hand-edited and
never committed. `xcodegen generate` globs `FXETennis/`, so a new `.swift` file
is picked up with no "add to target" step. CI regenerates on a fresh clone, so
a broken `project.yml` fails there first.

### Layering

```
FXETennis/
├── App/
│   ├── FXETennisApp.swift       @main; RootView switches on session.phase; forces .light
│   ├── Session.swift            SessionStore: auth, account, activePlayer, isAdmin,
│   │                            signUp → create_my_account, password reset
│   └── AppEnv.swift             DEBUG vs release: local stack vs hosted, reset URL
├── Data/
│   ├── SupabaseClient.swift     the one client (URL + publishable key, implicit flow)
│   ├── Repositories.swift       player reads/writes: Clinic, Registration, News, Profile
│   └── AdminRepository.swift    every admin RPC + the roster/late-request/notice models
├── Models/
│   ├── CoreModels.swift         Codable mirrors of the views (no hidden columns exist here)
│   ├── NTRPRating.swift         the USTA scale for the "?" explainer
│   ├── NotificationCopy.swift   Tara's notification catalogue, verbatim
│   └── ServiceWeek.swift        Sunday-in-New-York week math for grouping (pure, unit-tested)
├── Resources/
│   └── Brand.swift              tokens: navy / cream / court / brass, type, spacing, the gator mark
└── Views/
    ├── AuthView.swift           sign in, create account, forgot password
    ├── CompleteProfileView.swift name, phone, membership question, rating (after sign-up)
    ├── MainTabView.swift        Home, Clinics, Profile, plus Manage when isAdmin
    ├── HomeView.swift           My Clinics + Available Clinics glance
    ├── ClinicsView.swift        the list, grouped This week / Next week / Week of …
    ├── ClinicDetailView.swift   register / cancel / leave pool / respond, confirmations,
    │                            "Message Tara" once the clinic has closed
    ├── ClinicExplainerSheet.swift the "?" sheet (Tara's descriptions + the 105 definition)
    ├── ProfileView.swift        the player's own details, sign out
    ├── AdminClinicsView.swift   Manage: Action Needed, Today, Upcoming, Past; toolbar → Players
    ├── AdminClinicDetailView.swift roster: courts, paid, invite, cancel invite, late requests,
    │                            Message Players, Remind unpaid
    └── PlayersDirectoryView.swift search, member / active switches, private note
```

Four ideas run through the client code:

1. **One Supabase client.** The publishable key ships in the binary on purpose:
   it grants only what the grants and RLS allow. Every real permission lives in
   Postgres.
2. **Repositories are the only door to the network.** Views never touch
   `supabase` directly. One place to change when an RPC changes, and one place
   a reviewer can confirm the client never reads a hidden table.
3. **Models mirror the views, and absence is a feature.** `CoreModels.swift`
   has no field for capacity, counts, or other players, because those columns
   are not in the views the client reads. The app cannot display a hidden fact
   even by accident. (`AdminRepository`'s models are the exception, and they
   are fed by admin-only views and RPCs that return zero rows to a player.)
4. **`SessionStore` is the injected identity.** `RootView` switches on
   `session.phase` (`loading` / `signedOut` / `needsProfile` / `signedIn`).
   `needsProfile` exists because Supabase sign-up creates only an auth user;
   `create_my_account` creates the `accounts` and `players` rows with the
   caller's `auth.uid()` as the id and `role` hard-coded to `member`.

Copy rule (hard rule 13): every user-visible string is either Tara's verbatim
or plain chrome checked by Alex. `scripts/extract-copy.py` snapshots every
string in Swift and web into `docs/copy-approved.txt`; CI fails on a string
that is not in the snapshot; `docs/copy-review.md` is where new ones wait.

---

## 5. The backend (Supabase / Postgres) and its security model

### Hosted project

- **Project ref** `amnaxvznkadkgzdxzegw` (`fxe-tennis`, `us-east-1`),
  Postgres 17, free tier. Free-tier projects pause after a week idle; the
  nightly backup job doubles as the keep-warm.
- **Local development** uses the Supabase CLI pinned to **2.115.0** (also in
  CI; a version drift hid a broken grant surface for days). `supabase db reset`
  applies every migration then `supabase/seed.sql`.
- **Migrations** in `supabase/migrations/` apply in filename order and are
  pushed to hosted only with `supabase db push`. An applied migration is
  never edited, only superseded; CI enforces it.

### The central security rule, in plain terms

Nine things are hidden from players:

> clinic capacity, number registered, spots remaining, Player Pool size, other
> players' names, court assignments, other players' payment status, private
> coaching notes, and clinic location.

None of that can be enforced in a client: anyone with a proxy reads the raw
JSON. The hiding is done in the database by three mechanisms:

1. **Grants are explicit, in both directions.** Supabase's bootstrap gives new
   tables and views full privileges for `anon` and `authenticated`, and
   Postgres gives PUBLIC `EXECUTE` on every new function. Every migration
   therefore revokes before it grants (hard rule 11), and `authenticated` is
   granted exactly: `SELECT` on `accounts` and `players` (RLS scopes them to
   the caller), `SELECT` + `UPDATE(read_at)` on `notifications`, `SELECT` on
   the narrow views, and `EXECUTE` on the client RPCs. `anon` holds nothing:
   no table, no view, no function. `tests/sql/grants_are_explicit.sql`
   enumerates `pg_class` and `pg_proc` rather than naming objects, so an
   object added next month is covered before anyone remembers to list it.
2. **Narrow views** expose exactly the safe columns:

   | View | What it is | Who sees what |
   |---|---|---|
   | `clinics_public` | Published/canceled clinics that have not ended, both price rates, no capacity or counts | any authenticated user |
   | `my_registrations` | The caller's own registrations (no court, no `canceled_by`) | scoped by `owns_player()` |
   | `my_clinic_messages` | `everyone` messages for your clinics plus targeted messages sent to you | scoped to the caller |
   | `my_news` | Published news for your audience with a per-account read flag | scoped to the caller |
   | `clinics_admin`, `registrations_admin`, `templates_admin` | Explicit column lists (never `select *`, which freezes at creation) `where is_admin()` | admin only, else zero rows |
   | `revenue_by_clinic`, `revenue_by_segment` | Reconciliation aggregates | admin only |

   Views run with owner rights (not `security_invoker`), which is why writes
   through them are revoked outright: an auto-updatable view would bypass RLS.
3. **RLS on the base tables** as defense in depth. The grants are the
   load-bearing control; the policies catch what a grant mistake would miss.

### Who is an admin, who owns a player

- **`is_admin()`**: the caller's `auth.uid()` maps to an `accounts` row with
  `role = 'admin'`. The admin views are `… where is_admin()`, so that
  predicate is their entire access control.
- **`owns_player(player)`**: the player belongs to the caller's account. This
  scopes `my_registrations` and every player-facing RPC.
- **`require_admin()`** raises `42501` unless `is_admin()`; every admin RPC
  opens with it.
- **Becoming admin.** `role` is never a parameter anywhere. A BEFORE INSERT
  trigger (`bootstrap_first_admin`) promotes exactly one email, Tara's, at
  account creation, so she self-serves on the live site and nobody else can.

### The privilege-column protection

A player could once `update accounts set role = 'admin'`. Migration
`20260802000003` closed it three ways, any one sufficient: column-level
grants (`authenticated` may update only name and phone), `WITH CHECK` pinning
identity columns, and triggers (`guard_account_privilege_columns`,
`guard_player_owner_column`). `tests/sql/privilege_escalation.sql` performs
the attack and asserts it fails.

### The tables

| Table | What it holds |
|---|---|
| `accounts` | Login identity. `role` is `member` or `admin`. One row per `auth.users` row, created by `create_my_account`. |
| `players` | One row per person who can be registered. `adult_rating`, `is_member` (self-reported, corrected by Tara), `is_active` (archive, never delete). |
| `player_notes` | Tara's private note per player. Reached only through `admin_player_note` / `admin_set_player_note`. |
| `clinic_templates` | Reusable definitions; prices derive from duration via `default_price_cents`. |
| `clinics` | A scheduled clinic: capacity, both prices, `member_opens_at` / `public_opens_at` / `closes_at` (defaults from triggers: windows from the service week, close 3 h before start), `status`. |
| `registrations` | Clinic × player with `status`, `paid`, `court_number` (1-5), `source`, and the price snapshot (`price_cents_charged`, `was_member`, `duration_minutes`). |
| `late_requests` | "Can I still get in?" after the close; Tara approves or declines. |
| `clinic_messages` + `clinic_message_recipients` | Broadcasts; targeted audiences are snapshotted at send time. |
| `news_posts` + `news_reads` | Announcements; read state per account. |
| `notifications` | In-app rows written by RPCs (players and Tara). Readable by the owner; only `read_at` is writable. |
| `devices` | APNs tokens (groundwork; nothing delivers yet). |
| `app_settings` | Small admin-editable strings, e.g. Tara's payment line. Never anything hidden. |

Enums: `account_type`, `account_role`, `player_kind`, `clinic_audience`
(`juniors` kept, not offered), `clinic_status`, `registration_status`
(`in` / `pool` / `response_needed` / `canceled`), `message_audience`,
`news_audience`, `registration_source`.

### The RPCs

**Player-facing** (self-gated by `owns_player()` or `auth.uid()`):
`create_my_account`, `register_for_clinic`, `respond_to_invitation`,
`cancel_registration`, `leave_pool`, `request_late_spot`, `mark_news_read`,
`payment_instructions`.

**Admin** (each opens with `require_admin()`):

| RPC | What it does |
|---|---|
| `admin_upsert_clinic`, `admin_upsert_template`, `admin_delete_template`, `create_clinic_from_template` | Build the week. Templates are copy-on-create. |
| `publish_clinic`, `cancel_clinic` | Draft to published; cancel and notify everyone live. |
| `invite_from_pool`, `cancel_invitation` | Tara's hand-pick, and taking it back. |
| `resolve_late_request` | Put a late asker in, or say no room. |
| `place_player` | Walk-up placement; ignores window and capacity by design; still snapshots the price. |
| `set_paid`, `assign_court` | The court sheet. `assign_court` is the one unconditional update in the schema: a court is a value, not a transition. |
| `send_clinic_message` | Audiences `everyone` / `in` / `pool` / `response_needed` / `unpaid`, resolved server-side. The one-tap unpaid reminder is this with a fixed body. |
| `search_players`, `admin_player_note`, `admin_set_player_note`, `admin_set_membership`, `set_player_active` | The directory. `search_players` returns `has_notes`, never the note. |
| `publish_news` | Publish a draft post. |
| `revenue_summary` | The four numbers and the money (section 7). |

**Internal** (`notify_account`, `admin_account_ids`) is executable by no
client role. Helper functions used by defaults and views (`service_week_start`,
`member_opens_at`, `public_opens_at`, `default_closes_at`,
`default_price_cents`, `player_age`) are granted to `authenticated` only.

Every SECURITY DEFINER function pins `search_path`; the probe suite asserts it
for all of them.

---

## 6. The registration model (the one place software decides capacity)

**Service-week windows.** Registration opens per **service week**
(Sunday-Saturday, `America/New_York`), not per clinic (decision 0001).
Members: 8:00 AM the Thursday before; everyone: 8:00 AM the Friday, 24 hours
later (decision 0007 confirmed both). Stored per clinic so Tara can override,
defaulted by trigger. Registration **closes 3 hours before start**
(`closes_at`, also a trigger default); after that a player can only ask, via
`request_late_spot`, and Tara answers.

**The capacity decision.** `register_for_clinic` is the only place capacity is
decided, inside one transaction with the clinic row locked, because two members
tapping Register in the same second must not both land a spot. A partial unique
index allows at most one live registration per player per clinic, so a retry is
idempotent. `tests/sql/capacity_race.sh` races it for real.

**Nothing auto-promotes.** A spot opening does not pull the next person in.
Tara invites; the player accepts or declines; both are conditional updates so a
race with her canceling resolves cleanly (hard rules 2 and 3).

---

## 7. Payments, pricing, and the revenue report

v1 moves no money in the app (decision 0003): Zelle preferred, Venmo accepted,
and the app gives Tara a report. Prices are member/non-member by length: $18 /
$23 for 60 minutes, $22 / $28 for 90. At registration the price, membership and
duration are **snapshotted** onto the row (decision 0002), so editing a clinic
or correcting a membership never rewrites history. `revenue_summary()` returns
the four counts, expected, collected and outstanding; `revenue_by_clinic` and
`revenue_by_segment` break it down. Only `status = 'in'` counts.

---

## 8. The web admin

`web/` is three static files and no build step: `index.html`, `reset.html`,
`config.js` (which picks local vs hosted by hostname). Hosted on Vercel by
manual `vercel --prod` from that folder; the Git repo is deliberately **not**
connected, because preview deploys would point at Tara's live data. It signs
in with the same publishable key as the phone and calls the same RPCs; the
only gate is `is_admin()` in Postgres. The design record, including why there
is no application server, is `docs/web-admin.md`.

Built: clinics from templates (with save-as-template), edit, publish, rosters
with courts and paid, walk-up, message audiences, one-tap unpaid reminder,
Action Needed (late requests, unread cancellations and replies), Money, the
player directory with private notes, sign-up (Tara's email self-promotes) and
password reset. Drag-and-drop courts are deliberately not built until the
dropdown has been used for real.

---

## 9. Testing and CI

**SQL probes** in `tests/sql/`, 13 files, 313 checks, each printing
PASS/FAIL rows, plus the concurrency probe. `tests/run-probes.sh` prints its
own total and fails on silent SQL errors or a probe with zero assertions.
Every migration that adds a rule adds a probe that is **red first**.

| Probe | Asserts |
|---|---|
| `information_hiding` | A non-admin cannot read any of the nine hidden facts through any surface |
| `privilege_escalation` | Self-promotion to admin fails three ways |
| `grants_are_explicit` | The whole privilege surface, enumerated: tables, views, functions, PUBLIC |
| `view_write_paths` | No view is writable by a client (owner-rights bypass) |
| `registration_window_rule`, `registration_windows` | Service-week math incl. DST, and every branch of `register_for_clinic` |
| `pricing_and_revenue` | Snapshot correctness and the report's totals |
| `create_my_account` | Sign-up creates rows, cannot impersonate, cannot self-promote, is idempotent |
| `admin_clinic_crud`, `templates_floor_bootstrap` | CRUD, template pricing, the date floor, Tara's bootstrap |
| `late_requests`, `player_directory` | The late path and the directory, including "a member cannot read their own note" |
| `schema_decisions` | Tara's decisions with a DB consequence stay true |
| `capacity_race.sh` | Two racing registrations; invite-vs-accept |

**Swift**: 18 unit tests (`FXETennisTests`: price formatting, per-viewer
pricing, NTRP buckets, service-week edges) and 12 XCUITests: 8 player flows
(`PlayerFlowUITests`: sign in / browse / register, undo, sign-up end to end,
the bell, profile edit, My Clinics, prices, hidden information) and 4 admin
flows (`AdminFlowUITests`: court / reminder / paid, Pool → invite → Accept,
directory note, cancel clinic). The UI tests run against the
local stack and are order-dependent on a fresh seed.

**Web admin**: 8 Playwright tests (`web/tests/admin.spec.mjs`) walk Tara's
side against a fresh seed: sign-in and the non-admin door, prices, walk-up,
courts, unpaid reminder, a note round-trip, cancel clinic. One worker, file
order, no test depends on another's writes.

**GitHub Actions** on every push and PR (`probes.yml`): `sql-probes`
(pinned CLI, `db reset`, the suite), `ios-build-and-test` (XcodeGen, Debug
and Release builds, unit tests, app-icon gate, simulator chosen at run time),
`web-browser-tests` (the same pinned stack, then Playwright), `copy-gate`,
`secret-scan`, `migration-immutability`. Nightly (`backup.yml`):
`pg_dump` of hosted to an artifact, with a size floor so an empty dump fails
loudly, and a keep-warm query.

Merging: CI is the gate and a green run is required; there is no code review
by a second person. Branch protection on `main` is the intended enforcement
and is a repository setting still to be switched on.

---

## 10. Where decisions live

`docs/decisions/` (0001 service-week windows, 0002 price snapshot, 0003
payments, 0004 adults only, 0005 clinic messaging, 0006 three tabs and no
News, 0007 Tara's 2026-08-27 answers), `docs/roadmap.md` (plan of record),
`docs/whats-next.md` (what is blocked and on whom), `docs/backlog.md`,
`docs/copy.md` (Tara's words), `docs/web-admin.md`, `docs/notifications.md`,
and `CLAUDE.md` (the working rules and the changelog).

---

## 11. Deliberately not in v1

- **In-app purchase / Apple Pay for clinic fees.** Not required for a
  real-world service; Zelle keeps Apple's cut off a $23 fee.
- **Auto-promoting from the Player Pool, auto-expiring invitations.** Tara
  picks every player and takes a spot back by hand. This is the product.
- **Showing players any capacity, count, court, or other player.**
- **Juniors and parent-managed child accounts.** Schema ready; UI later.
- **Push delivery.** Rows are written; delivery is the next big piece.
- **Drag-and-drop courts, a category filter, a custom domain.**
