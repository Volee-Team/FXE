#!/usr/bin/env bash
# Does hosted grant client roles anything a database built from the migrations
# does not? Read-only on both sides.
#
#   bash scripts/check-hosted-grants.sh
#
# Runs scripts/grants-snapshot.sql on hosted (scripts/hosted-read.sh, a read-only
# transaction) and on the local database, and prints the lines that differ.
# Exit 1 when hosted holds a grant the local build does not. Run it right after
# `supabase db reset`, so the local side is exactly what the migrations make.
#
# Why (2026-11-14): tests/sql/grants_are_explicit.sql only ever sees fresh
# databases, so it certifies the migrations, not production. Hosted had
# writes and MAINTAIN on news_reads, MAINTAIN on accounts and players, EXECUTE
# on seven functions and open default privileges that no migration wrote; a
# docs audit found them by reading hosted's ACLs. This is that read, made a
# check. Called by scripts/live-status.sh.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT

sql=$(grep -v '^--' scripts/grants-snapshot.sql)
if ! bash scripts/hosted-read.sh "$sql" > "$tmp/hosted.raw"; then
  echo "   could not read hosted (is the Supabase CLI signed in?)"; exit 2
fi
python3 -c '
import json, sys
for l in open(sys.argv[1]):
    l = l.strip()
    if l.startswith("{"):
        d = json.loads(l)
        if "line" in d: print(d["line"])
' "$tmp/hosted.raw" | sort > "$tmp/hosted.txt"
if ! docker exec -i "$DB" psql -U postgres -d postgres -Atq < scripts/grants-snapshot.sql 2>/dev/null | sort > "$tmp/local.txt" \
   || [ ! -s "$tmp/local.txt" ]; then
  echo "   could not read the local database ($DB): start it and run supabase db reset first"; exit 2
fi

extra=$(comm -13 "$tmp/local.txt" "$tmp/hosted.txt")
missing=$(comm -23 "$tmp/local.txt" "$tmp/hosted.txt")
echo "   hosted $(wc -l < "$tmp/hosted.txt" | tr -d ' ') grant lines, local build $(wc -l < "$tmp/local.txt" | tr -d ' ')"
if [ -n "$missing" ]; then
  echo "   on the local build, not on hosted (an unpushed migration, or hosted lost a grant):"
  echo "$missing" | sed 's/^/     - /'
fi
if [ -n "$extra" ]; then
  echo "   ON HOSTED ONLY, written by no migration:"
  echo "$extra" | sed 's/^/     + /'
  exit 1
fi
echo "   hosted grants nothing the migrations do not"
