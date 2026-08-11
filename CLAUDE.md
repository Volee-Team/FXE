# FXE Tennis - Project Context

iOS native app (Swift / SwiftUI). Backend is Supabase (Postgres + Auth + Edge Functions + APNs). Clinic registration and roster management for the FXE tennis program.

**This is NOT Volee.** Separate repo, separate Supabase project, separate bundle ID, separate App Store listing. They share patterns and a developer, nothing else.

---

## What this app is

The digital front door for the FXE tennis program. It replaces repetitive texts, spreadsheets, manual clinic lists, and scattered reminders with one system for registration, player management, clinic communication, payment checkboxes, and court organisation.

**The product rule that settles most arguments:** the app organizes information. Tara makes all coaching, player-selection, clinic-balance, and court-placement decisions. When unsure whether to automate a decision or leave it to Tara, leave it to Tara.

Source spec: the FXE Tennis Version 1 Developer Guide. Engineering decisions derived from it: `~/Documents/FXE Tennis/engineering-design.md`. Open questions for Tara: `~/Documents/FXE Tennis/for-tara.md`.

---

## Who is who, and what matters to them

**Tara** — FXE tennis pro. She is the client, the sole administrator, and the
only person whose opinion settles a product argument. She currently runs the
program from texts, a spreadsheet, and a handwritten court sheet. She is not
technical and should never be asked a technical question; translate first.

**Alex** — building it. Relays Tara, makes engineering calls, does not want to
be asked the same thing twice.

**Kat** — product manager, joined 2026. Asks the questions a real company asks:
architecture diagrams, data docs, how changes get approved, where bugs live.

**FXE** is a member club. That is not decoration: it is why clinic location is
hidden from players. Tara, 2026-08-02: *"I don't want it to look like it is for
everyone and all nonmembers by listing where FXE is at."*

---

## Build & Run

```bash
# Local stack (Postgres, Auth, Storage). Docker must be running.
supabase start

# Apply every migration + seed. Destroys local data; that is the point.
supabase db reset

# The whole test suite: 142 checks + a concurrency probe.
bash tests/run-probes.sh

# Push migrations to the hosted project.
export SUPABASE_DB_PASSWORD='<from .env.local, gitignored>'
supabase db push
```

| | |
|---|---|
| Local DB container | `supabase_db_FXE-Tennis` |
| Hosted project | `amnaxvznkadkgzdxzegw` (`fxe-tennis`, us-east-1) |
| Remote | `github.com/Volee-Team/FXE`, branch `main` |
| CI | `.github/workflows/probes.yml`, runs the full suite on every push and PR |

**The hosted database is not seeded and must not be.** It will hold Tara's real
players. Probe verification runs against a throwaway Postgres: locally via
`supabase db reset`, and in CI on a fresh runner. Never point a probe at hosted.

Run a single probe:

```bash
docker exec -i supabase_db_FXE-Tennis psql -U postgres -d postgres -f - < tests/sql/pricing_and_revenue.sql
```

---

## Testing & verification protocol

**A clean build is not proof a feature works.** Before claiming any task is done, produce an artifact.

* **SQL / RPC changes** - run the probe suite (`bash tests/run-probes.sh`) and paste the result table. Add a new probe for any invariant worth protecting permanently.
* **Swift logic** - XCTest in `FXETennisTests/`.
* **UI flow changes** - build, install on the booted simulator, screenshot each step, and read the PNGs back.
* **Permission changes** - re-run `tests/sql/information_hiding.sql`. It is the safety-critical probe.
* **Concurrency changes** - re-run `tests/sql/capacity_race.sh`.

Never say "this should work." Either you verified it and can show the artifact, or you say plainly that you have not verified it yet.

### Write the probe from the rule, never from the code

Earned on 2026-08-02, when the registration window rule turned out to be wrong and its test had been green the whole time. The test had been written by reading the function, so it asserted the implementation's misunderstanding back at it. **Two copies of one mistake agreeing with each other is not evidence.** Transcribe expected values from the stated rule, work them out by hand, and write down the literal answer.

Then **prove the probe can fail.** Reinstall the old broken behaviour, run the probe, confirm it goes red on the rows you predicted, and only then restore. A probe that has never failed has not been tested either.

That exercise is what exposed a defect in the probe harness itself: the pass condition used `actual LIKE '%' || expected || '%'`, under which an actual count of **105 passed against an expected 0**, because "105" contains "0". Substring matching now applies only when the expected value contains a letter, which is the case it existed for (a server error message wrapping an expected error name). **Do not loosen it back.** If a new check needs fuzzy matching, normalise the actual value instead of widening the comparison.

---

## Hard rules

1. **Information hiding is a database concern, never a UI concern.** Nine things are hidden from players: clinic capacity, number registered, spots remaining, Player Pool size, other players' names, court assignments, other players' payment status, private coaching notes, and clinic location. Hiding these in SwiftUI hides nothing. They are enforced by revoked table grants plus narrow views (`clinics_public`, `my_registrations`, `my_clinic_messages`, `my_news`). **Never grant a client direct SELECT on `clinics`, `registrations`, `player_notes`, or `clinic_templates`. Never return a count of anything to a player.** Pinned by `tests/sql/information_hiding.sql`.

2. **Nothing is ever auto-promoted.** Tara picks every Player Pool invitation by hand. The app never invites the next player automatically, never auto-expires an invitation, and never confirms someone without their acceptance.

3. **Every state transition is conditional.** Use `UPDATE ... WHERE status = 'expected' RETURNING *` and treat zero rows as "someone got there first," surfaced as a friendly message. Never an unconditional status write: Tara cancelling an invitation while the player accepts is a real race.

4. **Archive, never delete.** Players deactivate (`is_active`), clinics and registrations cancel, templates and news archive. Canceled registrations stay visible to Tara with their timestamp.

5. **Age is derived, never stored.** Children store `date_of_birth`. Use `player_age(dob)`. A stored age is silently wrong within a year. (Volee learned this with a deprecated `age_group` column.)

6. **Never revert or remove existing functionality without asking.** If something looks unused, it may be load-bearing for someone's in-flight work. Ask.

7. **Templates snapshot, never reference.** `create_clinic_from_template` copies values in. Editing a template must never rewrite already-published clinics.

8. **A privilege column is never writable by the role it grants privilege to.** `accounts.role` decides whether `is_admin()` is true, and `is_admin()` is what the entire information-hiding model rests on. Anything of that shape gets three layers: column-level grants (revoke the table-level UPDATE *first*, or the column grant does nothing), `WITH CHECK` on the RLS policy, and a trigger backstop for future code paths that arrive with different grants. The same applies to `players.account_id`, which decides who owns a person.

   Earned 2026-08-02. A player could run `update accounts set role='admin' where id=<self>` and take over the club: read every roster, every court assignment, every payment status, **demote Tara**, and reassign other players to their own account. See hard rule 9 for why the tests did not catch it.

9. **Where a privilege boundary exists, write a probe that tries to cross it.** `information_hiding.sql` was green for the entire life of the bug above. It asserted `maria_is_not_admin = false` and then tested what a non-admin can read. It never attempted the transition. **A probe that only tests the state you expect cannot find a transition you did not think of.** `tests/sql/privilege_escalation.sql` attacks instead: eight attempts to escalate, each asserting the *resulting state*, plus one check that legitimate self-service still works so the hole cannot be "fixed" by breaking the product.

   Assert the outcome, not the error. An UPDATE blocked by RLS affects zero rows and raises nothing, so `exception when others` alone would have reported a pass.

10. **When you are not sure, ask. Including about small things.** This is the
    rule Alex has asked for most often, so it is the one most worth obeying.
    A sixty-second question beats half a day of rework and beats a confident
    guess that quietly becomes a load-bearing assumption.

    Ask **Alex** for engineering calls and anything about how work gets done.
    Ask **Tara**, through Alex and in plain language, for anything about how her
    program actually runs: prices, timing, who sees what, what she does today.
    Never ask Tara a technical question; translate it into her world first.

    Signals that you should be asking rather than deciding: you are about to
    write "presumably" or "I will assume"; two readings of a sentence would
    produce different code; you are inventing a value nobody gave you (a price,
    a limit, a default); or the answer changes a database column.

    When you do decide something yourself, **write it down** — a line in
    `docs/decisions/`, or the roadmap, or here. A decision that lives only in a
    chat log will be made again differently next month.

---

## Locked terminology

Use these exact words in all UI copy. Do not substitute synonyms.

| Term | Meaning |
|---|---|
| **You're In!** | The player has an active spot. Never "Confirmed", "Accepted", or "Registered". |
| **Player Pool** | Waiting for Tara's selection. Never "waitlist", "standby", or "reserve list". |
| **Response Needed** | Tara invited them; they must Accept or Decline. |
| **Canceled** | The registration or clinic is canceled. |
| **Action Needed** | Admin work requiring Tara's attention. |
| **My Clinics** | The player's upcoming registered clinics and Player Pool entries. |
| **Service week** | Sunday through Saturday, America/New_York. The unit registration opens for. Internal vocabulary, not player-facing copy. |
| **Ladies / Men / Coed** | The three v1 audiences. Juniors return in the fall. |

---

## Registration rules

| Situation | Result |
|---|---|
| Member, inside priority window, room available | You're In! |
| Member, inside priority window, clinic full | Player Pool |
| Member, after priority window | Player Pool |
| Non-member, after public opening | Player Pool |
| Non-member, inside member-only window | Rejected |
| Anyone, before member opening | Rejected |
| Anyone, after `closes_at` | Rejected |
| Same player twice | Rejected, exactly one live row survives |

### The window rule (corrected 2026-08-02, was wrong before that)

**Registration is per service week, not per clinic.** This is the single most important sentence in this section. Tara gave two different open dates for one identical date range, which is only coherent if the registrable unit is the week and the two dates are the two audiences.

> A clinic belongs to the **service week** containing it. A service week runs **Sunday 00:00 through Saturday 23:59, America/New_York**. Registration for every clinic in that week opens at one pair of moments derived only from the week's anchor Sunday:
>
> * **Members:** 08:00 local on `anchor_sunday - 3 days` (the Thursday before)
> * **Public:** 08:00 local on `anchor_sunday - 2 days` (the Friday before)
>
> **A clinic's own weekday has no effect on its open time.** Members keep access after Friday: the public open widens the audience, it does not transfer it. Member lead time runs from 3 days (Sunday clinic) to 9 days (Saturday clinic).

For the week of Sunday 2026-09-06: members open Thursday 2026-09-03, everyone else Friday 2026-09-04. Every clinic that week, Sunday through Saturday, shares that one pair.

Implemented by `service_week_start()` → `member_opens_at()` / `public_opens_at()`, and **stored on the clinic row** so Tara can override any single clinic by editing it. The functions supply the default; they do not own the column. Pinned by `tests/sql/registration_window_rule.sql`.

Two implementation traps, both pinned by probes:

* `AT TIME ZONE` must be applied **before** taking the day of week. A Saturday 21:00 EDT clinic is Sunday 01:00 UTC; anchoring off the UTC value pushes it a full week late.
* Never `date_trunc('week', ...)`. That is ISO, Monday-anchored, and shifts every Sunday clinic a week early. Postgres `DOW` is 0 = Sunday, which is exactly the offset back to the anchor.

**Do not reintroduce the per-clinic rule.** "The most recent Thursday strictly before the clinic date" is right on five weekdays out of seven and wrong on Friday and Saturday, the two days where seats are scarcest. On Tara's own Friday 2026-09-11 example it opens members a week late, and its public-side counterpart lands six days *before* the members: an inversion.

**Blocking non-members during the member window is our decision, not the guide's.** The guide only states their opening is Friday 8 AM. Tara sees the Pool in registration order, so letting non-members queue on Thursday would place them ahead of members in her list and quietly subvert the priority. Flagged for her review.

Capacity is decided in exactly one place: `register_for_clinic`, which locks the clinic row with `FOR UPDATE`. Pinned by `tests/sql/capacity_race.sh` (verified at 24-way concurrency). `place_player` deliberately performs **no** capacity check: capacity never blocks Tara (decision 4).

### Open questions on the window rule

Tara's example is consistent with more than one reading. The most defensible reading is implemented; these are the points where a wrong guess costs someone a seat.

1. **Saturday clinics.** Tara's range names Sunday to Friday. That is read here as the clinic *footprint*, not the boundary of a registration block, because a 6-day week leaves Saturday in no week at all and makes `week_of(date)` a partial function. Under the 6-day reading a Saturday clinic opens **a full week later**. Ask her: does a Saturday clinic open with the week before it, or with the week starting the next day?
2. **Anchor point.** Her example cannot distinguish week-start-anchored (`Sunday - 3`) from week-end-anchored (`last clinic day - 8`); both give 9/3 for a full week. Start-anchored is implemented, because end-anchoring only agrees with the Guide's "Thursday / Friday" on full weeks: on a Sunday-to-Wednesday holiday week it would open on a Tuesday and a Wednesday. Ask her: if a week has clinics on only some days, does registration still open that same Thursday and Friday?
3. **Holidays.** The rule has no holiday awareness. Christmas Day 2026 is a Friday public open, and Christmas Eve is its Thursday member open. Ask her whether registration still opens at 8:00 that morning.
4. **"Member"** means an FXE club member, not a paying app subscriber. `players.is_member`. Confirm with her if it ever becomes ambiguous.
5. **`closes_at` is still unset by `create_clinic_from_template`.** Nothing decides when registration closes. Ask her: at clinic start, some hours before, or only when it fills?

---

## Tara's decisions, 2026-08-02

Answered and now binding. Numbering is hers. Only the ones with a lasting consequence are restated here; the migration `20260802000002_tara_decisions_2026_08_02.sql` carries the full reasoning for each database change.

| # | Decision | Where it lives |
|---|---|---|
| 1 | Admin surface splits in two: a phone app for courtside work (invites, messages, marking paid) and a laptop/web page for weekly setup and court assignment. | Client |
| 3 | Tara can add anyone to any clinic directly, and move anyone between You're In! and Player Pool by hand. | `place_player()` |
| 4 | **Capacity never blocks Tara.** Show counts, never block an invite. | `place_player()` does no capacity check. Pinned. |
| 5 | Member status is **self-reported**, and Tara can override it on the profile. Both already work: `players.is_member` is writable by the owning account and by any admin. A player can tick the box and gain the Thursday window. That is what self-reported means. | `players_update_own` policy |
| 6+7 | Adult rating uses the **same NTRP scale and the same chart as Volee**, behind a tappable "?" button. Stored as `numeric(2,1)`, 2.0 to 5.0 in half steps, exactly as Volee stores it, so a rating crosses between the apps untranslated. **"5.0+" is a display label, never a stored value.** | `players.adult_rating`, `docs/ntrp-chart.md` |
| 8 | Audience is **Ladies / Men / Coed** in v1. **No category filter**: Tara said there is no need to filter anything, because there are not many clinics weekly and they are simply listed by week. | See below |
| 9 | Junior age groups deferred to the fall. Do not build. | none |
| 10 | **Clinic location is hidden**, and the reason matters: FXE is a member club and must not read as open to non-members. Location must not appear anywhere player-facing, in any form, including maps, addresses, and directions links. | Pinned by `information_hiding.sql` |
| 11 | Payment copy, exact string, Zelle preferred. | `app_settings.payment_instructions` |
| 12 | Targeted messages are visible only to the group they were sent to. | Already built: `clinic_message_recipients` |
| 13 | **Notifications-off is not Tara's problem.** See below. | Client |
| 14 | Every notification is 1 to 2 sentences and readable on a lock screen. Her drafts are verbatim. | `docs/notifications.md` |
| 15 | Brand is navy blue and a nice green, country-club feel, **not** the current royal blue and green. Same gator-with-tennis-ball mark. | `web/tokens.css`, `FXETennis/Resources/Brand.swift` |
| 16 | Apple Developer account must be "FXE Tennis, LLC". Privacy policy reuses Volee's. Waiver wording pending. | Business |

### The `juniors` enum value stays

Decision 8 limits v1 to three audiences, but `clinic_audience` keeps all four. Postgres has no `DROP VALUE`: removing one means creating a replacement type, rewriting every dependent column and default, recreating dependent indexes and views, and dropping the old type. That is a migration with real blast radius, run twice, to delete four characters no player can see. **The constraint Tara stated is a UI constraint.** Enforce the three options in the admin audience picker. A DB value nobody can select is inert. Pinned by `tests/sql/schema_decisions.sql` so nobody "tidies it up".

### Category is kept and not filtered

`clinics.category` and `clinic_templates.category` stay: nullable, free text, display only. **Deliberately unindexed**: an index is what you add when you intend to filter, and adding one is a quiet promise that we do. Do not build a category filter without asking her.

### Decision 13: the notifications-off disclosure is a client requirement, not a column

Tara explicitly does **not** want to manage or monitor who has notifications on or off. `accounts.push_enabled` is dropped, and no admin surface may display anything of the kind. Do not re-add it, and note that `engineering-design.md` §4 and `questions-for-tara.md` Q19 both still specify the old "notifications off" marker and are **overruled**.

What replaces it is app behaviour, and it is a real requirement, not a nicety:

* **At signup**, state that all clinic communication happens through the app.
* **Persistently in-app whenever permission is denied**, state that with notifications off they will miss important information.

`devices` already tells the server whether a push can be delivered, which is the only server-side question worth asking. iOS knows its own permission state locally and never needed a round-trip to nag its own user.

## Visual direction

Navy country-club styling, not bright royal blue. Cream or warm-white backgrounds, clean cards, restrained green accents. Large text and generous tap areas for outdoor use. Icons always paired with text labels. Player screens must never feel like long blocks of writing.

Status colors, always paired with text (never color alone, for accessibility):

| Color | Status |
|---|---|
| Green | You're In! |
| Orange | Player Pool |
| Yellow | Response Needed |
| Red | Canceled |

Micro-animations last about one second, never delay interaction, and are optional. A static reliable state is always acceptable.

---

## Writing & copy

Minimal everywhere. Short sentences, one thought per line. Button labels 1-2 words. **No em-dashes** anywhere in app copy: use a colon, a comma, or split the sentence.

Friendly empty states, each with one useful next action. Friendly errors: "We couldn't complete your registration. Please check your connection and try again."

---

## Database

Local development runs against a real Postgres via `supabase start`. Migrations live in `supabase/migrations/`, seed data in `supabase/seed.sql`, probes in `tests/sql/`.

```
supabase start          # boot local stack
supabase db reset       # re-apply all migrations + seed
bash tests/run-probes.sh
```

Never apply a migration to a hosted project without running the probe suite locally first.

### `app_settings`

A small key/value table for **player-safe, admin-editable strings**. Read by any authenticated user, written only by an admin. Currently holds one row, `payment_instructions`, whose value is Tara's exact wording:

```
Payment can be made via zelle to fersctennispro@gmail.com (preferred) or Venmo FXE Tennis
```

Lower-case "zelle" and the missing terminal period are hers. Do not tidy them: a corrected string is not the string she specified. Read it through `public.payment_instructions()` rather than hardcoding the key. Pinned character for character by `tests/sql/schema_decisions.sql`.

It is a table rather than a Swift constant because the payment reminder body is composed server-side, so the string has to exist in the database anyway and two copies drift. It is a table rather than a SQL literal because a Zelle address is exactly the kind of thing that changes on a Tuesday, and baking it into a function body means a migration to fix a typo in an email address.

**Never put anything hidden in this table.** No location, address, map link, or directions, and nothing from the nine hidden facts. The information-hiding probe asserts that no key or value here is location-shaped or contains a link.

### Known local-environment defect

The local Supabase dev image segfaults the Postgres backend when a role without EXECUTE calls a function (any function, `SECURITY DEFINER` or not). Reproduced 2026-07-28 with a two-line throwaway function; `pgaudit` is the likely culprit. This is **not** a schema defect and does not affect whether the permission is correct. Probes therefore assert function ACLs with `has_function_privilege(...)` rather than calling and catching. Re-check whether this reproduces on the hosted project before drawing conclusions from it.

---

## Working style

* Tone: senior CS professor. Direct, no fluff.
* Respond to numbered feedback with the same numbered structure. Drop nothing.
* Before touching any query: read the live schema. Never assume a table or column exists.
* Ask clarifying questions before building anything non-trivial. A 60-second clarification beats half a day of rework.
* Update this file when a rule is earned. A correction that only lives in a transcript is lost.

---

---

## Where things are written down

Chat is not memory. Every session ends and takes its context with it. If it
matters and it is not in the repo, it is gone.

| File | What belongs there |
|---|---|
| `CLAUDE.md` | Rules, conventions, hard-won lessons. What every session must know |
| `docs/roadmap.md` | What is in v1, v1.1, v2, what is parked, what we are deliberately not doing. **Tara's new asks land here first**, never straight into code |
| `docs/decisions/` | One file per decision that would otherwise be re-litigated. What we chose, why, what we rejected, how we would know we were wrong |
| `docs/backlog.md` | Bugs and chores. Anything noticed and not fixed goes here in the same breath |
| `CLAUDE.md` changelog | One entry per session. The diary |

**The habit that makes it work:** when Tara says something new, it goes in the
roadmap before it goes in a migration. When a decision gets made, it gets a
number. When something is noticed and skipped, it goes in the backlog. Writing
it down is part of doing it, not paperwork afterwards.

### Audit this file periodically

At the start of a session that will run long, and after any batch of decisions,
re-read CLAUDE.md against reality. Specifically: do the Build & Run commands
still work, does the probe count match what the suite prints, does every hard
rule still have a probe, and has anything in "Tara's decisions" been superseded
by a later call? Stale rules are worse than missing ones, because they get
obeyed.

## Changelog

- **2026-08-10** — Hosted Supabase live (`amnaxvznkadkgzdxzegw`), all migrations applied, schema verified against local. CI now runs the suite on every push and PR, plus a job that fails any PR editing an already-committed migration. **Pricing rebuilt** to Tara's locked table (member 60/90 = $18/$22, non-member = $23/$28), filled in by a trigger from clinic length, and **snapshotted onto the registration** so editing a price never rewrites past revenue (decision 0002). `revenue_summary()` returns the four numbers and the total she asked for. Juniors out of v1 (decision 0004). **Two more harness bugs found and fixed, both silently passing:** the error match was anchored to `^ERROR` but psql writes `psql:<stdin>:138: ERROR:`, so five aborting probes reported green; and a probe running zero assertions also reported green. Suite: 142 checks + concurrency. Added `docs/roadmap.md`, `docs/decisions/`, `docs/backlog.md`, and the Build & Run / Who is who sections above.

- **2026-08-02 (later)** - **Critical privilege escalation fixed.** Any player could run one UPDATE against their own `accounts` row to become an administrator, then read every roster, capacity, court assignment and payment status in the club, demote Tara, and reassign other players to their own account. Cause: the lockdown block revoked grants on every hidden table except `accounts` and `players`, and both update policies had `USING` but no `WITH CHECK`. Fixed in `20260802000003_fix_privilege_escalation.sql` with three layers (column grants, `WITH CHECK`, trigger). Found by adversarial review, not by the existing tests: `information_hiding.sql` was green throughout because it never attempted the escalation. New probe `privilege_escalation.sql` performs the attack; it was verified to go **red on 7 checks against the unfixed schema** before the fix was applied. Suite now 107 checks plus the concurrency test, all green. See hard rules 8 and 9.

- **2026-08-02** - **The registration window rule was wrong, and had been since the repo was created.** Corrected, plus Tara's answered decisions applied.

  **What was wrong.** `member_opens_at()` computed "8:00 AM on the most recent Thursday strictly before the clinic date". That is a per-*clinic* rule. Registration is per *service week*: every clinic in a Sunday-to-Saturday week shares one pair of open moments, derived from the week's anchor Sunday. The naive rule agrees on Sunday through Thursday and is a full week late on Friday and Saturday, which are the two weekdays where seats are scarcest. It was wrong on the exact case Tara spelled out: for a Friday 2026-09-11 clinic it opened members on Thu 2026-09-10, a week after the date she gave, and its public-side counterpart returned Fri 2026-09-04, so non-members would have opened **six days before members**. In production this would not have looked like a bug. It would have looked like popular Friday clinics filling with non-members while members were told registration had not opened.

  **Why the original test did not catch it.** The test was written by reading the function. It asserted "the most recent Thursday strictly before the clinic date" against code computing the most recent Thursday strictly before the clinic date, so it confirmed the implementation matched itself. It even swept all seven weekdays and both DST boundaries, which is why the 2026-07-28 entry below claims the date math was verified: the coverage was real, the oracle was not. Two copies of one misunderstanding agreeing is not evidence. The replacement, `tests/sql/registration_window_rule.sql`, transcribes every expected value from the rule statement and was mutation-tested by reinstalling the old function: it goes red on 17 checks, including the Friday and Saturday rows, the UTC-anchoring trap, and the one-open-moment-per-week property.

  **A second defect surfaced doing that.** The probe harness's pass condition was `actual LIKE '%' || expected || '%'`, so an actual count of 105 PASSED against an expected 0 because "105" contains "0". That is what initially hid the new naive-divergence assertion. Fixed in all four probe files: substring matching now applies only when the expected value contains a letter. No pre-existing check was found to have been masking a real failure, but the suite's earlier green results were weaker than they read.

  **Also landed.** Week-anchored `service_week_start()` / `member_opens_at()` / `public_opens_at()`, DST-correct by wall clock, with a backfill that corrects only clinics still carrying the old computed values and leaves hand-overridden rows alone. `accounts.push_enabled` dropped (decision 13). `app_settings` added with Tara's exact payment string (decision 11). `players.adult_rating` converted from free text to `numeric(2,1)` constrained to the seven NTRP buckets, matching Volee's storage so ratings cross untranslated (decisions 6+7); `search_players` rebuilt for the new type. `clinic_audience` keeps `juniors` on purpose, and `category` keeps its column and gains no index (decision 8). Location hiding generalised from one view to every player-facing relation (decision 10).

  Verified locally: `supabase db reset` clean, probes 45/45 window rule, 21/21 schema decisions, 19/19 information hiding, 10/10 registration windows, capacity race PASS.

  **Open:** the five window-rule questions for Tara above, of which Saturday clinics (Q1) is the one that changes who gets a seat. Nine of the fifteen notifications in `docs/notifications.md` have no trigger today; eight of the nine need no scheduler (seven are a missing `notify_account` call inside an RPC a human already invokes, and the payment reminder needs a new admin RPC that Tara taps). Only "Registration is Open" genuinely requires one. **No scheduler was built and none should be invented** without Tara answering which window, which recipients, and batched or per clinic.

- **2026-07-28** - Repo created. Core schema, RLS and grant model, registration and admin RPCs, seed data, and three probe suites. Verified locally: registration windows 10/10, information hiding 16/16, capacity race PASS at 24-way concurrency across 3 runs. Registration window date math verified for all seven weekdays and both DST boundaries. Open: everything in `for-tara.md`, plus the Swift app.
