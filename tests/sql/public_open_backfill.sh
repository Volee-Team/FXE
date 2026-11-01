#!/bin/bash
# public_open_backfill.sh
#
# 20261101000001 moves every clinic still carrying the old "Friday 08:00"
# public open to Friday noon (decision 0046). A .sql probe cannot test that:
# the seed is loaded after the migration, so on a reset database the backfill
# has nothing to move. This plants three rows, runs the REAL migration file
# over them inside one transaction, reads the rows back, and rolls everything
# back.
#
#   default   a future week still on Friday 08:00     -> Friday 12:00
#   by hand   a future week Tara set to Friday 07:00  -> untouched (hard rule 6)
#   opened    a past week whose Friday 08:00 has gone -> untouched
#   and the default row's member open stays Thursday 08:00.
#
# MIGRATION=<path> runs another copy of the file; that is how each guard was
# shown red (backfill removed, the equality guard removed, the now() guard
# removed).
#
# Usage: bash tests/sql/public_open_backfill.sh
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
MIGRATION=${MIGRATION:-supabase/migrations/20261101000001_public_opens_friday_noon.sql}

plant() {
  # $1 name, $2 clinic start (New York wall clock), $3 public open (New York wall clock)
  cat <<SQL
insert into public.clinics (name, audience, category, description, starts_at, ends_at,
    member_opens_at, public_opens_at, internal_capacity, status, duration_minutes,
    price_cents, member_price_cents, nonmember_price_cents)
values ('$1', 'coed', 'Clinic', 'backfill probe',
        timestamp '$2' at time zone 'America/New_York',
        timestamp '$2' at time zone 'America/New_York' + interval '1 hour',
        public.member_opens_at(timestamp '$2' at time zone 'America/New_York'),
        timestamp '$3' at time zone 'America/New_York',
        8, 'published', 60, 1800, 1800, 2500);
SQL
}

out=$({
  echo "begin;"
  # Week of Sunday 2099-06-07: Thursday 06-04, Friday 06-05.
  plant 'BACKFILL default' '2099-06-09 09:00' '2099-06-05 08:00'
  plant 'BACKFILL by hand' '2099-06-10 09:00' '2099-06-05 07:00'
  # Week of Sunday 2026-10-04: its Friday 10-02 08:00 is in the past.
  plant 'BACKFILL opened'  '2026-10-06 09:00' '2026-10-02 08:00'
  cat "$MIGRATION"
  cat <<'SQL'
\pset format unaligned
\pset tuples_only on
select name || '|' || to_char(public_opens_at at time zone 'America/New_York', 'YYYY-MM-DD Dy HH24:MI')
           || '|' || to_char(member_opens_at at time zone 'America/New_York', 'YYYY-MM-DD Dy HH24:MI')
  from public.clinics where name like 'BACKFILL %' order by name;
rollback;
SQL
} | docker exec -i "$DB" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1 -f - 2>&1)

expect() {
  if echo "$out" | grep -qxF "$1"; then echo "  ok    $1"; else echo "  MISS  $1"; bad=1; fi
}
bad=0
expect 'BACKFILL by hand|2099-06-05 Fri 07:00|2099-06-04 Thu 08:00'
expect 'BACKFILL default|2099-06-05 Fri 12:00|2099-06-04 Thu 08:00'
expect 'BACKFILL opened|2026-10-02 Fri 08:00|2026-10-01 Thu 08:00'

if [ "$bad" -eq 0 ]; then
  echo "PASS public_open_backfill: default moved to noon, hand-set and already-open rows untouched"
else
  echo "FAIL public_open_backfill"
  echo "$out" | sed 's/^/    /'
  exit 1
fi
