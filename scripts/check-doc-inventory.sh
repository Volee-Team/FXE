#!/bin/bash
# check-doc-inventory.sh: every schema object, edge function, probe and CI job
# that exists is named in docs/architecture.md. Needs the local stack
# (supabase start + db reset), so it runs in the sql-probes CI job after the
# suite, and locally by hand.
#
#   bash scripts/check-doc-inventory.sh
#
# WHY: on 2026-09-12 architecture.md was missing five probes, two enums, one
# view, four RPCs, eight Swift files and three CI jobs, all added over the
# preceding ten days by sessions that updated the code and the changelog but
# not the map. A map that omits a room is worse than no map: it is trusted.
# This does not check that the description is right, only that the thing is
# mentioned at all; the human audit does the rest.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
DOC=docs/architecture.md
FAIL=0
sql() { docker exec "$DB" psql -U postgres -d postgres -Atc "$1"; }
need() { # kind name
  grep -qF -- "$2" "$DOC" || { echo "  FAIL  $1 '$2' exists but is not mentioned in $DOC"; FAIL=1; }
}

if ! docker exec "$DB" pg_isready -U postgres >/dev/null 2>&1; then echo "Local Postgres is not up. Run: supabase start"; exit 1; fi

for t in $(sql "select tablename from pg_tables where schemaname='public' order by 1"); do need table "$t"; done
for v in $(sql "select viewname from pg_views where schemaname='public' order by 1"); do need view "$v"; done
for e in $(sql "select typname from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typtype='e' order by 1"); do need enum "$e"; done
# Functions a client can call (authenticated holds EXECUTE) must be documented;
# internal helpers and trigger functions need not be.
for f in $(sql "select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and has_function_privilege('authenticated', p.oid, 'EXECUTE') order by 1"); do need "client RPC" "$f"; done
for d in supabase/functions/*/; do n=$(basename "$d"); [ "$n" = "_shared" ] && continue; need "edge function" "$n"; done
# Probes are cited by name without the extension ("information_hiding").
for p in tests/sql/*.sql tests/sql/*.sh; do b=$(basename "$p"); need probe "${b%.*}"; done
for job in $(grep -E '^  [a-z-]+:$' .github/workflows/probes.yml | tr -d ' :'); do need "CI job" "$job"; done
for s in FXETennis/Views/*.swift FXETennis/Data/*.swift FXETennis/Models/*.swift FXETennis/App/*.swift; do need "Swift file" "$(basename "$s")"; done

# scripts/hosted-smoke-functions.txt must equal what the schema says now, and
# every edge function must be in hosted-smoke.sh's EDGE or EDGE_EXEMPT, or
# production never gets asked whether a signed-out caller can reach it (the
# hand-kept list had drifted to 46 of 81 functions by 2026-09-27).
SMOKE=scripts/hosted-smoke.sh
if ! diff -q <(FXE_DB_CONTAINER="$DB" bash scripts/gen-smoke-functions.sh --stdout) scripts/hosted-smoke-functions.txt >/dev/null; then
  echo "  FAIL  scripts/hosted-smoke-functions.txt is stale: run bash scripts/gen-smoke-functions.sh after supabase db reset"
  diff <(FXE_DB_CONTAINER="$DB" bash scripts/gen-smoke-functions.sh --stdout) scripts/hosted-smoke-functions.txt | head -10
  FAIL=1
fi
LISTED=$(grep -E '^(EDGE|EDGE_EXEMPT)=' "$SMOKE" | cut -d'"' -f2 | tr ' ' '\n')
for d in supabase/functions/*/; do n=$(basename "$d"); [ "$n" = "_shared" ] && continue
  echo "$LISTED" | grep -qx "$n" || { echo "  FAIL  edge function '$n' is in neither EDGE nor EDGE_EXEMPT in $SMOKE"; FAIL=1; }
done

if [ $FAIL -eq 0 ]; then echo "Inventory documented: every table, view, enum, client RPC, edge function, probe, CI job and Swift file is named in $DOC."; else echo "Inventory drifted."; exit 1; fi
