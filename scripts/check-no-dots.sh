#!/usr/bin/env bash
# check-no-dots.sh: no middle dot (·) in anything a person reads (decision
# 0034; Alex, 2026-10-01: "it looks super AI"). The copy gate sees only
# literal strings, and most of these lines are built from data ("60 min ·
# $18"), so this greps the code itself. Comment lines are allowed to keep
# their dots; everything else fails.
set -euo pipefail
cd "$(dirname "$0")/.."
hits=$(git ls-files 'FXETennis/*.swift' 'web/*.html' 'web/*.js' 'web/app/*' 'scripts/build-tara-review.py' \
  | xargs grep -n '·' 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*|<!--|#)' || true)
if [ -n "$hits" ]; then
  echo "$hits"
  echo "::error::A middle dot (·) in text a person reads. Use \"at\", a comma, a colon or parentheses (decision 0034)."
  exit 1
fi
echo "No middle dots in the app or the admin site."
