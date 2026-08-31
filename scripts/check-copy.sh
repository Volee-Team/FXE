#!/bin/bash
# Fail if the app gained user-visible text nobody approved.
#
# Alex, 2026-08-16: "text should either come straight from tara or made by u and
# checked by me first". This is that rule with a machine behind it.
#
# docs/copy-approved.txt is a snapshot of every user-visible string in the app.
# When a change adds or edits one, this fails and prints the diff. The fix is
# NOT to blindly regenerate: read the new lines, decide whether they are Tara's
# words, plain chrome, or invented filler, and only then run
#   python3 scripts/extract-copy.py > docs/copy-approved.txt
# and commit that alongside the change, so the new copy shows up in the diff a
# human reviews.
#
# The point is that new prose can never arrive silently.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SNAP="docs/copy-approved.txt"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

python3 scripts/extract-copy.py > "$TMP" || exit 1

if [ ! -f "$SNAP" ]; then
  echo "No $SNAP yet. Create it with:"
  echo "  python3 scripts/extract-copy.py > $SNAP"
  exit 1
fi

if diff -q "$SNAP" "$TMP" >/dev/null; then
  echo "Copy unchanged: $(wc -l < "$SNAP" | tr -d ' ') approved strings."
  exit 0
fi

echo "::error::The app's user-visible text changed."
echo ""
echo "  - = removed        + = ADDED, and needs Alex or Tara to approve it"
echo ""
diff "$SNAP" "$TMP" | grep -E '^[<>]' | sed 's/^</  - /; s/^>/  + /'
echo ""
echo "If the added lines are correct copy (Tara's words, or plain chrome that"
echo "Alex has seen), record them and commit the snapshot with your change:"
echo "  python3 scripts/extract-copy.py > $SNAP"
echo ""
echo "New player-facing sentences also belong in docs/copy-review.md,
the checklist Alex walks with Tara."
exit 1
