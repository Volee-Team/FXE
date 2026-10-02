#!/bin/bash
# Run every FXE probe against the local Postgres and report one red/green table.
#
#   bash tests/run-probes.sh
#
# Requires a running local stack: `supabase start`.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}

# A UI test run (scripts/run-ui-tests.sh) owns the main local database while
# it holds its lock: probes and race scripts write rows and hold locks that
# make its tests fail for reasons that are not regressions, and its rows make
# these probes fail the same way (2026-10-01, a reviewer's probe run during a
# UI run). Another stack (FXE_DB_CONTAINER) is not affected.
if [ "$DB" = "supabase_db_FXE-Tennis" ] && [ -d /tmp/fxe-ui-tests.lock ] \
   && kill -0 "$(cat /tmp/fxe-ui-tests.lock/pid 2>/dev/null)" 2>/dev/null; then
  echo "A UI test run holds the local database (pid $(cat /tmp/fxe-ui-tests.lock/pid)). Wait for it to finish."
  exit 2
fi

if ! docker exec "$DB" pg_isready -U postgres >/dev/null 2>&1; then
  echo "Local Postgres is not up. Run: supabase start"
  exit 1
fi

# Freshness. The probes assume the deterministic seed and nothing else. Browser
# tests and simulator runs leave rows behind, and a probe that fails on those
# rows looks exactly like a real regression. This cost an afternoon on
# 2026-09-12 (three "failures" that vanished after a reset). Every seed row is
# stamped inside the same reset (one transaction, so one now()), so anything
# created more than a few seconds after the first seed account was added
# later, by something other than the seed. The window was 60 seconds until
# 2026-09-21, when the browser suite's rows, written 23 seconds after a
# reset, slipped inside it and two false failures came back with no warning.
# Notifications are counted since 2026-09-28: registering now writes one, and
# an orphan whose registration a script deleted fails notification_targets.
STRAY=$(docker exec "$DB" psql -U postgres -d postgres -Atc "
  with seed as (select min(created_at) + interval '5 seconds' as t from public.accounts)
  select (select count(*) from public.accounts, seed where created_at > seed.t)
       + (select count(*) from public.players, seed where created_at > seed.t)
       + (select count(*) from public.clinics, seed where created_at > seed.t)
       + (select count(*) from public.registrations, seed where registered_at > seed.t)
       + (select count(*) from public.payments, seed where created_at > seed.t)
       + (select count(*) from public.devices, seed where updated_at > seed.t)
       + (select count(*) from public.card_consents, seed where accepted_at > seed.t)
       + (select count(*) from public.reset_links_issued, seed where issued_at > seed.t)
       + (select count(*) from public.notifications, seed where created_at > seed.t)" 2>/dev/null)
if [ -n "$STRAY" ] && [ "$STRAY" != "0" ]; then
  echo "DIRTY DATABASE: $STRAY rows were added after the seed. Failures below may be"
  echo "false. Reset first and rerun:  supabase db reset --yes"
  echo ""
fi

FAILED=0
# Grand total, printed by the suite itself so documentation points here instead
# of hardcoding a number. "142 checks" sat in three docs while the suite grew
# to 285; a count only the suite prints cannot rot.
TOTAL=0

echo "════ SQL probes ════"
for f in tests/sql/*.sql; do
  name=$(basename "$f" .sql)
  out=$(docker exec -i "$DB" psql -U postgres -d postgres -f - < "$f" 2>&1)
  if echo "$out" | grep -q "FAIL"; then
    echo "  FAIL  $name"
    echo "$out" | grep -E "FAIL" | sed 's/^/          /'
    FAILED=1
  # psql writes errors as "psql:<stdin>:138: ERROR: ...", so anchoring this
  # pattern to start-of-line silently let every SQL error through as a pass.
  # Match ERROR anywhere. (Found 2026-08-10, after a NOT NULL column made five
  # probes abort and the suite still reported them green.)
  elif echo "$out" | grep -qiE "ERROR:|server closed"; then
    echo "  ERROR $name"
    echo "$out" | grep -iE "ERROR:|server closed" | head -3 | sed 's/^/          /'
    FAILED=1
  else
    n=$(echo "$out" | grep -c "PASS")
    # A probe that ran zero assertions is not a passing probe. Same family of
    # bug as the one above: silence is not evidence.
    if [ "$n" -eq 0 ]; then
      echo "  EMPTY $name (0 checks ran — probe produced no assertions)"
      FAILED=1
    else
      echo "  ok    $name ($n checks)"
      TOTAL=$((TOTAL + n))
    fi
  fi
done

echo ""
echo "════ Concurrency probes ════"
for f in tests/sql/*.sh; do
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
echo "TOTAL: $TOTAL checks across $(ls tests/sql/*.sql | wc -l | tr -d ' ') probes"
echo "-------------------------------------"
[ "$FAILED" -eq 0 ] && echo "All probes green." || echo "Probes RED. See above."
exit $FAILED
