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

# The whole test suite. It prints its own totals; never quote a stale count
# in prose (the number 142 sat here for three weeks while the suite grew to
# 285).
bash tests/run-probes.sh

# Push migrations to the hosted project. THE ONLY sanctioned way to write hosted.
export SUPABASE_DB_PASSWORD='<from .env.local>'
supabase db push

# After any push, paste this into the session's changelog entry.
supabase migration list --linked
```

**`.env.local` goes at the repo root and IS ignored** as of 2026-08-13. It was
not before: `supabase/.gitignore` covers `supabase/.env.local` only, and the root
had no `.env` rule, so this very instruction was telling you to put the hosted
Postgres password somewhere `git add -A` would publish it. Nothing leaked, but
this line had asserted "gitignored" for three days as a parenthetical. **A claim
in a doc is not a control.** If a doc says something is protected, go and verify
the mechanism exists.

### Hosted is written by `supabase db push` and by nothing else

Earned 2026-08-13, immediately, by breaking it. The security migration was
applied through `mcp__supabase__apply_migration` because no `.env.local` existed
on the machine. It worked, and it silently stamped the remote ledger with its
own timestamp (`20260814011927`) instead of the file's (`20260813000001`).

Supabase matches applied migrations **by version string**, so the two
environments immediately disagreed: hosted had a version with no file, the repo
had a file with no version. The next `supabase db push` would have re-applied
that migration to a database where it had already run. It happened to be
idempotent `revoke`/`grant`, which is luck, not design. The next one will not be.

Repaired with `supabase migration repair --status reverted <mcp-version>` then
`--status applied <file-version>` (both rewrite the ledger only and run no DDL),
then verified with `supabase migration list --linked` showing every row paired
and `supabase db diff --linked --schema public` reporting no schema changes.

**Rule: `apply_migration` is for the local stack. Hosted gets `db push`.** If
`db push` cannot run because a credential is missing, the answer is to get the
credential, not to reach for a different tool that writes production.

| | |
|---|---|
| Local DB container | `supabase_db_FXE-Tennis` |
| Hosted project | `amnaxvznkadkgzdxzegw` (`fxe-tennis`, us-east-1) |
| Remote | `github.com/Volee-Team/FXE`, branch `main` |
| CI | `.github/workflows/probes.yml`, runs the full suite on every push and PR |

**No test fixtures in hosted, ever. Tara's real data is not a fixture.**
Clarified 2026-08-13, because the original wording ("the hosted database is not
seeded") read as a ban on putting anything in it, which was never the intent.

The line is between two different things:

| | Allowed in hosted? |
|---|---|
| Maria, Ken, Rob, "Tuesday Ladies 3.0+" and everything else in `supabase/seed.sql` | **No.** Fake people in a real roster, forever |
| Anything a probe creates | **No.** Probes write and delete. `capacity_race.sh` hard-deletes rows and is not transactional |
| Tara's real admin account, her real clinic templates, her real clinics | **Yes.** That is production data and the app is useless without it |

So the rule is: `supabase/seed.sql` is for local only, probes point only at a
throwaway Postgres (locally via `supabase db reset`, in CI on a fresh runner),
and **real content goes in through the same code path a real user would use**,
not a hand-written INSERT, so that the path itself gets exercised. Where no such
path exists yet, that is a missing feature to build, not a reason to hand-insert
around it.

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

11. **A grant you did not write is still a grant. Revoke before you grant, on
    views as well as tables.** Supabase bootstraps `alter default privileges in
    schema public grant all on tables to anon, authenticated`, so **every new
    table and every new view is born with INSERT, UPDATE, DELETE and TRUNCATE
    for both roles.** Adding `grant select` on top of that changes nothing.

    **Functions too, and the role is PUBLIC.** Postgres gives PUBLIC EXECUTE on
    every new function, and anon inherits it. `revoke ... from anon` alone is a
    no-op while PUBLIC still holds it; write `from public, anon`, then grant
    `authenticated` explicitly. 30 of 41 functions were anon-executable until
    2026-09-01 because of exactly this (migration 20260902000001).

    This matters more for a view than a table. Our views are single-table
    selects, so Postgres makes them **auto-updatable**; they were created without
    `security_invoker`, so they execute as their **owner** (postgres); and
    `relforcerowsecurity` is false, so the owner is **exempt from RLS**. A write
    through a view therefore runs as postgres with RLS switched off. The
    policies are not wrong, they are never reached. And a view's `WHERE` does
    **not** constrain an `INSERT` without `WITH CHECK OPTION`, so
    `where is_admin()` filtered reads and stopped no writes at all.

    Earned 2026-08-13. Any holder of the publishable key inside the iOS binary,
    signed out, could `delete from clinics_public` and destroy the whole
    schedule, cascading through every registration and message. An ordinary
    member could promote herself out of the Player Pool, mark herself paid, and
    cancel a clinic. Fixed in `20260813000001_lock_down_view_writes.sql`, pinned
    by `tests/sql/view_write_paths.sql`, verified red on 28 checks first.

    **Do not "fix" this with `security_invoker`.** It is the obvious-looking
    answer and it breaks the product: `authenticated` has no SELECT on the
    locked base tables, so the entire information-hiding model depends on these
    views reading with owner rights. The four `sanity_*` rows in that probe
    exist to fail loudly if anyone tries it. For the same reason the eight
    `security_definer_view` ERROR lints in Supabase's advisor are **permanent and
    accepted**, not a to-do list.

    The general shape, and the third time this project has been bitten by an
    implicit privilege: **enumerate what a role can do, never assume what it
    cannot.** See also hard rules 8 and 9.

12. **A claim about this repo comes with the command that produced it, in the
    same message. Never from memory, never copied from an earlier message.**

    Test counts, how many pass, what is built, whether something is ignored,
    what is deployed: all of these are claims, and every one of them has been
    wrong in this repo while sounding confident.

    Earned 2026-08-13, from the record itself. `ed88c1f` says the XCUITest suite
    was "2 of 4 green"; it was 0 of 4, and `docs/backlog.md` later had to correct
    the project's own commit message. `CLAUDE.md` said the probe suite ran 142
    checks while it ran 164, and that number had been copied forward through
    four documents. This file said `.env.local` was gitignored; it was not.
    `.claude/agents/sql-auditor.md` audits *Volee's* age brackets, in a repo that
    has no age brackets. Fifteen of the first sixteen commits were AI-authored
    with no reviewer, and every one of those errors is the same failure: a
    generated assertion accepted without independent re-derivation.

    The principle is **verification asymmetry**: the thing that produces an
    artifact cannot be the thing that certifies it. That is why code review, CI
    and separation of duties all exist. It is also why the SQL probes are the
    one part of this project that has never lied: they re-derive the claim from
    the database instead of restating it.

    In practice: run it, paste the output, then say what it means. "Tests pass"
    is not evidence. `Executed 13 tests, with 0 failures` is.

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

### 2026-08-12 call

| # | Decision |
|---|---|
| 17 | **Court number is never shown to a player.** Confirms hard rule 1. She reads it off her own screen |
| 18 | **Capacity is never shown to a player.** The wireframe's "Max: 12 Players" is not built |
| 19 | **Adults only, confirmed again.** Juniors return in the fall. The wireframe's child-profile screen is not v1 |
| 20 | **Clinic messaging: three audiences.** You're In!, Player Pool, or Both. Her example: a pro calls in sick. See `docs/decisions/0005-clinic-messaging.md` |
| 21 | **Three tabs, no Community tab.** Home, Clinics, Profile |
| 22 | **The gator-with-crossed-racquets mark**, not the tennis-ball one. Gets redrawn in whichever palette she picks |
| 23 | **Palette: racquet club / country club.** Her `#6dbe45` green kept but restrained; navy warms; cream ground. Three options sent for her to choose |

**On the wireframe mockups:** treat them as a *style guide*, not a spec. Alex,
2026-08-12: *"the wireframe is more of an overall style guide, dont let those
details override anything else... the most recent things tara says take
priority."* Where a mockup and a stated rule disagree, the rule wins, and the
most recent thing she said wins over both.

---

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

13. **Never put a word in front of a player that Tara did not write or Alex did
    not approve.** Copy is either hers, or plain functional chrome, and there is
    no third category.

    Earned 2026-08-16. Alex: *"text should either come straight from tara or
    made by u and checked by me first"*, after finding cliche AI filler of the
    *"Press play — Start Hitting!"* kind. The danger is not one bad sentence: it
    is that a generated line reads as plausible, arrives as one green line in a
    large diff, and ends up in front of a real club's members in a voice that is
    not their coach's.

    **Chrome** is a button that says Save, a field labelled Phone, an error that
    says the connection failed. Keep it plain and boring. **Everything else** —
    anything with tone, encouragement, a promise, or a claim about how FXE works
    — is Tara's, and if she has not written it yet the correct move is to ask,
    not to draft something plausible.

    Mechanically enforced. `docs/copy-approved.txt` snapshots every user-visible
    string; the `copy-gate` CI job fails on any addition or edit and prints the
    diff. Regenerating the snapshot is not a formality: read the new lines,
    decide which of the two categories each belongs to, and commit it alongside
    the change so a human sees the words in review. `docs/copy-audit.md` is the
    standing inventory of everything we wrote rather than her, with the 34 items
    that still need her marked.


---

## What this project is FOR (read this before optimising for speed)

Alex, 2026-08-13: *"the goal of this whole project is developing this app the
first time, using iteration and asking me and tara questions, double and triple
checking, being super thorough with writing down EVERYTHING in docs, using tons
of different tests, running agents, doing all the best SWE/AI practices."*

**Two products come out of this repo.** One is an app for Tara. The other is
Alex becoming a software engineer who can hold his own in a real company, and who
is heading for a SWE job. The second one is not a side effect and it is not
negotiable when it conflicts with the first.

What that means concretely for anyone working here, human or model:

* **Explain, do not just do.** When you use a concept Alex has not asked about
  before (a git tag, an RPC, a property-based test, a migration rollback), say
  what it is and why it is the right tool, in two or three sentences, in the same
  message. He has said explicitly that he wants to learn rather than vibe-code.
  A correct change he cannot explain to an interviewer is worth less than a
  correct change he can.
* **Show the reasoning, especially the rejected option.** "I used X" is worth
  little. "I used X, not Y, because Y would have broken Z" is the thing that
  transfers. This is why `docs/decisions/` has a Rejected section.
* **Prefer the practice a real team would use**, even when a shortcut works for
  one developer today. Decision records, probes, migrations, changelogs and tags
  are all overhead at n=1 and all of them are what n=5 requires.
* **Never trade a lesson for a few minutes.** If something broke, the write-up of
  why it broke is the deliverable, not just the fix.

### Always be auditing the practice, not only the code

The same scrutiny applied to a migration gets applied to how we work:

* At the start of a long session, and after any batch of decisions, re-read this
  file against reality. Stale rules are worse than missing ones because they get
  obeyed.
* When something is caught by an audit rather than by a test, that is a **test
  gap first and a bug second.** Write the probe, then the fix. See hard rule 9.
* When the same mistake happens twice, it stops being a mistake and becomes a
  missing mechanism. Promote it: `CLAUDE.md` rule, then slash command, then hook.
  Advisory, then procedural, then enforced.
* Ask what would have caught this earlier, every time. Then build that.
* Use the strongest tool available for the job, including parallel subagents and
  adversarial review, rather than the fastest one. Cost is not the constraint on
  this project; being wrong is.

### Standing instruction: improve the practice without being asked

Alex, 2026-08-13: *"i keep asking you these things, be more robust, think of
more docs to add to have better memory, use these hooks etc, but can you write
this down so you are constantly learning and automatically thinking of ways to
better yourself and make your SWE practices better?"*

So this is the instruction, and it does not need re-issuing. **Proposing
improvements to how we work is part of the work, not a separate request.**
Concretely, every session:

* **When something goes wrong, ask what mechanism would have caught it**, and
  build that mechanism in the same session. Not a note, not a resolution: a
  probe, a hook, a CI job, or a slash command. A lesson with no mechanism is a
  lesson you get to learn twice.
* **Notice repetition.** The third time a ritual is done by hand it becomes a
  slash command. The second time a rule is broken it becomes a hook.
* **Say when a practice is below what the tools allow.** Alex has explicitly
  said he wants the ceiling, not the floor, and that cost is not the constraint.
  Parallel subagents, adversarial verification, a full audit before a big
  decision: reach for them rather than economising.
* **Volunteer the concept, not just the fix.** When a technique applies here,
  name it and explain it briefly, because half the point of this project is that
  Alex learns the vocabulary. Recent examples worth knowing: verification
  asymmetry (hard rule 12), red-first testing, enumerate-don't-list, mechanism
  over discipline, context rot.
* **Keep an eye on the enforcement ladder.** Every rule in this file should be
  climbing it: advisory prose, then a slash command, then a hook or CI job that
  hard-blocks. If a rule has sat at prose for weeks, either promote it or admit
  it is not really a rule.

The measure is not "did we ship". It is whether the same class of mistake can
happen twice.

### Everything important gets saved, or it did not happen

Chat is not memory, and a `/clear` takes the whole session with it. This has
already cost a day. If it matters and it is not in the repo, it is gone. See
"Where things are written down" below for which file takes what.

---

---

## Copy: do not invent it

Alex, 2026-08-12: *"I pretty much NEVER want you making up sentences or little
text blurbs that go in the app... somehow the text is always cringe and
unnatural."*

**Player-facing words are Tara's, not yours.** Every notification body, every
piece of guidance, anything with a voice, comes from her. When a screen needs a
sentence nobody has written, do not invent one and move on: write the shortest
literal thing that works, add it to `docs/copy.md` marked **PENDING**, and tell
Alex it needs her words.

### Rules for the chrome you do write

Button labels, empty states, and error lines are unavoidable. Keep them plain.

* **No throat-clearing.** No "Heads up:", "Just a reminder,", "Oops!", "Please
  note", "Don't worry". Delete the opener and start at the fact.
* **One sentence.** If it needs two, the screen is doing too much.
* **No em-dash explainers**, no clever asides, no exclamation marks. Tara's own
  copy uses them; yours does not.
* **Say the thing, not the feeling.** "Couldn't load clinics." not "Something
  went wrong while we were fetching your clinics. Please try again."
* **Errors say what happened**, and only offer a next step if there is a real
  one. Pull-to-refresh already exists; the text does not need to explain it.
* **Match her vocabulary exactly.** You're In!, Player Pool, Response Needed,
  Canceled. Never waitlist, confirmed, registered.

Examples of the rewrite, all real:

| Before | After |
|---|---|
| "Heads up: clinic updates come through the app. If your notifications are off, you may miss important messages." | "Clinic updates come through the app. Keep notifications on so you don't miss them." |
| "That didn't go through — someone may have acted first. Here's the latest." | "That just changed. Here's the latest." |
| "New here? Create an account" | "Create an account" |
| "Couldn't load clinics. Pull to refresh." | "Couldn't load clinics." |

---

## Which source wins

Alex, 2026-08-12: *"dont 100% trust that dev guide, more what tara says and the
original spec."*

When two sources disagree, this is the order:

1. **What Tara said most recently.** A call today beats a document from June.
2. **The original spec** she approved.
3. **The Developer Guide.** Useful, and already wrong in places (it specs a News
   tab, junior flows, and a Community tab that are not v1).
4. **The wireframe mockups.** A style guide for look and feel, never a spec.

If a lower source contradicts a higher one, the higher one wins and the conflict
gets written down rather than silently resolved.

---

## Where things are written down

- `docs/feature-review-2026-09-02.md` — every screen walked after the 09-02 merges; one finding per line with the change to make and a severity. The UI-testing pass targets its coverage table.

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

- **2026-09-01** — **The pause we predicted happened, and hosted finally caught up.** The free-tier project sat idle past its window and Supabase paused it: DNS gone (NXDOMAIN), status `INACTIVE`. This is the exact "Tara opens the app Thursday 8am and the backend is asleep" scenario the 2026-08-16 audit flagged, and the keep-warm job that prevents it has **never run once** because `backup.yml` sits in the unmerged PRs. Restored via the management API (CLI keychain token, `POST /v1/projects/{ref}/restore`), then ran the first `supabase db push` since 2026-08-13: **seven migrations** (create_my_account, clinics_admin refresh, explicit grants, admin CRUD, 3h close, late requests, templates/floor/bootstrap). Verified per protocol: all 17 migrations paired local↔remote, `templates_admin` live (401 to anon, exists), `create_my_account` live (42501 to anon, exists — note PostgREST returns 404 for a wrong-argument call, which looks identical to "missing"; test with real argument names), and `fxe-tennis-admin.vercel.app` renders against hosted with zero console errors. **Merging PRs #1–#3 is now the single most overdue action in the project**: until then there is no keep-warm, no nightly backup, and `main` predates the security lockdown. (Alex merged #3 the same day.)

  **Action Needed, Money, and Forgot password — the last three roadmap rows that needed no new schema.** `notifications` was written by six RPCs and readable by nobody: `revoke all` in 20260813 had never been followed by a grant, so the late-request work of 08-28 notified Tara into a table she could not select from. Migration 20260901000001 grants SELECT and UPDATE of `read_at` only (the probe asserts the column list, red first). Web admin gained an Action Needed panel (late requests → `resolve_late_request`, unread cancellations and invitation replies → Seen) and a Money panel on `revenue_summary()` + `revenue_by_clinic()`; iOS gained the same Action Needed rows and the late-request section on the roster. Verified live in the browser: approving Priya put her in at $23 non-member and the Money numbers moved with her.

  **Password reset had a flaw no build would show.** The reset email's link ignored the app's redirect and pointed at the Site URL, because GoTrue silently falls back for any URL not on its allow-list (`additional_redirect_urls` locally, the dashboard on hosted). Worse, both clients used PKCE, so a reset started in the iOS app could never be finished by `reset.html` in a browser: the one-time code is bound to the device that asked. Both clients now use the implicit flow for this, and the reset page is allow-listed locally. Hosted still needs Alex to add the Vercel URL in the dashboard (`docs/backlog.md`). Lesson: an email link is a cross-device handoff, and PKCE is designed to forbid exactly that.

  **The sign-up XCUITest then failed on a screen this branch never touched, and it was right.** "Continue never became reachable": with the software keyboard up, the profile form cannot scroll far enough to expose Continue, so a real player who types their name and taps Yes is looking at a button under the keyboard. The test's own comment predicted this. Fixed in the app, not the test: answering the membership question or picking a rating drops the keyboard (`@FocusState`), and dragging the form dismisses it interactively. A UI test that fails on a screen you did not change is the test doing its job; the reflex to widen its timeout is the one to resist.

  **First backup ever, and it failed on the first try, and it was worth it.** I claimed the nightly backup had never run because the `SUPABASE_DB_URL` secret was unset. Wrong: Alex set it two weeks ago. The true reason was that `backup.yml` only reached `main` when PR #3 merged. Dispatched by hand once `gh` was signed in: the keep-warm job passed and the dump failed with `server version: 17.6; pg_dump version: 16.15`. The install step really did install client 17, but Ubuntu's `pg_dump` is a wrapper that still picked the runner's preinstalled 16. Fixed by calling `/usr/lib/postgresql/17/bin/pg_dump` by path. Two lessons: a claim about CI state comes from `gh run list`, not from memory (hard rule 12 again), and a backup job that has never produced an artifact is not a backup.

  **30 of 41 functions were executable by anon, and had been since July.** Found while checking `assign_court` before wiring it up. Postgres gives PUBLIC EXECUTE on every new function; several migrations revoked "from anon", which is a no-op while PUBLIC holds the privilege (20260815 said so about one function and the lesson stayed local). Nothing leaked: every one starts with `require_admin()` or an `auth.uid()` check. But the grants probe had enumerated relations since 08-16 and never asked the same question of functions, so the surface was one forgotten `require_admin()` away from mattering. Migration 20260902000001 revokes from PUBLIC and anon on all 41 and grants `authenticated` on the 34 client RPCs explicitly (trigger functions get nothing; Postgres checks EXECUTE at CREATE TRIGGER, not on fire). Four new enumerating checks, red first (299 across 12). Rule for the file: **`revoke from anon` without `revoke from public` is decoration.**

  **Courts, at last.** `assign_court` existed since 2026-07-28 and nothing called it. Now a dropdown on every You're In! row in the web admin and a menu on the same row in the app, both writing through that one RPC, and the You're In! list sorts by court so it reads as Tara's court sheet. Two things worth knowing: clearing a court means sending an explicit JSON `null`, and Swift's synthesized Encodable *omits* a nil optional, which makes PostgREST look for a one-argument overload and return 404 "function not found", the same 404 that means "not deployed" (2026-09-01 audit). The Swift params struct encodes the null by hand and says why. Drag-and-drop was not built and is not planned until the dropdown has been used for real (`docs/web-admin.md` section 4).

  **One-tap unpaid reminder.** "Remind unpaid (N)" on the clinic card (web) and under Message Players (iOS, with a confirmation because it messages several people and a courtside mis-tap should not). The body is assembled from what Tara owns: clinic name, date, and her payment line from `payment_instructions()`; the audience is `unpaid`, resolved by `send_clinic_message`, so the recipient list is the database's, not the screen's. Her payment line has no closing period, so both clients add one before "Thanks!". The connective words are mine and sit in `docs/copy-review.md` until Alex ticks them, per rule 13. Caught in the browser: the web toast was being wiped by the reload the action itself triggers; the confirmation is now written after the reload.

  **Player directory, and the notes that had a table but no door.** `player_notes` existed since the first migration with an admin-only policy and no privilege for `authenticated` and no RPC, so `search_players.has_notes` reported on notes nobody could write. Tara's "I can correct anyone's status on their profile" (for-tara.md q5) had the same shape: said yes to, never built. Migration 20260902000002 adds `admin_player_note`, `admin_set_player_note` (blank deletes the row so `has_notes` stays honest) and `admin_set_membership`, all `require_admin()`, revoked from PUBLIC first. Probe `player_directory.sql`, 14 checks red first, including the ones that matter: a member cannot read *their own* note (hidden fact 7) and cannot promote themselves to member pricing. Web: a Players panel (search, member / active toggles, inline note). iOS: a Players screen off the Manage tab with a detail page per player. Verified in the browser end to end; the note round-tripped through the database.

  **PR #9 was merged with a red check, by me, and that is the lesson of the night.** A docs-only PR failed the iOS job because the macos-15 runner image did not have the pinned "iPhone 17 Pro" simulator, and the merge chain I had written joined its steps with `;` instead of `&&`, so `gh pr merge` ran regardless of what `gh pr checks` returned. Nothing broke on `main` (the failure was the runner, and the push-event run of the same commit was green), but the process claimed "CI is the gate" while the shell script said otherwise. Two fixes: the workflow now picks any available iPhone simulator by UDID, and every merge chain gates the merge on the checks with `&&`. The durable fix is branch protection that makes GitHub refuse the merge, which is a repository setting for Alex to switch on.

  **Week grouping on the player's clinic list.** The list was flat; now it folds under This week / Next week / Week of …, using the same Sunday-in-New-York arithmetic as `service_week_start` (decision 0001). `ServiceWeek` is pure and unit-tested at the edge that matters: 23:30 on a Saturday in New York is already Sunday in UTC, and the database uses New York, so the client must too or the two disagree once a week. Grouping only; nothing here decides whether registration is open.

- **2026-09-02** — **My Clinics is a screen, and the list has an edge.** "View All Clinics" under My Clinics on Home opened the browse list, which is every clinic, not mine; it now opens a My Clinics screen: the clinics I hold a live registration in, grouped by week, each wearing its status chip, with the empty state handing off to the open list. The browse list gained the other edge it was missing: the view drops finished clinics (08-28), and the client now stops five weeks out, so a season Tara publishes in bulk is not one endless scroll. Eighth XCUITest: the link opens a screen titled My Clinics and renders none of the browse list's cards.

- **2026-09-02** — **Push notifications: everything but the key.** Decision 0008 written: APNs from an edge function on a `notifications` webhook, so every RPC that writes a row gets a push for free and no client holds a sending credential. Built today: `register_device` / `unregister_device` (account is `auth.uid()`, table stays client-unreadable, 11-check probe red first, including "Rob registering Maria's token string gets his own row and cannot unregister hers"); the permission sheet with Tara's Screen-3 sentence, shown once after the profile exists and suppressed in UI-test mode; the `aps-environment` entitlement via XcodeGen; registration on every signed-in launch; unregister on sign out so a shared phone never shows the next person someone else's invitation. Verified on the simulator up to Apple's push daemon adding the app's topic; it held no sandbox token, so the token callback and the RPC call were not observed end to end there. The sender, the webhook and the audit columns wait on the Apple Developer account for the signing key.

- **2026-09-02** — **The bell finally opens something.** Every RPC had been writing `notifications` rows since July and the bell on Home was a picture. Now it is a button with an unread badge, and it opens a notification center: newest first, unread in bold, tap a row to mark it read, Mark all read as the broom. Read state is `read_at` in the database, not on the device, so the badge agrees across reinstalls and later across the web admin. The rows' words are already Tara's because the RPC that caused each one wrote it. Seeded two rows for Maria so a fresh reset has something to show, and a sixth XCUITest walks bell → rows → Mark all read → badge gone, asserting on the bell's own accessibility label so it is the database that clears it, not the view.

- **2026-09-02** — **A player can fix their own name, phone and rating.** Profile was read-only since the day it was built. "Edit details" opens the same fields and rating pills as the sign-up profile screen, and saves with two narrow UPDATEs on exactly the columns `authenticated` holds column-level UPDATE for (20260802000003). Membership is shown with "Set by Tara" and is not editable: it decides pricing and the head-start window, so after sign-up it is hers to correct (for-tara.md q5, hard rule 2). Seventh XCUITest changes the phone to a per-run value and reads it back off Profile after the session reloads.

- **2026-09-02** — **Cancel clinic, the last RPC with no caller.** `cancel_clinic` flips the status, stamps `canceled_at`, and notifies everyone in You're In!, the Player Pool and Response Needed; it has done so since July with no button anywhere. Web: a two-click button on the clinic card (the second click reads "Really cancel? Everyone is told." and disarms after five seconds), chosen over a native `confirm()` because that is unstyleable and blocks browser tests. iOS: a More menu on the admin roster with a confirmation dialog that spells out the consequence, then pops back to a reloaded list. The already-canceled error is mapped to words. Archive, never delete (hard rule 4): the row and its registrations remain, and the card shows a Canceled chip.


- **2026-08-16** — **Tara's copy, the "?" explainer, and a diagnosable CI.** `docs/copy.md` finally exists: `CLAUDE.md` has pointed at it since the repo was created, which is exactly why clinic descriptions were invented placeholders for three weeks. It carries her verbatim text for **105** (a fast-paced doubles format, undefined anywhere until she explained it, and the answer to the one blocking question from `docs/taras-real-week.md`), Ladies 3.0+, All-Level Ladies, All-Level Men's, and a new **FXE Queen City Team Ladies Practice**. Built her own suggestion: a "?" on every clinic card opening an explainer, with the 105 definition appended when the name **or** category matches. Two deliberate non-fixes recorded: the two All-Level descriptions are identical apart from an exclamation mark and are *not* merged into a shared string, and Queen City's "team players only" is **not enforced**, because there is no team concept in the schema and inventing one is a schema decision, not a copy one.

  **App icon corrected twice, and the second correction was the real lesson.** The first icon used the tennis-ball mark, contradicting decision 22, which had already recorded the crossed-racquets mark as Tara's choice: a claim asserted instead of derived, one turn after writing hard rule 12 against exactly that. The second used the right mark but recoloured to palette-B tokens, which disagreed with the login screen rendering the same `gator-x` asset in its original grey. Now the untouched mark on `Brand.navy`. **Nothing checks that the shipped icon matches the recorded decision** — a gap, not a fix.

  **CI: the probes job had been failing on every branch with a log that said nothing**, because its only diagnostic step ran `supabase logs db` against a stack that had never started. Versions are now printed before anything runs, `start` output is unsuppressed, container state dumps with `if: always()`, and failure diagnostics fall through four sources. Also reverted a same-week pin of the CLI to 2.90.0 back to `latest`: it was the only change to that job before it began failing after ~2 minutes, which is `supabase start` dying rather than a probe failing.

- **2026-08-15** — **Sign-up was a dead end, and the admin surface did not exist.** `auth.signUp` created an auth user and nothing else: no client path could write `accounts` (no INSERT grant, no trigger, zero table writes in Swift), so a new member landed on a Home greeting them "there", was quoted every non-member price, and had a Register button that silently returned. Fixed with `create_my_account` (SECURITY DEFINER; the id is `auth.uid()`, the email comes from `auth.users`, and `role` is hard-coded to `member`, so it can neither impersonate nor self-promote) plus a `.needsProfile` phase and a profile screen using her Screen 4 copy. Probe: 22 checks, red-first. **Admin tab** built on RPCs that already existed and were already probe-covered: You're In! with a Paid toggle, Player Pool in registration order with Invite, Response Needed with Cancel Invite, and clinic messaging. Verified on the simulator that inviting moves a player to Response Needed while the You're In! count is unchanged, which is hard rule 2 holding.

  **Three bugs found by looking at the screen, none of which any test would have caught.** The worst: `myPlayers()` selected from `players` with no `WHERE`, trusting RLS to narrow it, but that policy is `account_id = auth.uid() OR is_admin()`, so an **admin got every player in the club** and `players.first` made Tara an arbitrary member. Signing in as her greeted "Good Morning, Maria!"; she would have seen someone else's My Clinics and could register and cancel as them. **An RLS policy written to also admit admins is not a substitute for a WHERE clause: RLS bounds what a query MAY return, never what it SHOULD.** Also: `CompleteProfileView` had no exit, so anyone who reached it and could not finish was stuck (the same dead-end shape the screen was built to fix, one screen later); and the greeting read only `activePlayer`, so an admin account, which has no player row, was greeted "there" on her own app.

  **`clinics_admin` was stale**, created as `select *`, which Postgres expands once at creation. The 2026-08-10 pricing columns therefore never appeared, so players could see both published rates and the person who sets them could not. It had already been caught in `docs/backlog.md` because naming those columns made an attack in `view_write_paths.sql` fail with 42703 and report a **false pass**. Columns are now listed explicitly, with two probe assertions verified red first. `select *` in a view is a time bomb whose fuse is the next migration.

- **2026-08-14** — **Test health, CI, and the things that were quietly untrue.** `FXETennisTests/` contained zero files, so the target built an `.xctest` with no executable and **every** `xcodebuild test` exited 65 regardless of the UI tests' own result; `build-for-testing` still printed SUCCEEDED, which is why nobody noticed, and `xcodegen` broke on a fresh clone for the same reason. 13 unit tests now cover the pure logic the probes cannot see. **XCUITests were 0 of 4, not the "2 of 4" `ed88c1f` claimed**: identifiers on Home and Profile were set on the view *inside* the button rather than the button, and one assertion compared visible text when `StatusChip` publishes its VoiceOver label, so it failed on a *correct* registration. Now 5 of 5 including a sign-up regression test. CI gained an iOS build job (it had never compiled a line of Swift), a secret scan, and an app-icon gate; `push:` no longer filters to `main`, so it finally runs on the branches the SessionStart hook tells every session to create. Nightly `pg_dump` backup added: the org is on the free plan, which has no PITR, while hosted is becoming the only copy of the club's data.

  **`.env.local` was never gitignored** while this file told you to put the hosted Postgres password there and called it "gitignored". Nothing leaked, but a claim had been standing in for a control. **Hard rule 12 added** from the pattern across all of it: a claim about this repo comes with the command that produced it. **Prompt and reply logging** now runs automatically via hooks, after a `/clear` destroyed a session and cost about a day.

- **2026-08-13** — **Critical: anyone holding the app's publishable key could destroy the database.** Found by audit, not by the suite. The 2026-07-28 lockdown revoked the base tables but never the views, which inherit `grant all` from Supabase's default privileges. Because the views are auto-updatable, run with owner rights, and sit on tables where RLS is not forced, a write through one executed as postgres with RLS switched off, and a view's `WHERE` does not constrain an `INSERT` anyway. Signed out, `delete from clinics_public` wiped every clinic and cascaded through all registrations and messages; an ordinary member could self-promote out of the Player Pool, mark herself paid, hard-delete her own registration, and cancel a clinic. Fixed in `20260813000001_lock_down_view_writes.sql` (revoke-then-regrant on all 8 views, anon stripped of every grant in `public`, and `alter default privileges ... revoke` so the next `create view` cannot re-open it). New attack probe `tests/sql/view_write_paths.sql`, **verified red on 28 checks before the fix**, green on 21 after. Hosted was empty, so nothing was lost. See hard rule 11.

  **Two lessons worth more than the fix.** First, the probe's own first draft ran the catastrophic `delete` before the other attacks; it succeeded, cascaded, and made five later attacks report a spurious PASS because their target rows were already gone. The destructive attacks now run last. Same family as the 2026-08-10 harness bugs: a probe that masks its own findings. Second, one attack reported PASS because it named a column that view does not have (42703), not because anything blocked it. Blocked-by-a-typo is not blocked-by-a-privilege, and the fixed attack then proved anon could create a clinic.

  **Also learned:** Supabase's advisor had 8 ERROR-level `security_definer_view` lints the whole time, and they were **not** this bug and must not be "fixed" (owner-rights reads are load-bearing here). The real hole was invisible to the linter. Separately, the 22 `anon_security_definer_function_executable` warnings are defence-in-depth only: `place_player` and `cancel_clinic` both return `not_authorized` to anon, verified.

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
