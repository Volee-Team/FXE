#!/bin/bash
# SessionStart hook: put the working state in front of Claude before it acts.
#
# Why: sessions have started work on `main` believing they were on a feature
# branch, and have started work with a dirty tree from someone else's in-flight
# change. Both are cheap to prevent and expensive to unwind.
#
# stdout is injected into the session context.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# Claude Code passes {"source": "startup" | "resume" | "clear" | "compact"} on
# stdin. Read it before anything else; a hook that ignores stdin still works,
# it just cannot tell a fresh start from a compaction.
SOURCE=$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("source",""), end="")
except Exception: pass' 2>/dev/null)

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

echo "## Working state"
echo ""
echo "Branch: \`$BRANCH\`"

if [ "$BRANCH" = "main" ]; then
  echo ""
  echo "WARNING: you are on \`main\`, which is the deployable branch. Create a"
  echo "feature branch before making changes unless Alex explicitly asked for a"
  echo "change on main."
fi

echo ""
echo "Uncommitted files: $DIRTY"
if [ "$DIRTY" -gt 0 ]; then
  echo ""
  echo '```'
  git status --short 2>/dev/null | head -25
  echo '```'
  echo ""
  echo "Some of this may be someone else's in-flight work. Do not revert, clean"
  echo "up, or commit files you did not change (CLAUDE.md hard rule 6)."
fi

echo ""
echo "Recent commits:"
echo '```'
git log --oneline -5 2>/dev/null
echo '```'

# Doc freshness. Docs rot silently between sessions; this makes the age of the
# last audit visible at the top of every session instead of discoverable by
# accident. The marker is updated by whoever completes a docs pass.
if [ -f docs/.last-doc-audit ]; then
  LAST=$(cat docs/.last-doc-audit)
  AGE=$(( ( $(date +%s) - $(date -j -f %Y-%m-%d "$LAST" +%s 2>/dev/null || date -d "$LAST" +%s) ) / 86400 ))
  echo ""
  echo "Docs last audited: $LAST ($AGE days ago)."
  if [ "$AGE" -gt 7 ]; then
    echo "OVERDUE: run a docs-freshness pass (check docs/ claims against reality,"
    echo "move fixed backlog rows, then update docs/.last-doc-audit)."
  fi
fi

# After a compaction (and on resume), put Alex's last prompts back in front
# of Claude VERBATIM. The compaction summary is written by the model, so it
# is a claim (hard rule 12), and a paraphrase of "tiny rounding of the
# corners" is exactly the kind of thing that drifts. The prompt log already
# holds every prompt word for word (log-prompt.sh); this reads the newest
# ones back so the summary can be checked against the source instead of
# trusted. Alex, 2026-09-23: "anything to make sure its as least lossy as
# possible compacting?"
if [ "$SOURCE" = "compact" ] || [ "$SOURCE" = "resume" ]; then
  python3 - <<'PY' 2>/dev/null
import glob, re
files = sorted(glob.glob("docs/prompt-log/*.md"))
if files:
    text = open(files[-1], encoding="utf-8", errors="replace").read()
    # A prompt entry starts "## <stamp> · `branch`" and holds one ~~~~text block.
    entries = re.findall(r"^## (.+?)\n\n~~~~text\n(.*?)\n~~~~", text, re.S | re.M)
    replies = re.findall(r"^### Claude replied · (.+?)\n\n~~~~text\n(.*?)\n~~~~", text, re.S | re.M)
    last = entries[-3:]
    if last:
        print()
        print("## Alex's last %d prompts, verbatim (from the prompt log; the compaction summary is a paraphrase, this is the source)" % len(last))
        for stamp, body in last:
            lines = body.rstrip().splitlines()
            cut = lines[:60]
            print()
            print("### %s" % stamp)
            print("```text")
            print("\n".join(cut))
            if len(lines) > len(cut):
                print("[... %d more lines in %s]" % (len(lines) - len(cut), files[-1]))
            print("```")
    if replies:
        stamp, body = replies[-1]
        lines = body.rstrip().splitlines()[:25]
        print()
        print("### The last reply Claude sent (%s), first lines" % stamp)
        print("```text")
        print("\n".join(lines))
        print("```")
    print()
    print("Before touching code: check the summary's pending list against these prompts, `git log --oneline -5`, the top of docs/whats-next.md and the newest CLAUDE.md changelog entry. If they disagree, the repo wins over the summary.")
PY
fi
