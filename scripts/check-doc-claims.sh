#!/bin/bash
# check-doc-claims.sh: the counts and index facts a doc states must match what
# the repo can derive right now. Companion to check-doc-paths.sh (paths exist)
# and check-doc-inventory.sh (schema objects are documented; needs the DB).
#
#   bash scripts/check-doc-claims.sh
#
# WHY: the 2026-09-12 docs audit found the same stale numbers copied across
# four files ("14 probes", "8 Playwright tests", "13 unit tests", "20
# migrations") weeks after each had changed, plus decisions written but never
# indexed, and a "last audited" date nobody looked at. A number a script can
# derive should never be typed by a person; this makes typing it safe.
#
# WHAT IT CHECKS
#   1. Every "N <thing>" claim in the CURRENT-STATE docs below equals the
#      derived N, for thing in: probes | unit tests | XCUITests | Playwright
#      tests | browser tests | migrations. Lines that are explicitly historical
#      ("as of <date>", "was N", "then N", "at the time") are skipped, and so is
#      everything under CLAUDE.md's "## Changelog" (a diary is allowed to be
#      old). Decision records and the feature review are snapshots by nature
#      and are not scanned.
#   2. Every docs/decisions/NNNN-*.md is linked from docs/decisions/README.md,
#      and every NNNN the README links exists.
#   3. Every numbered question in docs/questions-for-tara.md carries a status
#      line (*ANSWERED / DEFERRED / OVERRULED / SUPERSEDED / Default ...*).
#   4. docs/.last-doc-audit is recent: a warning past 21 days, a failure past
#      45. The audit is the human-shaped check this script cannot do.
#
# Exit 1 on any failure; prints one line per finding.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
FAIL=0
say() { echo "  $*"; }
fail() { echo "  FAIL  $*"; FAIL=1; }

# ---------------------------------------------------------------- derived ----
PROBES=$(ls tests/sql/*.sql | wc -l | tr -d ' ')
UNIT=$(cat FXETennisTests/*.swift | grep -c 'func test')
UITESTS=$(cat FXETennisUITests/*.swift | grep -c 'func test')
PLAYWRIGHT=$(grep -cE '^\s*test\(' web/tests/admin.spec.mjs)
MIGRATIONS=$(ls supabase/migrations/*.sql | wc -l | tr -d ' ')
echo "Derived now: probes=$PROBES unit=$UNIT xcuitests=$UITESTS playwright=$PLAYWRIGHT migrations=$MIGRATIONS"

# ------------------------------------------------------------ 1. counts ----
DOCS="docs/roadmap.md docs/whats-next.md docs/architecture.md docs/launch-checklist.md README.md web/README.md supabase/functions/README.md"
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
for f in $DOCS; do [ -f "$f" ] && awk -v F="$f" '{print F ":" NR ":" $0}' "$f"; done > "$TMP"
# CLAUDE.md above the changelog only
awk '/^## Changelog/{exit} {print "CLAUDE.md:" NR ":" $0}' CLAUDE.md >> "$TMP"

check_count() { # label regex expected
  local label=$1 re=$2 want=$3
  grep -iE "$re" "$TMP" \
    | grep -viE 'as of 20[0-9][0-9]|\bwas [0-9]|\bthen [0-9]|at the time|used to|previously|→' \
    | while IFS= read -r line; do
        n=$(echo "$line" | grep -oiE "$re" | head -1 | grep -oE '[0-9]+' | head -1)
        [ "$n" = "$want" ] || echo "  FAIL  $label: doc says $n, repo has $want :: ${line%%:*}:$(echo "$line" | cut -d: -f2)"
      done
}
{
check_count "probes"      '\b[0-9]+ (sql )?probes?\b'                       "$PROBES"
check_count "unit tests"  '\b[0-9]+ (swift )?unit tests?\b'                 "$UNIT"
check_count "XCUITests"   '\b[0-9]+ (xcuitests?|ui tests?)\b'               "$UITESTS"
check_count "Playwright"  '\b[0-9]+ (playwright|browser) tests?\b'          "$PLAYWRIGHT"
check_count "migrations"  '\b[0-9]+ migrations?\b'                          "$MIGRATIONS"
} | tee "$TMP.counts"
grep -q FAIL "$TMP.counts" && FAIL=1
rm -f "$TMP.counts"

# --------------------------------------------------- 2. decisions index ----
for f in docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
  n=$(basename "$f" | cut -c1-4)
  grep -q "($(basename "$f"))" docs/decisions/README.md || fail "decision $n ($f) is not linked from docs/decisions/README.md"
done
for link in $(grep -oE '\([0-9]{4}-[a-z0-9-]+\.md\)' docs/decisions/README.md | tr -d '()'); do
  [ -f "docs/decisions/$link" ] || fail "docs/decisions/README.md links $link, which does not exist"
done

# ------------------------------------------ 3. every question has a status ----
awk '
  /^\*\*[0-9]+\./ { if (q != "" && !seen) print "  FAIL  " q " has no status or default line"; q=$1 " " $2; seen=0; next }
  /^\*(ANSWERED|DEFERRED|OVERRULED|SUPERSEDED|HALF ANSWERED|Default|Re-asked|\(Not built|\(Moot)/ { seen=1 }
  END { if (q != "" && !seen) print "  FAIL  " q " has no status or default line" }
' docs/questions-for-tara.md | tee "$TMP.q"
grep -q FAIL "$TMP.q" && FAIL=1; rm -f "$TMP.q"

# ------------------------------------------------------- 4. audit age ----
if [ -f docs/.last-doc-audit ]; then
  LAST=$(tr -d '[:space:]' < docs/.last-doc-audit)
  if date -j >/dev/null 2>&1; then AGE=$(( ( $(date +%s) - $(date -j -f %Y-%m-%d "$LAST" +%s) ) / 86400 ));
  else AGE=$(( ( $(date +%s) - $(date -d "$LAST" +%s) ) / 86400 )); fi
  say "last docs audit: $LAST ($AGE days ago)"
  if [ "$AGE" -gt 45 ]; then fail "docs audit is $AGE days old (limit 45). Run the audit (CLAUDE.md, 'Audit this file periodically') and write today's date to docs/.last-doc-audit";
  elif [ "$AGE" -gt 21 ]; then echo "::warning::docs audit is $AGE days old; due at 45"; fi
else
  fail "docs/.last-doc-audit is missing"
fi

if [ $FAIL -eq 0 ]; then echo "Doc claims consistent."; else echo "Doc claims drifted."; exit 1; fi
