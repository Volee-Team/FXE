# Developer Practices for John

A portable pack of the SWE and AI-workflow practices this team now uses, so you
can apply them to Volee. Every practice below is one we actually run, in this
repo or in the sibling FXE Tennis repo. Where a practice exists in FXE but not
yet in Volee, it is marked **Adopt on Volee** with a concrete first step. Nothing
here is aspirational: every file path and command is real.

Two repos, one developer, shared patterns:

* **Volee** (`/Users/alex/Documents/GITHUB/Volee`) is live on the App Store.
* **FXE Tennis** (`/Users/alex/Documents/GITHUB/FXE-Tennis`) is a separate app,
  separate Supabase project, separate bundle id. Backend is further along;
  the iOS client is not started. It is where several of these practices were
  hardened, because a backend with no UI is where SQL discipline gets tested.

The one sentence under all of it: **chat is not memory, and a clean build is not
proof.** If a rule or a decision is not written into the repo, it is gone at the
end of the session. If a change was not exercised against an artifact, it is not
done.

---

## Orientation: where Volee stands on each practice

| # | Practice | Volee today | What to do |
|---|---|---|---|
| 1 | CLAUDE.md as enforceable memory | Strong CLAUDE.md, hooks and commands present | Understand the enforcement ladder; push load-bearing rules up it |
| 2 | Slash commands for rituals | 6 commands live | Keep; add commands for the decision/roadmap rituals |
| 3 | Hooks that hard-block | session-start + destructive-SQL guard + guard self-test | Strongest of the two repos. Keep it, do not weaken it |
| 4 | Probe methodology | probes + README with a mutation-test step | Add "from the rule", "assert the outcome", and attack probes |
| 5 | The two lessons that cost real bugs | Guard exists; no attack probe; no hardened runner | Add an attack probe and a hardened runner |
| 6 | Decision records + roadmap + backlog | Lives inline in CLAUDE.md only | Adopt `docs/decisions/`, `docs/roadmap.md`, `docs/backlog.md` |
| 7 | CI on every push against a throwaway DB | CI builds + runs XCTest + guard test; **no SQL probes in CI** | Add a SQL-probe job on a freshly reset DB |
| 8 | Adversarial review by a fresh context | sql-auditor subagent + CI review job present | Use the subagent proactively; set the API key so the CI job runs |

---

## 1. CLAUDE.md as enforceable memory

`CLAUDE.md` auto-loads into every session. It is the team's shared brain: rules,
conventions, hard-won lessons, and a per-session changelog. Both repos keep one.
Volee's is large and good.

The insight worth internalizing is that **a rule in CLAUDE.md is only the bottom
rung of an enforcement ladder.** A written rule depends on the agent reading it
and choosing to obey it, and that choice degrades under context pressure late in
a long session. The stronger a rule's consequences, the higher up the ladder it
belongs.

**The ladder, weakest to strongest:**

1. **Advisory (CLAUDE.md prose).** "Be careful with destructive SQL." Depends on
   compliance. This is the right home for judgment calls and conventions, but it
   is the wrong home for anything catastrophic. The proof is in Volee's own
   history: an advisory "be careful" did not stop the 2026-06-19 cleanup that
   deleted the App Review demo account. The guard hook's header says it plainly:
   *"CLAUDE.md already said 'be careful'; advisory rules drift under context
   pressure. This is the mechanical version."*
2. **Ritual (slash command or skill).** Codifies *how* a repeated task is done so
   it runs the same way every time (see section 2). Still needs a human to
   invoke it, but removes ambiguity about the steps.
3. **Mechanical (hook).** The harness runs it whether or not the model
   cooperates. SessionStart injects context; PreToolUse can block a tool call
   outright (see section 3). Reserve this for the rules whose violation is
   expensive and irreversible.

Two supporting habits that keep CLAUDE.md trustworthy, both from FXE and both
worth copying verbatim into how you work:

* **"Where things are written down."** FXE's CLAUDE.md carries a short table
  routing every kind of knowledge to its home: rules to CLAUDE.md, new asks to
  the roadmap, decisions to `docs/decisions/`, noticed-and-skipped items to the
  backlog, one diary entry per session to the changelog. The habit: *writing it
  down is part of doing it, not paperwork afterwards.*
* **"Audit this file periodically."** Stale rules are worse than missing ones,
  because they still get obeyed. At the start of a long session, check that the
  Build and Run commands still work, that the probe count in CLAUDE.md matches
  what the suite prints, and that no "decision" has been silently superseded by a
  later one.

**Volee today:** CLAUDE.md is strong and already spans all three rungs (prose
rules, `.claude/commands/`, `.claude/hooks/`). What is missing is the *routing
discipline* around it. Decisions, roadmap items, and known bugs all live inline
in CLAUDE.md, which is why that file is now very long and why "is this still
true?" is hard to answer per item. Sections 6 splits those out.

**Adopt on Volee:** add a short "Where things are written down" table to
`CLAUDE.md` once `docs/decisions/`, `docs/roadmap.md`, and `docs/backlog.md`
exist, so the next session knows where a new fact belongs before it writes it
into the wrong place.

---

## 2. Slash commands for repeated rituals

A slash command (a file in `.claude/commands/`, or the equivalent skill) turns a
multi-step ritual into one invocation that runs the same way every time. It
removes the "how did we do this last time" tax and stops steps from being
skipped under pressure.

**Volee already has six, and they are good:**

| Command | File | What it does |
|---|---|---|
| `/probes` | `.claude/commands/probes.md` | Run every `tests/sql/` probe against the live DB, report one red/green table, fix nothing |
| `/verify` | `.claude/commands/verify.md` | Build, install, launch, screenshot, visually verify a feature |
| `/screens` | `.claude/commands/screens.md` | Capture a screenshot of every screen into `docs/screens/<version>/` |
| `/ship-check` | `.claude/commands/ship-check.md` | Pre-App-Store-submission runbook: every gate that has bitten us before |
| `/bug` | `.claude/commands/bug.md` | Work a tester bug report: reproduce first, then fix |
| `/handoff` | `.claude/commands/handoff.md` | Write this session's changelog entry into CLAUDE.md |

These same names are also exposed as skills, so `/bug`, `/handoff`, `/probes`,
`/screens`, `/ship-check`, and `/verify` all work.

The design rule these follow, worth keeping: **a command reports or executes a
ritual; it does not make judgment calls.** `/probes` explicitly ends with "Do
not fix anything in this command. Report only." Reporting and fixing are separate
deliberate acts, and fusing them is how a "quick probe run" quietly rewrites data.

**FXE runs the same pattern** with a smaller set (`.claude/commands/probes.md`),
and its `/probes` starts the local stack first if it is down. That is the tell of
a good ritual: it handles its own precondition instead of failing on it.

**Adopt on Volee:** once the decision/roadmap/backlog system lands (section 6),
add a `/decision` command that scaffolds the next numbered file in
`docs/decisions/` from a template (what we decided, why, what we rejected, how we
would know we were wrong). The ritual is what makes the discipline survive a busy
week; an un-ritualized "remember to write a decision record" will not.

---

## 3. Hooks that hard-block

Hooks are the top rung: shell scripts the harness runs at defined moments,
independent of whether the model decides to cooperate. Wiring is in
`.claude/settings.json` under `hooks`.

**Volee has the strongest hook setup of the two repos.** All three are real:

| Hook | File | Type | What it does |
|---|---|---|---|
| Session start | `.claude/hooks/session-start.sh` | `SessionStart` | Prints branch, dirty-tree, and recent commits into context. Warns if you are on `main`. Warns not to touch someone else's in-flight files |
| Destructive-SQL guard | `.claude/hooks/guard-destructive-sql.sh` | `PreToolUse` | **Blocks** catastrophic SQL before it reaches the live DB |
| Guard self-test | `.claude/hooks/test-guard.sh` | run in CI | Proves the guard blocks the bad shapes and allows every real probe |

**The destructive-SQL guard is the concept to understand and protect.** FXE does
not have it; Volee invented it, and it is the cleanest example in either repo of
moving a rule from advisory to mechanical. Its design is deliberate and it is
worth reading in full (`.claude/hooks/guard-destructive-sql.sh`), because the
subtlety is what makes it usable rather than annoying:

* It fires only on `mcp__supabase__execute_sql` and `mcp__supabase__apply_migration`.
* It blocks exactly three catastrophic *shapes*, not all DML:
  1. any `DELETE FROM auth.users` (and admin user-deletion helpers),
  2. `DROP TABLE / SCHEMA / DATABASE` or `TRUNCATE` (scratch tables named with a
     leading underscore are exempt),
  3. `DELETE` or `UPDATE` with **no WHERE clause** on a protected core table
     (`profiles`, `family_groups`, `family_members`, `challenges`, `matches`,
     `subscriptions`, `player_locations`, `friendships`, `promo_code_submissions`).
* It has an explicit, auditable escape hatch: put the literal token
  `CONFIRMED-DESTRUCTIVE` in a SQL comment and the guard steps aside. Intent
  becomes explicit instead of accidental.
* Exit 2 blocks and returns the reason to the model; exit 0 allows.

The reason it must block *shapes* and not *all writes* is the same tension every
guard faces: several `tests/sql/` probes legitimately INSERT/UPDATE/DELETE their
own scratch rows. A guard with false positives gets disabled, which is worse than
no guard. That is why `test-guard.sh` exists and runs in CI: it asserts both
directions at once, that every real probe is allowed **and** every catastrophic
shape is blocked. A guard without its own regression test rots silently.

**Keep on Volee, do not weaken:** if a probe ever trips the guard, fix the probe
(scope its DELETE, name its temp table with a leading underscore) rather than
loosening the guard. If you edit the guard, run `bash .claude/hooks/test-guard.sh`
before committing; CI runs it too, but you want the answer in seconds.

**Adopt on Volee:** the guard's protected-table list is a manual list. When you
add a new core table, add it to `PROTECTED` in the guard and add a matching
`expect 2` line to `test-guard.sh`. Treat that as part of "creating the table",
not a follow-up.

---

## 4. The probe methodology

A probe is a small regression test for one invariant. Volee keeps them in
`tests/sql/` (fifteen today) with a `README.md` describing the convention:
one file per bug or behavior, boolean output columns named `*_ok` (must be true)
or `*_rejects` (must be false), a bug story in the header comment. FXE keeps the
same idea and adds a runner and a stricter methodology. Four rules make a probe
worth trusting.

### 4a. Write the probe from the RULE, never from the code

This is the load-bearing one, and it cost FXE a real bug. The original
registration-window test was written by reading the function it tested, so it
asserted the implementation's misunderstanding back at itself and was green for
the entire life of the bug. FXE's CLAUDE.md states the lesson exactly: *"Two
copies of one mistake agreeing with each other is not evidence."*

The fix was to rewrite the probe from the authoritative rule statement, with
every expected value transcribed by hand from the stated rule and checked against
a calendar, not computed by any code. See
`FXE-Tennis/tests/sql/registration_window_rule.sql`: its header carries the rule
verbatim, and each expected date is a literal (`'2026-09-03 Thu 08:00'`) worked
out by hand.

**On Volee this matters most for anything with a spec you can quote:** the
tennis scoring table, the Glicko-2 update, the yellow-ball age buckets, the
family price schedule. Assert the value the *rule* says, not the value the
function happens to return.

### 4b. PROVE the probe can fail before you trust it

A probe that has never gone red has not been tested; it has only been written.
Before trusting a new probe, reinstate the broken behavior (or inline the old
formula), run the probe, confirm it goes red on exactly the rows you predicted,
then restore. FXE mutation-tested the window probe this way and recorded that it
goes red on 17 of its checks against the old implementation.

**Volee already has this habit written down.** `tests/sql/README.md` step 3 says
"Run it pre-fix to confirm one column is wrong." That is exactly the discipline.
Keep doing it, and make it non-optional: a probe committed without a recorded
red-first result is a probe nobody has tested.

### 4c. Assert the OUTCOME, not the error

The most dangerous failure is the silent one. An `UPDATE` blocked by RLS affects
zero rows and raises **no exception**, so a probe that only wraps the statement in
`exception when others then ... 'PASS'` reports a pass whether the row changed or
not. The correct assertion reads the resulting state back: did the role actually
stay `member`, is the row count still 1. FXE's `privilege_escalation.sql` does
this after every attack, and its comments call it out: *"an UPDATE that silently
affects zero rows also succeeds, so checking the outcome is stronger than
checking for an exception."*

### 4d. Make the probe self-contained and transactional

FXE probes wrap the whole check in `begin; ... rollback;`, seed their own
fixtures inside that transaction, and assert against them. That is what lets the
entire suite run against an **empty throwaway database** and leave no trace. Most
Volee probes instead SELECT against whatever happens to be in the live DB (for
example `age_bracket_integrity.sql` counts real rows in live `profiles`). That is
fine for a manual `/probes` run against live, but it is the single thing standing
between Volee and running its probes in CI (section 7). A probe that needs
production data cannot run on a fresh CI database.

**Adopt on Volee:** when you write the next probe, seed its own fixtures inside
`begin; ... rollback;` so it is deterministic on an empty DB. Backfill the
existing probes toward that shape opportunistically, starting with the
safety-critical ones.

---

## 5. The two lessons that cost real bugs

These two are worth their own section because each one changed how the team
tests, and each was invisible to a green test suite until the moment it wasn't.

### Lesson 1: the privilege-escalation hole, found by an attack probe

On 2026-08-02 an adversarial review of FXE found that any ordinary player could
run one statement:

```sql
update accounts set role = 'admin' where id = <self>;
```

and become an administrator: read every roster, capacity, court assignment and
payment status in the club, **demote Tara**, and reassign other players to their
own account. The cause was mundane: the lockdown migration revoked grants on
every hidden table except `accounts` and `players`, and both update policies had
a `USING` clause but no `WITH CHECK`.

The part that matters for how you test: **the safety probe was green the whole
time.** `information_hiding.sql` asserted the player was *not* an admin and then
tested what a non-admin can read. It never attempted the transition. FXE's
CLAUDE.md hard rule 9 states the general form: *"A probe that only tests the
state you expect cannot find a transition you did not think of. Where a privilege
boundary exists, write a probe that tries to cross it."*

The response was a new *kind* of probe. `FXE-Tennis/tests/sql/privilege_escalation.sql`
does not assert a comfortable state; it **attacks**. Eight escalation attempts
(self-promote, promote a confederate, demote the admin, steal a player, insert a
new admin account, delete the admin, and more), each asserting the resulting
state, plus one check that legitimate self-service still works so the hole cannot
be "fixed" by breaking the product. It was verified to go red on 7 checks against
the unfixed schema before the three-layer fix (column-level grants, `WITH CHECK`
on the policy, and a trigger backstop) was applied.

**This is the most direct thing to adopt on Volee, because Volee has the exact
same shape of boundary.** The hard safety rule (18+ and U18 users never see each
other on any discovery, ladder, social, or messaging surface) is Volee's
equivalent of information hiding. And Volee's current safety probe,
`tests/sql/age_bracket_integrity.sql`, is a *state* assertion: it counts rows
where a minor sits on an adult ladder or an adult on a junior ladder. That is the
FXE information-hiding probe, not the FXE attack probe. It will catch existing bad
data; it will not catch a new RPC, view, or policy that *lets* a minor reach an
adult across a boundary.

**Adopt on Volee:** write `tests/sql/cross_bracket_attack.sql` on the FXE
`privilege_escalation.sql` model. Authenticate as a U18 account and *attempt* to
reach an adult through every surface the sql-auditor already enumerates (nearby
players, suggested friends, search, open-challenge feed, challenge eligibility,
message reachability, profile preview from a username), asserting the *outcome*
(zero rows, or a raised authorization error) after each attempt. Then prove it
can fail (4b) by temporarily loosening one filter. This is the probe that turns
the app's most important safety rule from advisory into mechanical.

### Lesson 2: the harness that reported passes falsely

Three separate times, FXE's probe **harness** reported green while a probe was
actually broken: twice in the runner (`run-probes.sh`), once in the probe files'
own pass condition. Each is a lesson about trusting your test harness no more than
your code:

1. **Substring false-pass (2026-08-02).** Unlike the other two, this defect lived
   in the probe files, not the runner. The pass condition shared by all four SQL
   probes was `actual LIKE '%' || expected || '%'`. Under it, an actual count of
   **105 passed against an expected 0**, because the string "105" contains "0".
   Fix, applied in all four probe files (`information_hiding.sql`,
   `schema_decisions.sql`, `registration_window_rule.sql`,
   `registration_windows.sql`): substring matching applies only when the expected
   value contains a letter (its one legitimate use, matching a server error
   message that wraps an expected error name), and it uses `strpos` rather than
   `LIKE` so that `_` in an error name is not treated as a wildcard. FXE's
   CLAUDE.md adds the standing order: *"Do not loosen it back. If a new check
   needs fuzzy matching, normalise the actual value instead of widening the
   comparison."*
2. **Errors read as passes (2026-08-10).** The runner matched errors with the
   pattern `^ERROR`, but psql writes them as `psql:<stdin>:138: ERROR:`. Anchoring
   to start-of-line let every SQL error through as a pass. **Five probes were
   aborting and the suite reported them green.** Fix: match `ERROR:` anywhere.
3. **Zero-assertion pass (2026-08-10).** A probe that ran no assertions at all was
   counted as passing. Silence is not evidence. Fix: zero checks is now red.

You can read the latter two fixes, with their reasons, in
`FXE-Tennis/tests/run-probes.sh` (the `ERROR:`-anywhere match and the
zero-assertion check); the substring fix lives in the four SQL probe files named
above. The common thread: **a test result you did not
try to disprove is not a result.** The same skepticism you apply to code (4b)
applies to the thing that grades the code.

**Volee's convention partially sidesteps these** by using explicit boolean
columns (`*_ok`, `*_rejects`) rather than substring-matching a formatted string,
which is a genuinely good design. But Volee has **no aggregating runner at all**:
`/probes` runs each file by hand and eyeballs the result. That is the gap section
7 closes, and when you write that runner, port FXE's three hardenings into it
from the start: treat any SQL error as a failure, treat zero assertions as a
failure, and never pass a numeric check by substring.

---

## 6. Decision records, roadmap, and backlog as durable memory

This is the largest structural gap on Volee, and the cheapest to close. FXE keeps
three files that together answer the three questions a new teammate (or the next
session) always asks: *what are we building, why is it like this, and what do we
already know is broken.*

| File | What belongs there | Volee equivalent today |
|---|---|---|
| `docs/roadmap.md` | What is in v1 / v1.1 / v2, what is parked, what we are deliberately **not** doing. New asks land here first, never straight into code | A "Roadmap / known open items" list inside CLAUDE.md |
| `docs/decisions/NNNN-*.md` | One file per decision that would otherwise be re-litigated | Scattered inline in CLAUDE.md, tagged "(Tara <date>)" |
| `docs/backlog.md` | Bugs and chores. Anything noticed and not fixed goes here in the same breath | A "Known Bugs (likely stale)" list inside CLAUDE.md |

The reason to split these out of CLAUDE.md is not tidiness. It is that each has a
different lifecycle. A decision is immutable history; the roadmap changes weekly;
the backlog churns daily. Keeping them in one file makes "is this still true?"
unanswerable per item, which is exactly the "likely stale" disclaimer already
sitting on Volee's Known Bugs list.

**The decision-record format** (from `FXE-Tennis/docs/decisions/README.md`) is
four headings: *what we decided, why, what we rejected, and how we would tell if
it was wrong.* Two rules make them trustworthy:

* **Never edit a decision.** If it changes, write a new numbered file that
  supersedes it and add a forward pointer at the top of the old one. The history
  of what you believed is part of the record.
* **Every decision names what pins it.** FXE decision 0002 (snapshot the price
  onto the registration) ends with the exact probe checks that enforce it. A
  decision with no probe is a decision waiting to be re-broken.

Volee has *excellent raw material* for this already, buried in CLAUDE.md prose,
each of which is a decision record that has never been written as one:

* Glicko-2 replacing the old +1/+3 ladder math (Tara 2026-05-13).
* StoreKit 2 IAP, deliberately **not** Apple Family Sharing IAP, with the reason
  the team rejected the shareable model.
* The paywall hard gate (`PaywallGate.shouldAdvance`) and the two bypasses it
  closed.
* Add-Kid and Remove-Kid deferred to v1.1 because pricing locks at subscription
  time.

**Adopt on Volee:**

1. Create `docs/decisions/README.md` with the index table and the four-heading
   format, copied from FXE.
2. Write `0001-glicko2-rating.md` and `0002-storekit-not-family-sharing.md` from
   the CLAUDE.md prose that already exists. You are transcribing, not deciding.
   Each ends with the probe or test that pins it (`glicko2_glickman_worked_example.sql`,
   `report_match_result_buckets.sql`; the paywall by `PaywallGateTests`).
3. Create `docs/roadmap.md` from the "Roadmap / known open items" section of
   CLAUDE.md (junior aging-out, doubles ladders, family plan-change pipeline, the
   individual-cancel revenue leak), and a "Deliberately not doing" section so the
   rejected ideas stop coming back.
4. Create `docs/backlog.md` from the "Known Bugs" list, with a priority marker on
   each, and adopt the habit: *anything noticed and not fixed goes into the
   backlog in the same breath,* or it is forgotten.

Then thin CLAUDE.md down to rules and conventions, and add the "Where things are
written down" table (section 1) so the split stays clean.

---

## 7. CI on every push against a throwaway database

CI is where a change that breaks a rule someone relies on fails in front of *you*
instead of in front of a user. Both repos run CI on every push and PR; they cover
different halves, and each should learn from the other.

**Volee CI** (`.github/workflows/ci.yml`) runs three jobs:

* `test`: build the app and run the `VoleeTests` XCTest target on an iPhone 17
  Pro simulator.
* `hooks`: run `bash .claude/hooks/test-guard.sh`, so the destructive-SQL guard
  can never silently rot.
* `review`: a read-only Claude review of the PR (see section 8).

What Volee CI does **not** do is run the SQL probes. They only ever run manually,
via `/probes`, against the live database.

**FXE CI** (`FXE-Tennis/.github/workflows/probes.yml`) does the opposite and is
the model to copy for the SQL half:

* `sql-probes`: install the Supabase CLI, `supabase start` a local stack,
  `supabase db reset` to apply every migration and seed onto a **fresh, empty
  Postgres**, then `bash tests/run-probes.sh` for the full suite (it prints its own count; 285 checks as of 2026-09-01) plus the
  concurrency probe. The database is disposable and is thrown away when the runner
  ends.
* `migration-immutability`: on pull requests, fail if any *already-committed*
  migration file was modified rather than superseded. A migration that may
  already be applied to the hosted database must never be edited in place.

The throwaway-DB principle is a hard rule in FXE's CLAUDE.md and it is the right
one for Volee too: *"The hosted database is not seeded and must not be."* Probes
verify against a database you can destroy: locally via `supabase db reset`, in CI
on a fresh runner. You never point an attack probe (section 5) or a
capacity-overfill probe at production.

**Adopt on Volee, in order:**

1. **Make the safety-critical probes self-contained** (section 4d) so they run on
   an empty DB. Start with `age_bracket_integrity.sql` and the new
   `cross_bracket_attack.sql`; seed fixtures inside `begin; ... rollback;`.
2. **Write `tests/run-probes.sh`** modeled on FXE's, with its three hardenings
   baked in from line one: any `ERROR:` is a failure, zero assertions is a
   failure, and numeric checks never pass by substring.
3. **Add a `sql-probes` job** to `.github/workflows/ci.yml` that does
   `supabase start` (or spins up Postgres and applies `supabase/migrations/`),
   then runs the runner. Volee's migrations already live in `supabase/migrations/`,
   so the schema can be reconstructed on a runner.
4. **Add the migration-immutability job.** Volee applies migrations directly and
   keeps canonical copies in `supabase/migrations/`; editing one that is already
   applied to the live project is exactly the mistake this job catches.

The end state: a PR that weakens a cross-bracket filter, breaks the Glicko math,
or edits a shipped migration fails CI, not App Review.

---

## 8. Subagents and adversarial review by a fresh context

The privilege-escalation hole (section 5) was found by adversarial review, **not
by the tests**. That is the whole argument for this practice: the author of a
change, and the tests the author wrote, share the author's blind spots. A fresh
context with an adversarial brief and no stake in the change being correct finds
what a state-assertion test cannot.

**Volee has two mechanisms for this. FXE already has the first (a copy of the
subagent was ported over), so only the second, the CI review job, is still
Volee-only:**

* **The `sql-auditor` subagent** (`.claude/agents/sql-auditor.md`). It runs on
  Opus with read-only tools, reads CLAUDE.md and the live schema, and reviews new
  or changed SQL ranked by severity, with a **concrete failure scenario** required
  for every finding. Its priority order is Volee's actual risk order:
  cross-bracket isolation first, then RLS coverage, then privilege escalation
  through `SECURITY DEFINER` RPCs, then races and idempotency, then the
  correctness traps this codebase has hit before. Its description says to use it
  *proactively whenever a migration or RPC is written or edited.* **FXE already
  has this**: an identical copy sits at
  `FXE-Tennis/.claude/agents/sql-auditor.md` (its body still reads "You audit SQL
  for the Volee codebase"), so the subagent is not a gap to close on FXE; the CI
  review job below is.
* **The CI `review` job.** On every PR it runs a read-only Claude review against
  CLAUDE.md, prioritized identically (cross-bracket isolation, then RLS and
  authorization holes, then races, then removal of functionality, then missing
  tests). It comments; it never pushes.

The subagent's report format is the standard to hold every review to: *"This
might be unsafe" is not a finding; "user A in the U18 bracket calls this RPC with
user B's id and receives B's coordinates" is.* A review that cannot state the
concrete sequence of events has not found anything. And the corollary, also in
the agent: a short clean report is a good outcome, so do not invent findings to
look useful.

**Two honest gaps to close on Volee:**

1. **The CI review job is inert until a secret is set.** It is guarded by
   `if: env.ANTHROPIC_API_KEY != ''` and is skipped when the key is absent. Set
   `ANTHROPIC_API_KEY` in the repo secrets so the job actually runs, or accept
   that this layer is currently decorative.
2. **The subagent is only as used as you make it.** "Use proactively" is
   advisory (rung 1, section 1). Make it a ritual: before any migration touching
   RLS, a `SECURITY DEFINER` function, or a discovery/social surface, run the
   `sql-auditor` in a fresh context and paste its findings into the PR. The one
   time it was skipped is the release that shipped the escalation hole.

**Adopt on Volee:** treat a fresh-context adversarial pass as a required gate for
the same three change types the guard and CI already care about (RLS, RPC
authorization, cross-bracket surfaces). The subagent is written; the discipline
of always invoking it is the part you add.

---

## If you do only three things

1. **Write the cross-bracket attack probe** (section 5) and prove it can fail.
   It turns Volee's most important safety rule from advisory into mechanical, and
   it is the direct lesson of the one bug that most nearly went to production
   silently.
2. **Split decisions, roadmap, and backlog out of CLAUDE.md** (section 6). It is
   pure transcription of material that already exists, and it makes every other
   practice easier to keep current.
3. **Put the SQL probes in CI against a throwaway DB** (section 7), with a runner
   that treats errors, silence, and substring-passes as failures. A probe that
   only runs when someone remembers to run it is a probe that stops running.

Everything else here is either already in Volee and worth protecting (the
destructive-SQL guard, the slash commands, the sql-auditor) or a refinement of
habits Volee already has written down (probe methodology, the CLAUDE.md
changelog).
