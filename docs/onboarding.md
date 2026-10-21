# Onboarding: a new person or a new Claude on FXE

Written 2026-10-21 for John's Claude, and for anyone after it. Read this
once, then work from the files it points at. It says where things are and
how work is done here; it never says what is done or left (that lives in
the four status files, below), so it does not go stale.

## 1. What you get from the repo, automatically

| Thing | How it reaches you |
|---|---|
| `CLAUDE.md`: the rules, the hard-won lessons, who is who, the changelog | Loaded into every Claude Code session in this folder |
| Team memory: how to work with Alex and Tara, one lesson per file | `.claude/team-memory/`, its index printed by the session-start hook |
| Working state at session start: branch, uncommitted files, recent commits, overdue audits, unread Tara answers | `.claude/hooks/session-start.sh` |
| Guardrails: no merge with a red check, no push that fails the doc checks, no database reset during a UI run | `.claude/hooks/gate.sh`, plus GitHub's 15 required checks on `main` |
| Every doc, decision, question and probe | `git pull` before starting, every time |

## 2. Read first, in this order

1. `CLAUDE.md`, all of it, especially the hard rules and "Which source wins".
2. `docs/launch-checklist.md`: the State today block and section 0. This is
   the one list of what is left.
3. `docs/architecture.md`: the system as built.
4. `docs/decisions/README.md`, then the newest three decisions.
5. `docs/questions-for-tara.md`: what is open with Tara, with our defaults.
6. `docs/live-facts.md`, then run `bash scripts/live-status.sh`.

**Status lives in four files only**: the launch checklist (work), the
backlog (bugs), the questions for Tara (questions), the decisions README
(decisions). Any other doc that says "done" or "pending" is a bug.

## 3. Setting up a Mac (once)

```bash
brew install xcodegen supabase/tap/supabase node gh
```

```bash
brew install stripe/stripe-mock/stripe-mock
```

Docker Desktop must be running for the local stack. Then, in the repo:

```bash
supabase start && supabase db reset
```

```bash
cd web && npm ci && npx playwright install chromium
```

```bash
gh auth login
```

```bash
supabase login
```

- **Simulators for the UI tests:** iOS 26.2 (iPhone 17 Pro), 18.6 (iPhone SE
  3rd generation) and 17.5 (iPhone 15). `scripts/run-ui-tests.sh` makes its
  own "FXE UI" copies and records green runs in `docs/ui-test-runs.log`;
  CI refuses a PR whose app code has no green record on all three.
- **Hosted access:** `scripts/live-status.sh` reads hosted through the
  Supabase CLI's login, so it works only if Alex has invited you to the FXE
  organization on supabase.com. Pushing migrations also needs the database
  password in `.env.local` (repo root, gitignored), shared by Alex through
  LastPass, never in chat.
- **The website** deploys with `scripts/deploy-web.sh` through Vercel on
  Alex's account; without access to that project, ask Alex to deploy.

## 4. How work is done here

- **Branch, PR, green, merge.** Never commit to `main`. The model merges its
  own PR once every check is green.
- **Hosted is written only by `supabase db push`** and `supabase functions
  deploy`. Never a hand-written statement, never any other tool that can
  write production (CLAUDE.md, "Hosted is written by supabase db push").
  No test data in hosted, ever.
- **Tests:** `bash tests/run-probes.sh` for SQL; `bash
  scripts/run-ui-tests.sh` three times (the three iOS versions) for app
  changes; `cd web && npx playwright test` for the website. A new rule gets a
  test written from Tara's words, shown failing first, one break at a time.
- **Words a player sees** are Tara's or approved by Alex
  (`docs/copy-review.md`); the copy gate in CI fails on anything new.
- **Any claim comes with the command that proved it**, in the same message.
  Before saying what is done or left, run `scripts/live-status.sh`.
- **Tara's answers** go into a dated decision record, verbatim, the same
  turn they arrive.

## 5. Two Claudes on one repo

- **Pull before starting, push before stopping.** Work that only exists on
  one laptop does not exist for the other.
- **Claim work with a draft PR** before starting, so the two never build the
  same thing.
- **Only one person pushes migrations or deploys at a time**, and migration
  file names must be newer than `main`'s newest
  (`scripts/check-migration-versions.sh` enforces it).
- **Team memory edits go through a PR** like any other file, so both
  Claudes see the same lesson.

## 6. What the repo cannot tell you

| Not in the repo | Where it is, and who to ask |
|---|---|
| The chat history with Alex | His laptop only (`docs/prompt-log/`, gitignored: it holds private details). Anything that mattered was written into a doc, a decision or the changelog; if it is not there, ask Alex |
| Tara's texts | Alex's phone. An answer that has not been pasted into a session is not known; ask Alex |
| Secrets: the database password, Stripe keys, the APNs `.p8`, the App Review login | Supabase secrets, LastPass, John's Apple account. Never in the repo or in chat, and never typed by a Claude |
| Stripe's dashboard (Tara's account) | Alex has access; facts read from it go into `docs/live-facts.md` with a date |
| Apple: Developer account, App Store Connect, APNs keys | John's account (decision 0042) until the transfer to the LLC |
| Supabase and Vercel dashboards | Alex's accounts |
| What is true on hosted right now | `bash scripts/live-status.sh`; never a doc's memory of it |
| Work on another laptop that is not pushed | Ask before starting anything that may overlap |

## 7. Who owns what

| Person | Owns |
|---|---|
| Tara | Every decision about how her program runs, and every word a player reads |
| Alex | Engineering calls, relaying Tara, Stripe and Supabase access |
| John | The Apple account, uploads to App Store Connect, the APNs key |
| Kat | Product questions and the style guide (`docs/style-guide.md`) |
| Claude | Building, testing, and keeping the docs true |
