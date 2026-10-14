#!/usr/bin/env bash
# No two migrations share a version.
#
# Supabase records an applied migration by the version string before the
# first underscore, so two files with one version cannot both reach hosted:
# the second is skipped or refused, depending on the order they are pushed.
# On 2026-09-28 two builders working in parallel both picked 20260928700001
# (declined_card and calendar_feed); it was caught by eye at merge time.
# This makes it a CI failure instead.
set -euo pipefail
cd "$(dirname "$0")/.."
dups=$(ls supabase/migrations/*.sql | xargs -n1 basename | cut -d_ -f1 | sort | uniq -d)
if [ -n "$dups" ]; then
  for v in $dups; do echo "  DUPLICATE  $v:"; ls supabase/migrations/${v}_*.sql | sed 's/^/    /'; done
  echo "Two migrations share a version. Renumber the newer one (it is not on hosted yet)."
  exit 1
fi
echo "Every migration has its own version ($(ls supabase/migrations/*.sql | wc -l | tr -d ' ') files)."

# A new migration is newer than every migration already on the base branch
# (2026-10-13, the go-live review). Hosted refuses an older version than its
# newest unless pushed with --include-all, and then it runs on hosted in a
# different order than every local and CI replay. A migration held on a
# branch for weeks (the go-live pair, crash reports from 10-01 to 10-13)
# must be renamed to its merge date; this makes forgetting a CI failure.
BASE=${MIGRATION_BASE:-origin/main}
if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
  # Locally a missing base is a skip; in CI it is a failure, so a checkout
  # that stops fetching main cannot quietly switch the check off.
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "  No $BASE in CI: fetch it (fetch-depth: 0)."; exit 1; fi
  echo "  (no $BASE here: the order check needs the base branch fetched; skipped)"
  exit 0
fi
newest=$(git ls-tree --name-only "$BASE" supabase/migrations/ | xargs -n1 basename | grep -E '^[0-9]+_' | cut -d_ -f1 | sort | tail -1)
late=""
for f in supabase/migrations/*.sql; do
  b=$(basename "$f")
  git cat-file -e "$BASE:supabase/migrations/$b" 2>/dev/null && continue
  v=${b%%_*}
  [ "$v" \> "$newest" ] || late="$late $b"
done
if [ -n "$late" ]; then
  for b in $late; do echo "  OUT OF ORDER  $b is not newer than $BASE's newest ($newest)"; done
  echo "Rename it to today's date before it merges: hosted would refuse it, or run it out of order."
  exit 1
fi
echo "Every migration new on this branch is newer than $BASE's newest ($newest)."
