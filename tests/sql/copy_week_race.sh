#!/bin/bash
# copy_week_race.sh
#
# 20260928800002: admin_copy_week skips a clinic whose copy already exists, so
# a second click creates nothing. That is a check followed by an insert, and a
# single-session probe (copy_week.sql) cannot see two of them interleave: two
# calls at once would both find no copy and both insert. The transaction
# advisory lock keyed on the target week makes the second wait for the first
# to commit, then read its copies. This races them for real and asserts the
# resulting rows (hard rule 9), not an error.
#
#   Tara's first click holds its transaction open for three seconds after the
#   copy; the second click, a second later, must wait, then create nothing.
#   Without the lock the second click inserts the week again: six drafts where
#   there should be three.
#
# A week in 2099, three clinics the probe makes and removes, so no seed row
# and no other probe is involved.
#
# Usage: bash tests/sql/copy_week_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111

cleanup() {
  psql -q -c "delete from public.clinics where name like 'COPY RACE %';" >/dev/null
}
cleanup   # a run killed half way leaves nothing behind for the next one

WEEK=$(psql -tAqc "select public.service_week_start('2099-06-03 16:00:00+00');" | tr -d '[:space:]')
psql -q -c "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  select 'COPY RACE ' || n, 'coed', 'Clinic', 'race probe',
         (('$WEEK'::date + n)::timestamp + time '09:00') at time zone 'America/New_York',
         (('$WEEK'::date + n)::timestamp + time '10:00') at time zone 'America/New_York',
         public.member_opens_at((('$WEEK'::date + n)::timestamp + time '09:00') at time zone 'America/New_York'),
         public.public_opens_at((('$WEEK'::date + n)::timestamp + time '09:00') at time zone 'America/New_York'),
         8, 'published', 60
    from generate_series(1, 3) n;" >/dev/null

TMP=$(mktemp -d)
as_tara() { # seconds to hold the transaction open after the copy
  psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$TARA","role":"authenticated"}', true);
set local role authenticated;
select 'copy ' || created || ' created ' || skipped || ' skipped' from public.admin_copy_week('$WEEK');
select pg_sleep($1);
commit;
SQL
}

as_tara 3 > "$TMP/a" &
A=$!
sleep 1
as_tara 0 > "$TMP/b"
wait $A

DRAFTS=$(psql -tAc "select count(*) from public.clinics where name like 'COPY RACE %'
  and public.service_week_start(starts_at) = '$WEEK'::date + 7 and status = 'draft';" | tr -d '[:space:]')
PER_CLINIC=$(psql -tAc "select coalesce(max(k), 0) from (select count(*) k from public.clinics
  where name like 'COPY RACE %' and public.service_week_start(starts_at) = '$WEEK'::date + 7 group by name, starts_at) t;" | tr -d '[:space:]')

echo "  first click  : $(grep -oE 'copy [0-9]+ created [0-9]+ skipped|ERROR:.*' "$TMP/a" | head -1)"
echo "  second click : $(grep -oE 'copy [0-9]+ created [0-9]+ skipped|ERROR:.*' "$TMP/b" | head -1)"
echo "  drafts       : $DRAFTS   (must be 3)"
echo "  most copies of one clinic : $PER_CLINIC   (must be 1)"
echo ""

cleanup
rm -rf "$TMP"

FAIL=0
[ "$DRAFTS" = "3" ]     || { echo "FAIL: two clicks made $DRAFTS drafts of a three-clinic week"; FAIL=1; }
[ "$PER_CLINIC" = "1" ] || { echo "FAIL: one clinic was copied $PER_CLINIC times"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: two simultaneous copies of one week make one draft per clinic"
exit $FAIL
