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

# Background-task notices arrive through the same hook as Alex's prompts but
# are written by the harness, not by him. 154 of them had piled into the
# September log by 2026-09-26 and pushed his real messages out of the
# post-compaction replay. They carry no decision; skip them.
case "$PROMPT" in
  "<task-notification>"*|*"[SYSTEM NOTIFICATION - NOT USER INPUT]"*) exit 0 ;;
esac

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


# Redact anything that looks like a government id, a bank or card number, or
# an SSN line before it touches the log. Tara sent her SSN and bank details in
# a message on 2026-09-16 and this hook copied them into a file that lives in
# a public repository until scrubbed by hand. Never again: the log is for what
# she decided, not for what she is.
redact() {
  python3 -c '
import re, sys
t = sys.stdin.read()
t = re.sub(r"\b\d{3}-\d{2}-\d{4}\b", "[redacted id number]", t)
t = re.sub(r"(?i)\b(ssn|social security)[^\n]*", r"\1 [redacted]", t)
t = re.sub(r"(?i)\b(routing|account|acct|iban|card)( number| no\.?| #)?[ :#]*\d[\d -]{6,}", r"\1 [redacted]", t)
t = re.sub(r"\b(?:\d[ -]?){13,19}\b", "[redacted long number]", t)
# Keys and secrets (2026-09-27, before Alex set up Stripe): this log is
# committed to a public repository, so a key pasted into a prompt would be
# published. Stripe secret and restricted keys, webhook signing secrets,
# Supabase secret keys, and long JWTs. Publishable keys (pk_) are public by
# design and stay readable.
t = re.sub(r"\b(sk|rk)_(test|live)_[A-Za-z0-9]{8,}", r"[redacted Stripe \2 key]", t)
t = re.sub(r"\bwhsec_[A-Za-z0-9]{8,}", "[redacted webhook secret]", t)
t = re.sub(r"\bsb_secre[t]_[A-Za-z0-9_-]{8,}", "[redacted Supabase secret]", t)
t = re.sub(r"\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}", "[redacted token]", t)
# A reset link is a one-hour sign-in as the member (decision 0017).
t = re.sub(r"token_hash=[0-9A-Fa-f]{20,}", "token_hash=[redacted]", t)
# 2026-10-04: a Stripe activation summary pasted into a prompt carried
# Tara: her date of birth, home address and phone, and the EIN letter was one
# photo away. None reached a commit (scrubbed by hand), but the rules above
# would not have caught them. An EIN (12-3456789), a date of birth after its
# label, and a street address with a number and a street-type word.
t = re.sub(r"\b\d{2}-\d{7}\b", "[redacted EIN]", t)
t = re.sub(r"(?i)\b(born on|date of birth|dob)\b[: ]*[^\n]*", r"\1 [redacted]", t)
t = re.sub(r"\b\d{2,6} (?:[A-Z][a-z]+ ){1,3}(?:Lane|Ln|Street|St|Road|Rd|Drive|Dr|Avenue|Ave|Court|Ct|Circle|Cir|Way|Boulevard|Blvd|Place|Pl|Trail|Trl)\b\.?", "[redacted address]", t)
# A phone in the "+1 (704) 555-0100" form that Stripe prints.
t = re.sub(r"\+1 \(\d{3}\) \d{3}-\d{4}", "[redacted phone]", t)
sys.stdout.write(t)
'
}
PROMPT=$(printf '%s' "$PROMPT" | redact)

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
