#!/bin/bash
# back_to_back_105_race.sh
#
# Decision 0015 §13, and the sql-auditor's finding of 2026-09-26: two
# registrations by the same non-member for two same-day 105s, at the same
# instant, share no row lock (each locks only its own clinic), so without a
# per-player lock both pass the back-to-back check and both insert.
#
# Session A registers Rob for the 16:30 105 and holds its transaction open for
# three seconds; session B, started one second later, registers him for the
# 18:00 105. With the lock, B waits for A, then sees A's row and is refused.
# Without it, B inserts at once. The resulting state is asserted, not the
# error: Rob must hold exactly one live spot across the two.

set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
ROB=44444444-4444-4444-4444-444444444444
ROB_P=a0000000-0000-0000-0000-000000000003

read -r X1 X2 <<<"$(psql -tAq <<'SQL' | tr '\n' ' '
with d as (select ((now() + interval '4 days') at time zone 'America/New_York')::date as day)
insert into public.clinics (name, audience, category, description, starts_at, ends_at,
    member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
select n, 'coed', '105', 'race probe', (d.day + s) at time zone 'America/New_York', (d.day + s + interval '1 hour') at time zone 'America/New_York',
       now() - interval '2 days', now() - interval '1 day', (d.day + s - interval '3 hours') at time zone 'America/New_York', 8, 'published', 60
  from d, (values ('RACE 105 A', time '16:30'), ('RACE 105 B', time '18:00')) v(n, s)
returning id;
SQL
)"

run_as_rob() { # clinic, seconds to hold the transaction open
  psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$ROB","role":"authenticated"}', true);
set local role authenticated;
select 'got ' || (public.register_for_clinic('$1', '$ROB_P')).status;
select pg_sleep($2);
commit;
SQL
}

run_as_rob "$X1" 3 > /tmp/race105_a.out &
A=$!
sleep 1
B_OUT=$(run_as_rob "$X2" 0)
wait $A
A_OUT=$(cat /tmp/race105_a.out); rm -f /tmp/race105_a.out

LIVE=$(psql -tAqc "select count(*) from public.registrations
  where player_id = '$ROB_P' and clinic_id in ('$X1','$X2') and status in ('in','pool','response_needed')" | tr -d '[:space:]')

psql -q -c "delete from public.registrations where clinic_id in ('$X1','$X2'); delete from public.clinics where id in ('$X1','$X2');" >/dev/null

echo "session A: $(echo "$A_OUT" | grep -oE 'got [a-z_]+|ERROR:.*' | head -1)"
echo "session B: $(echo "$B_OUT" | grep -oE 'got [a-z_]+|ERROR:.*' | head -1)"
if [ "$LIVE" = "1" ]; then
  echo "PASS: one live same-day 105 for the non-member after two concurrent registrations"
  exit 0
fi
echo "FAIL: $LIVE live same-day 105s for the non-member (expected 1)"
exit 1
