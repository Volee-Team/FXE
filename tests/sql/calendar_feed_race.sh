#!/bin/bash
# calendar_feed_race.sh
#
# 20260928700001 (decision 0029): my_calendar_feed_token() makes the
# account's token on first use. Two first calls at once (a double tap, or
# Subscribe on the phone and on an iPad in the same second) must end with ONE
# row and the SAME token handed to both, or one device subscribes to a link
# that is dead a moment later. calendar_feed.sql cannot see this: it runs in
# one session.
#
#   Priya's first call runs and holds its transaction open for three seconds
#   (its row inserted, not committed); her second call starts one second
#   later. The second call's insert waits on the first one's row, then does
#   nothing (ON CONFLICT DO NOTHING), and its read, a new statement with a
#   new snapshot, returns the first call's token.
#
# The resulting rows are asserted, not the error (hard rule 9). Red with the
# re-read removed (the second call returns nothing) and with a plain INSERT
# (the second call fails on the primary key), 2026-09-28.
#
# Usage: bash tests/sql/calendar_feed_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
PRIYA=55555555-5555-5555-5555-555555555555

# Start from no token for Priya (the seed has none; a walk on the simulator
# may have made one).
psql -q -c "delete from public.calendar_feeds where account_id = '$PRIYA';" >/dev/null

TMP=$(mktemp -d)
as_priya() { # seconds to hold the transaction open
  psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$PRIYA","role":"authenticated"}', true);
set local role authenticated;
select 'token=' || coalesce(public.my_calendar_feed_token(), 'NULL');
select pg_sleep($1);
commit;
SQL
}

as_priya 3 > "$TMP/a" &
A=$!
sleep 1
as_priya 0 > "$TMP/b"
wait $A

TA=$(grep -oE 'token=[0-9a-fA-FNUL]+' "$TMP/a" | head -1 | cut -d= -f2)
TB=$(grep -oE 'token=[0-9a-fA-FNUL]+' "$TMP/b" | head -1 | cut -d= -f2)
ROWS=$(psql -tAc "select count(*) from public.calendar_feeds where account_id = '$PRIYA';" | tr -d '[:space:]')
STORED=$(psql -tAc "select token from public.calendar_feeds where account_id = '$PRIYA';" | tr -d '[:space:]')

echo "  first call  : ${TA:-$(grep -oE 'ERROR:.*' "$TMP/a" | head -1)}"
echo "  second call : ${TB:-$(grep -oE 'ERROR:.*' "$TMP/b" | head -1)}"
echo "  rows        : $ROWS   (must be 1)"
echo ""

psql -q -c "delete from public.calendar_feeds where account_id = '$PRIYA';" >/dev/null
rm -rf "$TMP"

FAIL=0
[ ${#TA} -eq 64 ] && [ "$TA" != "NULL" ] || { echo "FAIL: the first call got no token"; FAIL=1; }
[ "$TA" = "$TB" ]     || { echo "FAIL: two first calls at once got different answers ('$TA' and '$TB')"; FAIL=1; }
[ "$ROWS" = "1" ]     || { echo "FAIL: $ROWS rows for one account"; FAIL=1; }
[ "$STORED" = "$TA" ] || { echo "FAIL: the stored token is not the one handed out"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: two first calls at once get the same token and leave one row"
exit $FAIL
