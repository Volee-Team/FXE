# FXE Tennis - Project Context

iOS native app (Swift / SwiftUI). Backend is Supabase (Postgres + Auth + Edge Functions; APNs delivery is designed in decision 0008 and not yet built). Clinic registration and roster management for the FXE tennis program.

**This is NOT Volee.** Separate repo, separate Supabase project, separate bundle ID, separate App Store listing. They share patterns and a developer, nothing else.

---

## What this app is

The digital front door for the FXE tennis program. It replaces repetitive texts, spreadsheets, manual clinic lists, and scattered reminders with one system for registration, player management, clinic communication, payment checkboxes, and court organisation.

**The product rule that settles most arguments:** the app organizes information. Tara makes all coaching, player-selection, clinic-balance, and court-placement decisions. When unsure whether to automate a decision or leave it to Tara, leave it to Tara.

Source spec: the FXE Tennis Version 1 Developer Guide. Engineering decisions derived from it: `docs/engineering-design.md`. Questions for Tara, each marked with the decision that answered it: `docs/questions-for-tara.md` (the August version she was first sent is `docs/for-tara.md`; the 2026-09-12 short list is `docs/for-tara-2026-09-12.md`). These four lived in a folder beside the repo until 2026-09-12, when Alex moved them in: a doc outside the repo is a doc nobody can find or version.

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

**Break one thing at a time.** Two breaks in one run can hide each other: on
2026-09-28 a sort flipped to "latest first" happened to pick the right clinic
and masked a removed filter, so the filter's test passed while broken. Each
rule gets its own red run.

That exercise is what exposed a defect in the probe harness itself: the pass condition used `actual LIKE '%' || expected || '%'`, under which an actual count of **105 passed against an expected 0**, because "105" contains "0". Substring matching now applies only when the expected value contains a letter, which is the case it existed for (a server error message wrapping an expected error name). **Do not loosen it back.** If a new check needs fuzzy matching, normalise the actual value instead of widening the comparison.

---

## Hard rules

1. **Information hiding is a database concern, never a UI concern.** Nine things are hidden from players: clinic capacity, number registered, spots remaining, Player Pool size, other players' names, court assignments, other players' payment status, private coaching notes, and clinic location. Hiding these in SwiftUI hides nothing. They are enforced by revoked table grants plus narrow views (`clinics_public`, `my_registrations`, `my_clinic_messages`, `my_news`, `my_past_clinics`). **Never grant a client direct SELECT on `clinics`, `registrations`, `player_notes`, or `clinic_templates`. Never return a count of anything to a player.** Pinned by `tests/sql/information_hiding.sql`.

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

    This matters more for a view than a table. Four of our views
    (`clinics_public`, `my_registrations`, `clinics_admin`, `templates_admin`)
    are single-table selects, so Postgres makes them **auto-updatable**; the
    joined ones are not, but revoke-before-grant applies to all eleven; they were created without
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
    views reading with owner rights. The five `sanity_*` rows in that probe
    exist to fail loudly if anyone tries it. For the same reason the
    `security_definer_view` ERROR lints in Supabase's advisor (one per
    owner-rights view; eleven views today) are **permanent and accepted**, not a
    to-do list.

    The general shape, and the third time this project has been bitten by an
    implicit privilege: **enumerate what a role can do, never assume what it
    cannot.** See also hard rules 8 and 9.

    Two more facts from 2026-08-19 (migration `20260817000001_explicit_read_grants.sql`), recorded here because they lived only in that file's header: **a grant you did not write can also be taken away**, and it was, when the Supabase CLI moved from 2.90 to 2.115 and the inherited blanket SELECT vanished, breaking the app for every user until the grants were written down; and **RLS does not apply to TRUNCATE**, so `authenticated` could `truncate players` until the table-level privilege was revoked. A policy is not a privilege.

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
    `.claude/agents/sql-auditor.md` audited *Volee's* age brackets in a repo that
    has none (rewritten for FXE since). Fifteen of the first sixteen commits were AI-authored
    with no reviewer, and every one of those errors is the same failure: a
    generated assertion accepted without independent re-derivation.

    The principle is **verification asymmetry**: the thing that produces an
    artifact cannot be the thing that certifies it. That is why code review, CI
    and separation of duties all exist. It is also why the SQL probes are the
    one part of this project that has never lied: they re-derive the claim from
    the database instead of restating it.

    In practice: run it, paste the output, then say what it means. "Tests pass"
    is not evidence. `Executed 23 tests, with 0 failures (0 unexpected)` is.

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
    2026-08-16 inventory of everything we wrote rather than her (its "34" predates
    her 2026-08-27 answers; §1 and §2's tone are settled), and
    `docs/copy-review.md` is the live checklist Alex ticks.

14. **When a decision is Tara's, ask Tara before building, even at five percent
    doubt.** Anything that encodes how she runs her clinics — a price, a fee, a
    window, who pays what, what a message says, what happens when someone
    cancels — is her call, not a sensible default. Alex, 2026-09-12: *"help me
    get the info from TARA before we do things ALWAYS ... always ask tara if
    you're unsure even 5%."*

    Mechanically: write the questions into `docs/questions-for-tara.md`,
    numbered, each answerable in one line, with the
    default we would otherwise pick stated so she can just say "yes". Hand them
    to Alex to relay. While waiting, build only the policy-independent parts.
    When the answers come back, record them as a dated decision record (the way
    0007 records 2026-08-27) and pin any rule with a DB consequence in a probe.
    The cost of asking is a text message; the cost of guessing is a rebuild and
    her trust.

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
| **Ladies / Men / Coed** | The three v1 audiences. Juniors return in November or the spring session (decision 0007 §6). |

---

## Registration rules

| Situation | Result |
|---|---|
| Anyone who has not signed the current waiver | Rejected by `register_for_clinic` (`waiver_required`), admins exempt (decision 0013 §4) |
| Anyone without a saved card, while payments are on | Rejected (`card_required`); a saved card is `card_last4`, not a Stripe customer id (decision 0015 §5), admins exempt |
| Non-member already holding a spot in a 105 that New York day, taking a second 105 | Rejected (`back_to_back_105`) until 48 hours before the earlier start; members and Tara exempt (decision 0015 §13) |
| Member, inside priority window, room available | You're In! |
| Member, inside priority window, clinic full | Player Pool |
| Member, after priority window | Player Pool |
| Non-member, after public opening | Player Pool |
| Non-member, inside member-only window | Rejected |
| Anyone, before member opening | Rejected |
| Anyone, after `closes_at` | Rejected by `register_for_clinic`; may file a late request (`request_late_spot`) that Tara approves or declines by hand |
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

**Blocking non-members during the member window is our decision, not the guide's.** The guide only states their opening is Friday 8 AM. Tara sees the Pool in registration order, so letting non-members queue on Thursday would place them ahead of members in her list and quietly subvert the priority. Confirmed by Tara 2026-08-27 (decision 0007 §2: members "get first dibs for 24 hours"); pinned by `tara_member_head_start_is_24h` in `tests/sql/schema_decisions.sql`.

Capacity is decided in exactly one place: `register_for_clinic`, which locks the clinic row with `FOR UPDATE`. Pinned by `tests/sql/capacity_race.sh` (12-way on every suite run; verified once at 24-way on 2026-07-28 with `bash tests/sql/capacity_race.sh 24`). `place_player` deliberately performs **no** capacity check: capacity never blocks Tara (decision 4).

### Open questions on the window rule

Tara's example is consistent with more than one reading. The most defensible reading is implemented; these are the points where a wrong guess costs someone a seat.

1. **Saturday clinics: answered 2026-09-21 (decision 0013, question 49).** *"Yes. But no Saturday clinics. The 'week' starts on a Sunday to Friday."* The week-start anchor as built is confirmed; Saturday is theoretical.
2. **Anchor point: answered 2026-09-21 (decision 0013, question 50).** A short week still opens that same Thursday and Friday. Start-anchored, as implemented.
3. **Holidays.** The rule has no holiday awareness. Christmas Day 2026 is a Friday public open, and Christmas Eve is its Thursday member open. Ask her whether registration still opens at 8:00 that morning.
4. **"Member"** means an FXE club member, not a paying app subscriber. `players.is_member`. Confirm with her if it ever becomes ambiguous.
5. **`closes_at`: answered 2026-08-27 (decision 0007 §5).** Registration closes 3 hours before start by default (`default_closes_at()` plus trigger `apply_default_clinic_close`, migration 20260827000001); Tara can override any clinic through `admin_upsert_clinic`. Inside the window a player can file a late request (`request_late_spot`, 20260827000002) that she resolves by hand.

---

## Tara's decisions, 2026-08-02

Answered and now binding. Numbering is hers. Only the ones with a lasting consequence are restated here; the migration `20260802000002_tara_decisions_2026_08_02.sql` carries the full reasoning for each database change.

| # | Decision | Where it lives |
|---|---|---|
| 1 | Admin surface splits in two: a phone app for courtside work (invites, messages, marking paid) and a laptop/web page for weekly setup and court assignment. | Client |
| 3 | Tara can add anyone to any clinic directly, and move anyone between You're In! and Player Pool by hand. | `place_player()` |
| 4 | **Capacity never blocks Tara.** Show counts, never block an invite. | `place_player()` does no capacity check. Pinned. |
| 5 | Member status is **self-reported** once at sign-up, and Tara can override it on the profile (`admin_set_membership`, web and iOS). Since 2026-09-02 the player's own Profile shows it as "Set by Tara" with no control. Since 2026-09-21 the column is Tara's at the DB level too: `revoke update (is_member)` (20260921000001), asserted by `tests/sql/player_directory.sql`. | `players_update_own` policy, `admin_set_membership()` |
| 6+7 | Adult rating uses the **same NTRP scale and the same chart as Volee**, behind a tappable "?" button. Stored as `numeric(2,1)`, 2.0 to 5.0 in half steps, exactly as Volee stores it, so a rating crosses between the apps untranslated. **"5.0+" is a display label, never a stored value.** | `players.adult_rating`, `docs/ntrp-chart.md` |
| 8 | Audience is **Ladies / Men / Coed** in v1. **No category filter**: Tara said there is no need to filter anything, because there are not many clinics weekly and they are simply listed by week. | See below |
| 9 | Junior age groups deferred to the fall. Do not build. | none |
| 10 | **Clinic location is hidden**, and the reason matters: FXE is a member club and must not read as open to non-members. Location must not appear anywhere player-facing, in any form, including maps, addresses, and directions links. | Pinned by `information_hiding.sql` |
| 11 | Payment copy, exact string, Zelle preferred. **Superseded by decision 0013 (2026-09-21): card only, `zelle_allowed` false. The string stays in `app_settings`; nothing sends it.** | `app_settings.payment_instructions` |
| 12 | Targeted messages are visible only to the group they were sent to. | Already built: `clinic_message_recipients` |
| 13 | **Notifications-off is not Tara's problem.** See below. | Client |
| 14 | Every notification is 1 to 2 sentences and readable on a lock screen. Her drafts are verbatim. | `docs/notifications.md` |
| 15 | Brand is navy blue and a nice green, country-club feel, **not** the current royal blue and green. Same gator-with-tennis-ball mark. **Mark superseded by decision 22 (2026-08-12): crossed racquets, not the tennis ball.** | `web/tokens.css`, `FXETennis/Resources/Brand.swift` |
| 16 | Apple Developer account must be "FXE Tennis, LLC". Privacy policy reuses Volee's. Waiver wording pending. | Business |

### The `juniors` enum value stays

Decision 8 limits v1 to three audiences, but `clinic_audience` keeps all four. Postgres has no `DROP VALUE`: removing one means creating a replacement type, rewriting every dependent column and default, recreating dependent indexes and views, and dropping the old type. That is a migration with real blast radius, run twice, to delete four characters no player can see. **The constraint Tara stated is a UI constraint.** Enforce the three options in the admin audience picker. A DB value nobody can select is inert. Pinned by `tests/sql/schema_decisions.sql` so nobody "tidies it up".

### Category is kept and not filtered

`clinics.category` and `clinic_templates.category` stay: nullable, free text, display only. **Deliberately unindexed**: an index is what you add when you intend to filter, and adding one is a quiet promise that we do. Do not build a category filter without asking her.

### Decision 13: the notifications-off disclosure is a client requirement, not a column

Tara explicitly does **not** want to manage or monitor who has notifications on or off. `accounts.push_enabled` is dropped, and no admin surface may display anything of the kind. Do not re-add it, and note that `docs/engineering-design.md` §4 and `docs/questions-for-tara.md` Q19 both still specify the old "notifications off" marker and carry an overruled note.

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
| 20 | **Clinic messaging.** Her ask was three audiences (You're In!, Player Pool, Both; `docs/decisions/0005`). **Built with five**, matching `message_audience`: Everyone, You're In!, Player Pool, Response Needed, Unpaid, on web and iOS; Unpaid is hidden while `zelle_allowed` is false. Decision 0005 records the three; the extra two are the enum's, kept (hard rule 4) |
| 21 | **Three tabs, no Community tab.** Home, Clinics, Profile for players. An admin account also gets a Manage tab (Alex, 2026-08-15; `MainTabView.swift`) |
| 22 | **The gator-with-crossed-racquets mark**, not the tennis-ball one. Gets redrawn in whichever palette she picks. **In colour since 2026-09-29 (decision 0032)**: one source file, every copy made by `scripts/make-logo-assets.py` |
| 23 | **Palette: racquet club / country club.** Her `#6dbe45` green kept but restrained; navy warms; cream ground. Three options sent for her to choose |

**On the wireframe mockups:** treat them as a *style guide*, not a spec. Alex,
2026-08-12: *"the wireframe is more of an overall style guide, dont let those
details override anything else... the most recent things tara says take
priority."* Where a mockup and a stated rule disagree, the rule wins, and the
most recent thing she said wins over both.

---

## Visual direction

**Kat's style guide is the source of truth for style from the day it lands** (Alex, 2026-09-22: *"for all of these edits in the app, go w the style guide! write down, this is source of truth for style!!"*). It goes in `docs/style-guide.md` when she sends it; until then `docs/design-system.md` and `Brand.swift` stand, and every visual change made before it arrives gets re-checked against it. Tara's one standing ask on top of it: pages carry a light cream-to-warmer-cream gradient, not flat white (`Brand.surfaceGradient`, 2026-09-22).

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

Friendly empty states, each with one useful next action. Friendly errors, one sentence: "Couldn't load clinics." (see "Rules for the chrome you do write" below).

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

A small key/value table for **player-safe strings and switches**. Read by any authenticated user. **No client can write it today** (2026-09-12 audit): `authenticated` holds SELECT only and no RPC updates it, so the `app_settings_admin_write` policy is unreachable and every value is set by migration; an admin edit path is a backlog item, and until it exists the "no migration for a typo" benefit below is not real. Holds `payment_instructions`, Tara's exact wording, plus the six payment-policy keys added 2026-09-12 (`payments_enabled`, `cancel_cutoff_hours`, `late_cancel_fee`, `charge_fee_at`, `late_charge_needs_tap`, `zelle_allowed`), `card_required` and `courtesy_cancel_days` (2026-09-16), and `waiver_version` (2026-09-21):

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
* Paths in replies must be clickable: markdown links relative to the repo, or absolute paths in plain text (Alex, 2026-08-15: a bare relative path errors when clicked).
* Alex does not run slash commands and will not be asked to (2026-08-15: *"I just forget to use them + I trust you more"*). Every ritual is the model's to run.
* Delegating to a cheaper model (Alex, 2026-09-10, from a thread he liked: "have Fable define the requirements, a lower AI implement, Fable check"): fine for fenced work that comes with a spec and a test (a migration plus its probe, a Playwright test, a web panel); never for simulator or browser verification, copy judgement, or anything that touches Tara's rules. Credits are not the constraint.
* A wait loop polls a process or a status, never a log line for a word (2026-09-10: one of mine spun seven hours waiting for a word that never appeared).
* **After a compaction, the summary is a claim, not a record.** The session-start hook replays Alex's last three prompts verbatim from the prompt log and the first lines of the last reply. Read them, then `git log --oneline -5`, section 0 of `docs/launch-checklist.md` and the newest changelog entry, before touching code. Where the summary and the repo disagree, the repo wins. (2026-09-23; a long session is compacted, never cleared, so this happens several times a day.)

---

## What this project is FOR (read this before optimising for speed)

**Timeline (Alex, 2026-09-22):** TestFlight fixes tonight; then Tara, Kat and Alex define what is CRITICAL for an MVP (`docs/mvp.md` is the draft to argue with); then a testing group; full launch hoped for the **launch party, moved by Tara to 2026-11-06** (2026-09-28, decision 0024: *"Party is changing to Nov 6"*; she would go earlier if the app is ready). Kat (product manager, ex big-tech PM) is on the team; John uploads TestFlight builds (decision 0014).

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
already cost a day (2026-08-13; Alex: *"I'm never doing clear again"*, so a
long session is compacted, never cleared). If it matters and it is not in the repo, it is gone. See
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
literal thing that works, add it to `docs/copy.md` under "Still open with Tara"
and as a numbered question in `docs/questions-for-tara.md`, and tell Alex it
needs her words.

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
| `docs/questions-for-tara.md` | Every question for Tara, numbered, with the default we would pick and the decision that answered it |
| `docs/whats-next.md` | The state of the app today. **No tasks**: those are in the launch checklist |
| `docs/launch-checklist.md` | **The one list of what is left** (Alex, 2026-09-27: *"one thing to totally trust"*): every row with an owner and a status word, a critical path to 2026-11-06 at the top, re-derived by command at least every 21 days, format enforced by `scripts/check-launch-checklist.sh` in CI. `docs/for-alex.md` is only the how-to for Alex's rows |
| `docs/copy.md` / `docs/copy-review.md` / `docs/copy-approved.txt` | Her words verbatim / ours awaiting Alex's tick / the CI snapshot |
| `docs/notifications.md` | Her notification drafts and what fires today |
| `docs/launch-runbook.md` | The pre-mortem (every way 2026-11-06 could go wrong, with its fix or owner), the dress rehearsal, and who does what on the day |
| `docs/prompt-log/` | Every prompt and reply, written by hooks |

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

Three of those questions are now machines (2026-09-13), and CI runs them:
`scripts/check-doc-paths.sh` (every path a doc names exists),
`scripts/check-doc-claims.sh` (counts, the decisions index, question statuses,
and the age of the last human audit: warning at 21 days, red at 45), and
`scripts/check-doc-inventory.sh` (every schema object, probe, job and Swift
file is named in `docs/architecture.md`). The rest is reading, and the brief
for it is `docs/audit-brief.md`: run it by hand with parallel read-only agents,
or let `docs-audit.yml` run it monthly once an API key is set. When the audit
is done, write today's date to `docs/.last-doc-audit`.

## Changelog

- **2026-10-04** — **Charlotte time everywhere, and Tara's details kept out of a public file.** A tester in Wisconsin saw every clinic an hour early; Tara: *"The times should not convert to where the phone is ... Charlotte time"*. Decision 0038: `ClubTime.apply()` first in the app's init sets the process's `TZ`, the system zone and `NSTimeZone.default` to America/New_York, plus SwiftUI's `\.timeZone`. Shown red first on a simulator launched with `TZ=America/Chicago` (3:59 PM for a 4:59 PM clinic) and green after (Home and Clinics 4:59 PM); `ClubTimeTests` red on three checks with `apply()` emptied; `Executed 234 tests, with 0 failures`. **The first fix did not work and the reason is the lesson:** `NSTimeZone.default` moves Calendar and DateFormatter but not `.formatted()`, which reads the system zone; the unit test could not see that, the screen could. Verify a display change on the display. **Privacy:** Alex pasted Stripe's activation summary, which carried Tara's date of birth, home address and phone; the prompt hook copied them into `docs/prompt-log/2026-10.md`. Nothing reached a commit (checked with `git log -S` for each), scrubbed by hand, and both logging hooks now redact an EIN, a date of birth after its label, a street address and a `+1 (xxx) xxx-xxxx` phone (a hook comment with an apostrophe broke the shell quoting once; `bash -n` caught it). Also: push on the simulator (the server's exact payload: banner in the background, Accept and Decline, Accept put Maria in and wrote Tara's #3; the icon badge shows the unread count; a banner with the app open did not appear, backlog); Steph's failed calendar subscription is not a bug (her feed answers 200 and subscribes on the simulator, empty or not; she was on flight Wi-Fi). Questions 105 (every cancel on the history line).
- **2026-10-01** — **The pre-launch audit: old iPhones, a 200-member rush, a test that proves it ran, and no dots.** Alex: *"we need to test EVERY edge case"*, *"ZERO margin for error on the first launch"*, and *"we should not have those little dots it looks super AI"*. **The SpringBoard crashes explained:** all four reports (2026-09-27/28) crashed inside `XCTAutomationSupport`, Apple's UI-test driver, on the nights several agents ran UI tests at once; none since. Mechanism: `scripts/run-ui-tests.sh` is now the one way to run the suite (a lock refuses a second run, a fresh database, the service key passed so nothing skips, any skip fails), and on a full green run it records a fingerprint of the app, tests, project, migrations and seed in `docs/ui-test-runs.log`; the `ui-test-record` CI job fails a PR whose code has no green record, because UI tests cannot run on GitHub and "I ran them" was only a claim. **Old iPhones:** iOS 18.6 and 17.5 simulators downloaded, an iPhone SE and a 13 mini created; the first SE run found what no iOS 26 run could: the notifications prompt cut its own sentence to "Clinic updates come through the app...." (fixed, seen whole on the SE), and three audit findings that the SE's pixels show are misreads (7.62:1 and 8.03:1), accepted by name with the numbers. **The rush:** `capacity_race.sh` at 200 lost 46 racers to the local 100-connection limit (every one that connected was right), which is not how phones reach the database, so `tests/sql/rush_via_api.sh` sends 200 signed-in requests through PostgREST at a clinic of 8: all 200 answered in at most 0.52 s, exactly 8 in, 192 pooled, red with the row lock removed (10 in). **Production every night:** `hosted-watch.yml` (health, the smoke test, the three public pages). **Crash reports** (decision 0035, branch `crash-reports`): MetricKit diagnostics to `app_diagnostics` through `report_app_diagnostic`, built by a delegated agent on its own stack, reviewed by the sql-auditor (no serious findings; eight probe gaps and a retention gap, all fixed and shown red), held for the privacy-policy sentence. **No dots** (decision 0034): every `·` a person reads became "at", a comma, a colon or parentheses, and `scripts/check-no-dots.sh` in the copy-gate job keeps them out (red on a planted line). Also: `docs/launch-runbook.md` (a 13-row pre-mortem, the dress rehearsal for the week of 2026-10-26, the day itself); Tara's round five refreshed (the new look, Foxcroft's share as a task); Alex's 274 unticked copy lines on one Keep-or-Change page that saves where the model can read it; the reset email proved on hosted from the app's own code (the server stamped it; his earlier attempt never reached it); the court photo confirmed as hers. **Two lessons.** A read-only reviewer ran the probe suite on the shared database during a UI run; the brief said read-only and it was not enforced, so so `tests/run-probes.sh` now refuses to touch the main database while a UI run holds the lock (shown refusing during the 2026-10-01 runs), and briefs for reviewers say "no database at all". And the first rush failure looked like a capacity bug until the per-racer output was read: every lost racer was refused a connection, not a seat. **Read the failure before believing it.** **Then the night (2026-10-01/02):** the iOS 17 runs found five more things no iOS 26 run could: the system's own title drawn navy on the navy banner (Profile, a clinic's page; `toolbar(removing:)` is iOS 18 only, so an empty principal item covers it now and the page name is ours at the leading edge on every version), Tara's Players search as a dark box in the navy bar (now the app's own white field), a clinic name clipped beside its chip at large sizes (`ViewThatFits`), a sign-up tap landing under the home bar (the scroll helper now brings a button fully on screen), and a waiver test that never scrolled. **The audit itself had hidden one:** it forgave all low contrast in a navigation bar, meant for iOS 26's glass buttons, so the navy-on-navy title passed; it now forgives buttons only. Kat's three calls landed (decision 0036: system tab bar, `Brand.courtText` #446A30 for text, the green line), and the reset line says it can take a few minutes. **Two flaws in today's own mechanism, both fixed:** the record fingerprinted code at the END of a run, so code edited mid-run was recorded as passing (now taken before the build, and a change refuses the record); and the fingerprint counted the build number, which would have cost three hours of runs per TestFlight build (now `project.yml` without its version lines; the three green runs re-keyed in `docs/ui-test-runs.log`, marked as such, after confirming the old hash of the same files). **The Mac slept twice mid-run** (lid closed on battery) and every failure that night was a timeout that read like a broken app; runs are now under `caffeinate`, and a run the Mac slept through says UNRELIABLE instead of RED. Green on the same code, one at a time, nothing else on the database: iOS 17.5 (iPhone 15), 18.6 (iPhone SE) and 26.2 (iPhone 17 Pro), each `232 unit, 22 UI`, 0 failed, 0 skipped; `TOTAL: 1240 checks across 43 probes` with `rush_via_api` ok; `45 passed` (browser). `ui-test-record` now requires all three iOS versions.
- **2026-09-29 (afternoon)** — **Kat's navy banner on every page, and Tara's logo over a smaller TENNIS.** Kat: *"dont forget the blue banner!"*; Tara: *"Can 'tennis' be smaller, logo bit larger"*; Alex: *"but also maybe everywhere?"* Decision 0033. Every titled page now sits under the same navy and green line as Home, the page name in white Playfair (`bannerTitle`, `navyTitle`, `navyBanner` in `BrandHeader.swift`), bar buttons white with no glass bubble (`onNavy()`), the clock white app-wide from the Info.plist; the gator leads in all three wordmarks. **iOS 26 took five tries, each seen on the simulator:** a UIKit navy appearance drew no title at all; "inline large" ignored the serif; `toolbarColorScheme(.dark)` made the back button's bubble pale blue under a white chevron (1.78:1, measured); a fixed navy tint vanished on the bubbles that turned dark; so the bubbles are off for text buttons and the clock is set once. **What the machines caught that the walk did not:** Apple's audit failed the first titles on every screen for not growing with Larger Text, and a moved button for a 43-point tap target; the extended `check-title-edge.sh` (now also banner and `onNavy`, shown red on My Clinics) found a bar button I had missed. One audit finding was wrong and is accepted with its number: Mark all read at 14.77:1 from the pixels of the frame it named. Local, fresh database each: `Executed 232 tests, with 0 failures` (unit), `Executed 22 tests, with 0 failures` (UI, the declined-card test run with the service key, none skipped). **CI then caught one more:** the new title modifiers hid five page titles from the copy scanner, so a title edit would have skipped review; `extract-copy.py` reads them now, shown red on a changed title. It passed here because I ran `extract-copy.py --check` instead of `scripts/check-copy.sh`, the script CI runs: **verify with the exact command the gate runs, never a sibling.** PR #83 merged on 27 of 27; build 7 (`v0.1.0-rc7`) carries it, because `v0.1.0-rc6` predates it and a tag is never moved.
- **2026-09-29** — **Build 6 landed, and the gator in colour.** Alex: *"i want everything to be green and checked 1000% before being finalizin"*, with Tara's coloured gator (her ask: *"I do ask the gator is changed in color first"*). Decision 0032: the artwork is committed once (`docs/brand/gator-2026-09-29.webp`) and `scripts/make-logo-assets.py` writes every copy (app icon with no alpha, the in-app cut-out, the web cut-out and a rounded tile for the light QR card), so the logo can no longer drift between places the way the grey icon and the grey login mark once did (2026-08-16). Seen on the simulator (header, app-switcher icon) and in the browser. Also this morning: the waiver as its own screen before anything else, its refusals naming the reason, Foxcroft's share as Tara's rate (question 101), QR opens counted (0031), and "Court 1" no longer printing as "Court ı". **Why the PR was red once:** the hosted smoke job ran before `supabase db push`, so all 30 findings were MISSING, none OPEN; rerun after the push, green. Before merging: `TOTAL: 1240 checks across 43 probes`, `Executed 232 tests, with 0 failures` (unit), all 22 UI tests (one needs the local service key and skips itself without it, so it was run alone with the key: `Executed 1 test, with 0 failures`), and 27 of 27 CI checks on the merged commit. PR #81 merged; `deploy-web.sh` matched byte for byte; `hosted-smoke.sh` 156 targets, 0 open; tag `v0.1.0-rc6` (build 6) for John. Two preview servers had been left running for 18 hours; stopped.
- **2026-09-28 (night)** — **Tara's round four, a demo page, and build 6: instant open, Siri, her laptop tools, and the bugs a walk-through finds.** Alex: *"can u gimme a demo of the fetures u build in most recent build + whats EVERYTHING else u can do to make it even MORE AMAZING ... anything more to make it good for tara too?"* and *"GRIND AWAY!!"*. **The demo** is a published page captured from the simulator (build 5, what is new, and an ideas list for players, for Tara and from her own someday wishes, quoted with who said them; the pros' first names kept out, and taken out of two docs that had them). The ideas are in `docs/roadmap.md`. **Round four** recorded in decision 0024 with her uninvite message on `cancel_invitation` (`20260928500001`, red first) and the QR code for members. **Making the demo was a test in itself**, and three bugs no suite had seen came out of it: a clinic held more than five weeks out was on no screen (the list's edge applied to her own spots), scrolled text ghosted through every title on iOS 26 (`crispTopEdge`, then `scripts/check-title-edge.sh` in CI so a new screen cannot bring it back), and the bell turned green with nothing unread (palette colours go to a symbol's layers in order). **New for players:** instant open (decision 0028: the last good answer per person on the phone, shown at once, refreshed behind, with no signal it stays on it with the connection line; with the API stopped Home was up in 1.5 s), "Hey Siri, when's my next clinic?" (also Spotlight and Shortcuts, run on the simulator), and the list's shape instead of a spinner. **For Tara**, built by a delegated agent on its own stack (decision 0027): her players' history beside every Pool name, Copy to next week as drafts on the same New York wall clock, and a court sheet to print; it found that a draft she cancels showed to every player as Canceled, fixed here (`20260929000001`, a `published_at` stamp, red under the old view). The laptop also lists every player by default and writes ratings as 3.0. **Mechanisms, each shown red:** `check-doc-claims.sh` reads a count split across two lines (it missed a stale "13 XCUITests"), the copy gate reads App Intents strings (it said "Copy unchanged" with seven new ones), and `web/.gitignore` ignores a `node_modules` symlink (one builder's link was a `git add -A` from being committed). **Lessons:** break one thing at a time (two mutations in one run hid each other; now in the probe section above), and a runtime `#available` is not a compile-time guard (CI's older Xcode failed on the iOS 26 symbol that built fine here; `#if compiler(>=6.2)`). **After the session limit** (all builders stopped at 21:00 and were resumed after the 22:30 reset), five branches merged into `build-6`, each through conflicts in the same shared docs: the pro role (decision 0025: a Today screen, Came / No-show and late cancels, nothing financial; the sql-auditor found seven issues, one critical once payments are on), declined cards that say why and hold no spot plus Tara's Resolved (0026), Subscribe in Calendar (0029, a per-account token and an edge function; renumbered at merge because two builders had both picked `20260928700001`, now `scripts/check-migration-versions.sh` in CI), saved messages (0030), and the laptop tools. **The auditor on the tools** found the canceled-draft fix incomplete: a player Tara had placed in a draft was told when it was canceled and found it in Past (`20260929000002`), and three probes could not fail on a named wrong implementation (a start-only skip key, `starts_at` for ended, an error-branch pass), each fixed and shown red. **CI caught what this Mac could not:** its older Xcode has no iOS 26 SDK, so `#available` is not enough (`#if compiler(>=6.2)`). **The title-edge check caught** the pro's Today screen within the hour it existed. Counts were hand-edited in five files after four merges, so `scripts/fix-doc-counts.py` now applies what the claims check derives. PR #80 merged and live (`supabase db push` 50 of 50 paired; website byte for byte; smoke 126 targets, 0 open). Questions 96 to 100 (the pros) and round five of her review page (73, 92 to 100). On `build-6`, fresh resets each: `TOTAL: 1219 checks across 42 probes`, `Calendar feed: all checks passed.`, `44 passed` (browser), `Executed 232 tests, with 0 failures` (unit).
- **2026-09-28** — **The polish round: four branches, one build, and three things only a walk could find.** Alex: *"do as MUCH as you possibly can w building and testing everything ... make the app as POLISHED as possibly and best feeatures"*, and the standing rule he asked to be remembered, *"WE WANT EXTRA FEATURES NOT JUST MVP"*. Three agents built from written briefs in parallel, each on its own Supabase stack or simulator, each reviewed by someone else (the sql-auditor on all three migrations, an adversarial reviewer on the iOS work), merged on `polish-0928`. **Tara's words:** her notification catalogue wired verbatim from the database functions that cause each event (#1, #3, #5, #6, #13 to #15; decision 0022), compared character for character by `notification_copy.sql`, with `place_player` taking two locks so a double tap sends one message (`place_player_race.sh`, red without either). **For players** (decision 0023): Accept and Decline right on an invitation's notification, Add to Calendar with nothing about where, Remind me at the player's own opening moment, haptics. **For Tara:** a Payouts card and chargebacks recorded from Stripe, a lost one subtracting what Stripe actually withdrew (decision 0021), and a crash already on `main` fixed on the way: Action Needed named a parameter `money` and hid the `money()` formatter, so the first declined card would have blanked This week. **Accessibility:** Apple's audit as a UI test on every main screen, text that follows Larger Text live (`.brandFont`; a `Font(UIFont)` never changed size after it was made), outlined tab icons and page titles in the guide's serif. **Found by walking the app as a new player, not by any test:** the clock was black on every navy header, because the root `.preferredColorScheme(.light)` pinned the status bar dark and nothing else could override it (light mode now locked in Info.plist; a UI test reads the clock's pixels, red at 98 and 79 against a bar of 600 with the old lock). **Found in the agents' reports:** no screen anywhere could take someone out of the Player Pool, so Tara's #6 could never be sent (Remove on the phone and the laptop now), and an invitation could still be accepted after she canceled the clinic, which the new lock-screen Accept made easier to hit (`20260928300001`, red first). **The sql-auditor on that fix** found the lock it rests on unpinned (deleting it left every probe green) and the same bug three more times: an Accept after the clinic had **ended** landed the player in a finished clinic and got them charged at Tara's next tap, and her own Invite and late-request Approve still worked on a canceled clinic. `20260928400001` refuses all three, `after_the_fact.sql` was red on exactly the six predicted rows, and `accept_cancel_race.sh` is red with no lock and with the weaker `FOR KEY SHARE`; where the Accept cut-off should sit (start or end) is question 91. **Review found a bug in the review, too:** the auditor's own red check once committed the old function to the shared database for 37 seconds; it noticed, restored and reported it. Two agents on one database is still the riskiest thing we do. **The lesson:** the audit is a measurement of a moving screen, and on one run in two it read 7.6:1 captions on a settling sheet as failures. A check that flakes teaches people to ignore it, so a finding now has to survive a second pass two seconds later; a deliberately too-light grey still fails 22 checks on six screens. Local, on the merged branch: `TOTAL: 866 checks across 35 probes` plus six race probes, `30 passed` (browser), `Executed 183 tests, with 0 failures` (unit), `Executed 18 tests, with 0 failures (0 unexpected)` (UI, all 18 on one fresh database). Questions 88 to 91 for Tara, on round four's page; build 5 is the tag `v0.1.0-rc5`.
- **2026-09-27 (night)** — **The MVP audit's seventeen fixes, built in parallel and checked by someone else.** Alex: *"WHAT ELSE ARE WE MISSING FOR THE APP TO BE MVP?? ... push update out in few hours"*. A workflow built five branches at once, each on its own local Supabase stack with offset ports and its own simulator (money integrity, Stripe robustness, the app when things go wrong, the web admin's bounded week, the push client), then a separate agent attacked each branch: four came back "fix first", with six majors none of the builders' own tests saw. **The Money tab would have told Tara to charge every clinic ever played the day payments went on**, including ones paid by Zelle (now only clinics that ended after `payments_enabled_at`, one definition shared by Money, Action Needed, Charge clinic and the web's week); **a retry after Stripe's 24-hour idempotency window could charge twice** (`first_attempted_at`, held rows Tara resolves with Went through / Did not go through, never SQL); **a sandbox charge would have blocked the real one after the key swap** (test rows stop counting at `stripe_live_since`); **a player could read their court number back from cancel and from accepting an invitation** (found by the checker, then its sibling by the sql-auditor: two leaks of hidden fact 17 through RPC return values, which `information_hiding.sql` never looked at). Two fix agents, then the sql-auditor again on the fix migrations. Decisions 0018 (money), 0019 (Stripe test and live), 0020 (no signal, stale screens, Larger Text, the bounded week), 0008 addendum (the push client). Questions 80 to 87 for Tara. On the simulator: a push banner while open, a tap opening the invited clinic with Accept and Decline, nothing after sign-out; the largest Larger Text size ran "Forgot password?" off the sign-in screen, fixed. Suite on the merged branch: `TOTAL: 785 checks across 32 probes`, browser `27 passed`, unit 120. **The lesson:** a builder's own tests share its blind spots; every major tonight was found by an agent told to break the branch, not by the one that wrote it (verification asymmetry, hard rule 12). Build number 4.
- **2026-09-27 (evening)** — **Tara's answers sat unread for five days, an MVP audit by six agents, and a password reset that needs no email.** Alex: *"is she not responding to the same questions over and over again?? like why tf are we giving her so many if she did this like last week"*, *"WHAT ELSE ARE WE MISSING FOR THE APP TO BE MVP??"*, *"for the password reset ... i want YOU to do as much as possible"*. **Her 09-22 answers** had saved to hosted as designed and nobody read them; round three was about to ask her the same things. Decision 0016 records them verbatim (three rewordings shipped as hers; "Rating Guide", "Only Tara can change this.", the charge summary as sentences and "Not charged yet" as ours, back in front of her), round four of the review page carries only the 15 new or changed strings and questions 69 to 79 (52 to 68 answered, merged, moved or withdrawn), and the mechanism: `review-watch.yml` opens a `tara-answers` issue whenever she saves (never her words: the repo is public) and the session-start hook lists open ones. PR #72; live on Vercel, verified from outside (`"version": "4"`, the Testing link at the foot, no Testing tab). **The MVP audit**: a workflow of six lens reviewers (member, admin, money, store, ops, messages), a skeptic per finding and a synthesis; 58 findings kept, none refuted, 17 to build now, 7 for Tara (75 to 79 plus the pros and guests already asked), 7 for Alex (A11, C3, C11, C13, D14, D15), 14 after launch (backlog). **Password reset** (decision 0017, PR #73): Tara's Reset link on the Players tab mints a one-time link with no email; the sql-auditor showed a link is a full member session, so admin accounts are never a target, the token rides in the URL fragment, the page keeps the session in memory and signs the account out everywhere on save, and every link handed out is audited. **Found on the way, invisible to every local test:** hosted answered `stripe-charge`'s browser preflight with 405 and no CORS header, so Charge clinic on the web admin would have queued fees that never reached Stripe (the local gateway answers preflights itself); `supabase/functions/_shared/cors.ts` fixes it and `hosted-smoke.sh` now sends the preflight, requiring a 2xx as well as the header, because hosted answers a function that does not exist with 404 and `allow-origin: *`. And the auditor was wrong once, checked rather than trusted: GoTrue v2.195.0 does end other sessions on a password change (refresh 200 before, 400 after). Hosted: `supabase db push` applied 20260927000001, 37 of 37 paired; `admin-reset-link` and `stripe-charge` deployed; smoke 63 targets, 0 open. `check-doc-claims.sh` now reads counts in table cells (a stale 31 sat in the checklist while the prose said 33).
- **2026-09-27 (later)** — **One list to trust, and the password reset that could never have worked.** Alex: *"is launch checklist complete source of truth? i like having one thing to totally trust"*, *"does forgot password work? do all features work?"*, the Stripe keys in, and the deadline (the LLC is still in Apple's queue). **Stripe:** `supabase secrets list` shows all three names; a forged webhook call now fails with `bad_signature`, so the signing secret is loaded; payments stay off until Alex's go after build 3 (checklist A9). **Forgot password does not work for members, and never has on hosted:** the management API shows no custom SMTP, and Supabase's built-in sender "will refuse to deliver messages to addresses that are not part of the project's team", 2 an hour; the Site URL is still `http://localhost:3000`. `docs/whats-next.md` and `docs/mvp.md` both said it worked: a claim restated instead of re-derived (hard rule 12), because nobody outside the Supabase team had ever asked for a reset. Now checklist D1 and D11 with click-by-click steps (Resend plus a domain). **The launch checklist is now the only list:** a critical path to 2026-10-16 at the top; 41 rows with an owner and a status word, re-derived by command today; whats-next became a state page with no tasks; `docs/for-alex.md` is only the how-to, every section naming its row; `scripts/check-launch-checklist.sh` in CI fails on a row with no owner or status, an undated DONE, a steps section pointing at a missing row, or a list not re-derived for 21 days (red-checked on a broken copy: all four fired). **Also found and fixed:** Apple transfers only apps with an App Store release, and a TestFlight upload ties the bundle id to that account, so `com.fxetennis.app` is John's and the LLC app needs a new id (C12; `docs/testflight.md` had said "keep the bundle id"); the style guide's darker-green contrast was 5.2:1 and is 5.51:1; Dependabot alerts were already on. `main` verified in a Release build (build 3, camera sentence, encryption flag, hosted backend); the nightly consent purge ran on hosted (0 rows).
- **2026-09-27** — **Tara's money asks shipped, and two checks that were passing while wrong.** #67: the board report (members and non-members who attended, visits and people, clinics, fees at clinic prices, collected by card net of refunds, 10% of each, CSV and print, "Run at" on all three), decline reasons on the Money tab beside the player's name, one live charge per registration and kind as a unique index (two simultaneous taps can no longer make two fees), and refunds made in Stripe's dashboard recorded once in the ledger. Built by a delegated agent on its own Supabase stack (offset ports, `project_id` FXE-Money, never touching the main one), audited by the sql-auditor (the probe accepted four wrong implementations and one check would have expired in two days; all fixed), then finished here after the agent stalled three times because the Mac slept. Suite 644 checks across 28 probes; Stripe harness 34; browser 15. Hosted: `supabase db push` applied 20260926000010, `supabase migration list --linked` 36 of 36 paired; `stripe-webhook` and `stripe-charge` deployed. **The admin deploy lied a fourth time, and this time the script believed it:** `deploy-web.sh` compared the navy colour and the tab count, neither of which this release changed, so it reported a match while the live page was the old one (51 KB live against 59 KB local). It now compares the md5 of every page and stylesheet with the working tree and confirms `.vercelignore` keeps the privacy draft out; the second deploy matched byte for byte, verified from outside (`Board report` in the live page; `privacy.html` and `tests/` 404). **The hosted smoke test had the same flaw in another place:** it counted 404 as closed and called every function with `{}`, and PostgREST's 404 for "wrong arguments" is byte-identical to "no such function", so a migration that never reached production would have passed. Functions are now called with their real argument names and a 404 is MISSING; a copy with a nonexistent function goes red. 58 targets, all 401/403. The lesson both share: **a check that cannot fail on the thing it guards is decoration; make the fingerprint change whenever the content does.**
- **2026-09-26** — **Kat and Tara's Final Updates: the front page, a card with permission, back-to-back 105s; two bugs a test could not see.** Alex relayed Kat (*"more color ... I just like the straight line across ... The screens just look really white"*), Tara's marked-up front page with her court photo, and a three-page "FXE Final Updates" list, all verbatim in decision 0015 with where each line is built. **#64, the screens:** header straight across with the guide's green line kept straight; smaller logo; Tara's photo behind every main screen under a porcelain wash (`CourtBackdrop`); Home rebuilt to their list (your clinics on top, what is open to you now while you hold fewer than two, else one blue button, nothing else; My Clinics moved to Profile); rating "?" beside the rating; card as `•••• 4242`; the Zelle line gone from every clinic page; a Stripe link on Manage. **#65, payments and rules:** the permission box in their words, recorded server-side (`card_consents`) and required by `stripe-setup-intent`, kept 90 days after deletion then purged by a nightly `retention` job; a card step after the waiver while cards are required; Tara's back-to-back 105 rule for non-members, her Sunday example as literal probe values. **Found by reading, not by any test:** (1) three places treated a Stripe *customer* as a card, and the customer exists from the moment someone opens the card sheet, so a player with no card could register and be "charged"; now `card_last4`, and `card_consent.sql` is red on the old code; (2) `stripe-charge` created PaymentIntents without naming the card, which Stripe does not default from `invoice_settings`, so the first real charge would have failed; stripe-mock accepts either, which is exactly why a mock is not a Stripe test. **The sql-auditor then found three more before the push:** a hard delete would cascade the consent away on day 0 (now RESTRICT), two simultaneous registrations could both pass the 105 check (per-player advisory lock, and `back_to_back_105_race.sh` red without it), and "48 hours" as elapsed time moved by an hour on daylight-saving weekends (now clock time). Suite 602 checks across 27 probes plus two race probes; Stripe harness 30; unit 31; XCUITests 12 of 13 in the full run and the 13th alone, after four tests were moved off Home (its content now depends on state) and the Mac was found to be sleeping mid-run (the app now holds it awake). Hosted: `supabase db push` applied 20260926000001, `supabase migration list --linked` 35 of 35 paired, `stripe-setup-intent` and `stripe-charge` deployed, hosted smoke 56 targets (the consent table and its four functions added), 0 open to a signed-out caller. Also: `docs/for-alex.md` (every step only Alex can do, kept current), `docs/stripe-e2e-test.md`, `docs/practice-ideas.md` (Jev: not now, and why), the prompt log fixed (153 harness notices had been logged as his prompts; uncommitted since 09-21), the privacy draft kept off deploys by `web/.vercelignore`, questions 58 to 66 for Tara. The board report and decline reasons are the next PR.
- **2026-09-23 (later)** — **Push delivery, everything but Apple's key; the privacy policy drafted.** Alex: *"what else can u do rn, testing, building mvp features?"* The sender half of decision 0008, built by a delegated agent from a written spec (`push-spec.md` in the session scratchpad, reproduced in the PR) and verified here. Migration 20260923000001: `delivered_at` and `delivery_error` on `notifications`, withheld from clients by replacing the table-level SELECT with the eight named columns (a table grant is a promise about columns that do not exist yet); `push_on_notification`, an AFTER INSERT trigger that posts the row id to the `push` edge function through pg_net, reading the function URL and a shared secret from Supabase Vault so no URL or secret is in the repo and nothing fires until Alex creates the two vault secrets. The edge function signs an ES256 provider token with WebCrypto, sends one request per device with Tara's body verbatim and the unread count as the badge, records the outcome on the row, prunes tokens Apple reports gone, and answers `apns_not_configured` until the five secrets exist. `tests/push/` is a mock APNs that verifies every provider token's signature against a key generated per run, 48 checks including the whole trigger-to-lock-screen path; `push_delivery.sql` 35 checks; suite 555 across 25. The sql-auditor found the real bug: the vault reads sat outside the exception guard, so a vault failure on hosted would have rolled back the invitation that caused the push; fixed, and the probe now makes the vault read fail on purpose. It also found pg_net's queue holds the secret header in plain text with PUBLIC read; the revoke is impossible from `postgres` (tried, "no privileges could be revoked"), so the control is that the API never exposes the `net` schema, pinned in `hosted-smoke.sh` (51 targets, 0 open) and in the push harness. Two client reads broke on the column grant and were fixed (`select=*` on the web, and the Swift SDK's default returning on mark-read updates, now `.minimal`). Hosted after the merge: `supabase db push` applied 20260923000001 and `supabase migration list --linked` shows 34 of 34 paired; `supabase functions deploy push --no-verify-jwt` is ACTIVE and a POST without the secret answers 401; `hosted-smoke.sh` 51 targets, 0 open. The CI job passed on its first run (PR #61). Not verified: real APNs. Also today: the privacy policy drafted from Volee's with eight listed deltas (`docs/legal/privacy-policy.md`, `web/privacy.html`, not deployed, `docs/copy-review.md` §G), so Apple's URL requirement is a read and a URL choice away.
- **2026-09-23** — **Compaction made less lossy, the header handed to Kat, the blocker list written down.** Alex: *"are we sure were not losing anything there?"* and *"anything to make sure its as least lossy as possible compacting?"* Honest answer: compaction is a model-written summary of a few hundred thousand tokens, so hard rule 12 applies to it. The mechanism: `session-start.sh` now reads the hook's `source` and, after a compaction or resume, prints Alex's last three prompts verbatim from the prompt log plus the first lines of the last reply, with the instruction to check the summary against them and the repo before touching code (exercised both ways: `compact` prints them, `startup` does not). The header: Alex rejected the deep arch (*"legit ugly"*) and then a rounded-corner version (*"even uglier"*), so `main` keeps the arch exactly as PR #56 merged it and the call is Kat's, recorded in `docs/whats-next.md` and `docs/style-guide.md`. His blocker list (Stripe test keys first, privacy policy URL, Apple enrollment, auth email delivery, the review page link, Kat's three style calls) is the "Blocked on Alex" section of `docs/whats-next.md`. In parallel, the push sender (decision 0008, everything but Apple's key) was delegated from a written spec and is reported in its own entry.
- **2026-09-22 (late)** — **The deploy that lies, made honest.** For the third time `vercel --prod` printed nothing and changed nothing on the first run and took on the second (2026-09-12, 09-21, today). Per the standing instruction, a mechanism: `scripts/deploy-web.sh` deploys, fetches the live `tokens.css` navy value and the tab count from the live `index.html`, and deploys once more if they do not match the working tree; it exits red if the live site still differs. The style-guide and TestFlight-feedback changes are live on the admin (fonts, tokens, the Testing tab, the Stripe link), verified by the script.
- **2026-09-22 (night)** — **Kat's style guide, applied.** Three pages: seven colour tokens (navy-900 #0A1B3D, gator-green #4F7A38, porcelain #F2F0EC and four more), seven type styles in Playfair Display and Inter, the header (navy arching into porcelain with one gator-green hairline), nav rows (28pt radius, alternating navy and white, icon, label, chevron), the tab bar, the greeting block, and spacing and radius defaults. Verbatim in `docs/style-guide.md` with the mapping onto the code. `Brand.swift` re-tokened; the two families bundled as variable fonts under the OFL and registered at first use, weights through the `wght` axis (a variable font's named weight is not a `UIFont(name:)`); `ArchedHeader`, `Wordmark` and `NavRowLabel` added, the two button labels now nav rows so every call site changed at once; the sign-in header and Home rebuilt (greeting in Playfair, "Let's Play." in italic green under it); web tokens and fonts mirrored. Three things learned on the simulator and recorded for Kat: the gator PNG already carries its F and E, so the flanking initials doubled them and were dropped; iOS 26's glass tab bar refuses a navy fill (the system bar with green active and navy inactive shipped instead); and the guide's green text sits just under the WCAG floor at 4.42:1, shipped as asked and flagged. Tara's cream gradient stays on top of the guide.
- **2026-09-22 (evening)** — **The first TestFlight round, and Kat.** Kat (product manager, ex big-tech PM) is on the team; she is writing a style guide that becomes the source of truth for style the day it lands, and asked for a Stripe dashboard link on the admin (v1: a link, later the API). John's internal TestFlight went out and the first feedback came back: a weak password read "Something went wrong" (the hosted rule is only "at least 6 characters", learned from GoTrue's own refusal text with a throwaway email that creates no user; the app now shows GoTrue's sentence and states the rule under the field at sign-up; a stricter rule is a dashboard setting and Alex's call), Profile values sat too far right (label above value, left-aligned now), Sign Out was a button (a text link now), and the review links moved off Players into a muted Testing tab. Tara's ask for "some kind of color variation" became `Brand.surfaceGradient`, cream to a warmer cream on every page, the way Volee does it, measured for contrast at the darker end. `docs/mvp.md` drafts the MVP-critical list for the Tara/Kat/Alex definition; the launch party target is 2026-10-16.
- **2026-09-22** — **Production asked the probe suite's question.** Alex: *"how to test it as close to 100% as you possibly can by yourself?"* The rules bound it: no fixtures in hosted, so no fake sign-up against production, and no credential of a real person is mine to type. What is mine: `scripts/hosted-smoke.sh`, 48 read-only requests with the publishable key against every base table, view, RPC and edge function on hosted, each of which must answer a signed-out caller with 401/403/404 (first run: 48 closed, 0 open), now the `hosted-smoke` CI job on every PR, because the class of bug it catches ("the migration pushed but the grant did not", 2026-08-13 and 2026-08-19) is invisible to the local suite. `supabase db diff --linked` was attempted and needs Docker, which was not running; it stays the second check whenever the stack is up. The signed-in half of production can only be walked by a real person on a real account: Alex on the simulator in Release configuration, or the first TestFlight tester. Also today: Alex's `age1` public key into `.github/backup-recipient.txt` (derived with `age-keygen -y` from the key file in his home folder; the private half never left it) and the first hand-dispatched encrypted backup (run 35691530447, 93 KB), downloaded, decrypted with his key and gunzipped into a real `pg_dump` with 47 tables, `auth.users` and `supabase_migrations`; the decrypted copy was deleted after the check. The backup is a fact now, not a job that has never produced an artifact anyone could open.
- **2026-09-21 (night)** — **TestFlight through John, and the runbook for it.** Kat asked for a TestFlight build for the Tuesday 7:30 call; the LLC enrollment is still in Apple's queue, so Alex chose an internal build from John's account (decision 0014). `docs/testflight.md` is the runbook: clone `main`, `brew install xcodegen`, generate, automatic signing on his team, archive Release (Debug points at localhost and would be an empty app), Distribute → TestFlight Internal, tag. `main` was confirmed identical to `origin/main`, so nothing a build needs is only on this Mac. No `DEVELOPMENT_TEAM` is committed; the LLC's team replaces John's later without a code change.
- **2026-09-21 (evening)** — **Hosted caught up.** PRs #48 and #49 merged on green. `supabase db push` applied the five 2026-09-21 migrations (`supabase migration list --linked`: 33 of 33 paired); `delete-account` and `review-submit` (`--no-verify-jwt`) deployed; the web admin redeployed to Vercel (the first `vercel --prod` printed nothing and changed nothing, again; the second took, verified by `curl`: `review.html` 200 and the `zelle_allowed` gate in `index.html`). Live probes: `review-submit` answers 400 to a malformed token and `delete-account` 401 without a JWT. Nothing charges anyone: the switch is still off. The September docs audit ran (four agents, parts A to D applied, `docs/.last-doc-audit` 2026-09-21).
- **2026-09-21 (later)** — **Past, the notifications-off line, the message probe, and the review page that saves.** Past under My Clinics: `my_past_clinics` (20260921000004), a player's own finished clinics with only their own outcome, own rows and none of the nine hidden facts, probe `past_clinics` (8); seen on the simulator with two hand-inserted rows ("Played · $18", "No-show"). `NotificationsOffLine` on Home while iOS reports the permission denied (decision 13 and 0008 item 3, open since August). `clinic_messaging.sql` (14) finally pins decision 0005: the whole list each player sees is asserted in brackets, because the harness's substring rule let a longer list pass, and it went red on three checks under a leaky view. The probe runner's dirty-database window shrank from 60 to 5 seconds after the browser suite's rows slipped inside it and produced two false failures with no warning. The review page's second version (built by a delegated agent from a spec, then rebased and verified here: 505 checks green, 14 browser tests): `web/review.html` on the admin site saves Tara's answers to `review_responses` through the `review-submit` edge function as she types, links are minted on the Players tab (`admin_create_review_link`), responses read back there (`admin_review_responses`), probe `review_responses` (26). Suite after all of it: 513 checks across 24 probes. Learned about sharing one local database with an agent: its reset wiped my migrations mid-run and my reset wiped its objects; next time one stack per branch, or one runner at a time with an explicit hand-off.
- **2026-09-21** — **Tara's first full review, applied: no courtesy, 3 hours, card only, the waiver, deletion that keeps history.** Alex pasted her page back (decision 0013, every line hers): *"NOT DOING THIS ANYMORE"* on the courtesy, *"3 hours instead of 4"*, *"Everyone using the app has to input a credit card"*, *"Keep their history"* on deletion, *"Both"* for where the level note shows, Saturday and short weeks *"Yes"*, her tap charges (*"app does nothing automatically w payments"*), and fourteen strings reworded. Three migrations: 20260921000001 (`courtesy_cancel_days` 0 with `courtesy_available()` false at zero so the switch is reversible without a migration, `cancel_cutoff_hours` 3, `zelle_allowed` false plus `zelle_allowed()`, `leave_pool` archives instead of deleting, `revoke update (is_member)`), 20260921000002 (`waivers` with her September 2026 text verbatim, `waiver_acceptances`, `current_waiver` / `my_waiver_accepted` / `accept_waiver` with the email taken from the account and a full legal name required, `register_for_clinic` raising `waiver_required` for non-admins, `search_players` returning `level_note` and `waiver_accepted`), 20260921000003 (`accounts.deleted_at`, `delete_my_account()` scrubbing name, phone, email, card summary, note, devices and notifications, giving back future spots and keeping played clinics, ledger and Tara's notes; `is_admin()` false once deleted; the `delete-account` edge function then soft-deletes the sign-in through Supabase's admin API, never SQL against the auth schema). Probes: `waiver` (23) and `account_deletion` (18) new; `cancellation_policy` proves the courtesy is a switch by setting 90 inside the transaction; `late_cancellation` at 3 hours plus `leave_pool` keeps the row; `player_directory` attacks the membership column and was shown red with the grant restored. The deletion probe caught a real bug red-first: the first draft canceled every "in" row including played clinics, which would have erased the history she said to keep. Phone: `WaiverView` (her checkbox sentence, typed legal name, Agree and sign) gating the app after sign-up and whenever the RPC refuses, Delete my account on Profile behind a spelled-out confirmation, the cancel sheet down to her one sentence at 3 hours with the note always offered, Paid and Remind unpaid rendered only while `zelle_allowed`, the level note and waiver state on the directory row and page. Web: the same gate, cutoff default 3, note and waiver on the Players tab. Copy: her fourteen strings applied verbatim, snapshot regenerated (161 strings), chrome listed for Alex. Verified: probes 443/21 green before the two new checks, the sign-up walked by hand on the simulator to the waiver sheet, XCUITests and the browser suite as recorded in the PR. Open for her: questions 52 to 57 (the "Set by Tara" caption, the blank replacement for "Tara has your message.", "this week" under My Clinics, "Let's Play." vs "Let's play!", whether her policy block is rewritten, and whether "Stripe needs to be connected" was a note to us). Also today: the review page lost her answers once (she had to redo it), so a second version that saves to our database as she types is being built on the admin site.
- **2026-09-18** — **A page Tara can answer on her phone, and three small calls.** Alex: *"how can we give the copy review file to tara so SHE can basically approve every word? ... super simple, just context for where each blurb is, then the blurb, then what she wants to do w it"*, paired with every open question in one place, and something for her to test. `scripts/build-tara-review.py` writes `docs/tara-review/index.html`: three tabs, Words (120 strings across sign-in, Home, Clinics, Profile, Notifications, her Manage tab and the web admin, each with where it shows in plain language, Keep or Change and a box for her wording, her own sentences tagged "Your words"), Questions (43 to 51: 48 account deletion, 49 Saturday clinics, 50 short weeks, 51 the mockup splash line, in plainer words than the doc), Try it (nine web-admin tasks with her real account, which double as entering her real templates and week; the phone app stated as not available until Apple approves the LLC account). Answers live in her browser's storage, roll up into one text under "Copy my answers", and she texts that to Alex; a claude.ai artifact cannot write anything back from an outside-link visitor, and she has no account, so nothing fancier was possible without a server. Verified in the built-in browser at phone width in both themes: a Change with a replacement and a typed answer survive a reload and appear in the summary; the clipboard is blocked in that sandbox, so the fallback selects the text and says so. Published privately; Alex shares it. Three decisions recorded: no CI Supabase project (launch checklist §F option 3, "no more money for now": UI tests run on a laptop before each TestFlight build); the 11 unencrypted backup artifacts deleted from the public repo (`gh api -X DELETE`, count verified 0), so until the `age1...` line is in `.github/backup-recipient.txt` there is no backup at all; Stripe keys stay parked until Alex asks. Also noted for the extractor: the courtesy and fee sentences on the cancel sheet and every notification body are invisible to `extract-copy.py` (ternaries and SQL), so the page's list is curated by hand from its report, and the doc says so.
- **2026-09-16** — **Tara's cancellation policy, verbatim, and the day her SSN nearly went into a public repo.** Tara answered the short list (decision 0012, her words in it): no more emergency note; *"Each player receives one courtesy late cancellation every 90 days, no questions asked"*; no-shows full fee; *"I want to charge everyone's card everytime they come to clinic"*, after the clinic, so *"there won't be a refund ever"*; a card required to register (*"Gosh I say yes"*); her policy text and two sentences, which ship as written and are marked for her edit; rating and phone required at sign-up; a note at level entry that only she reads. Built in 20260916000001: `courtesy_used`, `no_show`, `players.level_note`, `courtesy_available()` on a rolling 90 days, `admin_set_no_show`, `admin_charge_clinic` (one tap after a clinic ends; one pending row per attendee, no-show and non-courtesy late cancel; skips and counts rows without a card; idempotent), `register_for_clinic` raising `card_required` once payments are on, `create_my_account` taking the note. `cancel_registration` keeps its signature and stops refusing a late cancel without a note. 28-check probe `cancellation_policy`, `late_cancellation` rewritten for the courtesy. Web: Came/No-show on every You're In! row, Courtesy or Fee applies on late rows, Charge clinic on the card once it has ended, the per-row charge buttons gone. Phone: the same toggle and tap, the courtesy or fee sentence on the cancel sheet, her card sentence on Profile, the note field at sign-up and Edit details. Questions 43 to 47 for the parts her message left open, the biggest being whether the charge is her tap (built) or an end-time timer. **Her message also carried her SSN, home address and bank details, and the prompt-log hook copied it into a tracked file in a public repo.** Scrubbed before commit; both hooks now redact id-shaped and bank-shaped numbers, the secret-scan job fails on an SSN-shaped string anywhere in the tree, and those details live in Stripe's own form and nowhere else. Also: Dependabot for the browser-test tooling and the Actions.
- **2026-09-13** — **Docs that check themselves, and the CI project that could not be created.** Alex: *"can it do an audit of the other docs too so everything's up to date? I want the most ROBUST SWE setup you've ever seen."* The audit's questions split into two kinds. The mechanical kind is now three scripts in CI: paths exist (yesterday), `check-doc-claims.sh` (every count in the current-state docs equals the derived number; every decision indexed; every Tara question carries a status; the human audit at most 45 days old), and `check-doc-inventory.sh` (every table, view, enum, client RPC, probe, edge function, CI job and Swift file named in `docs/architecture.md`, run after the probe suite because it needs the database). The judgement kind has a written brief (`docs/audit-brief.md`) and an opt-in monthly workflow that runs it through Claude Code read-only and opens an issue; off until Alex sets an API key. **Corrected a claim of mine from yesterday:** the Supabase free tier is two active projects per *user*, not per org; `supabase projects create fxe-ci` was refused because Volee and `fxe-tennis` fill Alex's two. The two GitHub secrets set in that attempt were deleted the same minute. Everything else for UI tests in CI is built and waiting: the Debug app takes `FXE_SUPABASE_URL` / `FXE_SUPABASE_ANON_KEY` from its launch environment (Release ignores them), the UI tests forward them from `TEST_RUNNER_` variables, and the `ios-ui-tests` job resets the CI project with `supabase db reset --db-url` (proved against the local database) and runs the suite with one retry; it stays green with a notice until the three settings exist. The options and prices are in `docs/launch-checklist.md` §F for Alex to pick. **Then a knowledge audit** (Alex: *"are you SURE you're truly remembering everything you possibly can?"*): one agent read both prompt logs end to end against CLAUDE.md, `docs/` and the memory files and found 25 things said once and written nowhere: no `/clear` ever, no slash commands from Alex, no em-dashes in chat, the delegation rule, the wait-loop lesson, John's Apple login not to be used, Apple's document list, Tara's verbatim "super admin" ask, hosted email confirmation switched off by hand (now decision 0011), the invented seed clinic names, the SpringBoard crash, the 2026-08-19 grants lesson (TRUNCATE ignores RLS; a CLI upgrade took away an inherited grant) which the changelog had skipped, Alex's 95%-by-late-September target, and Kat's 18 due-diligence questions, which now have `docs/kat-due-diligence.md` mapping each to where its answer lives or does not. Each landed in its home file or a memory, and the memory index grew from three entries to seven.
- **2026-09-12** — **The docs audit, and a backup that anyone could read.** Alex: *"do a complete audit of every doc and make sure nothing's slipping/slowly drifting."* Four read-only agents in parallel, each with a disjoint file set and orders to re-derive every claim by command; three editing agents applied about 150 drifts across 20 files. The pattern in the drift: counts copied forward (probe files, tests, migrations), status markers never moved after the work landed (roadmap, whats-next, backlog, feature review), decisions superseded without a note (0003 by 0009, decision 15 by 22, three tabs by the Manage tab), and Volee's `sql-auditor` agent unchanged since 2026-08-08, still auditing age brackets and reading a folder that does not exist (rewritten for FXE). Also found by the audit, not by any test: **the nightly backup artifacts were downloadable by any signed-in GitHub user** (public repo) and carry `auth.users`, so Tara's email and bcrypt hash were one click from anyone; `backup.yml` now encrypts with `age` to a public key in `.github/backup-recipient.txt` and refuses to upload without one, so the job fails until Alex adds his key. `app_settings` turned out to have no client write path at all (SELECT only, no RPC), so the "no migration for a typo" story in this file was untrue until today's correction. Hard rules 13 and 14 now sit under Hard rules rather than Working style, where a reader stopped at twelve. Mechanism, per the standing instruction: `scripts/check-doc-paths.sh` fails when any backtick-quoted repo path in a doc does not exist (19 such references found), and runs as the **Doc paths exist** CI job. Also today: the first restore drill (a backup nobody has restored is a hypothesis) found the dump omitted `supabase_migrations`, fixed; the four Tara docs moved into `docs/` from a folder beside the repo that Alex has since deleted; `docs/launch-checklist.md` is the single list between today and a real member, with owners.
- **2026-09-12** — **The Money tab reads the ledger, and the probe runner knows a dirty database.** `payments_ledger` (20260912000003): an admin-only view that names the player and the clinic on every card payment, because `registrations` is unreadable to `authenticated` on purpose and PostgREST cannot embed through it. Same shape as `revenue_by_clinic`: owner-run, `is_admin()` inside, select only, 8-check probe (Maria sees nothing through it, anon has no grant, a four-table join is not updatable). The web Money tab lists it newest first, or says "No card payments yet." while `payments_enabled` is false; Zelle stays the Paid checkbox. `run-probes.sh` now prints DIRTY DATABASE when any row was created after the seed, because three false failures on 2026-09-12 came from rows the browser tests left behind and looked exactly like regressions. Suite: 365 checks, 17 probes; 11 browser tests.
- **2026-09-12** — **The 4-hour honor system, Tara's tap on the web, and the whole Stripe pipeline proven against a mock.** Tara, via Alex: *"honor system for canceling ... the threshold will be 4 hours ... after that you have to say it's an emergency to cancel."* Decision 0010 (partial; her exact words in it, plus the club-wide vision and the white-label dream, logged verbatim). 20260912000005: `cancel_cutoff_hours` becomes 4, `registrations.late_cancel` + `cancel_note`, and `cancel_registration(p_registration, p_note)` refuses a You're In! late cancel without a note (old signature dropped so the call cannot be ambiguous); pool drop-outs and Tara's removals are never late; the note rides in her notification. 18-check probe. Web: `payments_enabled` read on every load; Charge fee / Charge late cancel / Refund buttons exist only while it is true, the late note shows always; `stripe-charge` is invoked right after the RPC. iOS: `CancelPolicy` (5 unit tests) and a note sheet inside the cutoff; the sentence above the box is Tara's (Q40) and does not exist yet. **`tests/stripe/run.sh`**: SetupIntent, signed and unsigned webhooks, charge → processing → succeeded → paid, refund → unpaid, decline → failed with reason, switch off → nothing, 27 checks against stripe-mock, and a CI job that runs it on every PR. On this Mac Docker Hub pulls hung for an hour, so locally the mock is the Homebrew binary reached as `host.docker.internal`; CI uses the image on the Supabase network. GitHub's push protection refused the first push because the mock env carried Stripe's public example key; now `make-env.sh` invents one per run and nothing key-shaped is in the repo. Nothing charges anyone: the switch is still off.
- **2026-09-12** — **A date on every note, a version on Profile.** `admin_player_note_edited` (20260912000004) returns the note's `updated_at` or null; the web admin shows "Edited <date>." under the note and refreshes it on save, because a note without a date reads the same whether it is from March or yesterday. Three probe checks (matches the row, null without a note, gone after a blank save). Profile ends with "Version 0.1.0 (1)" from the bundle, the first thing to ask for when a TestFlight build looks wrong. Local lesson: after `supabase db reset` the auth container kept stale connections and answered 504 for ten-second stretches, which made browser sign-in flake; `docker restart supabase_auth_FXE-Tennis` fixed it. Also: the browser suite is not idempotent (it cancels Sunday Social), so a second full run on the same database fails three tests. Reset between runs; the runner's DIRTY warning is the tell. And the iOS 26 simulator's tab bar dropped the first tap on Profile in two of three UI runs (a hand-driven session needed two taps as well), so both UI test files open Profile through `openProfileTab()`, which taps once more after five quiet seconds. Not seen on a device; in the backlog to check on Tara's phone.
- **2026-09-12** — **The Stripe edge functions, and the trusted role that could not read a table.** Three Deno functions: `stripe-setup-intent` (customer + SetupIntent for PaymentSheet), `stripe-webhook` (the only writer of card summaries and ledger outcomes, Stripe-signature auth, JWT verification off for it alone), `stripe-charge` (every pending ledger row becomes one off-session PaymentIntent or Refund, idempotency key per row, claim-then-call so a crash never double-charges). The Stripe client is built lazily so an unconfigured deploy answers `stripe_not_configured` instead of dying at load. First real call found that **`service_role` held no DML on any table**: the August PUBLIC revokes had taken it, and nothing noticed for a month because no server-side code existed. 20260912000002 grants it explicitly with default privileges for future tables, and `grants_are_explicit.sql` now asserts it on every table (red first). Hosted needs that push before any edge function can work.
- **2026-09-12** — **The card screen.** "Payment method" on Profile: the summary the webhook recorded ("Visa ···4242") or Add a card, which asks `stripe-setup-intent` for a SetupIntent and opens Stripe's PaymentSheet; the app never sees a number. Verified on the simulator up to the missing key: the tap reaches the function and comes back "Cards aren't set up yet." The consent sentence at card entry is Tara's (Q37) and does not exist until she writes it; only chrome shows. Stripe iOS SDK added (PaymentSheet product only).

- **2026-09-12** — **Payments: the foundation, with the switch off.** Tara: *"I just wanna charge them"* (seven late cancellations, an hour before a clinic). Decision 0009: Stripe direct with a card on file, Apple takes nothing (real-world service), every money event a row. Built today without a Stripe account: `stripe_customer_id` and a card *summary* on accounts (written only by the webhook, so a player cannot forge one), the `payments` ledger with owner/admin RLS and no client writes, `admin_charge_registration` (amount defaults to the price snapshot; a double tap is one fee) and `admin_refund_payment` (whole, once), and a trigger so a succeeded fee marks the registration paid and a succeeded refund unmarks it. Policy is `app_settings`, defaults matching the eleven questions sent to Tara, and `payments_enabled` is false: per hard rule 14 nothing charges anyone until she has answered. 21-check probe, red first, including "nothing charges while disabled" and "a player cannot write the ledger".

- **2026-09-10** — **Copy extractor: an interpolation is not a sentence.** `“\(m)”` had sat in the approved snapshot since 09-01 as if it were words; the noise filter now drops strings that are nothing but an interpolation. Backlog row closed.

- **2026-09-10** — **Web admin hides canceled clinics.** They stayed in the week forever wearing their chip (review 09-02). Now hidden by default with a one-line count and a Show canceled toggle; nothing is deleted (hard rule 4). The cancel browser test ticks the toggle to find the chip.

- **2026-09-10** — **Templates can be archived, and come back.** `archived_at` had existed since 08-28 with nothing writing it; the only retirement was a delete (hard rule 4 says archive). `admin_set_template_archived` stamps once and restores; `templates_admin` now carries the column and no longer hides archived rows, so the web admin's new Templates card offers Archive, Show archived and Restore, and the picker lists only live ones. Probe `template_archive.sql`, 10 checks, red first. Browser suite: 10.

- **2026-09-10** — **Remove from clinic has a UI test.** Fifth admin flow: Maria registers, Tara removes her from the row menu behind the confirmation, the roster reads "Nobody is in yet." and the row is gone from the screen (and kept as canceled in the database, hard rule 4). 13 XCUITests.

- **2026-09-10** — **Phone polish from the review.** Roster rows use `ViewThatFits`: one line when the name and its controls fit, two when they do not (long names, small phones). Home's open-clinics button carries the count once more than three are open, so three rows never read as the whole list. The roster's More menu is the word rather than an ellipsis, for the same reason Players became a word this morning: a `Label` in a toolbar ignores its label style on iOS 26.

- **2026-09-10** — **Docs-freshness pass (nine days overdue by the hook's own count) and the first review fixes.** Backlog: four rows had been fixed for a week without moving (hosted reset URL, the unmerged-main row, the date bounds, anon EXECUTE); moved with dates. Counts corrected to 14 probes / 324 checks. From `docs/feature-review-2026-09-02.md`, the four "fix now" items on the phone: a notification row now opens the clinic it is about (marks read first; a clinic that has since ended stays a note), the Players toolbar button is the word rather than an icon that ignored its label style, a canceled clinic no longer wears a green count chip, and Tara can remove a player from a clinic from the same per-row menu as the court, behind a confirmation, using the same RPC the player's own Cancel uses. Also observed: the nightly backup ran green every night of the week it was unattended, except the one night GitHub Actions was billing-blocked.

- **2026-09-10** — **Web admin: three tabs.** Money had been the last thing on a page that grows with every clinic, and Tara's first question on a Monday is money (review 09-02). This week · Players · Money across the top, one page, the last tab remembered per browser. The browser suite gained a Money test and now clicks the Players tab before searching; 9 tests.

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

- **2026-09-02** — **Tara's side of the phone has UI tests.** Every XCUITest until today was a player. `AdminFlowUITests` adds four flows: Maria registers for the members-only clinic and Tara gives her a court, sends the unpaid reminder and marks her paid; Maria lands in Tuesday's Player Pool (its public window is open, decision 0001), Tara invites, You're In! stays empty, and only Maria's own Accept moves her (hard rule 2, asserted from the screen); the directory note round-trips; cancel clinic needs the confirmation and leaves the chip. Three things the tests taught: the first attempt targeted the wrong clinic and found Maria in the Pool instead of You're In!, which is the rule working; Accept and Decline share the primary-action identifier on the invitation screen; and a trailing sign-out from a screen with an active search field is not reachable, so tests no longer sign out at the end (each launch starts signed out anyway).

- **2026-09-02** — **My Clinics is a screen, and the list has an edge.** "View All Clinics" under My Clinics on Home opened the browse list, which is every clinic, not mine; it now opens a My Clinics screen: the clinics I hold a live registration in, grouped by week, each wearing its status chip, with the empty state handing off to the open list. The browse list gained the other edge it was missing: the view drops finished clinics (08-28), and the client now stops five weeks out, so a season Tara publishes in bulk is not one endless scroll. Eighth XCUITest: the link opens a screen titled My Clinics and renders none of the browse list's cards.

- **2026-09-02** — **Push notifications: everything but the key.** Decision 0008 written: APNs from an edge function on a `notifications` webhook, so every RPC that writes a row gets a push for free and no client holds a sending credential. Built today: `register_device` / `unregister_device` (account is `auth.uid()`, table stays client-unreadable, 11-check probe red first, including "Rob registering Maria's token string gets his own row and cannot unregister hers"); the permission sheet with Tara's Screen-3 sentence, shown once after the profile exists and suppressed in UI-test mode; the `aps-environment` entitlement via XcodeGen; registration on every signed-in launch; unregister on sign out so a shared phone never shows the next person someone else's invitation. Verified on the simulator up to Apple's push daemon adding the app's topic; it held no sandbox token, so the token callback and the RPC call were not observed end to end there. The sender, the webhook and the audit columns wait on the Apple Developer account for the signing key.

- **2026-09-02** — **The web admin has automated tests for the first time.** Until today it was verified by hand in a browser after every change and by nothing else. Eight Playwright tests now walk Tara's side against a fresh seed: sign-in and the non-admin door (Maria signs in fine and is told this is not hers), prices on every card, a walk-up straight into You're In!, a court assigned and cleared, the unpaid reminder, a private note that round-trips through a reload, and cancel clinic's two clicks. They run in a new CI job that starts the same pinned stack the probes use. Two lessons on the way: Playwright 1.49 hangs silently on Node 25 (1.62 is fine), and the copy gate walked `web/node_modules` and tried to approve twenty thousand strings, so the extractor now prunes dependencies and test tooling.

- **2026-09-02** — **The bell finally opens something.** Every RPC had been writing `notifications` rows since July and the bell on Home was a picture. Now it is a button with an unread badge, and it opens a notification center: newest first, unread in bold, tap a row to mark it read, Mark all read as the broom. Read state is `read_at` in the database, not on the device, so the badge agrees across reinstalls and later across the web admin. The rows' words are already Tara's because the RPC that caused each one wrote it. Seeded two rows for Maria so a fresh reset has something to show, and a sixth XCUITest walks bell → rows → Mark all read → badge gone, asserting on the bell's own accessibility label so it is the database that clears it, not the view.

- **2026-09-02** — **A player can fix their own name, phone and rating.** Profile was read-only since the day it was built. "Edit details" opens the same fields and rating pills as the sign-up profile screen, and saves with two narrow UPDATEs on exactly the columns `authenticated` holds column-level UPDATE for (20260802000003). Membership is shown with "Set by Tara" and is not editable: it decides pricing and the head-start window, so after sign-up it is hers to correct (for-tara.md q5, hard rule 2). Seventh XCUITest changes the phone to a per-run value and reads it back off Profile after the session reloads.

- **2026-09-02** — **Cancel clinic, the last RPC with no caller.** `cancel_clinic` flips the status, stamps `canceled_at`, and notifies everyone in You're In!, the Player Pool and Response Needed; it has done so since July with no button anywhere. Web: a two-click button on the clinic card (the second click reads "Really cancel? Everyone is told." and disarms after five seconds), chosen over a native `confirm()` because that is unstyleable and blocks browser tests. iOS: a More menu on the admin roster with a confirmation dialog that spells out the consequence, then pops back to a reloaded list. The already-canceled error is mapped to words. Archive, never delete (hard rule 4): the row and its registrations remain, and the card shows a Canceled chip.


- **2026-08-19** — **The grant that was taken away, and TRUNCATE.** (Entry written 2026-09-13 from the migration header and the prompt log; the changelog had jumped from 08-16 to 09-01.) Upgrading the Supabase CLI from 2.90 to 2.115 removed the inherited blanket SELECT that `anon`/`authenticated` had never been granted explicitly, so the app broke for every user; `20260817000001_explicit_read_grants.sql` writes every read the client depends on. The same pass found `authenticated` could `truncate players`: RLS never applies to TRUNCATE, only a revoked privilege stops it. Both now in hard rule 11. Also that week: Alex decided the App Store account is the LLC from the start, no personal-account TestFlight shortcut ("we're not in a big rush, I can do it as an org from the start"), and that John's Volee login, which Alex holds, is not to be used for FXE (an Individual account shows John as the seller).

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
