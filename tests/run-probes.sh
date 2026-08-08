#!/bin/bash
# Run every FXE probe against the local Postgres and report one red/green table.
#
#   bash tests/run-probes.sh
#
# Requires a running local stack: `supabase start`.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}

if ! docker exec "$DB" pg_isready -U postgres >/dev/null 2>&1; then
  echo "Local Postgres is not up. Run: supabase start"
  exit 1
fi

FAILED=0

echo "════ SQL probes ════"
for f in tests/sql/*.sql; do
  name=$(basename "$f" .sql)
  out=$(docker exec -i "$DB" psql -U postgres -d postgres -f - < "$f" 2>&1)
  if echo "$out" | grep -q "FAIL"; then
    echo "  FAIL  $name"
    echo "$out" | grep -E "FAIL" | sed 's/^/          /'
    FAILED=1
  elif echo "$out" | grep -qiE "^ERROR|server closed"; then
    echo "  ERROR $name"
    echo "$out" | grep -iE "^ERROR|server closed" | head -3 | sed 's/^/          /'
    FAILED=1
  else
    n=$(echo "$out" | grep -c "PASS")
    echo "  ok    $name ($n checks)"
  fi
done

echo ""
echo "════ Concurrency probes ════"
for f in tests/sql/*.sh; do
  [ "$(basename "$f")" = "run-probes.sh" ] && continue
  name=$(basename "$f" .sh)
  out=$(bash "$f" 2>&1)
  if echo "$out" | grep -q "^PASS"; then
    echo "  ok    $name"
  else
    echo "  FAIL  $name"
    echo "$out" | tail -6 | sed 's/^/          /'
    FAILED=1
  fi
done

echo ""
echo "-------------------------------------"
[ "$FAILED" -eq 0 ] && echo "All probes green." || echo "Probes RED. See above."
exit $FAILED
