#!/bin/bash
# UserPromptSubmit hook: append every prompt Alex writes, verbatim, to a log.
#
# WHY THIS EXISTS
# ---------------
# Alex, 2026-08-13: "the MOST important things i say, info i relay from tara,
# etc literally come from my prompts ... if smth happens or your context is
# running low, then you could look at the convo of the whole entire history of
# the app and have tons of context and see the progression."
#
# On 2026-08-13 a /clear destroyed a session's context and cost roughly a day.
# The docs survived it; the conversation did not. Everything Tara wants reaches
# this repo through Alex typing it, and until now that channel was the only one
# with no durable record. A decision record captures the conclusion. This
# captures the raw input the conclusion came from, including the half-formed
# parts that turn out to matter three weeks later.
#
# This is a MECHANISM, not a discipline. Nobody has to remember to run it.
#
# HOW IT WORKS
# ------------
# Claude Code passes the submitted prompt as JSON on stdin. We append it to
# docs/prompt-log/YYYY-MM.md and print NOTHING: anything this script writes to
# stdout gets injected into Claude's context, and echoing the prompt back would
# duplicate every message. Silence is correct here.
#
# The hook must never block Alex. Every failure path exits 0.
#
# PRIVACY: THIS FILE IS COMMITTED TO GIT
# --------------------------------------
# Whatever gets pasted into a prompt lands in the repository permanently, and
# git history is very hard to scrub. Tara forwards real club emails containing
# hundreds of members' addresses. Those are real people who gave her an address
# for clinic scheduling, not for a GitHub repo.
#
# Rule: redact personal data BEFORE committing the log. `git add -p` the
# prompt-log, read what you are about to commit, and replace any roster,
# address list or phone number with a short note saying what was removed. The
# content that matters for context is what Tara DECIDED, never the addresses.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

LOG_DIR="docs/prompt-log"
LOG_FILE="$LOG_DIR/$(date +%Y-%m).md"

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

# Parse the prompt out of the hook's JSON payload. python3 rather than jq:
# macOS ships python3 and does not ship jq, and a missing tool here would
# silently stop the log without anyone noticing, which is the failure mode this
# whole hook exists to prevent.
PROMPT=$(python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("prompt", ""), end="")
except Exception:
    pass
' 2>/dev/null) || exit 0

# An empty prompt means the payload shape changed or parsing failed. Leave a
# marker rather than nothing, so a silent break is visible in the log itself
# instead of looking like a quiet week.
if [ -z "$PROMPT" ]; then
  printf '\n---\n\n## %s\n\n_(hook could not read the prompt payload: check .claude/hooks/log-prompt.sh)_\n' \
    "$(date '+%Y-%m-%d %H:%M:%S %Z')" >> "$LOG_FILE" 2>/dev/null
  exit 0
fi

# Header, written once per file.
if [ ! -s "$LOG_FILE" ]; then
  {
    printf '# Prompt log: %s\n\n' "$(date +%Y-%m)"
    printf 'Every prompt Alex submitted this month, verbatim and unedited, newest at the bottom.\n'
    printf 'Written automatically by `.claude/hooks/log-prompt.sh`. Do not hand-edit except to\n'
    printf 'redact personal data before committing (see the header comment in that script).\n\n'
    printf 'This is the raw record. The *decisions* that came out of it live in\n'
    printf '`docs/decisions/`, and the running summary lives in the CLAUDE.md changelog.\n'
  } >> "$LOG_FILE" 2>/dev/null
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

{
  printf '\n---\n\n## %s · `%s`\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$BRANCH"
  # Fenced as `text` so markdown inside a prompt cannot break the log's own
  # structure. Prompts routinely contain code blocks, tables and stray
  # backticks; a ~~~~ fence is long enough that a pasted ``` cannot close it.
  printf '~~~~text\n'
  printf '%s\n' "$PROMPT"
  printf '~~~~\n'
} >> "$LOG_FILE" 2>/dev/null

exit 0
