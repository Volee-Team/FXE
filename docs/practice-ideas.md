# Tools and practices worth adopting, and the ones not worth it yet

Living file. Alex, 2026-09-26: *"can we use jev?? + other ideas to be
catching up w all the new tools/workflows/be best SWE as possible??"* Each
entry says what it is, what it would do here, and a recommendation. The ones
adopted move to "Adopted" with the date.

## Jev (TypeSafe's "System One" decision model)

**What it is.** A small, fast model that only makes bounded decisions (yes/no,
which of these, is this safe) instead of writing text. Its makers report
about $0.0004 and 0.4 seconds per decision, against cents and ten seconds for
a frontier model. The usual uses are guardrails ("is this tool call
destructive?"), routing ("easy or hard?"), and rule checks ("does this diff
break a rule in AGENTS.md?").

**Where it could fit here.** Two places:
1. The copy gate: classify each new string as chrome or voice (hard rule 13)
   so the CI message says which kind it is.
2. A PR check: "does this diff touch one of CLAUDE.md's hard rules?"

**Recommendation: not now.** Every rule this repo enforces today is enforced by
a deterministic check (probes, grants enumeration, the copy snapshot, doc
claims). A model's yes/no is weaker evidence than those, and verification
asymmetry (hard rule 12) says the checker should be more certain than the
thing it checks, not less. It would also send code and prompt text to another
vendor. Revisit after launch if the copy gate's false alarms become a chore.

Sources: firecrawl.dev/blog/what-is-jev, langchain.com/blog/building-a-harness-with-jev (read 2026-09-26).

## Ideas worth doing, in order

| # | Idea | What it buys | Cost | Recommendation |
|---|---|---|---|---|
| 1 | **Screenshot tour as a UI test**: one XCUITest that walks every screen and saves a PNG of each, attached to the test result | Kat and Tara review every screen from one folder after each build; a visual change can't hide in a diff | half a day | Do before the testing group |
| 2 | **Crash and error reporting** (Sentry, free tier) for the app and the edge functions | The first TestFlight crash is known in minutes, not when a tester texts | an hour plus Alex's account | Do before the testing group (launch checklist D6) |
| 3 | **Tighten branch protection on `main`** | It exists with two required checks (2026-09-26, `gh api`), but admins may bypass it and the hosted smoke test is not required; tightening makes GitHub itself refuse a red merge | 5 minutes, Alex's setting | Do now |
| 4 | **A git tag per TestFlight build** (`v0.1.0-tf2`) with the build number | A tester's "version 0.1.0 (3)" maps to one commit | minutes per build | Do at the next upload (launch checklist C10) |
| 5 | **Supabase Pro** | No pause after a quiet week, point-in-time recovery | $25/month | Decide before real members (launch checklist D3) |
| 6 | **Dependabot security alerts** turned on for the repo | Known-vulnerable dependencies flagged automatically | minutes | Do now (Dependabot version updates already run) |

## Adopted

- 2026-09-23: post-compaction replay of Alex's last prompts (session-start hook).
- 2026-09-22: hosted signed-out smoke test in CI.
- 2026-09-13: doc claims, paths and inventory checked in CI.
