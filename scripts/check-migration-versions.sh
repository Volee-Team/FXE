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
