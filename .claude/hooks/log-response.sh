#!/bin/bash
# Stop hook: append Claude's reply, verbatim, to the same log as the prompt.
#
# WHY THIS EXISTS
# ---------------
# Alex, 2026-08-13: "it only makes sense if my prompt and your replies are
# logged, probably exactly ... so i could TRULY restart with just the docs if
# anything happened and you would respond the same."
#
# He is right, and the reason is sharper than "more context is better". A prompt
# log alone records what was ASKED and loses what was DECIDED. Half of this
# project's decisions were made in a reply: the reasoning, the rejected option,
# the number that came back from a command. `docs/decisions/` captures the big
# ones deliberately. This captures everything else, automatically, including the
# parts nobody realised were load-bearing until three weeks later.
#
# Together with log-prompt.sh this makes docs/prompt-log/ a complete transcript.
# The 2026-08-13 /clear cost roughly a day precisely because no such file
# existed. After this, a fresh session can read the log and pick up mid-thought.
#
# HOW IT WORKS
# ------------
# The Stop hook receives JSON on stdin containing `transcript_path`, pointing at
# the session's JSONL transcript. We read the LAST assistant message from it.
# We do not get the reply text directly, which is why this parses a file rather
# than a field.
#
# Writes nothing to stdout. Always exits 0: a logging hook must never be able to
# block or fail a turn.
#
# `stop_hook_active` guards against recursion. When Claude is resumed BY a stop
# hook, that flag is true and we skip, otherwise a hook that causes further
# output could log itself in a loop.
#
# PRIVACY: same rule as log-prompt.sh. This file is committed. Redact personal
# data before committing. Tara's roster does not belong in git.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

LOG_DIR="docs/prompt-log"
LOG_FILE="$LOG_DIR/$(date +%Y-%m).md"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

PAYLOAD=$(cat 2>/dev/null) || exit 0

REPLY=$(printf '%s' "$PAYLOAD" | python3 -c '
import json, sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

# Do not log a turn that a stop hook itself resumed.
if payload.get("stop_hook_active"):
    sys.exit(0)

path = payload.get("transcript_path") or ""
if not path:
    sys.exit(0)

# Walk the transcript backwards to the most recent assistant turn and collect
# its text blocks. Tool calls and thinking blocks are skipped: the log is for
# what Claude SAID, and a transcript of every tool call would bury it.
last = None
try:
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except Exception:
                continue
            if entry.get("type") != "assistant":
                continue
            msg = entry.get("message") or {}
            parts = []
            for block in msg.get("content") or []:
                if isinstance(block, dict) and block.get("type") == "text":
                    text = block.get("text") or ""
                    if text.strip():
                        parts.append(text)
            if parts:
                last = "\n\n".join(parts)
except Exception:
    sys.exit(0)

if last:
    print(last, end="")
' 2>/dev/null) || exit 0

[ -z "$REPLY" ] && exit 0

{
  printf '\n### Claude replied · %s\n\n' "$(date '+%H:%M:%S %Z')"
  # ~~~~ fence: long enough that a ``` block inside the reply cannot close it.
  printf '~~~~text\n'
  printf '%s\n' "$REPLY"
  printf '~~~~\n'
} >> "$LOG_FILE" 2>/dev/null

exit 0
