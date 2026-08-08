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
  echo "up, or commit files you did not change (CLAUDE.md hard rule 7)."
fi

echo ""
echo "Recent commits:"
echo '```'
git log --oneline -5 2>/dev/null
echo '```'
