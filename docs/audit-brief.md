# Docs audit brief

The brief a model is given to audit this repository's documentation for drift.
Used by hand (paste it into a session with four read-only agents, one per file
set, as on 2026-09-12) and by `.github/workflows/docs-audit.yml` monthly when
`ANTHROPIC_API_KEY` is set. Deterministic checks already run on every PR
(`scripts/check-doc-paths.sh`, `scripts/check-doc-claims.sh`,
`scripts/check-doc-inventory.sh`, `scripts/check-doc-status.sh`,
`scripts/check-doc-registry.sh`, `scripts/check-launch-checklist.sh`); this
brief is for the claims a script cannot judge.

---

You are auditing documentation drift in this repository. Do not edit any file.
Do not run supabase, xcodebuild, npm or docker. Read the code, the migrations,
the tests and the workflows, and compare every checkable claim in the docs
against them.

Scope, in this order: `CLAUDE.md` above `## Changelog`;
`docs/launch-checklist.md`; `docs/backlog.md`; `docs/questions-for-tara.md`;
`docs/decisions/README.md` and `docs/decisions/*.md`; `docs/roadmap.md`;
`docs/architecture.md`; `docs/web-admin.md`; `docs/style-guide.md`;
`docs/notifications.md`; `docs/copy.md`, `docs/copy-review.md`;
`docs/for-alex.md`, `docs/testflight.md`, `docs/launch-runbook.md`,
`docs/stripe-e2e-test.md`; `README.md`, `web/README.md`,
`supabase/functions/README.md`; `.claude/agents/*.md`. Everything under
`docs/archive/` is a dated snapshot with an "Archived" banner and is out of
scope.

What counts as drift: a status marker (done, missing, not built, blocked) that
disagrees with the code; a status restated outside its four homes
(`docs/launch-checklist.md`, `docs/backlog.md`, `docs/questions-for-tara.md`,
`docs/decisions/README.md`) instead of pointing at a row ID such as
"checklist C11"; a "we will" that was built differently; a decision
superseded by a later decision or a later Tara answer without a note saying so;
a backlog row already fixed; a question already answered but unmarked; a
function, column, view, setting, file or job named that does not exist or has
changed shape; a number that a script could derive (do not report those, the
scripts do); a doc describing another repository without saying so.

Output one markdown table: `File:line` | `Claim` | `Reality (the command you
ran and its abbreviated output)` | `Proposed fix (exact replacement text)`.
Certain drifts first, then a short "could not verify" list, then a short
"verified, no drift" list so the next audit can skip it. Factual drift only; no
style opinions. Be exhaustive and terse.
