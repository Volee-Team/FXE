#!/bin/bash
# beginner_backfill.sh
#
# 20261106000001 makes a beginner clinic's name carry no minimum (decision
# 0049). clinics.min_rating is a stored generated column, so clinics that
# already exist keep the old value until their row is rewritten, and that
# rewrite is the part hosted depends on. A .sql probe cannot test it: the seed
# has no beginner clinic and any clinic made after the migration is right from
# birth. This restores the old function inside one transaction, plants two rows
# so they carry the old value, runs the REAL migration file over them, reads
# them back, and rolls everything back.
#
#   beginner   "BACKFILL Beginner - 2.5"  2.5 -> null
#   gated      "BACKFILL Ladies 3.0+"     3.0 -> 3.0
#   and neither row's published_at or price moves.
#
# MIGRATION=<path> runs another copy of the file; that is how the rewrite was
# shown red (a copy without the UPDATE leaves the beginner row at 2.5).
#
# Usage: bash tests/sql/beginner_backfill.sh
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
MIGRATION=${MIGRATION:-supabase/migrations/20261106000001_beginner_clinics_open.sql}

plant() {
  cat <<SQL
insert into public.clinics (name, audience, category, description, starts_at, ends_at,
    member_opens_at, public_opens_at, internal_capacity, status, duration_minutes,
    price_cents, member_price_cents, nonmember_price_cents, published_at)
values ('$1', 'coed', 'Clinic', 'backfill probe',
        timestamptz '2099-06-09 09:00-04', timestamptz '2099-06-09 10:00-04',
        timestamptz '2099-06-04 08:00-04', timestamptz '2099-06-05 12:00-04',
        8, 'published', 60, 1800, 1800, 2500, timestamptz '2099-01-01 00:00+00');
SQL
}

out=$({
  echo "begin;"
  # The function as 20261105000002 wrote it, so the rows carry the old value.
  cat <<'SQL'
create or replace function public.clinic_level_from_name(p_name text)
returns numeric language sql immutable set search_path = public, pg_temp as $$
  select substring(coalesce(p_name, '') from '(?:^|[^0-9.])([2-5]\.[05])(?![0-9])')::numeric(2,1);
$$;
SQL
  plant 'BACKFILL Beginner - 2.5'
  plant 'BACKFILL Ladies 3.0+'
  cat <<'SQL'
\pset format unaligned
\pset tuples_only on
select 'before|' || name || '|' || coalesce(min_rating::text, 'null')
  from public.clinics where name like 'BACKFILL %' order by name;
\pset tuples_only off
SQL
  cat "$MIGRATION"
  cat <<'SQL'
\pset tuples_only on
select 'after|' || name || '|' || coalesce(min_rating::text, 'null')
           || '|' || (published_at = timestamptz '2099-01-01 00:00+00')::text
           || '|' || nonmember_price_cents
  from public.clinics where name like 'BACKFILL %' order by name;
rollback;
SQL
} | docker exec -i "$DB" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1 -f - 2>&1)

expect() {
  if echo "$out" | grep -qxF "$1"; then echo "  ok    $1"; else echo "  MISS  $1"; bad=1; fi
}
bad=0
# Before the migration: the planted rows really do carry the old value.
expect 'before|BACKFILL Beginner - 2.5|2.5'
expect 'before|BACKFILL Ladies 3.0+|3.0'
expect 'after|BACKFILL Beginner - 2.5|null|true|2500'
expect 'after|BACKFILL Ladies 3.0+|3.0|true|2500'

if [ "$bad" -eq 0 ]; then
  echo "PASS beginner_backfill: the existing beginner clinic lost its minimum, nothing else moved"
else
  echo "FAIL beginner_backfill"
  echo "$out" | sed 's/^/    /'
  exit 1
fi
