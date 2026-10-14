#!/bin/bash
# app_diagnostics_race.sh
#
# Decision 0035, and the sql-auditor's review of 2026-10-01: the rate limit
# in report_app_diagnostic (20 per account per rolling 24 hours) is a count
# followed by an insert. Two calls at the same instant both count 19 and
# both insert, unless something makes the second wait for the first: the
# per-account advisory lock taken before the count.
#
# Maria starts at 19 rows. Session A reports and holds its transaction open
# for three seconds; session B, started one second later, reports too. With
# the lock, B waits for A, then counts 20 and is refused. Without it, B
# inserts at once and Maria ends at 21. The resulting state is asserted, not
# the error: exactly 20 rows.

set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
MARIA=22222222-2222-2222-2222-222222222222

psql -q -c "delete from public.app_diagnostics where account_id = '$MARIA';
  insert into public.app_diagnostics (account_id, kind, payload)
  select '$MARIA', 'crash', jsonb_build_object('race_seed', g) from generate_series(1, 19) g;" >/dev/null

run_as_maria() { # tag, seconds to hold the transaction open
  psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$MARIA","role":"authenticated"}', true);
set local role authenticated;
select public.report_app_diagnostic('crash', null, null, null, null, '{"race": "$1"}');
select 'reported $1';
select pg_sleep($2);
commit;
SQL
}

run_as_maria A 3 > /tmp/diag_race_a.out &
A=$!
sleep 1
B_OUT=$(run_as_maria B 0)
wait $A
A_OUT=$(cat /tmp/diag_race_a.out); rm -f /tmp/diag_race_a.out

ROWS=$(psql -tAqc "select count(*) from public.app_diagnostics where account_id = '$MARIA'" | tr -d '[:space:]')
psql -q -c "delete from public.app_diagnostics where account_id = '$MARIA';" >/dev/null

echo "session A: $(echo "$A_OUT" | grep -oE 'reported [AB]|ERROR:.*' | head -1)"
echo "session B: $(echo "$B_OUT" | grep -oE 'reported [AB]|ERROR:.*' | head -1)"
if [ "$ROWS" = "20" ]; then
  echo "PASS: 20 reports for Maria after two concurrent calls at 19"
  exit 0
fi
echo "FAIL: $ROWS reports for Maria (expected 20)"
exit 1
